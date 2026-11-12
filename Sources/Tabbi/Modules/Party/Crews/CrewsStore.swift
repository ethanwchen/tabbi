import Combine
import Foundation
import TabbiKitCore

/// The Party tab's Crews mode: My crew, This week, the Hall of Fame, Find,
/// the crew pages and the crest editor (the Crews UI spec), and the finished
/// focus sessions it reports to the board.
///
/// It talks to the server through Party's identity (`PartyStore.crewAccount`)
/// and only while Party is connected, so Crews follows Party's age check and
/// server setting for free, and a snapshot run stays offline exactly when
/// Party does. Like Party it fetches only while Crews mode is on screen; a
/// demo run never fetches and shows `CrewsState.demo`
/// (`TABBI_CREWS_PREVIEW` picks the screen).
///
/// Sessions are the exception: they are queued as they finish (merged, so one
/// stretch is sent once) and sent in the background while I am in a crew,
/// since the board counts them whether or not the panel is open. The Party
/// heartbeat's crews pulse badges the tab when people ask to join my crew and
/// tells the store when the owner I asked lets me in.
@MainActor
final class CrewsStore: ObservableObject {
    @Published private(set) var state: CrewsState
    /// The Party or Crews mode switch at the top left of the Party tab.
    @Published var showsCrews: Bool
    /// The action in flight, so its button can show progress.
    @Published private(set) var pending: CrewAction?
    /// What the crest editor holds while it is open.
    @Published var draft: CrewDraftForm
    /// The crew or member the report card is about, while it shows.
    @Published private(set) var reporting: CrewReportTarget?
    /// The More menu of My crew, while it is open.
    @Published var showsMoreMenu = false
    /// The moment the week's countdown measures against.
    @Published private(set) var now = Date()
    /// Join requests waiting for the crew I own, from the heartbeat.
    @Published private(set) var waitingRequests = 0

    let party: PartyStore
    private let isDemo: Bool
    private let queueFile: CrewSessionQueueFile?
    private var queue: CrewSessionQueue
    private var visible = false
    private var cancellables: Set<AnyCancellable> = []
    private var refreshTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    /// The crew id the last heartbeat named, to notice an approval.
    private var pulseCrew: String??

    /// How often Crews mode refreshes while it shows.
    static let refreshInterval: TimeInterval = 60
    /// How long Find waits after a keystroke before it asks the server.
    static let searchDelay: TimeInterval = 0.35
    /// How long a failed session report waits before trying again.
    static let retryInterval: TimeInterval = 600

    /// - Parameters:
    ///   - storage: where the session queue is kept; nil keeps it in memory.
    ///   - environment: `TABBI_CREWS_PREVIEW` picks a demo screen.
    init(party: PartyStore, runMode: RunMode, storage: URL?,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.party = party
        isDemo = runMode.isDemo
        draft = CrewDraftForm()
        if isDemo {
            let scenario = environment["TABBI_CREWS_PREVIEW"].flatMap(CrewDemoScenario.init) ?? .week
            state = .demo(scenario, now: Date())
            showsCrews = environment["TABBI_CREWS_PREVIEW"] != nil
            queueFile = nil
            queue = CrewSessionQueue()
            draft = Self.demoDraft(for: scenario, state: state)
            waitingRequests = state.mine?.requests.count ?? 0
            return
        }
        state = CrewsState()
        showsCrews = false
        let file = runMode.isSnapshot ? nil : storage.map(CrewSessionQueueFile.init(folder:))
        queueFile = file
        queue = file?.load() ?? CrewSessionQueue()
        // `@Published` sends before the property changes, so the change is
        // taken on the next turn of the main run loop, when `crewAccount`
        // already answers for the new connection.
        party.$state.map(\.connection).removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] connection in
                MainActor.assumeIsolated { self?.connectionDidChange(connection) }
            }
            .store(in: &cancellables)
    }

    // MARK: Following the app

    /// Queues every finished focus stretch the activity log records, and
    /// sends it when I am in a crew.
    func follow(activity records: AnyPublisher<ActivityRecord, Never>) {
        guard !isDemo else { return }
        records
            .compactMap(CrewSessionQueue.session(for:))
            .sink { [weak self] session in
                MainActor.assumeIsolated { self?.queueSession(session) }
            }
            .store(in: &cancellables)
    }

    /// Follows the heartbeat's crews pulse: waiting requests badge the tab,
    /// and a crew appearing means my request was approved.
    func follow(pulse: AnyPublisher<PartyCrewsPulse, Never>) {
        guard !isDemo else { return }
        pulse
            .receive(on: RunLoop.main)
            .sink { [weak self] pulse in
                MainActor.assumeIsolated { self?.didReceive(pulse) }
            }
            .store(in: &cancellables)
    }

    private func didReceive(_ pulse: PartyCrewsPulse) {
        waitingRequests = pulse.requests
        let previous = pulseCrew
        pulseCrew = .some(pulse.crew)
        // A different crew than last seen (approved, removed): fetch mine.
        if let previous, previous != pulse.crew { loadMine(thenSend: true) }
        if let id = pulse.crew, state.mine?.id != id, state.mineLoaded { loadMine(thenSend: true) }
    }

    private func queueSession(_ session: CrewSession) {
        // Not in a crew (as last seen): nothing to count, so nothing is kept.
        guard state.inCrew || !state.mineLoaded else { return }
        queue.add(session)
        saveQueue()
        sendSessions()
    }

    private func connectionDidChange(_ connection: PartyState.Connection) {
        guard connection == .connected else {
            refreshTask?.cancel()
            return
        }
        loadMine(thenSend: true)
        if visible && showsCrews { refreshNow() }
    }

    /// The Party panel appeared or went away.
    func setVisible(_ visible: Bool) {
        self.visible = visible
        if visible && showsCrews { refreshNow() } else { refreshTask?.cancel() }
        if !visible { showsMoreMenu = false }
        scheduleClock()
    }

    /// Flips the Party or Crews mode switch.
    func setShowsCrews(_ shows: Bool) {
        guard shows != showsCrews else { return }
        showsCrews = shows
        showsMoreMenu = false
        if shows && visible { refreshNow() } else { refreshTask?.cancel() }
        scheduleClock()
    }

    // MARK: Navigation

    /// Goes to a section, closing any pushed screen.
    func show(_ section: CrewsState.Section) {
        state.show(section)
        showsMoreMenu = false
        load(section)
    }

    /// Back from a crew page or the editor.
    func pop() {
        state.pop()
        showsMoreMenu = false
    }

    /// Opens a crew's page from a board, Find or a member.
    func open(crew id: String) {
        showsMoreMenu = false
        let from = state.section
        if let mine = state.mine, mine.id == id {
            state.show(.mine)
            return
        }
        if isDemo {
            let data = CrewsState.demo(.crew, now: now)
            if case .crew(let page, _) = data.pushed { state.pushed = .crew(page, from: from) }
            return
        }
        run(.open(id)) { store, account in
            let crew = try await account.perform { try await $0.crew(id: id) }
            store.state.pushed = .crew(crew, from: from)
        }
    }

    /// Opens the crest editor for a new crew (with a random crest) or, for
    /// the owner, to edit mine.
    func openEditor(editing: Bool) {
        showsMoreMenu = false
        if editing, let mine = state.mine, mine.owner {
            draft = CrewDraftForm(editing: mine)
        } else {
            var generator = SystemRandomNumberGenerator()
            draft = CrewDraftForm()
            draft.crest = CrewCrest.random(using: &generator)
        }
        state.pushed = .editor(editing: editing && state.mine?.owner == true, from: state.section)
    }

    func shuffleCrest() {
        var generator = SystemRandomNumberGenerator()
        draft.shuffle(using: &generator)
    }

    // MARK: Actions

    /// Creates my crew from the editor, or saves the owner's edit.
    func saveDraft() {
        guard draft.problem == nil else { return }
        let draft = draft
        if isDemo {
            party.showNotice(String(localized: "This is a demo. Run without TABBI_DEMO to make a crew.", bundle: .tabbi),
                             confirms: false)
            return
        }
        if case .editor(true, _) = state.pushed, let mine = state.mine {
            let change = draft.changes(from: mine)
            run(.save) { store, account in
                let crew = try await account.perform { try await $0.updateCrew(change) }
                store.state.didLoadMine(crew, week: store.state.week)
                store.state.show(.mine)
                store.party.showNotice(String(localized: "Saved.", bundle: .tabbi), confirms: true)
            }
        } else {
            run(.save) { store, account in
                let crew = try await account.perform {
                    try await $0.createCrew(name: draft.cleanName, description: draft.cleanDescription, crest: draft.crest,
                                            visibility: draft.visibility)
                }
                store.state.didLoadMine(crew, week: store.state.week)
                store.state.show(.mine)
                store.loadBoard()
            }
        }
    }

    /// Joins with a typed or pasted invite code (or a whole invite message):
    /// the invite is the owner's yes, so it joins at once.
    func join(invite text: String) {
        guard let code = CrewCode.findInvite(in: text) else {
            party.showNotice(String(localized: "Crew invite codes have \(CrewCode.inviteLength) characters.", bundle: .tabbi),
                             confirms: false)
            return
        }
        if isDemo { return demoOnly() }
        run(.join) { store, account in
            let crew = try await account.perform { try await $0.joinCrew(invite: code) }
            store.state.invite = nil
            store.state.didLoadMine(crew, week: store.state.week)
            store.state.show(.mine)
            store.party.showNotice(String(localized: "You joined \(crew.summary.name).", bundle: .tabbi), confirms: true)
            store.sendSessions()
        }
    }

    /// Asks to join a public crew; its owner lets me in.
    func requestToJoin(_ crew: CrewSummary) {
        if isDemo {
            state.myRequest = CrewMyRequest(crew: crew, requestedAt: now, expiresAt: now.addingTimeInterval(7 * 86_400))
            return
        }
        run(.join) { store, account in
            let outcome = try await account.perform { try await $0.requestToJoin(id: crew.id) }
            switch outcome {
            case .joined(let detail):
                store.state.didLoadMine(detail, week: store.state.week)
                store.state.show(.mine)
                store.party.showNotice(String(localized: "You joined \(detail.summary.name).", bundle: .tabbi), confirms: true)
            case .requested(let request):
                store.state.myRequest = request
                store.party.showNotice(String(localized: "Asked to join \(crew.name). Its owner lets you in.", bundle: .tabbi),
                                       confirms: true)
            }
        }
    }

    /// Withdraws my pending request.
    func cancelRequest() {
        if isDemo {
            state.myRequest = nil
            return
        }
        run(.cancelRequest) { store, account in
            _ = try await account.perform { try await $0.cancelJoinRequest() }
            store.state.myRequest = nil
        }
    }

    /// The owner lets someone in.
    func approve(_ request: CrewJoinRequest) {
        if isDemo {
            state.mine?.requests.removeAll { $0.id == request.id }
            waitingRequests = state.mine?.requests.count ?? 0
            return
        }
        run(.approve(request.ref)) { store, account in
            let crew = try await account.perform { try await $0.approveJoinRequest(ref: request.ref) }
            store.state.didLoadMine(crew, week: store.state.week)
            store.waitingRequests = crew.requests.count
            store.party.showNotice(String(localized: "\(request.name) joined the crew.", bundle: .tabbi), confirms: true)
        }
    }

    /// The owner says no, quietly: the request just goes away.
    func decline(_ request: CrewJoinRequest) {
        if isDemo {
            state.mine?.requests.removeAll { $0.id == request.id }
            waitingRequests = state.mine?.requests.count ?? 0
            return
        }
        run(.decline(request.ref)) { store, account in
            try await account.perform { try await $0.declineJoinRequest(ref: request.ref) }
            store.state.mine?.requests.removeAll { $0.id == request.id }
            store.waitingRequests = store.state.mine?.requests.count ?? 0
        }
    }

    func leave() {
        showsMoreMenu = false
        if isDemo { return demoOnly() }
        let name = state.mine?.summary.name ?? ""
        run(.leave) { store, account in
            _ = try await account.perform { try await $0.leaveCrew() }
            store.state.didLoadMine(nil, week: store.state.week)
            store.party.showNotice(String(localized: "You left \(name).", bundle: .tabbi), confirms: true)
        }
    }

    /// The owner takes a member out; they cannot join this crew again.
    func remove(_ member: CrewMember) {
        if isDemo { return demoOnly() }
        run(.remove(member.ref)) { store, account in
            let crew = try await account.perform { try await $0.removeCrewMember(ref: member.ref) }
            store.state.didLoadMine(crew, week: store.state.week)
            store.party.showNotice(String(localized: "Removed \(member.name) from the crew.", bundle: .tabbi), confirms: true)
        }
    }

    /// Shows or hides my pet on crew pages.
    func setShowsPet(_ shows: Bool) {
        if isDemo { return demoOnly() }
        run(.showPet) { store, account in
            let crew = try await account.perform { try await $0.setShowsPet(shows) }
            store.state.didLoadMine(crew, week: store.state.week)
        }
    }

    func block(_ member: CrewMember, in crew: CrewDetail) {
        if isDemo { return demoOnly() }
        run(.block(member.ref)) { store, account in
            _ = try await account.perform { try await $0.blockCrewMember(crew: crew.id, member: member.ref) }
            store.party.showNotice(String(localized: "Blocked \(member.name). Unblock them in Party options.", bundle: .tabbi),
                                   confirms: true)
            store.refreshNow()
        }
    }

    func beginReport(_ target: CrewReportTarget) {
        showsMoreMenu = false
        reporting = target
    }

    func cancelReport() {
        guard pending != .report else { return }
        reporting = nil
    }

    func sendReport(reason: CrewReportReason, note: String, alsoBlock: Bool) {
        guard let target = reporting else { return }
        if isDemo {
            reporting = nil
            party.showNotice(String(localized: "This is a demo. No report was sent.", bundle: .tabbi), confirms: true)
            return
        }
        run(.report) { store, account in
            _ = try await account.perform {
                try await $0.reportCrew(id: target.crew.id, member: target.member?.ref, reason: reason, note: note)
            }
            store.reporting = nil
            if alsoBlock, let member = target.member {
                _ = try await account.perform { try await $0.blockCrewMember(crew: target.crew.id, member: member.ref) }
                store.party.showNotice(String(localized: "Thanks. Your report was sent and \(member.name) is blocked.", bundle: .tabbi),
                                       confirms: true)
                store.refreshNow()
            } else {
                store.party.showNotice(String(localized: "Thanks. Your report was sent.", bundle: .tabbi), confirms: true)
            }
        }
    }

    private func demoOnly() {
        party.showNotice(String(localized: "This is a demo. Run without TABBI_DEMO to study with a crew.", bundle: .tabbi),
                         confirms: false)
    }

    // MARK: Invites

    /// A crew invite link was opened: My crew asks before joining.
    func open(_ invite: CrewInvite) {
        state.invite = invite.code
        state.show(.mine)
        setShowsCrews(true)
    }

    func dismissInvite() {
        state.invite = nil
    }

    // MARK: Find

    func search(_ query: String) {
        state.query = query
        if isDemo {
            let needle = query.trimmingCharacters(in: .whitespaces)
            let all = CrewsState.demo(.find, now: now).results ?? []
            state.results = needle.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(needle) }
            return
        }
        searchTask?.cancel()
        guard let account = party.crewAccount else { return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.searchDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            do {
                let crews = try await account.perform { try await $0.searchCrews(query) }
                guard !Task.isCancelled, let self, self.state.query == query else { return }
                self.state.results = crews
            } catch {
                guard !Task.isCancelled else { return }
                self?.state.loadError = Self.partyError(error)
            }
        }
    }

    // MARK: Loading

    /// Loads what a section shows.
    private func load(_ section: CrewsState.Section) {
        guard !isDemo else { return }
        switch section {
        case .mine: loadMine(thenSend: false)
        case .week: loadBoard()
        case .hall: loadHall()
        case .find: if state.results == nil { search(state.query) }
        }
    }

    /// Retries after a failure ("Try again" in the offline state).
    func retry() {
        state.loadError = nil
        party.retry()
        refreshNow()
    }

    private func refreshNow() {
        guard !isDemo else { return }
        loadMine(thenSend: false)
        load(state.section)
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        guard visible, showsCrews, !isDemo else { return }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.refreshInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.refreshNow()
        }
    }

    private func loadMine(thenSend: Bool) {
        guard !isDemo, let account = party.crewAccount else { return }
        Task { [weak self] in
            do {
                let (crew, week, request) = try await account.perform { try await $0.myCrew() }
                guard let self else { return }
                self.state.didLoadMine(crew, week: week, request: request)
                self.waitingRequests = crew?.requests.count ?? 0
                if crew == nil {
                    // Nothing to count: forget sessions kept for a crew I left.
                    self.queue = CrewSessionQueue()
                    self.saveQueue()
                } else if thenSend {
                    self.sendSessions()
                }
            } catch {
                self?.state.loadError = Self.partyError(error)
            }
        }
    }

    private func loadBoard() {
        guard !isDemo, let account = party.crewAccount else { return }
        Task { [weak self] in
            do {
                let board = try await account.perform { try await $0.crewBoard() }
                self?.state.didLoadBoard(board)
            } catch {
                self?.state.loadError = Self.partyError(error)
            }
        }
    }

    /// The next page of the weekly board's rows, when the list scrolls near its end.
    func loadMoreBoard() {
        guard !isDemo, let cursor = state.board?.next, let account = party.crewAccount else { return }
        Task { [weak self] in
            if let page = try? await account.perform({ try await $0.crewBoard(cursor: cursor) }) {
                self?.state.didLoadBoard(page, appending: true)
            }
        }
    }

    private func loadHall() {
        guard !isDemo, let account = party.crewAccount else { return }
        Task { [weak self] in
            do {
                let page = try await account.perform { try await $0.crewHall() }
                self?.state.didLoadHall(page)
            } catch {
                self?.state.loadError = Self.partyError(error)
            }
        }
    }

    func loadMoreHall() {
        guard !isDemo, let cursor = state.hallNext, let account = party.crewAccount else { return }
        Task { [weak self] in
            if let page = try? await account.perform({ try await $0.crewHall(cursor: cursor) }) {
                self?.state.didLoadHall(page, appending: true)
            }
        }
    }

    // MARK: Sessions

    /// Sends the queued sessions in batches while I am in a crew; a transient
    /// failure keeps them and tries again later.
    private func sendSessions() {
        guard sendTask == nil, !isDemo, state.inCrew, let account = party.crewAccount else { return }
        queue.prune(now: Date())
        guard !queue.pending.isEmpty else { return }
        sendTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let batch = self.queue.nextBatch
                guard !batch.isEmpty else { break }
                do {
                    let reply = try await account.perform { try await $0.reportCrewSessions(batch) }
                    self.queue.didSend(batch)
                    self.saveQueue()
                    self.didReport(reply)
                } catch {
                    let error = Self.partyError(error)
                    if !error.isTransient {
                        // The server refused the batch itself; it would refuse it again.
                        self.queue.didSend(batch)
                        self.saveQueue()
                        continue
                    }
                    self.sendTask = nil
                    try? await Task.sleep(nanoseconds: UInt64(Self.retryInterval * 1_000_000_000))
                    self.sendSessions()
                    return
                }
            }
            self?.sendTask = nil
        }
    }

    private func didReport(_ reply: CrewSessionsReply) {
        state.week = reply.week
        guard var mine = state.mine else { return }
        if let crewMinutes = reply.crewMinutes { mine.summary.weekMinutes = crewMinutes }
        if let index = mine.members.firstIndex(where: \.me) { mine.members[index].weekMinutes = reply.myMinutes }
        state.mine = mine
    }

    private func saveQueue() {
        try? queueFile?.save(queue)
    }

    // MARK: Plumbing

    /// Ticks `now` when the countdown's text changes, only while it shows.
    private func scheduleClock() {
        clockTask?.cancel()
        now = Date()
        guard visible, showsCrews else { return }
        let next = CrewFormat.nextChange(state.week, now: now)
        clockTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(1, next.timeIntervalSinceNow) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.scheduleClock()
        }
    }

    /// Runs one action: one at a time, with its failure as the panel's notice.
    private func run(_ action: CrewAction, _ body: @escaping (CrewsStore, PartyAccount) async throws -> Void) {
        guard pending == nil else { return }
        guard let account = party.crewAccount else {
            party.showNotice(PartyError.unreachable.message, confirms: false)
            return
        }
        pending = action
        Task { [weak self] in
            guard let self else { return }
            do {
                try await body(self, account)
            } catch {
                let error = Self.partyError(error)
                if case .server(let code, _) = error, code == "not_in_crew" {
                    self.state.didLoadMine(nil, week: self.state.week)
                }
                self.party.showNotice(CrewErrorText.message(error), confirms: false)
            }
            self.pending = nil
        }
    }

    private static func partyError(_ error: any Error) -> PartyError {
        (error as? PartyError) ?? .transport(error.localizedDescription)
    }

    // MARK: Snapshots

    private static func demoDraft(for scenario: CrewDemoScenario, state: CrewsState) -> CrewDraftForm {
        switch scenario {
        case .edit: return state.mine.map(CrewDraftForm.init(editing:)) ?? CrewDraftForm()
        case .create:
            var draft = CrewDraftForm()
            draft.name = "Bibliotheksratten"
            draft.crest = CrewCrest(frame: CrewCatalog.frames[1 % CrewCatalog.frames.count],
                                    emblem: CrewCatalog.emblems[3 % CrewCatalog.emblems.count],
                                    color: CrewCatalog.colors[5 % CrewCatalog.colors.count].id)
            return draft
        default: return CrewDraftForm()
        }
    }

    /// Snapshot runs only: shows a demo screen for the next shot, or the
    /// Party side again with nil.
    func showForSnapshot(_ scenario: CrewDemoScenario?, moreMenu: Bool = false) {
        guard let scenario else {
            showsCrews = false
            reporting = nil
            showsMoreMenu = false
            return
        }
        state = .demo(scenario, now: now)
        draft = Self.demoDraft(for: scenario, state: state)
        waitingRequests = state.mine?.requests.count ?? 0
        reporting = nil
        showsMoreMenu = moreMenu
        showsCrews = true
    }

    /// Snapshot runs only: the report card about a crew's member.
    func showReportForSnapshot() {
        state = .demo(.crew, now: now)
        showsCrews = true
        if case .crew(let crew, _) = state.pushed { reporting = CrewReportTarget(crew: crew.summary, member: crew.members.first) }
    }
}

/// The action in flight.
enum CrewAction: Hashable {
    case save, join, leave, showPet, report, cancelRequest
    case open(String)
    case remove(String)
    case block(String)
    case approve(String)
    case decline(String)
}

/// What a crew report is about: a crew, or one member of it.
struct CrewReportTarget: Hashable, Identifiable {
    let crew: CrewSummary
    let member: CrewMember?

    var id: String { crew.id + (member?.ref ?? "") }
}

/// The crest editor, with the crest builder's choice.
struct CrewDraftForm: Equatable {
    var name = ""
    var description = ""
    var crest = CrewCrest.default
    var visibility = CrewVisibility.public

    init() {}

    init(editing crew: CrewDetail) {
        name = crew.summary.name
        description = crew.summary.description
        crest = crew.summary.crest.resolved
        visibility = crew.summary.visibility
    }

    var cleanName: String { CrewDraftCheck.clean(name) }
    var cleanDescription: String { CrewDraftCheck.clean(description) }

    var problem: CrewDraftCheck.Problem? { CrewDraftCheck.problem(name: name, description: description) }

    /// A new random crest, never the one showing; the name stays.
    mutating func shuffle<G: RandomNumberGenerator>(using generator: inout G) {
        var next = crest
        while next == crest { next = CrewCrest.random(using: &generator) }
        crest = next
    }

    /// Only what changed, for `PATCH /v1/crews/mine`.
    func changes(from crew: CrewDetail) -> CrewDraft {
        let summary = crew.summary
        return CrewDraft(name: cleanName == summary.name ? nil : cleanName,
                         description: cleanDescription == summary.description ? nil : cleanDescription,
                         frame: crest.frame == summary.frame ? nil : crest.frame,
                         emblem: crest.emblem == summary.emblem ? nil : crest.emblem,
                         color: crest.color == summary.color ? nil : crest.color,
                         visibility: visibility == summary.visibility ? nil : visibility)
    }
}
