import AppKit
import Combine
import TabbiKitCore
import TabbiKit

/// The Study tab's timer: owns the `StudySession` so a block keeps running
/// while the notch is closed or another tab is showing.
///
/// Like `FocusStore`, time comes from wall-clock dates. A one-shot timer
/// fires at the running phase's end to chime and roll into the next phase,
/// and the view only ticks once a second while the panel is visible. The
/// session is saved on every change so a relaunch picks up where it was.
/// Finished stretches move from the session into the persisted `StudyLog`,
/// which totals the day and holds earned points for the pet ledger.
/// With deep focus on, study phases drive the shared focus mode (sound and
/// Do Not Disturb) through `context.focusMode`, alongside the Focus timer.
/// It also plays the corner pet, which dozes while the clock is stopped,
/// wakes when it runs and celebrates each finished block (`StudyPetCue`).
/// In demo mode it shows a sample Pomodoro round and a sample
/// day, and never touches sounds or disk.
@MainActor
final class StudyStore: ObservableObject {
    @Published private(set) var session: StudySession {
        didSet {
            reportFocusActivity()
            reactPet(from: oldValue)
        }
    }
    /// Whether study phases turn on focus mode. Opt-in, like focus sound.
    @Published private(set) var deepFocus: Bool {
        didSet { reportFocusActivity() }
    }
    /// The moment the view measures against; advances every second while visible.
    @Published private(set) var now = Date()
    /// Every logged study stretch and the points not yet credited to the pet.
    @Published private(set) var log: StudyLog
    /// The methods the picker offers and where a fresh timer starts, set by the kit.
    @Published private(set) var menu: StudyMethodMenu
    /// The user's own lengths for the Custom method.
    @Published private(set) var custom: StudyCustomRhythm
    /// Minutes a day to aim for, set by the kit; shared with Today as progress.
    @Published private(set) var goal: StudyDailyGoal
    /// Cards reviewed today from the modules that share a card goal (Anki),
    /// or nil when none does; an Anki sprint counts its cards from this.
    @Published private(set) var cardsReviewedToday: Int?
    /// Whether an Anki sprint has a card count to follow; the demo's sample
    /// sprint always does.
    var canCountCards: Bool { isDemo || cardsReviewedToday != nil }
    /// The pet in the panel's corner, wearing the look saved by the Closet.
    let pet: PetPlayer

    private let isDemo: Bool
    /// Snapshot runs read the saved session but never write it back, so
    /// rendering with another kit can't change the user's method.
    private let isSnapshot: Bool
    private let defaults = UserDefaults.standard
    private var cancellables: Set<AnyCancellable> = []
    private var isVisible = false
    /// False while the Study module is turned off, so a session left
    /// running in a hidden tab never holds focus mode on.
    private var isEnabled = false
    private var ticker: Timer?
    private var phaseEndTimer: Timer?
    private let logURL: URL?
    /// Set when the log on disk could not be read: new stretches are still
    /// logged in memory, but the file is never overwritten, so nothing is lost.
    private let logIsUnreadable: Bool
    /// Where every phase that ran is logged, as the Study module's.
    private let activity: ActivityLog?
    private let focusMode: FocusController?
    /// Plays a paw print burst over the panel when a block finishes in view.
    private let celebrations: CelebrationCenter?
    /// A block finished while the panel was hidden; the pet celebrates it
    /// the next time the panel shows, so the hop is never played unseen.
    private var celebrationPending = false

    private static let sessionKey = "study.session"
    private static let deepFocusKey = "study.deepFocus"
    private static let customKey = "study.custom"

    /// - Parameters:
    ///   - menu: the active kit's methods; a saved session on a method the
    ///     kit no longer offers moves to its starting method.
    ///   - goal: the active kit's daily study goal.
    ///   - focusMode: plays the focus sound and turns on Do Not Disturb
    ///     during deep focus blocks; nil in tests.
    ///   - petProfile: the study pet's look now; `follow(pet:)` keeps it
    ///     current. Demo runs show their own sample pet.
    ///   - celebrations: plays a paw print burst when a block finishes
    ///     while the panel shows; nil in tests.
    init(menu: StudyMethodMenu = .all, goal: StudyDailyGoal = .standard, storage: EditionStorage,
         activity: ActivityLog? = nil, focusMode: FocusController? = nil, petProfile: PetProfile = .starter(.cat),
         celebrations: CelebrationCenter? = nil, runMode: RunMode) {
        isDemo = runMode.isDemo
        self.focusMode = focusMode
        self.celebrations = celebrations
        isSnapshot = runMode.isSnapshot
        self.activity = activity
        self.menu = menu
        self.goal = goal
        if isDemo {
            custom = Self.demoCustom
            let now = Date()
            let session = Self.demoSession(StudySnapshotState.current, now: now)
            self.session = session
            log = Self.demoLog(now: now)
            deepFocus = true
            logURL = nil
            logIsUnreadable = false
            pet = PetPlayer(profile: .starter(.cat), asleep: StudyPetCue.isDozing(session), seed: 7)
            return
        }
        let custom = defaults.data(forKey: Self.customKey)
            .flatMap { try? JSONDecoder().decode(StudyCustomRhythm.self, from: $0) } ?? .standard
        self.custom = custom
        var saved = defaults.data(forKey: Self.sessionKey)
            .flatMap { try? JSONDecoder().decode(StudySession.self, from: $0) }
            ?? StudySession(method: .preset(menu.startingKind, custom: custom))
        // A phase may have ended while the app wasn't running; catch up quietly.
        let launch = Date()
        saved.advance(to: launch)
        if let kind = menu.replacement(for: saved, kitApplied: false) {
            saved.switchMethod(to: .preset(kind, custom: custom), at: launch)
        }
        // A snapshot of one method shows it fresh, as a new user would see it.
        if let kind = StudySnapshotState.current?.demoMethod { saved = StudySession(method: .preset(kind, custom: custom)) }
        session = saved
        pet = PetPlayer(profile: petProfile, asleep: StudyPetCue.isDozing(saved))
        deepFocus = defaults.bool(forKey: Self.deepFocusKey)
        logURL = Self.logURL(in: storage)
        do {
            log = try logURL.flatMap { try StudyLog.load(from: $0) } ?? StudyLog()
            logIsUnreadable = false
        } catch {
            log = StudyLog()
            logIsUnreadable = true
        }
        scheduleSideEffects()

        // Rolls the shared day tally over at midnight even while the panel is hidden.
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.catchUp() }
            }
            .store(in: &cancellables)
    }

    /// `~/Library/Application Support/<edition>/Study/log.json`.
    static func logURL(in storage: EditionStorage) -> URL? {
        storage.file("log.json", in: "Study")
    }

    /// Dresses the corner pet in the study pet's look as it changes (a new
    /// outfit or breed in the Closet, or a kit's starter pet before the
    /// first save). Demo runs keep their sample pet.
    func follow(pet profiles: AnyPublisher<PetProfile, Never>) {
        guard !isDemo else { return }
        profiles
            .removeDuplicates()
            .sink { [weak self] profile in
                MainActor.assumeIsolated { self?.pet.update(profile: profile) }
            }
            .store(in: &cancellables)
    }

    /// The kit's methods for the picker, with Custom on the user's lengths.
    var methods: [StudyMethod] { menu.methods(custom: custom) }

    var readout: StudyDialReadout { StudyTimerFormat.readout(session, at: now) }
    var progress: Double? { session.progress(at: now) }
    /// Minutes, finished stretches and points logged today.
    var today: StudyDayTally { log.summary(on: now) }

    /// Call from the panel's `onAppear` / `onDisappear`; the clock ticks
    /// only while it's visible.
    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        catchUp()
        updateTicker()
        guard visible else { return }
        if celebrationPending {
            celebrationPending = false
            pet.send(.celebrate)
            if StudyPetCue.isDozing(session) { pet.send(.sleep) }
        }
    }

    /// Called by the module's `start()` / `stop()`.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        reportFocusActivity()
    }

    func setDeepFocus(_ on: Bool) {
        guard on != deepFocus else { return }
        deepFocus = on
        if !isDemo { defaults.set(on, forKey: Self.deepFocusKey) }
    }

    /// The big button: start, pause, resume, or end a Flowtime stretch.
    func primaryAction() {
        catchUp()
        if session.isRunning, session.phase == .focus, case .openEnded = session.method.focus {
            change { $0.stopFocus(at: now) }
        } else if session.isRunning {
            change { $0.pause(at: now) }
        } else {
            change { $0.start(at: now) }
        }
    }

    func pause() {
        catchUp()
        change { $0.pause(at: now) }
    }

    func skip() {
        catchUp()
        change { $0.skip(at: now) }
    }

    func reset() {
        catchUp()
        change { $0.reset(at: now) }
    }

    /// Starts over with `kind`'s preset; no-op if it's already the method.
    func choose(_ kind: StudyMethodKind) {
        guard kind != session.method.kind else { return }
        catchUp()
        change { $0.switchMethod(to: .preset(kind, custom: custom), at: now) }
    }

    /// Saves new Custom lengths. A session on Custom keeps its round and
    /// clock and takes them on at once (`StudySession.retune`).
    func setCustom(_ rhythm: StudyCustomRhythm) {
        guard rhythm != custom else { return }
        custom = rhythm
        if !isDemo, !isSnapshot, let data = try? JSONEncoder().encode(rhythm) {
            defaults.set(data, forKey: Self.customKey)
        }
        catchUp()
        change { $0.retune(to: rhythm.method, at: now) }
    }

    /// Follows a new kit: the picker offers its methods, and a stopped
    /// timer moves to its starting method. A running block is never cut short.
    /// - Parameter kitApplied: true when the user just picked or reset the
    ///   kit, so even a still-offered method gives way to the kit's start.
    func use(_ menu: StudyMethodMenu, goal: StudyDailyGoal, kitApplied: Bool) {
        if menu != self.menu { self.menu = menu }
        if goal != self.goal { self.goal = goal }
        catchUp()
        guard let kind = menu.replacement(for: session, kitApplied: kitApplied) else { return }
        change { $0.switchMethod(to: .preset(kind, custom: custom), at: now) }
    }

    /// Today's study minutes, finished stretches and points, for Wrap Up.
    /// Recomputed when a stretch is logged or the clock moves (so a new day
    /// starts from zero).
    var dayTally: AnyPublisher<StudyDayTally, Never> {
        $log.combineLatest($now)
            .map { log, now in log.summary(on: now) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Today's study minutes against the daily goal, for Today and Plan my
    /// day.
    var goalProgress: AnyPublisher<ProgressItem, Never> {
        dayTally
            .combineLatest($goal)
            .map { tally, goal in goal.progressItem(for: tally) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// The session as the shared focus clock with the deep focus switch,
    /// republished only when either changes: a running block carries its
    /// end (or start) date, so the closed notch counts without a per-second
    /// feed.
    func sharedFocus(by source: ModuleID) -> AnyPublisher<ProvidedFocus?, Never> {
        $session
            .combineLatest($deepFocus)
            .map { $0.sharedFocus(by: source, isDeep: $1, at: Date()) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Counts an Anki sprint's cards from the shared progress goals, so the
    /// timer never depends on the Anki module itself. The demo keeps its
    /// fixed sample sprint.
    func followCards(from snapshots: some Publisher<ProviderSnapshot, Never>) {
        guard !isDemo else { return }
        snapshots
            .map { $0.cardsReviewedToday(excluding: .study) }
            .removeDuplicates()
            .sink { [weak self] count in
                MainActor.assumeIsolated { self?.receiveCards(count) }
            }
            .store(in: &cancellables)
    }

    // MARK: Private

    private func receiveCards(_ count: Int?) {
        cardsReviewedToday = count
        guard count != nil else { return }
        catchUp()
        let finished = session.completedFocusCount
        change { _ in }
        // Reaching the card goal ends the sprint like a timer running out.
        if session.completedFocusCount > finished, !isSnapshot { Self.playChime() }
    }

    /// Applies `edit`, then the latest card count (which sets a sprint's
    /// baseline right after it starts or resumes, and counts cards while it
    /// runs), then saves and re-arms the phase-end timer and ticker.
    private func change(_ edit: (inout StudySession) -> Void) {
        var updated = session
        edit(&updated)
        if let cardsReviewedToday { updated.recordReviewedToday(cardsReviewedToday, at: now) }
        guard updated != session else { return }
        session = updated
        scheduleSideEffects()
        updateTicker()
    }

    /// Moves `now` forward and applies phase ends that have passed, chiming
    /// for one that just happened.
    private func catchUp() {
        now = Date()
        let ended = session.advance(to: now)
        guard !ended.isEmpty else { return }
        // Stale ends (the Mac was asleep) stay quiet.
        if !isDemo, let last = ended.last, now.timeIntervalSince(last.endedAt) < 60 {
            Self.playChime()
        }
        scheduleSideEffects()
        updateTicker()
    }

    /// Moves finished stretches into the log, saves the session and the log,
    /// and arms a one-shot timer for the running phase's end.
    private func scheduleSideEffects() {
        guard !isDemo, !isSnapshot else { return }
        collectLog()
        if let data = try? JSONEncoder().encode(session) { defaults.set(data, forKey: Self.sessionKey) }

        phaseEndTimer?.invalidate()
        phaseEndTimer = nil
        guard let endsAt = session.endsAt else { return }
        let fire = Timer(fire: endsAt, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.catchUp() }
        }
        fire.tolerance = 0.2
        RunLoop.main.add(fire, forMode: .common)
        phaseEndTimer = fire
    }

    /// Ticks once a second, only while the panel is visible and the clock runs.
    private func updateTicker() {
        guard isVisible, session.isRunning, !isDemo else {
            ticker?.invalidate()
            ticker = nil
            return
        }
        guard ticker == nil else { return }
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.catchUp() }
        }
        tick.tolerance = 0.1
        RunLoop.main.add(tick, forMode: .common)
        ticker = tick
    }

    /// Tells focus mode what the session needs. `FocusController` ignores
    /// repeats and is inert in demo and snapshot runs.
    private func reportFocusActivity() {
        focusMode?.activityChanged(FocusActivity(session, deepFocus: deepFocus && isEnabled), from: .study)
    }

    /// Plays the pet's reaction to a session change. A celebration that
    /// would happen out of sight waits for the panel to show; one in view
    /// also scatters paw prints over the panel.
    private func reactPet(from old: StudySession) {
        for event in StudyPetCue.events(from: old, to: session) {
            if event == .celebrate, !isVisible {
                celebrationPending = true
            } else {
                pet.send(event)
                if event == .celebrate {
                    celebrations?.celebrate(.burst, style: .pawPrints, accent: StudyModule.descriptor.accentColor,
                                            from: StudyModule.descriptor.id, hasOwnSound: true)
                }
            }
        }
    }

    /// Drains the session's phase records into the persisted log and the
    /// shared activity log.
    private func collectLog() {
        guard !session.log.isEmpty else { return }
        let records = session.takeLog()
        activity?.record(records.compactMap { $0.activityRecord(source: StudyModule.descriptor.id) })
        var updated = log
        updated.record(records)
        if updated != log {
            log = updated
            if let logURL, !logIsUnreadable { try? log.write(to: logURL) }
        }
    }

    private static func playChime() {
        guard let sound = NSSound(named: "Glass") else { return }
        sound.volume = 0.5
        sound.play()
    }

    /// A believable session part-way through: a Pomodoro on its second
    /// round, a Flowtime stretch counting up, a sprint with cards done, or
    /// another method a bit over a third into its first focus block.
    /// The `paused` snapshot state pauses the Pomodoro, so the pet dozes.
    private static func demoSession(_ state: StudySnapshotState?, now: Date) -> StudySession {
        let kind = state?.demoMethod ?? .pomodoro
        var session = StudySession(method: .preset(kind, custom: demoCustom))
        switch kind {
        case .pomodoro:
            let start = now.addingTimeInterval(-(30 * 60 + 9 * 60 + 47))
            session.start(at: start)
            session.advance(to: start.addingTimeInterval(30 * 60))
            session.start(at: start.addingTimeInterval(30 * 60))
        case .flowtime:
            session.start(at: now.addingTimeInterval(-(23 * 60 + 12)))
        case .ankiSprint:
            let start = now.addingTimeInterval(-(11 * 60 + 5))
            session.start(at: start)
            session.recordReviewedToday(120, at: start)
            session.recordReviewedToday(157, at: now)
        default:
            if case .duration(let length) = session.method.focus {
                session.start(at: now.addingTimeInterval(-(length * 0.38).rounded()))
            }
        }
        _ = session.takeLog()
        if state == .paused { session.pause(at: now) }
        return session
    }

    /// A 45/10 rhythm with a long break every third round.
    private static let demoCustom = StudyCustomRhythm(focusMinutes: 45, breakMinutes: 10, longBreakMinutes: 25,
                                                      longBreakEvery: 3, hasLongBreak: true)

    /// A morning's work: two finished Pomodoros and a short sprint.
    private static func demoLog(now: Date) -> StudyLog {
        let start = Calendar.current.startOfDay(for: now).addingTimeInterval(9 * 3600)
        func stretch(_ method: StudyMethodKind, from minute: Double, minutes: Double, cards: Int? = nil) -> StudyPhaseRecord {
            StudyPhaseRecord(method: method, phase: .focus, startedAt: start.addingTimeInterval(minute * 60),
                             endedAt: start.addingTimeInterval((minute + minutes) * 60),
                             activeDuration: minutes * 60, outcome: .completed, cards: cards)
        }
        var log = StudyLog()
        log.record([stretch(.pomodoro, from: 0, minutes: 25), stretch(.pomodoro, from: 30, minutes: 25),
                    stretch(.ankiSprint, from: 70, minutes: 14, cards: 100)])
        return log
    }
}
