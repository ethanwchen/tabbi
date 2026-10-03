import Foundation

/// Whether the session clock is moving.
public enum StudyRunState: String, Codable, Hashable, Sendable {
    /// The current phase hasn't started yet.
    case idle
    case running
    case paused
}

/// How a phase ended.
public enum StudyPhaseOutcome: String, Codable, Hashable, Sendable {
    /// Ran its full length or hit its card goal.
    case completed
    /// The user stopped an open-ended Flowtime focus phase, its normal end.
    case stopped
    /// The user ended the phase early and moved on.
    case skipped
    /// The session was reset or switched to another method mid-phase.
    case abandoned

    /// Whether a focus phase with this outcome counts as done, for long-break
    /// cadence and the day's tally.
    public var countsAsDone: Bool { self == .completed || self == .stopped }
}

/// One phase that actually ran, for the session log and notifications.
public struct StudyPhaseRecord: Codable, Hashable, Sendable {
    public var method: StudyMethodKind
    public var phase: StudyPhaseKind
    /// When the phase was first started.
    public var startedAt: Date
    /// Wall-clock end. For a phase that ran out while the app was asleep this
    /// is when it really ended, not when the app noticed.
    public var endedAt: Date
    /// Time the clock was running, excluding pauses.
    public var activeDuration: TimeInterval
    public var outcome: StudyPhaseOutcome
    /// Cards answered during an Anki sprint focus phase; nil otherwise.
    public var cards: Int?

    public init(
        method: StudyMethodKind,
        phase: StudyPhaseKind,
        startedAt: Date,
        endedAt: Date,
        activeDuration: TimeInterval,
        outcome: StudyPhaseOutcome,
        cards: Int? = nil
    ) {
        self.method = method
        self.phase = phase
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeDuration = activeDuration
        self.outcome = outcome
        self.cards = cards
    }
}

/// The study-timer state machine shared by every `StudyMethod`.
///
/// Time comes from wall-clock dates (when the clock last resumed plus the
/// time banked before that), never a ticking counter, so the session stays
/// right while the notch is closed or the Mac sleeps, and a Codable snapshot
/// restored after relaunch picks up exactly where it was. Every call takes
/// `now`, which keeps transitions deterministic and testable.
///
/// Flow mirrors the Today panel's focus timer: when focus (or review) ends,
/// the next phase starts on its own; when a break ends, the next focus phase
/// waits idle so the timer never runs on while the user is away.
/// Open-ended Flowtime focus ends with `stopFocus(at:)`; Anki sprint focus
/// ends when `recordReviewedToday(_:at:)` reaches the card goal.
public struct StudySession: Codable, Hashable, Sendable {
    public private(set) var method: StudyMethod
    public private(set) var phase: StudyPhaseKind
    /// Length of the current phase, or nil for open-ended or card-goal focus.
    /// Fixed when the phase begins, so a proportional break keeps its length.
    public private(set) var phaseDuration: TimeInterval?
    /// Focus phases finished this session (completed or stopped; skips don't count).
    public private(set) var completedFocusCount: Int
    /// Cards answered in the current sprint focus phase.
    public private(set) var cardsDone: Int
    /// Phases that ran, oldest first, until the app collects them with `takeLog()`.
    public private(set) var log: [StudyPhaseRecord]

    /// Running time banked before the current run segment.
    private var banked: TimeInterval
    /// Start of the current run segment; nil while idle or paused.
    private var resumedAt: Date?
    /// First start of the current phase; nil while idle.
    private var phaseStartedAt: Date?
    /// Active time of the last focus phase, which sizes Flowtime breaks.
    public private(set) var lastFocusWorked: TimeInterval
    /// Whether the last focus phase counted, so a skipped one never earns a long break.
    private var lastFocusCounted: Bool
    /// Last reviewed-today count seen from AnkiConnect; cards are its deltas.
    private var cardBaseline: Int?

    public init(method: StudyMethod) {
        self.method = method
        phase = .focus
        phaseDuration = method.duration(of: .focus)
        completedFocusCount = 0
        cardsDone = 0
        log = []
        banked = 0
        resumedAt = nil
        phaseStartedAt = nil
        lastFocusWorked = 0
        lastFocusCounted = false
        cardBaseline = nil
    }

    /// Decodes a saved session, repairing values a corrupt or hand-edited
    /// file could carry: a phase shorter than `StudyMethod.minimumPhase`
    /// (which would complete instantly), non-finite or negative banked time,
    /// and negative tallies. The method itself re-clamps in its own decoder.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decode(StudyMethod.self, forKey: .method)
        phase = try container.decode(StudyPhaseKind.self, forKey: .phase)
        phaseDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .phaseDuration).map {
            $0.isNaN ? StudyMethod.minimumPhase : max($0, StudyMethod.minimumPhase)
        }
        completedFocusCount = max(try container.decode(Int.self, forKey: .completedFocusCount), 0)
        cardsDone = max(try container.decode(Int.self, forKey: .cardsDone), 0)
        log = try container.decode([StudyPhaseRecord].self, forKey: .log)
        banked = Self.nonNegative(try container.decode(TimeInterval.self, forKey: .banked))
        resumedAt = try container.decodeIfPresent(Date.self, forKey: .resumedAt)
        phaseStartedAt = try container.decodeIfPresent(Date.self, forKey: .phaseStartedAt)
        lastFocusWorked = Self.nonNegative(try container.decode(TimeInterval.self, forKey: .lastFocusWorked))
        lastFocusCounted = try container.decode(Bool.self, forKey: .lastFocusCounted)
        cardBaseline = try container.decodeIfPresent(Int.self, forKey: .cardBaseline)
        // A running clock always belongs to a started phase.
        if resumedAt != nil, phaseStartedAt == nil { phaseStartedAt = resumedAt }
    }

    private static func nonNegative(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? max(value, 0) : 0
    }

    // MARK: Reading

    public var runState: StudyRunState {
        if resumedAt != nil { return .running }
        return phaseStartedAt == nil ? .idle : .paused
    }

    public var isRunning: Bool { runState == .running }

    /// Running time in the current phase at `now`, excluding pauses.
    public func elapsed(at now: Date) -> TimeInterval {
        guard let resumedAt else { return banked }
        return banked + max(now.timeIntervalSince(resumedAt), 0)
    }

    /// The moment the running phase would have started had it never paused,
    /// so a clock counting up from it shows `elapsed`; nil unless running.
    public var runningSince: Date? {
        resumedAt.map { $0.addingTimeInterval(-banked) }
    }

    /// Time left at `now`, never negative; nil when the phase has no length.
    public func remaining(at now: Date) -> TimeInterval? {
        phaseDuration.map { max($0 - elapsed(at: now), 0) }
    }

    /// When the running phase runs out, for scheduling a notification.
    public var endsAt: Date? {
        guard let resumedAt, let phaseDuration else { return nil }
        return resumedAt.addingTimeInterval(phaseDuration - banked)
    }

    /// Fraction done, 0...1: time for timed phases, cards for a sprint, and
    /// nil for open-ended focus, which has no finish line.
    public func progress(at now: Date) -> Double? {
        let fraction: Double
        if let phaseDuration {
            fraction = elapsed(at: now) / phaseDuration
        } else if phase == .focus, let goal = method.cardGoal {
            fraction = Double(cardsDone) / Double(goal)
        } else {
            return nil
        }
        return min(max(fraction, 0), 1)
    }

    /// Whether a sprint has gone long enough to suggest a pause even before
    /// the card goal (200 cards or 30 minutes, whichever comes first).
    public func suggestsSprintBreak(at now: Date) -> Bool {
        guard phase == .focus, method.cardGoal != nil else { return false }
        return cardsDone >= StudyMethod.sprintBreakCards || elapsed(at: now) >= StudyMethod.sprintBreakInterval
    }

    // MARK: Controls

    /// Starts an idle phase or resumes a paused one. No-op while running.
    ///
    /// For sprint focus, the next `recordReviewedToday(_:at:)` sets a fresh
    /// card baseline, so call it right after starting.
    public mutating func start(at now: Date) {
        guard resumedAt == nil else { return }
        if phaseStartedAt == nil { phaseStartedAt = now }
        resumedAt = now
        dropStaleCardBaseline()
    }

    /// Freezes the clock. No-op unless running.
    ///
    /// Call `advance(to:)` first so a phase that already ran out isn't paused
    /// with zero seconds left.
    public mutating func pause(at now: Date) {
        guard resumedAt != nil else { return }
        banked = elapsed(at: now)
        resumedAt = nil
    }

    /// Ends the current phase early and moves on.
    ///
    /// The next phase keeps running if the clock was running, so skipping a
    /// break while in flow drops straight into the next focus phase.
    public mutating func skip(at now: Date) {
        let wasRunning = isRunning
        endPhase(at: now, outcome: .skipped, startNext: wasRunning)
    }

    /// Ends an open-ended Flowtime focus phase and starts its proportional
    /// break. Returns false (and does nothing) for any other phase.
    @discardableResult
    public mutating func stopFocus(at now: Date) -> Bool {
        guard phase == .focus, case .openEnded = method.focus, phaseStartedAt != nil else { return false }
        endPhase(at: now, outcome: .stopped, startNext: true)
        return true
    }

    /// Back to an idle first focus phase. Logs the current phase as
    /// abandoned if it had started; keeps the uncollected log.
    public mutating func reset(at now: Date) {
        switchMethod(to: method, at: now)
    }

    /// Starts over with another method, logging the current phase as abandoned.
    public mutating func switchMethod(to newMethod: StudyMethod, at now: Date) {
        if let record = currentRecord(endingAt: now, outcome: .abandoned) { log.append(record) }
        let kept = (log, cardBaseline)
        self = StudySession(method: newMethod)
        (log, cardBaseline) = kept
    }

    /// Swaps in new lengths for the same kind of method without starting
    /// over, e.g. after editing the Custom rhythm mid-session. Rounds,
    /// cards and the clock carry on; the current phase takes its new length,
    /// but a phase already past it ends no sooner than a minute from `now`,
    /// so trimming a block never finishes it on the spot.
    /// Returns false (and does nothing) when `newMethod` is another kind.
    @discardableResult
    public mutating func retune(to newMethod: StudyMethod, at now: Date) -> Bool {
        guard newMethod.kind == method.kind else { return false }
        method = newMethod
        phaseDuration = newMethod.duration(of: phase, workedBeforeBreak: lastFocusWorked).map { length in
            phaseStartedAt == nil ? length : max(length, elapsed(at: now) + StudyMethod.minimumPhase)
        }
        return true
    }

    // MARK: Time and cards

    /// Applies every phase end that has passed by `now` and returns them.
    ///
    /// Usually zero or one. After a long sleep it can be a focus end followed
    /// by the auto-started break's end, each stamped with its real end time.
    @discardableResult
    public mutating func advance(to now: Date) -> [StudyPhaseRecord] {
        var ended: [StudyPhaseRecord] = []
        while let endsAt, endsAt <= now {
            if let record = endPhase(at: endsAt, outcome: .completed, startNext: phase != .shortBreak && phase != .longBreak) {
                ended.append(record)
            }
        }
        return ended
    }

    /// Feeds AnkiConnect's reviewed-today count. Cards answered while a sprint
    /// focus phase runs count toward its goal; reaching it ends the phase.
    ///
    /// Only increases count, so cards answered during a break or a pause are
    /// ignored, and the drop to zero at Anki's day rollover just rebases.
    /// The first reading after a sprint focus starts or resumes only sets the
    /// baseline.
    /// Applies `advance(to:)` first and returns every phase that ended.
    @discardableResult
    public mutating func recordReviewedToday(_ count: Int, at now: Date) -> [StudyPhaseRecord] {
        var ended = advance(to: now)
        defer { cardBaseline = count }
        guard let baseline = cardBaseline else { return ended }
        let delta = count - baseline
        guard delta > 0, isRunning, phase == .focus, let goal = method.cardGoal else { return ended }
        cardsDone += delta
        if cardsDone >= goal, let record = endPhase(at: now, outcome: .completed, startNext: true) {
            ended.append(record)
        }
        return ended
    }

    /// Hands the logged phases to the caller for persistence and clears them.
    public mutating func takeLog() -> [StudyPhaseRecord] {
        defer { log.removeAll() }
        return log
    }

    // MARK: Transitions

    private func currentRecord(endingAt end: Date, outcome: StudyPhaseOutcome) -> StudyPhaseRecord? {
        guard let phaseStartedAt else { return nil }
        let isSprintFocus = phase == .focus && method.cardGoal != nil
        return StudyPhaseRecord(
            method: method.kind,
            phase: phase,
            startedAt: phaseStartedAt,
            endedAt: end,
            activeDuration: elapsed(at: end),
            outcome: outcome,
            cards: isSprintFocus ? cardsDone : nil
        )
    }

    /// Closes the current phase at `end` and enters the next one, running from
    /// `end` if `startNext`, otherwise idle. Returns the logged record, or nil
    /// when the phase never started (skipping an idle phase logs nothing).
    @discardableResult
    private mutating func endPhase(at end: Date, outcome: StudyPhaseOutcome, startNext: Bool) -> StudyPhaseRecord? {
        let record = currentRecord(endingAt: end, outcome: outcome)
        if let record { log.append(record) }

        if phase == .focus {
            lastFocusWorked = elapsed(at: end)
            lastFocusCounted = outcome.countsAsDone
            if lastFocusCounted { completedFocusCount += 1 }
        }
        // A skipped focus phase passes 0 so it can never land on a long break.
        let next = method.nextPhase(after: phase, completedFocusCount: lastFocusCounted ? completedFocusCount : 0)

        phase = next
        phaseDuration = method.duration(of: next, workedBeforeBreak: lastFocusWorked)
        banked = 0
        cardsDone = 0
        phaseStartedAt = startNext ? end : nil
        resumedAt = startNext ? end : nil
        if startNext { dropStaleCardBaseline() }
        return record
    }

    /// Forgets the card baseline when a sprint focus run segment begins.
    /// The app may not poll while the notch is closed, so an older reading
    /// would count cards answered before the sprint started or while paused.
    private mutating func dropStaleCardBaseline() {
        if phase == .focus, method.cardGoal != nil { cardBaseline = nil }
    }
}
