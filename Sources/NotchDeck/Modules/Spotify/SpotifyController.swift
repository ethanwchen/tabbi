import AppKit
import SwiftUI
import NotchDeckCore

/// Spotify playback state and controls.
///
/// Spotify is found through `NSRunningApplication` and is never launched
/// implicitly: AppleScript (which would launch it) only runs after a running
/// check. Updates come from Spotify's `PlaybackStateChanged` distributed
/// notification; while the panel is visible the position ticks locally every
/// second and is re-synced with a 5 s read. With `NOTCHDECK_DEMO=1` it shows
/// `SpotifyPlayback.demo` and never talks to Spotify.
@MainActor
final class SpotifyController: NSObject, ObservableObject {
    /// When true, album art + equalizer show beside the closed notch.
    @Published var showsCompactActivity = false
    /// What the panel shows; the playback position is extrapolated between reads.
    @Published private(set) var status: SpotifyStatus = .notRunning

    private static let playbackChanged = Notification.Name("com.spotify.client.PlaybackStateChanged")
    private static let automationSettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    /// Resync interval while the panel is visible. Never poll faster than this.
    private static let pollInterval: TimeInterval = 5

    private let isDemo = ProcessInfo.processInfo.environment["NOTCHDECK_DEMO"] == "1"
    private var clock: SpotifyPlaybackClock?
    private var isPanelVisible = false
    private var tickTimer: Timer?
    private var pollTimer: Timer?
    /// Bumped by every read and command so a slow, stale read can't overwrite
    /// a newer state (e.g. an optimistic play/pause).
    private var generation = 0

    override init() {
        super.init()
        if isDemo {
            apply(.connected(.demo))
            return
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(applicationsChanged(_:)),
                              name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(applicationsChanged(_:)),
                              name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        // Background (LSUIElement) apps are "inactive", so ask for immediate
        // delivery or Spotify's notifications would queue until activation.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(playbackStateChanged(_:)),
            name: Self.playbackChanged, object: nil, suspensionBehavior: .deliverImmediately
        )
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
        guard let playback = currentStatus.playback, playback.track != nil else { return }
        applyOptimistic(playback.togglingPlayPause())
        send(SpotifyScript.playPause)
    }

    func next() { send(SpotifyScript.nextTrack) }

    func previous() { send(SpotifyScript.previousTrack) }

    func seek(to seconds: TimeInterval) {
        guard let playback = currentStatus.playback, playback.track != nil else { return }
        let target = playback.clampedPosition(seconds)
        applyOptimistic(playback.seeking(to: target))
        send(SpotifyScript.seek(to: target))
    }

    /// Launches Spotify. Only ever called from an explicit user action.
    func openSpotify() {
        guard !isDemo,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyScript.bundleIdentifier)
        else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(Self.automationSettings)
    }

    // MARK: - Reading state

    /// Reads Spotify's state now, if it's running.
    func refresh() {
        guard !isDemo else { return }
        generation += 1
        let current = generation
        guard Self.isRunning else {
            apply(SpotifyStatus.resolve(isRunning: false, isInstalled: Self.isInstalled, read: nil, previous: currentStatus))
            return
        }
        apply(SpotifyStatus.resolve(isRunning: true, isInstalled: true, read: nil, previous: currentStatus))
        Task {
            let result = await Self.run(SpotifyScript.readState)
            guard current == generation else { return }
            apply(SpotifyStatus.resolve(isRunning: Self.isRunning, isInstalled: Self.isInstalled,
                                        read: result, previous: currentStatus))
        }
    }

    /// `status` with the playback position extrapolated to now; `status` itself
    /// only advances while the panel ticks.
    private var currentStatus: SpotifyStatus {
        clock.map { .connected($0.playback(at: Date())) } ?? status
    }

    private func send(_ source: String) {
        if isDemo {
            if source == SpotifyScript.nextTrack || source == SpotifyScript.previousTrack {
                applyOptimistic(SpotifyPlayback.demo.seeking(to: 0))
            }
            return
        }
        guard Self.isRunning else { return refresh() }
        generation += 1
        Task {
            let result = await Self.run(source)
            if case .failure(.permissionDenied) = result {
                apply(.permissionDenied)
            }
            refresh()
        }
    }

    private func applyOptimistic(_ playback: SpotifyPlayback) {
        generation += 1
        apply(.connected(playback))
    }

    /// Sets the confirmed status, re-anchoring the local position clock.
    private func apply(_ newStatus: SpotifyStatus) {
        if let playback = newStatus.playback {
            clock = SpotifyPlaybackClock(anchor: playback, at: Date())
        } else {
            clock = nil
        }
        if status != newStatus { status = newStatus }
        if showsCompactActivity != newStatus.isPlaying { showsCompactActivity = newStatus.isPlaying }
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
        let poll = isPanelVisible && !isDemo && Self.isRunning
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
        guard let clock else { return }
        let playback = clock.playback(at: Date())
        if status.playback != playback { status = .connected(playback) }
    }

    // MARK: - Notifications

    @objc private func applicationsChanged(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard app?.bundleIdentifier == SpotifyScript.bundleIdentifier else { return }
        if notification.name == NSWorkspace.didTerminateApplicationNotification {
            generation += 1
            apply(Self.isInstalled ? .notRunning : .notInstalled)
        } else {
            refresh()
        }
    }

    @objc private func playbackStateChanged(_ notification: Notification) {
        refresh()
    }

    // MARK: - AppleScript

    private static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: SpotifyScript.bundleIdentifier).isEmpty
    }

    private static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyScript.bundleIdentifier) != nil
    }

    /// One serial queue: `NSAppleScript` isn't safe to run concurrently, and
    /// Apple Events can block for seconds, so keep them off the main thread.
    private nonisolated static let scriptQueue = DispatchQueue(label: "dev.notchdeck.spotify.applescript",
                                                               qos: .userInitiated)

    private nonisolated static func run(_ source: String) async -> Result<String, SpotifyScriptError> {
        await withCheckedContinuation { continuation in
            scriptQueue.async {
                // Re-check right before sending: an Apple Event to a quit
                // Spotify would relaunch it.
                guard !NSRunningApplication.runningApplications(
                    withBundleIdentifier: SpotifyScript.bundleIdentifier).isEmpty
                else { return continuation.resume(returning: .failure(.notRunning)) }
                var error: NSDictionary?
                let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
                    continuation.resume(returning: .failure(SpotifyScriptError(code: code)))
                } else {
                    continuation.resume(returning: .success(output?.stringValue ?? ""))
                }
            }
        }
    }
}
