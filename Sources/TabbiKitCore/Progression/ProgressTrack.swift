import Foundation

/// One habit the Goals section counts, each with its own ladder of badge
/// tiers (`ProgressTier`). Every count is read from the activity log
/// (`ProgressTally`) and only ever grows, so nothing here can be lost.
/// docs/design/progression.md walks through the goals and why.
public enum ProgressTrack: String, CaseIterable, Codable, Sendable {
    /// Focused minutes in total (`focus.completed`, any module, finished or not).
    case focusHours
    /// Days with at least `PetMilestoneProgress.minutesForStudyDay` focused minutes.
    case studyDays
    /// The longest run of study days ever, with the Streak section's freezes.
    case gentleStreak
    /// Focus stretches that ran to their end (`countsAsFinishedSession`).
    case sessions
    /// Flashcards answered (`cards.reviewed`).
    case cards
    /// Distinct tasks checked off (`task.completed`).
    case tasks
    /// Break moves done with the pet (`break.move`).
    case breakMoves
    /// Party shared sessions that ran to their end with a friend along.
    case party
    /// Named study methods used for at least one focus stretch.
    case methods
    /// Monday to Sunday weeks with at least `steadyWeekDays` study days.
    case steadyWeeks
    /// Glasses of water logged on the break card (`water.logged`).
    case water
    /// Months whose three monthly quests were all finished (`MonthlyQuests`).
    case monthlyQuests

    /// What each tier asks for, Bronze first, in the track's own unit:
    /// minutes for `focusHours`, otherwise days, sessions, cards, tasks,
    /// moves, methods, weeks, glasses or months. The early tiers come in
    /// days so a new pet's shelf lights up; Starlight takes months.
    public var thresholds: [Int] {
        switch self {
        case .focusHours: [10 * 60, 50 * 60, 200 * 60, 500 * 60]
        case .studyDays: [7, 30, 100, 250]
        case .gentleStreak: [7, 30, 90, 180]
        case .sessions: [15, 75, 300, 800]
        case .cards: [500, 2500, 10000, 30000]
        case .tasks: [10, 50, 200, 500]
        case .breakMoves: [10, 50, 150, 400]
        case .party: [1, 5, 20, 60]
        case .methods: [2, 3, 4, 6]
        case .steadyWeeks: [2, 4, 12, 26]
        case .water: [20, 100, 300, 1000]
        case .monthlyQuests: [1, 3, 6, 12]
        }
    }

    /// The goal of `tier` in the track's unit.
    public func goal(for tier: ProgressTier) -> Int { thresholds[tier.rawValue - 1] }

    /// The highest tier `value` reaches, or nil below Bronze.
    public func tier(for value: Int) -> ProgressTier? {
        ProgressTier.allCases.last { value >= goal(for: $0) }
    }

    /// The badge's name on the Goals shelf.
    public var displayName: String {
        switch self {
        case .focusHours: String(localized: "Focus time", bundle: .tabbi)
        case .studyDays: String(localized: "Study days", bundle: .tabbi)
        case .gentleStreak: String(localized: "Gentle streak", bundle: .tabbi)
        case .sessions: String(localized: "Sessions", bundle: .tabbi)
        case .cards: String(localized: "Flashcards", bundle: .tabbi)
        case .tasks: String(localized: "Tasks", bundle: .tabbi)
        case .breakMoves: String(localized: "Break moves", bundle: .tabbi)
        case .party: String(localized: "Party", bundle: .tabbi)
        case .methods: String(localized: "Study methods", bundle: .tabbi)
        case .steadyWeeks: String(localized: "Steady weeks", bundle: .tabbi)
        case .water: String(localized: "Water", bundle: .tabbi)
        case .monthlyQuests: String(localized: "Monthly quests", bundle: .tabbi)
        }
    }

    /// How to reach `goal` (in the track's unit), as one sentence for
    /// tooltips and the footer: "Focus for 200 hours in total."
    public func howToReach(_ goal: Int) -> String {
        switch self {
        case .focusHours: String(localized: "Focus for \(goal / 60) hours in total.", bundle: .tabbi)
        case .studyDays: String(localized: "Study on \(goal) different days.", bundle: .tabbi)
        case .gentleStreak: String(localized: "Keep a \(goal)-day streak. Freezes count.", bundle: .tabbi)
        case .sessions: String(localized: "Finish \(goal) focus sessions.", bundle: .tabbi)
        case .cards: String(localized: "Review \(goal) flashcards.", bundle: .tabbi)
        case .tasks: String(localized: "Check off \(goal) tasks.", bundle: .tabbi)
        case .breakMoves: String(localized: "Do \(goal) break moves with your pet.", bundle: .tabbi)
        case .party: String(localized: "Finish \(goal) Party sessions with friends.", bundle: .tabbi)
        case .methods: String(localized: "Try \(goal) different study methods.", bundle: .tabbi)
        case .steadyWeeks: String(localized: "Study 3 days or more in \(goal) different weeks.", bundle: .tabbi)
        case .water: String(localized: "Log \(goal) glasses of water.", bundle: .tabbi)
        case .monthlyQuests: String(localized: "Finish every monthly quest in \(goal) months.", bundle: .tabbi)
        }
    }

    /// How far along `value` is toward `goal`, short enough for a tile:
    /// "142/200 h", "23/30", "4.2k/10k". Hours round down and the value is
    /// capped at the goal, so a tile never shows a goal met before it is.
    public func progressLabel(value: Int, goal: Int) -> String {
        let value = max(0, min(value, goal))
        if self == .focusHours {
            return String(localized: "\(value / 60)/\(goal / 60) h", bundle: .tabbi)
        }
        return "\(Self.shortCount(value))/\(Self.shortCount(goal))"
    }

    /// A count as a tile shows it: as is below 10,000, then in whole
    /// thousands ("12k"), so five-digit card counts still fit a tile.
    public static func shortCount(_ count: Int) -> String {
        guard count >= 10_000 else { return "\(count)" }
        return String(localized: "\(count / 1000)k", bundle: .tabbi)
    }

    /// Weeks need this many study days to count as steady.
    public static let steadyWeekDays = 3
}

/// A badge tier. Each track has all four; Starlight is the rare one.
public enum ProgressTier: Int, CaseIterable, Codable, Comparable, Sendable {
    case bronze = 1
    case silver
    case gold
    case starlight

    public var displayName: String {
        switch self {
        // Keyed by id: "Silver" is also a fur color, which some languages
        // say as an adjective.
        case .bronze: String(localized: "badge.tier.bronze", bundle: .tabbi)
        case .silver: String(localized: "badge.tier.silver", bundle: .tabbi)
        case .gold: String(localized: "badge.tier.gold", bundle: .tabbi)
        case .starlight: String(localized: "badge.tier.starlight", bundle: .tabbi)
        }
    }

    /// The next tier up, or nil at Starlight.
    public var next: ProgressTier? { ProgressTier(rawValue: rawValue + 1) }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One badge: a track at a tier, such as Focus time Gold. Its stable id
/// (`focusHours.3`) is what the progression save stores.
public struct ProgressBadge: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public var track: ProgressTrack
    public var tier: ProgressTier

    public init(_ track: ProgressTrack, _ tier: ProgressTier) {
        self.track = track
        self.tier = tier
    }

    public var id: String { "\(track.rawValue).\(tier.rawValue)" }

    public init?(id: String) {
        let parts = id.split(separator: ".").map(String.init)
        guard parts.count == 2, let track = ProgressTrack(rawValue: parts[0]),
              let raw = Int(parts[1]), let tier = ProgressTier(rawValue: raw) else { return nil }
        self.init(track, tier)
    }

    /// The goal in the track's unit.
    public var goal: Int { track.goal(for: tier) }

    /// "Focus for 200 hours in total."
    public var howToEarn: String { track.howToReach(goal) }

    /// "Focus time Gold".
    public var displayName: String {
        String(localized: "\(track.displayName) \(tier.displayName)", bundle: .tabbi)
    }

    /// Every badge, track by track, Bronze first.
    public static var allCases: [ProgressBadge] {
        ProgressTrack.allCases.flatMap { track in ProgressTier.allCases.map { ProgressBadge(track, $0) } }
    }

    public var description: String { id }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let order = ProgressTrack.allCases
        let left = order.firstIndex(of: lhs.track) ?? 0, right = order.firstIndex(of: rhs.track) ?? 0
        return (left, lhs.tier.rawValue) < (right, rhs.tier.rawValue)
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let badge = ProgressBadge(id: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown badge \(raw)"))
        }
        self = badge
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}
