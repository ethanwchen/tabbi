import AppKit
import SwiftUI
import NotchKitCore

/// Now Playing state and controls for Spotify and Apple Music.
///
/// Both apps are found through `NSRunningApplication` and are never launched
/// implicitly: AppleScript (which would launch them) only runs after a
/// running check. `MediaSourceTracker` decides which app the panel follows.
/// Updates come from each app's distributed notification; while the panel is
/// visible the position ticks locally every second and is re-synced with a
/// 5 s read. With `NOTCHDECK_DEMO=1` it shows `SpotifyPlayback.demo` and
/// never talks to either app.
@MainActor
final class SpotifyController: NSObject, ObservableObject {
    /// When true, album art + equalizer show beside the closed notch.
    @Published var showsCompactActivity = false
    /// What the panel shows; the playback position is extrapolated between reads.
    @Published private(set) var status: SpotifyStatus = .notRunning
    /// The app `status` belongs to; nil while no player app is running.
    @Published private(set) var source: MediaSource?
    /// Player apps on this Mac, for the empty state's open buttons.
    @Published private(set) var installedSources: [MediaSource] = []

    private static let notifications: [MediaSource: Notification.Name] = [
        .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged"),
        .music: Notification.Name("com.apple.Music.playerInfo"),
    ]
    private static let automationSettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    /// Resync interval while the panel is visible. Never poll faster than this.
    private static let pollInterval: TimeInterval = 5

    private let isDemo = ProcessInfo.processInfo.environment["NOTCHDECK_DEMO"] == "1"
    private var tracker = MediaSourceTracker()
    /// Per app, so a read of one app never re-anchors the other's position.
    private var clocks: [MediaSource: SpotifyPlaybackClock] = [:]
    private var isPanelVisible = false
    private var tickTimer: Timer?
    private var pollTimer: Timer?
    /// Bumped per app by every read and command so a slow, stale read can't
    /// overwrite a newer state (e.g. an optimistic play/pause).
    private var generations: [MediaSource: Int] = [:]
    private var appIcons: [MediaSource: NSImage] = [:]
    /// The newest volume requested per app but not yet sent. A slider drag
    /// produces many values; only one set-volume script runs at a time and
    /// the latest value wins, so Apple Events never pile up.
    private var pendingVolumes: [MediaSource: Int] = [:]
    private var volumeInFlight: Set<MediaSource> = []
    /// The level before the speaker button muted each app, for unmuting.
    private var volumesBeforeMute: [MediaSource: Int] = [:]

    override init() {
        super.init()
        if isDemo {
            record(.music, .notRunning)
            record(.spotify, .connected(.demo))
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
        guard let source, let playback = currentStatus.playback, playback.track != nil else { return }
        let target = playback.clampedPosition(seconds)
        applyOptimistic(playback.seeking(to: target), to: source)
        send(source.seekScript(to: target), to: source)
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
    func open(_ source: MediaSource) {
        guard !isDemo,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier)
        else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// The app's Finder icon for launch buttons and the source badge; nil if
    /// it isn't installed. Cached, since the panel re-renders every second.
    func appIcon(for source: MediaSource) -> NSImage? {
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
        for source in MediaSource.allCases { refresh(source) }
    }

    private func refresh(_ source: MediaSource) {
        let current = bumpGeneration(source)
        let isRunning = Self.isRunning(source)
        record(source, SpotifyStatus.resolve(source: source, isRunning: isRunning,
                                             isInstalled: Self.isInstalled(source),
                                             read: nil, previous: latestStatus(source)))
        guard isRunning else { return }
        Task {
            let result = await Self.run(source.readStateScript, on: source)
            guard current == generations[source] else { return }
            record(source, SpotifyStatus.resolve(source: source, isRunning: Self.isRunning(source),
                                                 isInstalled: Self.isInstalled(source),
                                                 read: result, previous: latestStatus(source)))
        }
    }

    /// `status` with the playback position extrapolated to now; `status` itself
    /// only advances while the panel ticks.
    private var currentStatus: SpotifyStatus {
        source.map(latestStatus) ?? status
    }

    /// `source`'s last known status, its position extrapolated to now.
    private func latestStatus(_ source: MediaSource) -> SpotifyStatus {
        if let clock = clocks[source] { return .connected(clock.playback(at: Date())) }
        return tracker.statuses[source] ?? .notRunning
    }

    private func send(_ script: String, to source: MediaSource) {
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

    private func sendPendingVolume(_ source: MediaSource) {
        guard !volumeInFlight.contains(source), let volume = pendingVolumes.removeValue(forKey: source) else { return }
        guard Self.isRunning(source) else { return refresh(source) }
        volumeInFlight.insert(source)
        bumpGeneration(source)
        Task {
            let result = await Self.run(source.setVolumeScript(volume), on: source)
            volumeInFlight.remove(source)
            if case .failure(.permissionDenied) = result {
                pendingVolumes[source] = nil
                return record(source, .permissionDenied)
            }
            // Confirm with a read only once the drag's last value is sent.
            if pendingVolumes[source] != nil { sendPendingVolume(source) } else { refresh(source) }
        }
    }

    private func applyOptimistic(_ playback: SpotifyPlayback, to source: MediaSource) {
        bumpGeneration(source)
        record(source, .connected(playback))
    }

    @discardableResult
    private func bumpGeneration(_ source: MediaSource) -> Int {
        let next = (generations[source] ?? 0) + 1
        generations[source] = next
        return next
    }

    /// Stores `source`'s confirmed status, re-anchoring its position clock,
    /// and republishes whichever app the tracker now selects.
    private func record(_ source: MediaSource, _ newStatus: SpotifyStatus) {
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
        let poll = isPanelVisible && !isDemo && MediaSource.allCases.contains(where: Self.isRunning)
        if poll, pollTimer == nil {
            pollTimer = makeTimer(interval: Self.pollInterval) { $0.refresh() }
        } else if !poll {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func makeTimer(interval: TimeInterval, _ action: @escaping @MainActor (SpotifyController) -> Void) -> Timer {
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
        guard let source = MediaSource.allCases.first(where: { $0.bundleIdentifier == app?.bundleIdentifier })
        else { return }
        if notification.name == NSWorkspace.didTerminateApplicationNotification {
            bumpGeneration(source)
            record(source, Self.isInstalled(source) ? .notRunning : .notInstalled)
        } else {
            refresh(source)
        }
    }

    @objc private func playbackStateChanged(_ notification: Notification) {
        guard let source = Self.notifications.first(where: { $0.value == notification.name })?.key else { return }
        refresh(source)
    }

    // MARK: - AppleScript

    private nonisolated static func isRunning(_ source: MediaSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).isEmpty
    }

    private static func isInstalled(_ source: MediaSource) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) != nil
    }

    /// One serial queue: `NSAppleScript` isn't safe to run concurrently, and
    /// Apple Events can block for seconds, so keep them off the main thread.
    private nonisolated static let scriptQueue = DispatchQueue(label: "dev.notchdeck.spotify.applescript",
                                                               qos: .userInitiated)

    private nonisolated static func run(_ script: String,
                                        on source: MediaSource) async -> Result<String, SpotifyScriptError> {
        await execute(script, on: source) { $0.stringValue ?? "" }
    }

    /// Runs a script that returns raw bytes; nil for `missing value`.
    private nonisolated static func runForData(_ script: String, on source: MediaSource) async -> Data? {
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
        _ script: String, on source: MediaSource,
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
