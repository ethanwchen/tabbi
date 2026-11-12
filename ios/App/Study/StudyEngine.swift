import Foundation
import TabbiKitCore

/// The iPhone's study timer and points, as a pure value: every call takes
/// `now`, so tests replay sessions exactly and the store only adds saving,
/// notifications and the Live Activity.
///
/// The timer is TabbiKitCore's `StudySession`, the same state machine the
/// Mac's Study tab runs, and the points are `PetCloset`'s, so the rules are
/// the Mac's to the minute. Time comes from stored dates, never a ticking
/// counter: an iPhone app is suspended or killed while a session runs, and
/// on the next launch `catchUp(at:)` applies every phase end that passed,
/// each stamped with its real end time.
///
/// Points are credited the way the Mac's Closet credits the Study tab:
/// - Finished focus blocks through `PetCloset.credit(from:to:at:)`, which
///   compares the session's `completedFocusCount` with the count already
///   paid (`PetSave.creditedFocusCount`), so a block is paid once even when
///   it finished while the app was not running.
/// - Focus cut short (Stop, or skipped) through `PetCloset.credit(_:)` from
///   the phase's activity record, the minutes actually studied.
/// The one difference is when a finished block is noticed. The Mac reads the
/// session through `sharedFocus`, which hides an idle session (it would only
/// cover another module's clock), so a block that ends into an idle phase
/// (a Timer, or a focus and break that both ran out while the app slept) is
/// paid at the next start. The iPhone has no other clock, so it also
/// observes the idle session and pays such a block as soon as it sees it.
struct StudyEngine: Equatable {
    /// The module id the Mac logs and credits Study under, so records and
    /// the crediting baseline read the same on both.
    static let source: ModuleID = .study

    /// The methods the iPhone offers: every Mac method except the Anki
    /// sprint, which counts cards from AnkiConnect on the Mac.
    static let menu = StudyMethodMenu(kinds: StudyMethodKind.allCases.filter { $0 != .ankiSprint })

    private(set) var session: StudySession
    private(set) var closet: PetCloset
    private(set) var custom: StudyCustomRhythm
    private(set) var timer: StudyTimerLength
    /// Every study stretch that ran (breaks are not study time), for the
    /// day's tally and a later history screen.
    private(set) var log: StudyLog
    /// The session as last credited; nil until the first observation after
    /// launch, which only compares against the saved baseline.
    private var observed: ProvidedFocus?

    init(session: StudySession? = nil, closet: PetCloset = PetCloset(save: PetSave(profile: .starter(.cat))),
         custom: StudyCustomRhythm = .standard, timer: StudyTimerLength = .standard, log: StudyLog = StudyLog()) {
        let kind = session?.method.kind
        self.session = session.flatMap { Self.menu.offers($0.method.kind) ? $0 : nil }
            ?? StudySession(method: .preset(kind.flatMap { Self.menu.offers($0) ? $0 : nil } ?? Self.menu.startingKind,
                                            custom: custom, timer: timer))
        self.closet = closet
        self.custom = custom
        self.timer = timer
        self.log = log
    }

    /// What one call changed, for the store's side effects.
    struct Update: Equatable {
        /// Phases that ended, oldest first, each with its real end time.
        var ended: [StudyPhaseRecord] = []
        /// Points paid, in the order they were credited.
        var awards: [PetStudyAward] = []

        var isEmpty: Bool { ended.isEmpty && awards.isEmpty }
        /// Whether a phase ran out on its own (a block or a break done).
        var phaseCompleted: Bool { ended.contains { $0.outcome == .completed } }
    }

    // MARK: Controls

    /// Applies every phase end that has passed by `now` and pays for it.
    /// Call on launch, on returning to the foreground and at each phase end.
    @discardableResult
    mutating func catchUp(at now: Date) -> Update {
        settle(at: now) { _ in }
    }

    /// The big button: start, pause, resume, or end a Flowtime stretch,
    /// as on the Mac (`StudyTimerFormat.primaryAction` names it).
    @discardableResult
    mutating func primaryAction(at now: Date) -> Update {
        settle(at: now) { session in
            if session.isRunning, session.phase == .focus, case .openEnded = session.method.focus {
                session.stopFocus(at: now)
            } else if session.isRunning {
                session.pause(at: now)
            } else {
                session.start(at: now)
            }
        }
    }

    /// Ends the session and banks the time so far: the phase is logged as
    /// abandoned with the minutes it ran, which pays like the Mac's Stop.
    @discardableResult
    mutating func stop(at now: Date) -> Update {
        settle(at: now) { $0.reset(at: now) }
    }

    /// Starts over on `kind`'s preset; nothing happens for the current
    /// method or one the iPhone does not offer.
    @discardableResult
    mutating func choose(_ kind: StudyMethodKind, at now: Date) -> Update {
        guard kind != session.method.kind, Self.menu.offers(kind) else { return Update() }
        let method = StudyMethod.preset(kind, custom: custom, timer: timer)
        return settle(at: now) { $0.switchMethod(to: method, at: now) }
    }

    /// A new Timer length. A session on the Timer takes it on at once, and
    /// one already counting keeps at least a minute (`StudySession.retune`).
    @discardableResult
    mutating func setTimer(_ length: StudyTimerLength, at now: Date) -> Update {
        guard length != timer else { return Update() }
        timer = length
        return settle(at: now) { $0.retune(to: length.method, at: now) }
    }

    /// The pet as it should be drawn now.
    var pet: PetProfile { closet.profile }

    /// Points earned on `day`, from the log (the Mac's day tally).
    func summary(on day: Date, calendar: Calendar = .current) -> StudyDayTally {
        log.summary(on: day, calendar: calendar)
    }

    // MARK: Crediting

    /// Catches up to `now`, applies `edit`, then logs and pays everything
    /// that ended: the same order the Mac's Study tab follows (advance
    /// before every action).
    private mutating func settle(at now: Date, _ edit: (inout StudySession) -> Void) -> Update {
        var update = Update()
        update.ended = session.advance(to: now)
        edit(&session)
        let records = session.takeLog()
        // Phase ends from `advance` are already in `update.ended`; add what
        // the edit itself ended (a stop, a skip, a Flowtime stretch).
        update.ended += records.filter { record in !update.ended.contains(record) }
        _ = log.record(records)
        for activity in records.compactMap({ $0.activityRecord(source: Self.source) }) {
            if let award = closet.credit(activity) { update.awards.append(award) }
        }
        let focus = Self.observation(of: session, at: now)
        if let award = closet.credit(from: observed, to: focus, at: now) { update.awards.append(award) }
        observed = focus
        return update
    }

    /// The session as the clock the pet is paid from: `sharedFocus`, or an
    /// idle clock carrying the same count and focus length while nothing
    /// runs, so a finished block is never left waiting for the next start.
    static func observation(of session: StudySession, at now: Date) -> ProvidedFocus {
        if let shared = session.sharedFocus(by: source, at: now) { return shared }
        return ProvidedFocus(
            source: source, phase: session.phase.isBreak ? .rest : .focus,
            label: StudyTimerFormat.phaseName(session.phase, method: session.method), clock: .idle,
            phaseLength: session.phaseDuration,
            focusLength: session.method.duration(of: .focus) ?? session.lastFocusWorked,
            completedFocusCount: session.completedFocusCount, logsEarlyEnds: true
        )
    }
}
