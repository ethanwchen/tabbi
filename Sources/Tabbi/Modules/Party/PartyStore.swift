import AppKit
import Combine
import TabbiKitCore

/// The Party tab's connection to the friends server: it keeps my profile
/// and presence in sync, refreshes friends and the party while the panel is
/// open, and runs the panel's actions.
///
/// All timing follows the backend's polling guidance through the core
/// types: `PartyPresenceTracker` decides when the shared focus timer is
/// worth a heartbeat, `PartyHeartbeatSchedule` when the next one is due or
/// how long to back off, and `PartyRefreshPlan` when friends and the party
/// are fetched (never while the panel is hidden). Heartbeats stop after an
/// `offline` one, which is sent when going invisible, when the Mac sleeps,
/// and when the module stops or the app quits.
///
/// With `TABBI_DEMO=1` it shows `PartyState.demo` (or the screen
/// `TABBI_PARTY_PREVIEW` names) and never touches the
/// network or the Keychain. Neither does a live `--snapshot` run, which
/// would otherwise register a throwaway user on the production server: it
/// renders the state a first launch shows before the server answers.
/// `TABBI_PARTY_SERVER=http://localhost:8787` makes a snapshot run
/// render a local worker's real data instead (see `localSnapshotServer`).
@MainActor
final class PartyStore: ObservableObject {
    @Published private(set) var state: PartyState {
        didSet { scheduleSessionEnd() }
    }
    @Published private(set) var settings: PartySettings
    /// The moment countdowns measure against; ticks while the panel shows.
    @Published private(set) var now = Date()
    /// The action in flight, so its button can show progress.
    @Published private(set) var pending: PartyAction?
    /// The last action's failure, shown once under the control that caused it.
    @Published private(set) var notice: String?

    let isDemo: Bool
    /// A `--snapshot` render: stays offline so no user is ever registered,
    /// unless `snapshotServer` names a local worker to render live data from.
    private let isSnapshot: Bool
    private var snapshotServer: URL?
    private let repository: PartySettingsRepository?
    private let credentials: any PartyCredentialStore
    /// Replaces HTTPS in tests; nil talks to the server.
    private let transport: (any PartyTransport)?
    private let defaults = UserDefaults.standard
    private var account: PartyAccount?
    private var tracker: PartyPresenceTracker
    private var heartbeats = PartyHeartbeatSchedule()
    private var connectBackoff = PartyHeartbeatSchedule()
    private var plan = PartyRefreshPlan()
    /// The study timer from the shared providers, for presence.
    private var focus: ProvidedFocus?
    /// My pet as friends should see it.
    private(set) var pet = PetProfile.starter(.cat)
    private var isRunning = false

    private var connectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var nameSyncTask: Task<Void, Never>?
    /// Moves `now` to the shared session's end, so the Timer tab and the
    /// closed notch drop it on time even while the panel is hidden.
    private var sessionEndTask: Task<Void, Never>?
    /// Writes a name edited in Party back to the app-wide name.
    private var saveName: ((String) -> Void)?
    /// True when `TABBI_PARTY_NAME` picked the name a local snapshot renders as.
    private var pinsName = false
    private var cancellables: Set<AnyCancellable> = []

    private static let trackerKey = "party.presence"

    /// - Parameter environment: the snapshot-only knobs, such as
    ///   `TABBI_PARTY_PREVIEW` and a local `TABBI_PARTY_SERVER`.
    ///   `transport` replaces HTTPS (tests).
    init(runMode: RunMode, environment: [String: String] = ProcessInfo.processInfo.environment,
         transport: (any PartyTransport)? = nil) {
        isDemo = runMode.isDemo
        self.transport = transport
        isSnapshot = runMode.isSnapshot
        if isDemo {
            repository = nil
            credentials = InMemoryPartyCredentialStore()
            settings = PartySettings(name: "Sam")
            // `TABBI_PARTY_PREVIEW=lobby` and friends pick another screen for snapshots.
            let scenario = environment["TABBI_PARTY_PREVIEW"].flatMap(PartyDemoScenario.init) ?? .hosting
            state = .demo(scenario, now: Date())
            tracker = PartyPresenceTracker()
            return
        }
        if isSnapshot, let local = Self.localSnapshotServer(environment) {
            // An end-to-end snapshot against a local worker: connect as
            // the given user (or a new one) and render what the server returns.
            repository = nil
            snapshotServer = local.server
            pinsName = environment["TABBI_PARTY_NAME"] != nil
            let settings = PartySettings(serverText: local.server.absoluteString,
                                         name: environment["TABBI_PARTY_NAME"] ?? "Sam")
            self.settings = settings
            credentials = InMemoryPartyCredentialStore(local.credentials.map { [local.server: $0] } ?? [:])
            state = PartyState(settings: settings)
            tracker = PartyPresenceTracker()
            return
        }
        let repository = PartySettingsRepository()
        self.repository = repository
        credentials = isSnapshot
            ? InMemoryPartyCredentialStore()
            : KeychainPartyCredentialStore(service: Edition.current.bundleIdentifier + ".party")
        let settings = repository.load()
        self.settings = settings
        state = PartyState(settings: settings)
        tracker = defaults.data(forKey: Self.trackerKey)
            .flatMap { try? JSONDecoder().decode(PartyPresenceTracker.self, from: $0) } ?? PartyPresenceTracker()
        tracker.setInvisible(settings.invisible)
    }

    /// Follows the shared focus timer, so presence reflects whichever
    /// module runs it (Focus, Today, Study) without reaching into them.
    func followFocus(from timers: AnyPublisher<ProvidedFocus?, Never>) {
        timers
            .removeDuplicates()
            .sink { [weak self] timer in self?.focusDidChange(timer) }
            .store(in: &cancellables)
    }

    /// Follows the study pet (`context.studyPet`), so friends see the pet
    /// dressed in the Closet rather than a starter.
    func follow(pet profiles: AnyPublisher<PetProfile, Never>) {
        profiles
            .sink { [weak self] profile in self?.update(pet: profile) }
            .store(in: &cancellables)
    }

    /// Makes the app-wide name (`AppSettings.displayName`) the name friends
    /// see: Party shows and syncs whatever `names` publishes, and a name
    /// edited in Party (its pane, onboarding, Connections) goes back
    /// through `save`, so there is one name to change.
    func follow(name names: AnyPublisher<String, Never>, save: @escaping (String) -> Void) {
        saveName = save
        names
            .removeDuplicates()
            .sink { [weak self] name in self?.nameDidChange(name) }
            .store(in: &cancellables)
    }

    private func nameDidChange(_ name: String) {
        guard name != settings.name, !pinsName else { return }
        let old = settings
        settings.name = name
        repository?.save(settings)
        if settings.cleanedName != old.cleanedName { scheduleNameSync() }
    }

    /// Syncs a new name once typing pauses, since General saves the name
    /// on every keystroke and each sync is a request.
    private func scheduleNameSync() {
        nameSyncTask?.cancel()
        guard isRunning, !isDemo else { return }
        nameSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(Self.nameSyncDelay))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    private static let nameSyncDelay: TimeInterval = 1

    /// `TABBI_PARTY_SERVER` for a `--snapshot` run, with the optional
    /// `TABBI_PARTY_TOKEN` and `TABBI_PARTY_CODE` of the user to
    /// render as. Only plain-http servers count, which `PartyServer.parse`
    /// allows for this Mac alone, so a snapshot can never register users
    /// on a deployed server.
    private static func localSnapshotServer(_ environment: [String: String])
        -> (server: URL, credentials: PartyCredentials?)? {
        guard let text = environment["TABBI_PARTY_SERVER"],
              let server = PartyServer.parse(text), server.scheme == "http" else { return nil }
        let credentials = environment["TABBI_PARTY_TOKEN"].flatMap { token in
            environment["TABBI_PARTY_CODE"].map { PartyCredentials(token: token, code: $0) }
        }
        return (server, credentials)
    }

    // MARK: Lifecycle

    /// The module was enabled: connect and start heartbeats.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduleSessionEnd()
        guard !isDemo, !isSnapshot || snapshotServer != nil else { return }
        if snapshotServer != nil {
            // Nothing calls `onAppear` in an offscreen render; load as if open.
            plan.setVisible(true)
            rebuildAccount()
            return
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        rebuildAccount()
    }

    /// The module was disabled or the app is quitting: tell friends I'm
    /// offline (best effort) and stop every timer.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        connectTask?.cancel()
        refreshTask?.cancel()
        nameSyncTask?.cancel()
        sendOfflineOnce()
    }

    /// The panel appeared or disappeared; refreshes only run while it shows.
    func setVisible(_ visible: Bool) {
        now = Date()
        plan.setVisible(visible)
        clockTask?.cancel()
        if visible {
            clockTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    self?.now = Date()
                }
            }
            if case .unreachable = state.connection { retry() }
        }
        scheduleRefresh()
    }

    // MARK: Settings

    /// Applies edited settings: a new server starts over with that server's
    /// identity, a new name becomes the app-wide name and syncs, and the
    /// invisible toggle sends one heartbeat (`offline`, or the current
    /// status when coming back).
    func update(_ new: PartySettings) {
        let old = settings
        guard new != old else { return }
        settings = new
        repository?.save(new)
        if new.name != old.name { saveName?(new.name) }
        guard !isDemo else { return }
        if new.serverURL != old.serverURL || new.serverIssue != old.serverIssue {
            state.reset(settings: new)
            rebuildAccount()
            return
        }
        if new.cleanedName != old.cleanedName { scheduleNameSync() }
        if new.invisible != old.invisible, tracker.setInvisible(new.invisible) {
            saveTracker()
            sendHeartbeat()
        }
    }

    /// My pet changed (e.g. in the Closet): friends see it after the sync.
    func update(pet: PetProfile) {
        guard pet != self.pet else { return }
        self.pet = pet
        if account != nil { connect() }
    }

    // MARK: Actions

    /// Tries the server again now, after `unreachable` or a stale refresh.
    func retry() {
        guard !isDemo else { return }
        connectBackoff.reset()
        heartbeats.reset()
        if state.connection == .connected {
            plan.invalidate(.friends)
            plan.invalidate(.party)
            scheduleRefresh()
        } else {
            connect()
        }
    }

    func addFriend(code text: String) {
        guard let code = PartyCode.normalize(text, length: PartyCode.friendCodeLength) else {
            notice = "Friend codes are \(PartyCode.friendCodeLength) letters and digits."
            return
        }
        run(.addFriend) { store, account in
            let (_, friend) = try await account.perform { try await $0.addFriend(code: code) }
            store.state.didAddFriend(friend, at: Date())
            store.plan.invalidate(.friends)
        }
    }

    func removeFriend(code: String) {
        run(.removeFriend(code)) { store, account in
            _ = try await account.perform { try await $0.removeFriend(code: code) }
            store.state.didRemoveFriend(code: code)
        }
    }

    func createParty() {
        run(.createParty) { store, account in
            let party = try await account.perform { try await $0.createParty() }
            store.state.didFetchParty(.success(party))
        }
    }

    func joinParty(code text: String) {
        guard let code = PartyCode.normalize(text, length: PartyCode.partyCodeLength) else {
            notice = "Party codes are \(PartyCode.partyCodeLength) letters and digits."
            return
        }
        run(.joinParty) { store, account in
            let party = try await account.perform { try await $0.joinParty(code: code) }
            store.state.didFetchParty(.success(party))
        }
    }

    /// Joins the party a friend is in.
    func join(friend code: String) {
        run(.joinFriend(code)) { store, account in
            let party = try await account.perform { try await $0.joinParty(friend: code) }
            store.state.didFetchParty(.success(party))
            store.plan.invalidate(.friends)
        }
    }

    func leaveParty() {
        run(.leaveParty) { store, account in
            _ = try await account.perform { try await $0.leaveParty() }
            store.state.didFetchParty(.success(nil))
            store.plan.invalidate(.friends)
        }
    }

    /// Host only: starts a shared focus phase of `minutes` for everyone.
    func startSession(minutes: Int) {
        let method = tracker.method
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        run(.session) { store, account in
            let party = try await account.perform { try await $0.startSession(method: method, phaseEndsAt: end) }
            store.state.didFetchParty(.success(party))
        }
    }

    /// Host only: ends the shared session.
    func endSession() {
        run(.session) { store, account in
            let party = try await account.perform { try await $0.endSession() }
            store.state.didFetchParty(.success(party))
        }
    }

    /// Steps out of the shared session while it goes on for the others.
    /// Only on this Mac: the server keeps the session for the party.
    func leaveSession() {
        state.leaveSession()
    }

    func rejoinSession() {
        state.rejoinSession()
    }

    /// The party and its shared session for other modules, republished
    /// when either changes (and when the session runs out).
    var provided: AnyPublisher<ProvidedParty?, Never> {
        $state.combineLatest($now)
            .map { state, now in state.provided(at: now) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Shared sessions that ran to their end with me in them, once each
    /// (`PartySessionTracker`), so the module can pay and log them.
    var completedSessions: AnyPublisher<PartySessionCompletion, Never> {
        var tracker = PartySessionTracker()
        return provided
            .map { $0?.session }
            .compactMap { tracker.observe($0, at: Date()) }
            .eraseToAnyPublisher()
    }

    func clearNotice() {
        notice = nil
    }

    /// Runs one panel action: one at a time, with its failure as `notice`.
    private func run(_ action: PartyAction, _ body: @escaping (PartyStore, PartyAccount) async throws -> Void) {
        guard pending == nil else { return }
        notice = nil
        if isDemo {
            notice = "This is a demo. Run without TABBI_DEMO to study with friends."
            return
        }
        guard let account else { return }
        pending = action
        Task { [weak self] in
            guard let self else { return }
            do {
                try await body(self, account)
            } catch {
                let error = Self.partyError(error)
                if error == .notInParty || error == .partyNotFound { state.didFetchParty(.failure(error)) }
                notice = error.message
            }
            pending = nil
            plan.inParty = state.inParty
            scheduleRefresh()
        }
    }

    // MARK: Connection

    private func rebuildAccount() {
        connectTask?.cancel()
        heartbeatTask?.cancel()
        refreshTask?.cancel()
        heartbeats.reset()
        connectBackoff.reset()
        guard let server = settings.serverURL else {
            account = nil
            return
        }
        account = PartyAccount(server: server, transport: transport, credentials: credentials)
        connect()
    }

    /// Registers or syncs the profile, then sends the launch heartbeat.
    private func connect() {
        guard isRunning, let account else { return }
        connectTask?.cancel()
        state.willReconnect()
        let update = settings.profileUpdate(for: pet)
        connectTask = Task { [weak self] in
            do {
                let profile = try await account.connect(profile: update)
                guard let self, !Task.isCancelled, self.account === account else { return }
                connectBackoff.reset()
                state.didConnect(profile)
                sendHeartbeat()
                scheduleRefresh()
            } catch {
                guard let self, !Task.isCancelled, self.account === account else { return }
                let error = Self.partyError(error)
                state.didFailToConnect(error)
                guard let delay = connectBackoff.delayAfterFailure(error) else { return }
                try? await Task.sleep(nanoseconds: Self.nanoseconds(delay))
                guard !Task.isCancelled else { return }
                connect()
            }
        }
    }

    // MARK: Presence

    private func focusDidChange(_ timer: ProvidedFocus?) {
        focus = timer
        guard !isDemo else { return }
        let changed = tracker.observe(timer, at: Date())
        saveTracker()
        if changed { sendHeartbeat() }
    }

    /// Sends a heartbeat now and schedules the next one from the reply.
    private func sendHeartbeat() {
        guard isRunning, let account, state.connection == .connected else { return }
        heartbeatTask?.cancel()
        tracker.observe(focus, at: Date())
        let body = tracker.heartbeat(at: Date())
        saveTracker()
        heartbeatTask = Task { [weak self] in
            let delay: TimeInterval?
            do {
                let reply = try await account.perform { try await $0.heartbeat(body) }
                guard let self, !Task.isCancelled else { return }
                delay = heartbeats.delayAfterSuccess(reply)
            } catch {
                guard let self, !Task.isCancelled else { return }
                delay = heartbeats.delayAfterFailure(Self.partyError(error))
            }
            guard let delay else { return }
            try? await Task.sleep(nanoseconds: Self.nanoseconds(delay))
            guard let self, !Task.isCancelled else { return }
            sendHeartbeat()
        }
    }

    /// One `offline` heartbeat with no follow-up, unless already invisible
    /// (which sent it).
    ///
    /// Waits up to `wait` seconds for it, because it's sent when the app is
    /// quitting or the Mac is about to sleep: a request left to an async
    /// task would never leave the machine.
    private func sendOfflineOnce(wait: TimeInterval = 2) {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        guard let account, state.connection == .connected, !tracker.isInvisible else { return }
        let sent = DispatchSemaphore(value: 0)
        Task.detached {
            _ = try? await account.perform { try await $0.heartbeat(.offline) }
            sent.signal()
        }
        _ = sent.wait(timeout: .now() + wait)
    }

    @objc private func willSleep() {
        sendOfflineOnce()
    }

    @objc private func didWake() {
        heartbeats.reset()
        if state.connection == .connected { sendHeartbeat() } else { connect() }
    }

    private func saveTracker() {
        guard !isDemo, let data = try? JSONEncoder().encode(tracker) else { return }
        defaults.set(data, forKey: Self.trackerKey)
    }

    // MARK: Refresh

    /// Sleeps until the next feed is due, fetches it, and repeats while the
    /// panel is visible.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        plan.inParty = state.inParty
        guard !isDemo, isRunning, state.connection == .connected, let account, let next = plan.nextDue() else { return }
        refreshTask = Task { [weak self] in
            let wait = next.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: Self.nanoseconds(wait)) }
            guard let self, !Task.isCancelled else { return }
            for feed in plan.due(at: Date()) {
                plan.didFetch(feed, at: Date())
                await fetch(feed, from: account)
                guard !Task.isCancelled else { return }
            }
            scheduleRefresh()
        }
    }

    private func fetch(_ feed: PartyFeed, from account: PartyAccount) async {
        do {
            switch feed {
            case .friends:
                let friends = try await account.perform { try await $0.friends() }
                state.didFetchFriends(.success(friends))
            case .party:
                let party = try await account.perform { try await $0.party() }
                state.didFetchParty(.success(party))
            }
        } catch is CancellationError {
            return
        } catch {
            let error = Self.partyError(error)
            switch feed {
            case .friends: state.didFetchFriends(.failure(error))
            case .party: state.didFetchParty(.failure(error))
            }
        }
    }

    private func scheduleSessionEnd() {
        sessionEndTask?.cancel()
        guard let end = state.session(at: Date())?.endsAt else { return }
        sessionEndTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.now = Date()
        }
    }

    private static func partyError(_ error: any Error) -> PartyError {
        error as? PartyError ?? .transport(error.localizedDescription)
    }

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(seconds, 0) * 1_000_000_000)
    }
}

/// A panel action in flight.
enum PartyAction: Hashable {
    case addFriend
    case removeFriend(String)
    case createParty
    case joinParty
    case joinFriend(String)
    case leaveParty
    case session
}
