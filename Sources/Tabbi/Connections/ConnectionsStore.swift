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

    /// The rows Connections lists.
    static let listed = ConnectionKind.allCases

    /// The latest answer for each connection, with the checks behind it;
    /// absent until its first check.
    @Published private(set) var diagnoses: [ConnectionKind: ConnectionDiagnosis] = [:]
    /// When each connection was last checked, for "Copy details".
    private(set) var checkedAt: [ConnectionKind: Date] = [:]
    /// The rows with a check running right now.
    @Published private(set) var running: Set<ConnectionKind> = []
    /// The latest Do Not Disturb test, shown under its row until the next.
    @Published private(set) var doNotDisturbTest: DoNotDisturbTest?

    let isDemo: Bool
    private let probes = ConnectionProbes()
    private var checks: [ConnectionKind: Task<Void, Never>] = [:]
    private var waiting: [ConnectionKind: Task<Void, Never>] = [:]
    private var watchers = 0
    private var activationObserver: NSObjectProtocol?
    /// What the Party tab shares (see `follow(party:)`).
    @Published private var party: PartyLink?
    private var partyCancellables: Set<AnyCancellable> = []

    init(runMode: RunMode) {
        isDemo = runMode.isDemo
        if isDemo {
            diagnoses = Dictionary(uniqueKeysWithValues: ConnectionKind.allCases.map { ($0, $0.demoDiagnosis) })
        }
    }

    /// The status to show: the latest answer, or "checking" before the first.
    func status(of kind: ConnectionKind) -> ConnectionStatus {
        diagnoses[kind]?.status ?? ConnectionStatus(light: .checking, headline: "Checking \(kind.title)",
                                                    detail: "This takes a second.")
    }

    /// The troubleshooter's checks, or nil before the first check finishes.
    func diagnosis(of kind: ConnectionKind) -> ConnectionDiagnosis? {
        diagnoses[kind]
    }

    /// The text "Copy details" puts on the clipboard for support.
    func details(of kind: ConnectionKind) -> String? {
        guard let diagnosis = diagnoses[kind] else { return nil }
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String).map { version in
            (info?["CFBundleVersion"] as? String).map { "\(version) (\($0))" } ?? version
        } ?? "development build"
        let system = ProcessInfo.processInfo.operatingSystemVersion
        return diagnosis.details(
            appVersion: isDemo ? "\(version), demo" : version,
            systemVersion: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
            checkedAt: checkedAt[kind] ?? Date()
        )
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
            // Party's state comes from its tab as it changes; no probe.
            if kind == .party {
                showParty()
                continue
            }
            checks[kind]?.cancel()
            running.insert(kind)
            checks[kind] = Task { [weak self, probes] in
                let diagnosis = await probes.diagnosis(of: kind)
                guard !Task.isCancelled, let self else { return }
                checks[kind] = nil
                running.remove(kind)
                diagnoses[kind] = diagnosis
                checkedAt[kind] = Date()
            }
        }
    }

    // MARK: Party

    /// What the Party tab shares with Connections: where it stands, the
    /// name and pet it would use, and how to start it from the setup sheet.
    struct PartyLink {
        var state: PartyConnectionState = .connecting
        var name = ""
        var species: PetSpecies = .cat
        /// Saves the name and pet; Party registers by itself after that.
        let start: @MainActor (_ name: String, _ species: PetSpecies) -> Void
        /// Tries the server again now.
        let retry: @MainActor () -> Void
    }

    /// Lets the Party tab report where it stands, so its row needs no
    /// probe and the setup sheet can start it. The tab calls this once.
    func follow(party state: AnyPublisher<PartyConnectionState, Never>,
                name: AnyPublisher<String, Never>, species: AnyPublisher<PetSpecies, Never>,
                start: @escaping @MainActor (_ name: String, _ species: PetSpecies) -> Void,
                retry: @escaping @MainActor () -> Void) {
        partyCancellables = []
        party = PartyLink(start: start, retry: retry)
        state.removeDuplicates()
            .sink { [weak self] in
                self?.party?.state = $0
                self?.showParty()
            }
            .store(in: &partyCancellables)
        name.sink { [weak self] in self?.party?.name = $0 }.store(in: &partyCancellables)
        species.sink { [weak self] in self?.party?.species = $0 }.store(in: &partyCancellables)
    }

    /// Where Party stands, for its setup sheet.
    var partyState: PartyConnectionState {
        isDemo ? .connected(friendCode: "PUFF-42") : party?.state ?? .connecting
    }

    /// The name and pet the setup sheet starts from.
    var partyDraft: (name: String, species: PetSpecies) {
        (party?.name ?? "", party?.species ?? .cat)
    }

    /// The setup sheet's start button: saves the name and pet, then Party
    /// registers by itself and the row turns green.
    func startParty(name: String, species: PetSpecies) {
        guard !isDemo else { return }
        party?.start(name, species)
    }

    private func showParty() {
        guard !isDemo, let party else { return }
        diagnoses[.party] = party.state.diagnosis
        checkedAt[.party] = Date()
    }

    // MARK: Waiting for a walkthrough

    /// While a walkthrough is open, checks its row every few seconds, so
    /// the sheet turns green as soon as the steps work, even when the user
    /// never leaves Tabbi (Anki and Terminal can sit beside it).
    func beginWaiting(for kind: ConnectionKind) {
        waiting[kind]?.cancel()
        guard !isDemo else { return }
        waiting[kind] = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshIfIdle(kind)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Checks a row unless a check is already running, so a slow probe
    /// (Claude's takes a moment) isn't restarted before it can answer.
    private func refreshIfIdle(_ kind: ConnectionKind) {
        guard checks[kind] == nil else { return }
        refresh([kind])
    }

    func endWaiting(for kind: ConnectionKind) {
        waiting[kind]?.cancel()
        waiting[kind] = nil
    }

    /// The walkthrough for a guide, naming the user's own shortcuts.
    func walkthrough(for guide: ConnectionGuide) -> ConnectionWalkthrough {
        guard guide == .focusShortcuts, !isDemo else { return guide.walkthrough() }
        let names = ConnectionProbes.focusShortcutNames()
        return guide.walkthrough(onShortcut: names.on, offShortcut: names.off)
    }

    // MARK: Actions

    /// Runs a row's button. Guides and permission prompts open a sheet in
    /// the list first (see `ConnectionsList`), which then calls `run` or
    /// `request`. Demo runs only pretend.
    func perform(_ action: ConnectionAction, for kind: ConnectionKind) {
        guard !isDemo else { return }
        switch action {
        case .download(let app):
            if let page = app.downloadPage { NSWorkspace.shared.open(page) }
        case .openApp(let app):
            open(app, for: kind)
        case .openSettings(let link):
            NSWorkspace.shared.open(link.url)
        case .checkAgain where kind == .party:
            party?.retry()
        case .checkAgain, .setUp, .showGuide:
            refresh([kind])
        case .askPermission(let permission):
            Task { await request(permission, for: kind) }
        case .copyFriendCode(let code):
            copy(code)
        case .testDoNotDisturb:
            testDoNotDisturb()
        }
    }

    /// Runs the user's Focus shortcuts once, on then off, so they see Do
    /// Not Disturb really switch. Demo runs pretend it worked.
    func testDoNotDisturb() {
        guard doNotDisturbTest?.isRunning != true else { return }
        guard !isDemo else {
            doNotDisturbTest = .passed
            return
        }
        let names = ConnectionProbes.focusShortcutNames()
        Task { [weak self] in
            let runner = FocusShortcutRunner()
            let result = await DoNotDisturbTest.run(onName: names.on, offName: names.off,
                                                    run: { await runner.run($0) },
                                                    update: { @MainActor [weak self] stage in self?.showTest(stage) })
            // A missing shortcut means the row is out of date.
            if case .failed(_, _, .notFound) = result { self?.refresh([.doNotDisturb]) }
        }
    }

    private func showTest(_ stage: DoNotDisturbTest) {
        doNotDisturbTest = stage
    }

    /// Runs a walkthrough's start button.
    func run(_ step: ConnectionStepAction, for kind: ConnectionKind) {
        guard !isDemo else { return }
        switch step {
        case .copyAndOpen(let text, let app):
            copy(text)
            open(app, for: kind)
        case .openApp(let app):
            open(app, for: kind)
        case .openSettings(let link):
            NSWorkspace.shared.open(link.url)
        }
    }

    /// Puts text on the clipboard (a code or line from a walkthrough).
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Opens an app, then checks again once it had time to start (Anki
    /// takes a few seconds before its add-on answers). Terminal and
    /// Shortcuts always come with the Mac.
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
    /// Call it from the priming screen's Continue button.
    func request(_ permission: ConnectionPermission, for kind: ConnectionKind) async {
        guard !isDemo else { return }
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
}
