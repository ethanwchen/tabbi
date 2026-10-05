import AppKit
import TabbiKit
import TabbiKitCore
import os

/// Runs focus mode: follows the focus timer (and the Study timer when its
/// deep focus is on) and performs what `FocusSession` decides (focus
/// sound, playlist, Do Not Disturb shortcuts).
///
/// One instance per app, `context.focusMode`, because the focus timer,
/// Study, the Focus settings pane and kit defaults all need it and none of
/// them owns the others. It also owns the persisted
/// `FocusSettings`, so a change from Settings applies immediately: volume and
/// sounds update live while focusing (crossfading), the rest on the next
/// focus phase.
///
/// Music apps are followed through their playback notifications, never by
/// polling. An Apple Event is only sent to an app that is already running,
/// except `play` when a focus phase really starts with a playlist set.
///
/// Inert in demo and snapshot runs: it shows sample settings and never
/// plays sound, runs scripts or saves.
@MainActor
final class FocusController: ObservableObject {
    @Published var settings: FocusSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    /// True during a focus phase (sound and Do Not Disturb applied).
    @Published private(set) var isFocusing = false
    /// True while Settings is previewing the sound outside a focus phase.
    @Published private(set) var isPreviewing = false

    /// False in demo and snapshot runs, where focus mode only shows sample settings.
    let isLive: Bool

    private let repository: FocusSettingsRepository
    private let shortcuts = FocusShortcutRunner()
    private var session = FocusSession()
    /// Created on first use, so an app that never plays focus sound never
    /// builds an audio graph.
    private var engine: FocusSoundEngine?
    /// The last state each music app reported; absent until it posts one.
    private var playerStates: [MediaSource: SpotifyPlayerState] = [:]
    /// What each timer last asked for; focus mode follows the strongest.
    private var activities: [FocusActivitySource: FocusActivity] = [:]
    /// The combined activity last asked for, ahead of `session` while a
    /// transition is waiting on a player-state read.
    private var requestedActivity: FocusActivity = .idle
    /// Transitions run one at a time, in order.
    private var transitions: Task<Void, Never>?
    /// Shortcut runs finish in order, so an Off never lands before its On.
    private var shortcutRuns: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(runMode: RunMode, repository: FocusSettingsRepository = FocusSettingsRepository()) {
        isLive = !runMode.isEphemeral
        self.repository = repository
        settings = isLive ? repository.load() : Self.sampleSettings
        guard isLive else { return }

        for source in MediaSource.allCases {
            observers.append(DistributedNotificationCenter.default().addObserver(
                forName: FocusPlayerInfo.notificationName(for: source), object: nil, queue: .main
            ) { [weak self] notification in
                let state = FocusPlayerInfo.state(from: notification.userInfo)
                MainActor.assumeIsolated { self?.playerChanged(source, state: state) }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let source = MediaSource.allCases.first(where: { $0.bundleIdentifier == app?.bundleIdentifier })
            else { return }
            MainActor.assumeIsolated { self?.playerChanged(source, state: .stopped) }
        })
        // The Do Not Disturb row in Connections follows the switch and can flip it on.
        ConnectionsStore.shared.follow(doNotDisturb: $settings.map(\.doNotDisturb).eraseToAnyPublisher(),
                                       turnOn: { [weak self] in self?.settings.doNotDisturb = true })
    }

    // MARK: - Timer

    /// Call whenever the focus timer changes. Starts focus mode when a focus
    /// phase starts running, and ends it on a break, pause or reset.
    func timerChanged(_ timer: FocusTimer) {
        activityChanged(FocusActivity(timer), from: .focusTimer)
    }

    /// Call whenever another timer that drives focus mode changes (the
    /// Study tab with deep focus on). Focus mode stays on while any timer
    /// is focusing.
    func activityChanged(_ sourceActivity: FocusActivity, from source: FocusActivitySource) {
        guard isLive else { return }
        activities[source] = sourceActivity
        let activity = FocusActivity.combined(activities.values)
        guard activity != requestedActivity else { return }
        requestedActivity = activity
        let previous = transitions
        transitions = Task { [weak self] in
            await previous?.value
            await self?.transition(to: activity)
        }
    }

    private func transition(to activity: FocusActivity) async {
        // Starting a playlist over music the user is already playing would
        // fight them, so learn a running app's state first if it hasn't
        // posted one since launch.
        if activity == .focusing, let source = settings.playlist?.source,
           Self.isRunning(source), playerStates[source] == nil {
            playerStates[source] = await Self.readState(of: source)
        }
        let actions = session.transition(to: activity, settings: settings) { [playerStates] source in
            Self.isRunning(source) && playerStates[source] == .playing
        }
        isFocusing = session.isFocusing
        for action in actions { perform(action) }
        // A sound picked mid-phase wasn't in the captured settings, so the
        // session doesn't know to stop it; make sure it stops with the phase.
        if !isFocusing, !isPreviewing { engine?.stop() }
    }

    private func perform(_ action: FocusSessionAction) {
        switch action {
        case .startSound(let mix, let volume):
            isPreviewing = false
            playSound(mix, volume: volume)
        case .stopSound:
            if !isPreviewing { engine?.stop() }
        case .runShortcut(let name):
            let previous = shortcutRuns
            shortcutRuns = Task { [shortcuts] in
                await previous?.value
                let result = await shortcuts.run(name)
                if !result.succeeded {
                    Self.log.error("Focus shortcut \"\(name, privacy: .public)\": \(result.message, privacy: .public)")
                }
            }
        case .playPlaylist(let playlist):
            Task { await Self.run(FocusPlaylistScript.play(playlist), on: playlist.source, launching: true) }
        case .resumePlaylist(let source):
            Task { await Self.run(FocusPlaylistScript.resume(source), on: source, launching: false) }
        case .pausePlaylist(let source):
            Task { await Self.run(FocusPlaylistScript.pause(source), on: source, launching: false) }
        }
    }

    private func playerChanged(_ source: MediaSource, state: SpotifyPlayerState?) {
        guard let state else { return }
        playerStates[source] = state
        session.observe(state, of: source)
    }

    // MARK: - Settings and preview

    /// Plays the current sound so the user can hear it from Settings.
    /// Ignored while focusing, since the sound is already playing.
    func setPreviewing(_ previewing: Bool) {
        guard isLive, !isFocusing, previewing != isPreviewing else { return }
        isPreviewing = previewing
        if previewing {
            playSound(settings.mix, volume: settings.volume)
        } else {
            engine?.stop()
        }
    }

    /// Runs a shortcut by name for the Settings Test button.
    func testShortcut(_ name: String) async -> FocusShortcutResult {
        guard isLive else { return .succeeded }
        return await shortcuts.run(name)
    }

    private func settingsChanged(from old: FocusSettings) {
        guard isLive, settings != old else { return }
        repository.save(settings)
        guard isFocusing || isPreviewing else { return }
        if settings.mix != old.mix || settings.volume != old.volume {
            playSound(settings.mix, volume: settings.volume)
        }
    }

    private func playSound(_ mix: FocusMix, volume: Float) {
        // An Off mix never needs the engine; don't build one just to stay silent.
        guard engine != nil || !mix.isOff else { return }
        let engine = engine ?? FocusSoundEngine(volume: volume)
        self.engine = engine
        engine.setVolume(volume)
        engine.setMix(mix)
        engine.play()
    }

    /// What demo mode and snapshots show: a cozy blend and a playlist.
    private static let sampleSettings = FocusSettings(
        mix: FocusMix([.init(sound: .rain), .init(sound: .fireplace, level: 0.6)]),
        volume: 0.45,
        playlistText: "https://open.spotify.com/playlist/0vvXsWCC9xrXsKd4FyS8kM",
        doNotDisturb: true
    )

    // MARK: - AppleScript

    private nonisolated static let log = Logger(subsystem: "Tabbi", category: "Focus")

    private nonisolated static func isRunning(_ source: MediaSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).isEmpty
    }

    /// Serial, and off the main thread: Apple Events can block for seconds.
    private nonisolated static let scriptQueue = DispatchQueue(label: "dev.tabbi.focus.applescript",
                                                               qos: .userInitiated)

    /// Runs `script` against `source`. Unless `launching`, it's skipped when
    /// the app isn't running, since any Apple Event would launch it.
    @discardableResult
    private nonisolated static func run(_ script: String, on source: MediaSource, launching: Bool) async -> String? {
        await withCheckedContinuation { continuation in
            scriptQueue.async {
                guard launching || isRunning(source) else { return continuation.resume(returning: nil) }
                var error: NSDictionary?
                let output = NSAppleScript(source: script)?.executeAndReturnError(&error)
                if let error {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
                    log.error("Focus script for \(source.displayName, privacy: .public) failed: \(message, privacy: .public)")
                    return continuation.resume(returning: nil)
                }
                continuation.resume(returning: output?.stringValue ?? "")
            }
        }
    }

    /// The app's current player state, read once; nil if it can't be read.
    private nonisolated static func readState(of source: MediaSource) async -> SpotifyPlayerState? {
        guard let output = await run(source.readStateScript, on: source, launching: false) else { return nil }
        return source.parse(output)?.state
    }
}

/// A timer that can turn focus mode on.
enum FocusActivitySource: Hashable {
    case focusTimer, study
}
