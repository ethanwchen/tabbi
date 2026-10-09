import AppKit
import SwiftUI
import TabbiKitCore

/// Now Playing state and controls for Spotify and Apple Music.
///
/// Both apps are found through `NSRunningApplication` and are never launched
/// implicitly: AppleScript (which would launch them) only runs after a
/// running check. `MediaSourceTracker` decides which app the panel follows.
/// Updates come from each app's distributed notification; while the panel is
/// visible the position ticks locally every second and is re-synced with a
/// 5 s read. With `TABBI_DEMO=1` it shows `SpotifyPlayback.demo` and
/// never talks to either app.
@MainActor
final class SpotifyController: NSObject, ObservableObject {
    /// When true, album art + equalizer show beside the closed notch.
    @Published var showsCompactActivity = false
    /// What the panel shows; the playback position is extrapolated between reads.
    @Published private(set) var status: SpotifyStatus = .notRunning
    /// The app `status` belongs to; nil while no player app is running.
    @Published private(set) var source: NowPlayingSource?
    /// Player apps on this Mac, for the empty state's open buttons.
    @Published private(set) var installedSources: [MediaSource] = []

    private static let notifications: [NowPlayingSource: Notification.Name] = [
        .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged"),
        .music: Notification.Name("com.apple.Music.playerInfo"),
    ]
    /// The players the panel follows. SoundCloud in a browser is not one
    /// yet: reading it asks for Automation access to the browser, which
    /// should only happen once the user turns it on.
    private static let sources: [NowPlayingSource] = NowPlayingSource.all.filter { $0.app != nil }
    private static let automationSettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    /// Resync interval while the panel is visible. Never poll faster than this.
    private static let pollInterval: TimeInterval = 5

    private let isDemo: Bool
    private var tracker = MediaSourceTracker()
    /// Per app, so a read of one app never re-anchors the other's position.
    private var clocks: [NowPlayingSource: SpotifyPlaybackClock] = [:]
    private var isPanelVisible = false
    private var tickTimer: Timer?
    private var pollTimer: Timer?
    /// Bumped per app by every read and command so a slow, stale read can't
    /// overwrite a newer state (e.g. an optimistic play/pause).
    private var generations: [NowPlayingSource: Int] = [:]
    private var appIcons: [NowPlayingSource: NSImage] = [:]
    /// The newest volume requested per app but not yet sent. A slider drag
    /// produces many values; only one set-volume script runs at a time and
    /// the latest value wins, so Apple Events never pile up.
    private var pendingVolumes: [NowPlayingSource: Int] = [:]
    private var volumeInFlight: Set<NowPlayingSource> = []
    /// The level before the speaker button muted each app, for unmuting.
    private var volumesBeforeMute: [NowPlayingSource: Int] = [:]
    /// Shuffle and repeat changes per app that the player may not show yet.
    private var pendingModes: [NowPlayingSource: PendingMediaModes] = [:]

    init(runMode: RunMode) {
        isDemo = runMode.isDemo
        super.init()
        if isDemo {
            record(.spotify, .notRunning)
            record(.music, .connected(.demo))
            return
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(applicationsChanged(_:)),
                              name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(applicationsChanged(_:)),
                              name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        // Background (LSUIElement) apps are "inactive", so ask for immediate
        // delivery or the players' notifications would queue until activation.
        for name in Self.notifications.values {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(playbackStateChanged(_:)),
                name: name, object: nil, suspensionBehavior: .deliverImmediately
            )
        }
        refresh()
    }

    // MARK: - Panel visibility

    /// Call from the panel's `onAppear` / `onDisappear`. Timers only run
    /// while the panel can be seen.
    func setPanelVisible(_ visible: Bool) {
        guard visible != isPanelVisible else { return }
        isPanelVisible = visible
        if visible { refresh() }
        updateTimers()
    }

    // MARK: - Commands

    func playPause() {
        guard let source, let playback = currentStatus.playback, playback.track != nil else { return }
        applyOptimistic(playback.togglingPlayPause(), to: source)
        send(source.playPauseScript, to: source)
    }

    func next() {
        guard let source else { return }
        send(source.nextTrackScript, to: source)
    }

    func previous() {
        guard let source else { return }
        send(source.previousTrackScript, to: source)
    }

    func seek(to seconds: TimeInterval) {
        guard let source, let playback = currentStatus.playback, let track = playback.track else { return }
        let target = playback.clampedPosition(seconds)
        applyOptimistic(playback.seeking(to: target), to: source)
        send(source.seekScript(to: target, in: track), to: source)
    }

    /// Turns shuffle on or off in the active app.
    func toggleShuffle() {
        guard let source, let playback = currentStatus.playback, playback.track != nil else { return }
        let isOn = !playback.isShuffling
        expectModes(source) { $0.adding(shuffle: isOn, at: $1) }
        applyOptimistic(playback.settingShuffle(isOn), to: source)
        sendModeChange(source.setShuffleScript(isOn), to: source)
    }

    /// Steps the active app's repeat mode: off, all, then (in Music) one.
    func cycleRepeat() {
        guard let source, let playback = currentStatus.playback, playback.track != nil else { return }
        let mode = source.repeatMode(after: playback.repeatMode)
        expectModes(source) { $0.adding(repeatMode: mode, at: $1) }
        applyOptimistic(playback.settingRepeat(mode), to: source)
        sendModeChange(source.setRepeatScript(mode), to: source)
    }

    /// Likes or unlikes the current track. Does nothing where the player
    /// can't, which is also where the panel hides the heart.
    func toggleFavorite() {
        guard let source, let playback = currentStatus.playback, let track = playback.track,
              let isFavorite = track.isFavorite,
              let script = source.setFavoriteScript(!isFavorite, for: track) else { return }
        applyOptimistic(playback.settingFavorite(!isFavorite), to: source)
        send(script, to: source)
    }

    /// Sets the active app's own volume (0 ... 100). Safe to call for every
    /// step of a drag: the panel updates at once and commands are coalesced.
    func setVolume(_ volume: Int) {
        guard let source, let playback = currentStatus.playback, let current = playback.volume else { return }
        let target = MediaVolume.clamped(volume)
        guard target != current else { return }
        applyOptimistic(playback.settingVolume(target), to: source)
        guard !isDemo else { return }
        pendingVolumes[source] = target
        sendPendingVolume(source)
    }

    /// Mutes the active app, or restores the level it had before muting.
    func toggleMute() {
        guard let source, let current = currentStatus.playback?.volume else { return }
        if current > 0 { volumesBeforeMute[source] = current }
        setVolume(MediaVolume.togglingMute(current, previous: volumesBeforeMute[source]))
    }

    /// Launches `source`, or brings it forward if it's running. Only ever
    /// called from an explicit user action.
    /// For SoundCloud this brings its browser forward.
    func open(_ source: NowPlayingSource) {
        guard !isDemo,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier)
        else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// The app's Finder icon for launch buttons and the source badge; nil if
    /// it isn't installed. Cached, since the panel re-renders every second.
    func appIcon(for source: NowPlayingSource) -> NSImage? {
        if let icon = appIcons[source] { return icon }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        appIcons[source] = icon
        return icon
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(Self.automationSettings)
    }

    // MARK: - Artwork

    /// Raw cover bytes for a Music track (Music has no artwork URLs). Nil for
    /// other tracks, in demo mode, when the track has no artwork, or once
    /// Music has moved on to another track.
    func artworkData(for track: SpotifyTrack) async -> Data? {
        guard !isDemo, let script = MusicScript.readArtwork(forTrackID: track.id) else { return nil }
        return await Self.runForData(script, on: .music)
    }

    // MARK: - Reading state

    /// Reads every running player's state now.
    func refresh() {
        guard !isDemo else { return }
        for source in Self.sources { refresh(source) }
    }

    private func refresh(_ source: NowPlayingSource) {
        let current = bumpGeneration(source)
        let isRunning = Self.isRunning(source)
        record(source, SpotifyStatus.resolve(source: source, isRunning: isRunning,
                                             isInstalled: Self.isInstalled(source),
                                             read: nil, previous: latestStatus(source)))
        guard isRunning else { return }
        Task {
            let result = await Self.run(source.readStateScript, on: source)
            guard current == generations[source] else { return }
            var status = SpotifyStatus.resolve(source: source, isRunning: Self.isRunning(source),
                                               isInstalled: Self.isInstalled(source),
                                               read: result, previous: latestStatus(source))
            if case .connected(let playback) = status, let pending = pendingModes[source] {
                status = .connected(pending.applied(to: playback, at: Date()))
            }
            record(source, status)
        }
    }

    /// `status` with the playback position extrapolated to now; `status` itself
    /// only advances while the panel ticks.
    private var currentStatus: SpotifyStatus {
        source.map(latestStatus) ?? status
    }

    /// `source`'s last known status, its position extrapolated to now.
    private func latestStatus(_ source: NowPlayingSource) -> SpotifyStatus {
        if let clock = clocks[source] { return .connected(clock.playback(at: Date())) }
        return tracker.statuses[source] ?? .notRunning
    }

    private func send(_ script: String, to source: NowPlayingSource) {
        if isDemo {
            if script == source.nextTrackScript || script == source.previousTrackScript {
                applyOptimistic(SpotifyPlayback.demo.seeking(to: 0), to: source)
            }
            return
        }
        guard Self.isRunning(source) else { return refresh(source) }
        bumpGeneration(source)
        Task {
            let result = await Self.run(script, on: source)
            if case .failure(.permissionDenied) = result {
                record(source, .permissionDenied)
            }
            refresh(source)
        }
    }

    private func expectModes(_ source: NowPlayingSource,
                             _ update: (PendingMediaModes, Date) -> PendingMediaModes) {
        let now = Date()
        pendingModes[source] = update(pendingModes[source] ?? PendingMediaModes(deadline: now), now)
    }

    /// Sends a shuffle or repeat change, then reads the player again once
    /// the change has settled, so the buttons end on the player's real state
    /// (Spotify applies these a moment after the command returns).
    private func sendModeChange(_ script: String, to source: NowPlayingSource) {
        send(script, to: source)
        guard !isDemo else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(PendingMediaModes.settleTime + 0.1))
            guard let self, let pending = pendingModes[source], !pending.isActive(at: Date()) else { return }
            pendingModes[source] = nil
            refresh(source)
        }
    }

    private func sendPendingVolume(_ source: NowPlayingSource) {
        guard !volumeInFlight.contains(source), let volume = pendingVolumes.removeValue(forKey: source),
              let script = source.setVolumeScript(volume) else { return }
        guard Self.isRunning(source) else { return refresh(source) }
        volumeInFlight.insert(source)
        bumpGeneration(source)
        Task {
            let result = await Self.run(script, on: source)
            volumeInFlight.remove(source)
            if case .failure(.permissionDenied) = result {
                pendingVolumes[source] = nil
                return record(source, .permissionDenied)
            }
            // Confirm with a read only once the drag's last value is sent.
            if pendingVolumes[source] != nil { sendPendingVolume(source) } else { refresh(source) }
        }
    }

    private func applyOptimistic(_ playback: SpotifyPlayback, to source: NowPlayingSource) {
        bumpGeneration(source)
        record(source, .connected(playback))
    }

    @discardableResult
    private func bumpGeneration(_ source: NowPlayingSource) -> Int {
        let next = (generations[source] ?? 0) + 1
        generations[source] = next
        return next
    }

    /// Stores `source`'s confirmed status, re-anchoring its position clock,
    /// and republishes whichever app the tracker now selects.
    private func record(_ source: NowPlayingSource, _ newStatus: SpotifyStatus) {
        clocks[source] = newStatus.playback.map { SpotifyPlaybackClock(anchor: $0, at: Date()) }
        tracker.update(source, status: newStatus, at: Date())
        publish()
    }

    private func publish() {
        let selected = tracker.selected
        let shown = selected.map(latestStatus) ?? tracker.status
        if source != selected { source = selected }
        if status != shown { status = shown }
        let installed = tracker.installedSources
        if installedSources != installed { installedSources = installed }
        if showsCompactActivity != shown.isPlaying { showsCompactActivity = shown.isPlaying }
        updateTimers()
    }

    // MARK: - Timers

    private func updateTimers() {
        let tick = isPanelVisible && status.isPlaying
        if tick, tickTimer == nil {
            tickTimer = makeTimer(interval: 1) { $0.tick() }
        } else if !tick {
            tickTimer?.invalidate()
            tickTimer = nil
        }
        let poll = isPanelVisible && !isDemo && Self.sources.contains(where: Self.isRunning)
        if poll, pollTimer == nil {
            pollTimer = makeTimer(interval: Self.pollInterval) { $0.refresh() }
        } else if !poll {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func makeTimer(interval: TimeInterval, _ action: @escaping @MainActor @Sendable (SpotifyController) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func tick() {
        guard let source, let clock = clocks[source] else { return }
        let playback = clock.playback(at: Date())
        if status.playback != playback { status = .connected(playback) }
    }

    // MARK: - Notifications

    @objc private func applicationsChanged(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        // A browser hosts one SoundCloud source, but match every source
        // so the rule doesn't depend on that.
        for source in Self.sources where source.bundleIdentifier == app?.bundleIdentifier {
            if notification.name == NSWorkspace.didTerminateApplicationNotification {
                bumpGeneration(source)
                record(source, Self.isInstalled(source) ? .notRunning : .notInstalled)
            } else {
                refresh(source)
            }
        }
    }

    @objc private func playbackStateChanged(_ notification: Notification) {
        guard let source = Self.notifications.first(where: { $0.value == notification.name })?.key else { return }
        refresh(source)
    }

    // MARK: - AppleScript

    private nonisolated static func isRunning(_ source: NowPlayingSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).isEmpty
    }

    private static func isInstalled(_ source: NowPlayingSource) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) != nil
    }

    /// One serial queue: `NSAppleScript` isn't safe to run concurrently, and
    /// Apple Events can block for seconds, so keep them off the main thread.
    private nonisolated static let scriptQueue = DispatchQueue(label: "dev.tabbi.spotify.applescript",
                                                               qos: .userInitiated)

    private nonisolated static func run(_ script: String,
                                        on source: NowPlayingSource) async -> Result<String, SpotifyScriptError> {
        await execute(script, on: source) { $0.stringValue ?? "" }
    }

    /// Runs a script that returns raw bytes; nil for `missing value`.
    private nonisolated static func runForData(_ script: String, on source: NowPlayingSource) async -> Data? {
        let result = await execute(script, on: source) { descriptor -> Data? in
            // `missing value` comes back as a type descriptor ('msng').
            guard descriptor.descriptorType != typeNull, descriptor.descriptorType != typeType else { return nil }
            return descriptor.data.isEmpty ? nil : descriptor.data
        }
        return (try? result.get()) ?? nil
    }

    /// Converts the result on the script queue, since `NSAppleEventDescriptor`
    /// isn't `Sendable`.
    private nonisolated static func execute<Output: Sendable>(
        _ script: String, on source: NowPlayingSource,
        convert: @escaping @Sendable (NSAppleEventDescriptor) -> Output
    ) async -> Result<Output, SpotifyScriptError> {
        await withCheckedContinuation { continuation in
            scriptQueue.async {
                // Re-check right before sending: an Apple Event to a quit
                // app would relaunch it.
                guard isRunning(source) else { return continuation.resume(returning: .failure(.notRunning)) }
                var error: NSDictionary?
                let output = NSAppleScript(source: script)?.executeAndReturnError(&error)
                if let error {
                    let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
                    continuation.resume(returning: .failure(SpotifyScriptError(code: code)))
                } else {
                    continuation.resume(returning: .success(convert(output ?? .null())))
                }
            }
        }
    }
}
