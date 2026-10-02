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
    /// The last Sync or Start reviews failure, shown briefly in the panel.
    @Published private(set) var actionError: AnkiConnectError?

    let isDemo = ProcessInfo.processInfo.environment["NOTCHDECK_DEMO"] == "1"
    private let client: AnkiConnectClient
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isPanelVisible = false

    init() {
        client = AnkiConnectClient(isAnkiRunning: { await MainActor.run { AnkiStore.runningAnki() != nil } })
        if isDemo {
            summary = .demo()
            updatedAt = Date()
            state = .ready
        }
    }

    // MARK: Lifecycle

    /// The module was enabled: fetch once so Today and the ticker have
    /// numbers, then follow Anki's launches and quits.
    func start() {
        guard !isDemo, workspaceObservers.isEmpty else { return }
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
    }

    func stop() {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        stopPolling()
    }

    func panelDidAppear() {
        isPanelVisible = true
        guard !isDemo else { return }
        refresh()
        schedulePoll()
    }

    func panelDidDisappear() {
        isPanelVisible = false
        stopPolling()
    }

    // MARK: Refresh

    /// Fetches the summary. A refresh already in flight is replaced, so the
    /// newest request always wins.
    func refresh() {
        guard !isDemo else { return }
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
        if isPanelVisible { schedulePoll() }
    }

    /// One timer at a time, re-armed after every refresh with the interval
    /// the current state calls for.
    private func schedulePoll() {
        pollTask?.cancel()
        let interval = state.refreshInterval
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, let self, isPanelVisible else { return }
            refresh()
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Actions

    /// Opens Anki, which starts AnkiConnect along with it.
    func openAnki() {
        guard let url = Self.ankiURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    /// Opens `deck` (or the deck with the most due) for review and brings
    /// Anki forward, which `guiDeckReview` doesn't do on its own.
    func startReviews(deck: String? = nil) {
        guard let name = deck ?? summary?.topDecks.first?.name else {
            Self.runningAnki()?.activate()
            return
        }
        guard !isDemo else { return }
        Task { [weak self, client] in
            do {
                try await client.guiDeckReview(name: name)
                Self.runningAnki()?.activate()
                self?.actionError = nil
            } catch let error as AnkiConnectError {
                self?.actionError = error
            } catch {}
        }
    }

    /// Syncs with AnkiWeb, then refreshes the counts.
    func sync() {
        guard !isDemo, !isSyncing else { return }
        isSyncing = true
        Task { [weak self, client] in
            var failure: AnkiConnectError?
            do { try await client.sync() } catch let error as AnkiConnectError { failure = error } catch {}
            guard let self else { return }
            isSyncing = false
            actionError = failure
            refresh()
        }
    }

    // MARK: Sharing

    /// Today's reviews as a shared progress goal, while the summary is
    /// current. Yesterday's numbers are never shared as today's.
    func provision(source: ModuleID) -> AnyPublisher<ModuleProvision, Never> {
        $summary
            .map { summary in
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
