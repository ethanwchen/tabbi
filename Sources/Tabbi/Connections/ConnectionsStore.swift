import AppKit
import Combine
import EventKit
import UserNotifications
import TabbiKitCore

/// Where every connection stands, and the one button that moves each
/// forward. One per app (`shared`), so Settings, onboarding and the tabs'
/// empty states all show the same lights.
///
/// It checks only while someone is looking (between `beginWatching` and
/// `endWatching`): when the first view appears, and again each time Tabbi
/// becomes active, so a fix made in another app turns green on return.
/// Demo runs show `ConnectionKind.demoStatus` and never look at the Mac.
@MainActor
final class ConnectionsStore: ObservableObject {
    static let shared = ConnectionsStore(runMode: .current)

    /// The rows Connections lists. Party joins once its tab shares its state.
    static let listed = ConnectionKind.allCases.filter { $0 != .party }

    /// The latest answer for each connection; absent until its first check.
    @Published private(set) var statuses: [ConnectionKind: ConnectionStatus] = [:]

    let isDemo: Bool
    private let probes = ConnectionProbes()
    private var checks: [ConnectionKind: Task<Void, Never>] = [:]
    private var watchers = 0
    private var activationObserver: NSObjectProtocol?

    init(runMode: RunMode) {
        isDemo = runMode.isDemo
        if isDemo {
            statuses = Dictionary(uniqueKeysWithValues: ConnectionKind.allCases.map { ($0, $0.demoStatus) })
        }
    }

    /// The status to show: the latest answer, or "checking" before the first.
    func status(of kind: ConnectionKind) -> ConnectionStatus {
        statuses[kind] ?? ConnectionStatus(light: .checking, headline: "Checking \(kind.title)",
                                           detail: "This takes a second.")
    }

    // MARK: The hub

    /// Opens the Connections hub. The app installs it at launch (it owns the
    /// Settings window); until then `showHub()` does nothing.
    var hubPresenter: (() -> Void)?

    /// Shows the Connections hub, so a tab's empty state or onboarding can
    /// send the user to the one place that fixes any connection.
    func showHub() {
        hubPresenter?()
    }

    // MARK: Watching

    /// A view showing connections appeared: check now, and on every return
    /// to Tabbi until the last one goes away.
    func beginWatching() {
        watchers += 1
        guard watchers == 1, !isDemo else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func endWatching() {
        watchers = max(watchers - 1, 0)
        guard watchers == 0, let activationObserver else { return }
        NotificationCenter.default.removeObserver(activationObserver)
        self.activationObserver = nil
    }

    /// Checks the given connections again. A check already running for a
    /// row is replaced, so the newest answer always wins.
    func refresh(_ kinds: [ConnectionKind] = ConnectionsStore.listed) {
        guard !isDemo else { return }
        for kind in kinds {
            checks[kind]?.cancel()
            checks[kind] = Task { [weak self, probes] in
                let status = await probes.status(of: kind)
                guard !Task.isCancelled, let self else { return }
                checks[kind] = nil
                statuses[kind] = status
            }
        }
    }

    // MARK: Actions

    /// Runs a row's button. Demo runs only pretend.
    func perform(_ action: ConnectionAction, for kind: ConnectionKind) {
        guard !isDemo else { return }
        switch action {
        case .download(let app):
            if let page = app.downloadPage { NSWorkspace.shared.open(page) }
        case .openApp(let app):
            open(app, for: kind)
        case .openSettings(let link):
            NSWorkspace.shared.open(link.url)
        case .checkAgain:
            refresh([kind])
        case .askPermission(let permission):
            Task { await request(permission, for: kind) }
        case .showGuide(let guide):
            showFallback(for: guide, kind: kind)
        case .setUp:
            refresh([kind])
        }
    }

    /// Opens an app, then checks again once it had time to start (Anki
    /// takes a few seconds before its add-on answers).
    private func open(_ app: ConnectionApp, for kind: ConnectionKind) {
        guard let url = ConnectionProbes.installedURL(of: app) else {
            if let page = app.downloadPage { NSWorkspace.shared.open(page) }
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        Task { [weak self] in
            for delay in [3, 12] {
                try? await Task.sleep(for: .seconds(delay))
                self?.refresh([kind])
            }
        }
    }

    /// Lets macOS show its permission prompt, then checks the answer.
    private func request(_ permission: ConnectionPermission, for kind: ConnectionKind) async {
        switch permission {
        case .calendar:
            _ = try? await EKEventStore().requestFullAccessToEvents()
        case .notifications:
            guard ConnectionProbes.isAppBundle else { break }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        case .automation(let app):
            guard let bundleID = app.bundleIDs.first else { break }
            // macOS can only ask while the app is open, so open it first.
            if !ConnectionProbes.isRunning(app), let url = ConnectionProbes.installedURL(of: app) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
            _ = await ConnectionProbes.automationPermission(for: bundleID, askIfNeeded: true)
        }
        refresh([kind])
    }

    /// Until the walkthroughs exist, each guide button does its single most
    /// useful step.
    private func showFallback(for guide: ConnectionGuide, kind: ConnectionKind) {
        switch guide {
        case .ankiAddOn, .ankiAddOnUpdate, .ankiAccess:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(AnkiConnectClient.addOnCode, forType: .string)
            open(.anki, for: kind)
        case .googleCalendar:
            NSWorkspace.shared.open(SystemSettingsLink.internetAccounts.url)
        case .claudeInstall, .claudeSignIn:
            NSWorkspace.shared.open(ClaudeConnectionState.installPage)
        case .focusShortcuts:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
        }
    }
}
