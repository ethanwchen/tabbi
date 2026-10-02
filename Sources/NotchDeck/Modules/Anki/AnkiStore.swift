import AppKit
import Combine
import NotchKitCore

/// State for the Anki tab: the AnkiConnect connection and today's summary.
///
/// Refreshes when the module starts, when the panel opens, on a timer only
/// while the panel is visible (fast during setup steps, every few minutes
/// once connected), and when Anki launches, quits, or loses focus after a
/// review session. The rest of the time nothing polls. The summary is
/// shared with Today and the ticker through `provision`.
@MainActor
final class AnkiStore: ObservableObject {
    @Published private(set) var state: AnkiConnectionState = .checking
    /// The latest good summary; kept through transient problems.
    @Published private(set) var summary: AnkiSummary?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSyncing = false
    @Published private(set) var isRestarting = false
    /// The last Sync or Start reviews failure, shown briefly in the panel.
    @Published private(set) var actionError: AnkiConnectError? {
        didSet { scheduleActionErrorExpiry() }
    }
    /// Bumped at each Anki-day rollover so `provision` re-checks whether
    /// the summary is still today's even when no new one arrives.
    @Published private var rolloverCount = 0

    let isDemo = ProcessInfo.processInfo.environment["NOTCHDECK_DEMO"] == "1"
    /// A screen pinned by `NOTCHDECK_ANKI_STATE` for snapshots; nothing
    /// refreshes while it is set.
    private let pinnedState = ProcessInfo.processInfo.environment["NOTCHDECK_ANKI_STATE"]
        .flatMap(AnkiConnectionState.init(previewName:))
    /// Demo or pinned: sample data only, no AnkiConnect calls.
    private var isStatic: Bool { isDemo || pinnedState != nil }
    private let client: AnkiConnectClient
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var rolloverTask: Task<Void, Never>?
    private var actionErrorTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isPanelVisible = false

    init() {
        client = AnkiConnectClient(isAnkiRunning: { await MainActor.run { AnkiStore.runningAnki() != nil } })
        if let pinnedState {
            state = pinnedState
            if pinnedState.keepsLastSummary && pinnedState != .checking {
                summary = .demo()
                updatedAt = Date().addingTimeInterval(pinnedState == .ready ? 0 : -9 * 60)
            }
        } else if isDemo {
            summary = .demo()
            updatedAt = Date()
            state = .ready
        }
    }

    /// Why the shown numbers may be stale: a failed refresh, or else the
    /// last failed Sync or Start reviews.
    var problem: AnkiConnectError? {
        if case .problem(let error) = state { return error }
        return actionError
    }

    // MARK: Lifecycle

    /// The module was enabled: fetch once so Today and the ticker have
    /// numbers, then follow Anki's launches and quits.
    func start() {
        guard !isStatic, workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
        ]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let app, AnkiConnectClient.isAnkiApp(bundleIdentifier: app.bundleIdentifier, localizedName: app.localizedName) else { return }
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
        scheduleRollover()
    }

    /// Between `start()` and `stop()`; late action results are dropped
    /// once the module is off.
    private var isStarted: Bool { !workspaceObservers.isEmpty }

    func stop() {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        rolloverTask?.cancel()
        rolloverTask = nil
        actionError = nil
        stopPolling()
    }

    func panelDidAppear() {
        isPanelVisible = true
        guard !isStatic else { return }
        refresh()
        schedulePoll()
    }

    func panelDidDisappear() {
        isPanelVisible = false
        if !state.pollsWhileHidden { stopPolling() }
    }

    // MARK: Refresh

    /// Fetches the summary. A refresh already in flight is replaced, so the
    /// newest request always wins.
    func refresh() {
        guard !isStatic else { return }
        refreshTask?.cancel()
        isRefreshing = true
        refreshTask = Task { [weak self, client] in
            let outcome: Result<AnkiSummary, AnkiConnectError>
            do {
                outcome = .success(try await client.summary())
            } catch let error as AnkiConnectError {
                outcome = .failure(error)
            } catch {
                return // Cancelled: a newer refresh or stop() owns the state.
            }
            guard !Task.isCancelled else { return }
            self?.finishRefresh(outcome)
        }
    }

    private func finishRefresh(_ outcome: Result<AnkiSummary, AnkiConnectError>) {
        refreshTask = nil
        isRefreshing = false
        let now = Date()
        let anki = Self.runningAnki()
        switch outcome {
        case .success(let value):
            summary = value
            updatedAt = now
            state = .ready
        case .failure(let error):
            state = .resolve(error: error, isInstalled: Self.isInstalled, launchedAt: anki?.launchDate, now: now)
            if !state.keepsLastSummary { summary = nil }
        }
        if shouldPoll { schedulePoll() } else { stopPolling() }
    }

    /// One timer at a time, re-armed after every refresh with the interval
    /// the current state calls for.
    private func schedulePoll() {
        pollTask?.cancel()
        let interval = state.refreshInterval
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, let self, shouldPoll else { return }
            refresh()
        }
    }

    /// Polls run while the panel shows, or while Anki is starting up.
    private var shouldPoll: Bool { isPanelVisible || state.pollsWhileHidden }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Once a day, at Anki's rollover: stop sharing yesterday's numbers and
    /// fetch the new day's. One wake-up per day, not a poll.
    private func scheduleRollover() {
        rolloverTask?.cancel()
        let delay = max(AnkiSummary.nextRollover(after: Date()).timeIntervalSinceNow, 1)
        rolloverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            rolloverCount += 1
            refresh()
            scheduleRollover()
        }
    }

    // MARK: Actions

    /// Opens Anki, which starts AnkiConnect along with it, and brings it
    /// forward if it is already running.
    func openAnki() {
        guard let url = Self.ankiURL else {
            Self.runningAnki()?.activate()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }


    /// Quits Anki and opens it again, the last step after installing or
    /// updating AnkiConnect (add-ons load only at launch). Anki saves and
    /// may sync on quit, so wait up to a minute for it to exit.
    func restartAnki() {
        guard !isStatic, !isRestarting, let anki = Self.runningAnki() else { return }
        isRestarting = true
        anki.terminate()
        Task { [weak self] in
            for _ in 0..<120 where !anki.isTerminated {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let self else { return }
            isRestarting = false
            if anki.isTerminated { openAnki() } else { anki.activate() }
        }
    }

    /// Opens the Anki download page in the browser.
    func getAnki() {
        guard let url = URL(string: "https://apps.ankiweb.net") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens `deck` (or the deck with the most due) for review and brings
    /// Anki forward, which `guiDeckReview` doesn't do on its own.
    func startReviews(deck: String? = nil) {
        guard let name = deck ?? summary?.topDecks.first?.name else {
            Self.runningAnki()?.activate()
            return
        }
        guard !isStatic else { return }
        Task { [weak self, client] in
            do {
                try await client.guiDeckReview(name: name)
                Self.runningAnki()?.activate()
                guard self?.isStarted == true else { return }
                self?.actionError = nil
            } catch let error as AnkiConnectError {
                guard self?.isStarted == true else { return }
                self?.actionError = error
            } catch {}
        }
    }

    /// Syncs with AnkiWeb, then refreshes the counts.
    func sync() {
        guard !isStatic, !isSyncing else { return }
        isSyncing = true
        Task { [weak self, client] in
            var failure: AnkiConnectError?
            do { try await client.sync() } catch let error as AnkiConnectError { failure = error } catch {}
            guard let self else { return }
            isSyncing = false
            guard isStarted else { return }
            actionError = failure
            refresh()
        }
    }

    /// Clears a Sync or Start reviews failure after a few seconds, so one
    /// failed action doesn't leave a warning up for good.
    private func scheduleActionErrorExpiry() {
        actionErrorTask?.cancel()
        guard actionError != nil else { return }
        actionErrorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.actionErrorLifetime))
            guard !Task.isCancelled else { return }
            self?.actionError = nil
        }
    }

    private static let actionErrorLifetime: TimeInterval = 8

    // MARK: Sharing

    /// Today's reviews as a shared progress goal, while the summary is
    /// current. Yesterday's numbers are never shared as today's.
    func provision(source: ModuleID) -> AnyPublisher<ModuleProvision, Never> {
        $summary
            .combineLatest($rolloverCount)
            .map { summary, _ in
                guard let summary, summary.isCurrent(now: Date()) else { return ModuleProvision.empty }
                return ModuleProvision(progress: [summary.progressItem(source: source)])
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    // MARK: Finding Anki

    /// The running Anki, matched by either bundle id or by name.
    private static func runningAnki() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            AnkiConnectClient.isAnkiApp(bundleIdentifier: $0.bundleIdentifier, localizedName: $0.localizedName)
        }
    }

    private static var ankiURL: URL? {
        AnkiConnectClient.ankiBundleIdentifiers.lazy
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
    }

    static var isInstalled: Bool { ankiURL != nil }
}
