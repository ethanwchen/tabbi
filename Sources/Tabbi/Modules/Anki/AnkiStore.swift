import AppKit
import Combine
import TabbiKitCore
import TabbiKit

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
    /// The deck a click is opening, while Anki starts or AnkiConnect
    /// answers, for the panel's "Opening Anki" state.
    @Published private(set) var opening: AnkiOpening?
    /// How the last click on a deck went wrong, shown briefly in the panel.
    @Published private(set) var openNotice: AnkiOpenOutcome? {
        didSet { scheduleOpenNoticeExpiry() }
    }
    /// Bumped at each Anki-day rollover so `provision` re-checks whether
    /// the summary is still today's even when no new one arrives.
    @Published private var rolloverCount = 0

    let isDemo: Bool
    /// A screen pinned by `TABBI_ANKI_STATE` for snapshots; nothing
    /// refreshes while it is set.
    private let pinnedState = ProcessInfo.processInfo.environment["TABBI_ANKI_STATE"]
        .flatMap(AnkiConnectionState.init(previewName:))
    /// Demo or pinned: sample data only, no AnkiConnect calls.
    private var isStatic: Bool { isDemo || pinnedState != nil }
    private let client: AnkiConnectClient
    private let opener: AnkiDeckOpener
    private var openTask: Task<Void, Never>?
    private var openNoticeTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var rolloverTask: Task<Void, Never>?
    private var actionErrorTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isPanelVisible = false
    /// Where newly answered cards are logged, as the Anki module's.
    private let activity: ActivityLog?
    /// Plays a confetti milestone when the review streak reaches a round length.
    private let celebrations: CelebrationCenter?
    /// The streak length last seen, the baseline for `StreakMilestone.reached`.
    private var seenStreak: Int?
    /// A milestone reached while the notch was closed (Anki refreshes when
    /// it loses focus after a review session), saved for the next open panel.
    private var pendingMilestone: Int?

    init(activity: ActivityLog? = nil, celebrations: CelebrationCenter? = nil, runMode: RunMode) {
        self.activity = activity
        self.celebrations = celebrations
        isDemo = runMode.isDemo
        let client = AnkiConnectClient(isAnkiRunning: { await MainActor.run { AnkiWorkspaceLauncher.runningAnki() != nil } })
        self.client = client
        opener = AnkiDeckOpener(client: client, launcher: AnkiWorkspaceLauncher())
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
        if isStatic { pinOpenPreview() }
    }

    /// Pins the result of a click named by `TABBI_ANKI_OPEN` (`launching`,
    /// `opening`, or an `AnkiOpenOutcome` preview name) for snapshots.
    private func pinOpenPreview() {
        guard let name = ProcessInfo.processInfo.environment["TABBI_ANKI_OPEN"] else { return }
        let deck = summary?.topDecks.first?.name ?? "Default"
        switch name.lowercased() {
        case "launching": opening = AnkiOpening(deck: deck, phase: .launching)
        case "opening": opening = AnkiOpening(deck: deck, phase: .opening)
        default: openNotice = AnkiOpenOutcome(previewName: name, deck: deck)
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
        openTask?.cancel()
        openTask = nil
        opening = nil
        openNotice = nil
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
        let anki = AnkiWorkspaceLauncher.runningAnki()
        switch outcome {
        case .success(let value):
            summary = value
            updatedAt = now
            state = .ready
            logReviews(value, now: now)
            noteStreak(value.streak)
        case .failure(let error):
            state = .resolve(error: error, isInstalled: Self.isInstalled, launchedAt: anki?.launchDate, now: now)
            if !state.keepsLastSummary { summary = nil }
        }
        if shouldPoll { schedulePoll() } else { stopPolling() }
    }

    /// Celebrates a streak that just reached a milestone, once, over the open
    /// panel. Opening the panel always refreshes, so a milestone reached out
    /// of sight plays on the next open, unless the streak broke meanwhile.
    func noteStreak(_ streak: Int) {
        if let reached = StreakMilestone.reached(from: seenStreak, to: streak) {
            pendingMilestone = reached
        }
        seenStreak = streak
        guard let milestone = pendingMilestone else { return }
        guard streak >= milestone else {
            pendingMilestone = nil
            return
        }
        guard let celebrations, celebrations.isShowing else { return }
        pendingMilestone = nil
        celebrations.celebrate(.milestone, style: .confetti, accent: AnkiModule.descriptor.accentColor,
                               from: AnkiModule.descriptor.id)
    }

    /// Logs the cards answered since the last logged count. The log is read
    /// back each time (yesterday and today, which covers Anki's rollover),
    /// so a relaunch never logs the same cards twice.
    private func logReviews(_ summary: AnkiSummary, now: Date) {
        guard let activity else { return }
        let today = PlannerDayKey(date: now)
        let yesterday = PlannerDayKey(date: now.addingTimeInterval(-86_400))
        let logged = activity.records(from: yesterday, through: today)
        if let record = summary.reviewActivity(after: logged, source: AnkiModule.descriptor.id, now: now) {
            activity.record(record)
        }
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
        guard let url = AnkiWorkspaceLauncher.applicationURL else {
            AnkiWorkspaceLauncher.runningAnki()?.activate()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    /// Quits Anki and opens it again, the last step after installing or
    /// updating AnkiConnect (add-ons load only at launch). Anki saves and
    /// may sync on quit, so wait up to a minute for it to exit.
    func restartAnki() {
        guard !isStatic, !isRestarting, let anki = AnkiWorkspaceLauncher.runningAnki() else { return }
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

    /// One click on a deck: brings Anki forward, starting it if it is
    /// closed, and opens `deck` (or the deck with the most due) for review
    /// once AnkiConnect answers. A newer click replaces one still waiting.
    func startReviews(deck: String? = nil) {
        guard !isStatic else { return }
        let name = (deck ?? summary?.topDecks.first?.name).flatMap(AnkiDeckName.normalized)
        openTask?.cancel()
        openNotice = nil
        opening = nil
        openTask = Task { [weak self, opener] in
            let outcome = try? await opener.open(deck: name) { phase in
                await self?.show(phase, deck: name)
            }
            guard let self, let outcome, !Task.isCancelled else { return }
            finishOpening(outcome)
        }
    }

    private func show(_ phase: AnkiOpenPhase, deck: String?) {
        guard !Task.isCancelled else { return }
        opening = AnkiOpening(deck: deck, phase: phase)
    }

    private func finishOpening(_ outcome: AnkiOpenOutcome) {
        openTask = nil
        opening = nil
        guard isStarted else { return }
        openNotice = outcome.isSuccess ? nil : outcome
        if outcome.isSuccess { actionError = nil }
        // A launch or a missing deck changes what Anki has to show.
        refresh()
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

    /// Clears a failed click's notice after a while. The add-on step stays
    /// longer, since following it means switching to Anki and back.
    private func scheduleOpenNoticeExpiry() {
        openNoticeTask?.cancel()
        guard let openNotice, !isStatic else { return }
        let lifetime = openNotice == .addOnMissing ? Self.actionErrorLifetime * 4 : Self.actionErrorLifetime
        openNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(lifetime))
            guard !Task.isCancelled else { return }
            self?.openNotice = nil
        }
    }

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

    static var isInstalled: Bool { AnkiWorkspaceLauncher.applicationURL != nil }
}

/// A click opening a deck in Anki, while it waits.
struct AnkiOpening: Equatable {
    /// The full deck name, or nil when only Anki itself is opening.
    var deck: String?
    var phase: AnkiOpenPhase
}
