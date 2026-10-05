import Foundation

/// The study-timer presets Tabbi offers, plus a user-defined one.
///
/// Interval lengths are conventions rather than science (see
/// `StudyMethodInfo`), so each kind is a preset of `StudyMethod` parameters
/// and the engine treats every method the same way.
public enum StudyMethodKind: String, Codable, CaseIterable, Hashable, Sendable {
    case pomodoro
    case fiftyTwoSeventeen
    case ultradian
    case flowtime
    case ankiSprint
    case questionBlock
    case custom
    /// A plain countdown with no breaks, for everyday things (a 5 min tea,
    /// a 10 min tidy-up, a 25 min task).
    case timer
}

/// What happens in one stretch of a study session.
public enum StudyPhaseKind: String, Codable, CaseIterable, Hashable, Sendable {
    /// Studying: a timed block, an open-ended Flowtime stretch, or a card sprint.
    case focus
    /// Going through question explanations after a question block.
    case review
    case shortBreak
    case longBreak

    public var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

/// When a focus phase ends.
public enum StudyFocusTarget: Codable, Hashable, Sendable {
    /// After a fixed wall-clock length.
    case duration(TimeInterval)
    /// When the user stops it (Flowtime).
    case openEnded
    /// After this many Anki cards are answered (Anki sprint).
    case cards(Int)
}

/// How Flowtime turns time worked into a break.
public enum FlowtimeBreakScheme: String, Codable, CaseIterable, Hashable, Sendable {
    /// 5 min after up to 25 min of work, 8 min after up to 50, otherwise 10.
    /// This is the scheme used by Smits, Wenzel & de Bruin (2025).
    case tiered
    /// A fifth of the time worked, e.g. 10 min after 50.
    case fifth

    /// Break length after `worked` seconds of focus, never shorter than a minute.
    public func breakDuration(afterWorking worked: TimeInterval) -> TimeInterval {
        let minutes = worked.isFinite ? max(worked, 0) / 60 : 0
        switch self {
        case .tiered:
            if minutes <= 25 { return 5 * 60 }
            if minutes <= 50 { return 8 * 60 }
            return 10 * 60
        case .fifth:
            // Whole minutes keep the countdown tidy; one minute is the floor
            // so a tiny stretch still gets a real pause.
            return max((minutes / 5).rounded(), 1) * 60
        }
    }
}

/// How long a regular break lasts.
public enum StudyBreakRule: Codable, Hashable, Sendable {
    case fixed(TimeInterval)
    /// Scales with how long the focus phase actually ran (Flowtime).
    case proportional(FlowtimeBreakScheme)
    /// No break: the timer stops once focus ends (the plain Timer).
    case none
}

/// A longer break that replaces every `every`-th regular break.
///
/// Fields are immutable and decoding goes through `init`, so `every >= 2`
/// and the 1 min...4 h duration hold however the value was made.
public struct StudyLongBreak: Codable, Hashable, Sendable {
    public let duration: TimeInterval
    public let every: Int

    public init(duration: TimeInterval, every: Int) {
        self.duration = StudyMethod.clamped(duration)
        self.every = max(every, 2)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            duration: try container.decode(TimeInterval.self, forKey: .duration),
            every: try container.decode(Int.self, forKey: .every)
        )
    }
}

/// Parameters of a study method: the phase lengths and break rules the
/// session engine follows.
///
/// A session cycles focus -> (review) -> break -> focus. `nextPhase` and
/// `duration(of:...)` are the only rules the engine needs, so presets and
/// custom methods run through identical code. Codable so a running session
/// can persist the exact method it started with. Fields are immutable and
/// decoding goes through `init`, so the clamping rules hold on every path.
public struct StudyMethod: Codable, Hashable, Sendable, Identifiable {
    /// Shortest phase the engine accepts, so a bad custom value never makes a
    /// zero-length phase that would complete instantly.
    public static let minimumPhase: TimeInterval = 60
    /// Longest timed phase accepted for a custom method (4 hours).
    public static let maximumPhase: TimeInterval = 4 * 60 * 60

    public let kind: StudyMethodKind
    public let focus: StudyFocusTarget
    public let breakRule: StudyBreakRule
    public let longBreak: StudyLongBreak?
    /// Length of the review phase that follows each focus phase, if any.
    public let review: TimeInterval?
    /// Questions per block, shown as a target ("40 questions"); not enforced.
    public let questionCount: Int?

    public var id: StudyMethodKind { kind }

    public init(
        kind: StudyMethodKind,
        focus: StudyFocusTarget,
        breakRule: StudyBreakRule,
        longBreak: StudyLongBreak? = nil,
        review: TimeInterval? = nil,
        questionCount: Int? = nil
    ) {
        self.kind = kind
        self.focus = Self.clamped(focus)
        self.breakRule = Self.clamped(breakRule)
        self.longBreak = longBreak
        self.review = review.map(Self.clamped)
        self.questionCount = questionCount.map { max($0, 1) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(StudyMethodKind.self, forKey: .kind),
            focus: try container.decode(StudyFocusTarget.self, forKey: .focus),
            breakRule: try container.decode(StudyBreakRule.self, forKey: .breakRule),
            longBreak: try container.decodeIfPresent(StudyLongBreak.self, forKey: .longBreak),
            review: try container.decodeIfPresent(TimeInterval.self, forKey: .review),
            questionCount: try container.decodeIfPresent(Int.self, forKey: .questionCount)
        )
    }

    // MARK: Presets

    /// 25 min focus, 5 min break, 15 min long break after every 4th focus.
    public static let pomodoro = StudyMethod(
        kind: .pomodoro,
        focus: .duration(25 * 60),
        breakRule: .fixed(5 * 60),
        longBreak: StudyLongBreak(duration: 15 * 60, every: 4)
    )

    /// 52 min focus, 17 min break.
    public static let fiftyTwoSeventeen = StudyMethod(
        kind: .fiftyTwoSeventeen,
        focus: .duration(52 * 60),
        breakRule: .fixed(17 * 60)
    )

    /// 90 min deep block, 20 min rest.
    public static let ultradian = StudyMethod(
        kind: .ultradian,
        focus: .duration(90 * 60),
        breakRule: .fixed(20 * 60)
    )

    /// Open-ended focus; the break scales with the time worked.
    public static let flowtime = flowtime(scheme: .tiered)

    public static func flowtime(scheme: FlowtimeBreakScheme) -> StudyMethod {
        StudyMethod(kind: .flowtime, focus: .openEnded, breakRule: .proportional(scheme))
    }

    /// Default card goal when no due counts are known.
    public static let defaultSprintCards = 100
    /// A sprint suggests a break after this many cards...
    public static let sprintBreakCards = 200
    /// ...or after this long, whichever comes first.
    public static let sprintBreakInterval: TimeInterval = 30 * 60

    /// Answer `cards` Anki cards, then take a 5 min break.
    public static func ankiSprint(cards: Int = defaultSprintCards) -> StudyMethod {
        StudyMethod(kind: .ankiSprint, focus: .cards(cards), breakRule: .fixed(5 * 60))
    }

    /// Card goal that clears today's reviews and learning cards, the work
    /// that should come before new cards. Falls back to the default goal
    /// when nothing is due.
    public static func sprintGoal(reviewDue: Int, learnDue: Int) -> Int {
        let due = max(reviewDue, 0) + max(learnDue, 0)
        return due > 0 ? due : defaultSprintCards
    }

    /// Up to 40 questions in 60 min (one board-exam block), then an equally
    /// long review of every explanation, then a 10 min break.
    public static let questionBlock = StudyMethod(
        kind: .questionBlock,
        focus: .duration(60 * 60),
        breakRule: .fixed(10 * 60),
        review: 60 * 60,
        questionCount: 40
    )

    /// A user-defined rhythm. Lengths are clamped to 1 min...4 h.
    public static func custom(
        focus: TimeInterval,
        breakLength: TimeInterval,
        longBreak: StudyLongBreak? = nil
    ) -> StudyMethod {
        StudyMethod(kind: .custom, focus: .duration(focus), breakRule: .fixed(breakLength), longBreak: longBreak)
    }

    /// One countdown of `length`, then the timer stops and waits; no breaks
    /// or rounds. Clamped to 1 min...4 h.
    public static func timer(_ length: TimeInterval) -> StudyMethod {
        StudyMethod(kind: .timer, focus: .duration(length), breakRule: .none)
    }

    /// Every method in picker order, with default parameters.
    public static let presets: [StudyMethod] = [
        .pomodoro, .fiftyTwoSeventeen, .ultradian, .flowtime, .ankiSprint(), .questionBlock,
        .custom(focus: 30 * 60, breakLength: 5 * 60), StudyTimerLength.standard.method,
    ]

    /// The default-parameter method for `kind`.
    public static func preset(_ kind: StudyMethodKind) -> StudyMethod {
        presets.first { $0.kind == kind } ?? .pomodoro
    }

    // MARK: Rules

    /// The phase after `phase` ends.
    ///
    /// - Parameter completedFocusCount: focus phases finished so far in this
    ///   session, including the one that just ended. Picks long breaks.
    public func nextPhase(after phase: StudyPhaseKind, completedFocusCount: Int) -> StudyPhaseKind {
        guard hasBreaks else { return .focus }
        switch phase {
        case .focus where review != nil:
            return .review
        case .focus, .review:
            if let longBreak, completedFocusCount > 0, completedFocusCount % longBreak.every == 0 {
                return .longBreak
            }
            return .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }

    /// Wall-clock length of `phase`, or nil when it has none (open-ended or
    /// card-goal focus).
    ///
    /// - Parameter workedBeforeBreak: how long the preceding focus phase
    ///   actually ran; only proportional breaks use it.
    public func duration(of phase: StudyPhaseKind, workedBeforeBreak: TimeInterval = 0) -> TimeInterval? {
        switch phase {
        case .focus:
            if case .duration(let length) = focus { return length }
            return nil
        case .review:
            return review
        case .shortBreak:
            switch breakRule {
            case .fixed(let length): return length
            case .proportional(let scheme): return scheme.breakDuration(afterWorking: workedBeforeBreak)
            case .none: return nil
            }
        case .longBreak:
            return longBreak?.duration ?? duration(of: .shortBreak, workedBeforeBreak: workedBeforeBreak)
        }
    }

    /// Whether focus is followed by breaks; false for the plain Timer, which
    /// stops when its countdown ends instead of moving on.
    public var hasBreaks: Bool { breakRule != .none }

    /// The card goal of an Anki sprint, or nil for time-based methods.
    public var cardGoal: Int? {
        if case .cards(let goal) = focus { return goal }
        return nil
    }

    /// Short label for the picker and the timer header, e.g. "25/5", "100 cards" or "10 min".
    public var rhythmLabel: String {
        func minutes(_ seconds: TimeInterval) -> String { "\(Int((seconds / 60).rounded()))" }
        switch focus {
        case .cards(let goal):
            return "\(goal) cards"
        case .openEnded:
            return "Open"
        case .duration(let length):
            guard let pause = duration(of: .shortBreak) else { return "\(minutes(length)) min" }
            if let review {
                return "\(minutes(length))+\(minutes(review))/\(minutes(pause))"
            }
            return "\(minutes(length))/\(minutes(pause))"
        }
    }

    // MARK: Clamping

    /// Clamps a phase length to 1 min...4 h. NaN, which `min`/`max` would
    /// pass straight through, becomes the minimum so labels and timers never
    /// see a non-finite length.
    static func clamped(_ length: TimeInterval) -> TimeInterval {
        guard !length.isNaN else { return minimumPhase }
        return min(max(length, minimumPhase), maximumPhase)
    }

    private static func clamped(_ focus: StudyFocusTarget) -> StudyFocusTarget {
        switch focus {
        case .duration(let length): return .duration(clamped(length))
        case .openEnded: return .openEnded
        case .cards(let goal): return .cards(max(goal, 1))
        }
    }

    private static func clamped(_ rule: StudyBreakRule) -> StudyBreakRule {
        switch rule {
        case .fixed(let length): return .fixed(clamped(length))
        case .proportional, .none: return rule
        }
    }
}
