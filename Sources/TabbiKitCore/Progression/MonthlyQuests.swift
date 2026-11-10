import Foundation

/// A local calendar month, written `yyyy-MM`, the prefix of its days'
/// `PlannerDayKey`s.
public struct MonthKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "-")
        guard rawValue.count == 7, parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
              year > 0, (1...12).contains(month) else { return nil }
        self.rawValue = rawValue
    }

    /// The month `day` falls in.
    public init(day: PlannerDayKey) {
        rawValue = String(day.rawValue.prefix(7))
    }

    public init(date: Date, calendar: Calendar = .current) {
        self.init(day: PlannerDayKey(date: date, calendar: calendar))
    }

    /// The month's first day.
    public var firstDay: PlannerDayKey {
        PlannerDayKey(rawValue: rawValue + "-01")!
    }

    public func contains(_ day: PlannerDayKey) -> Bool { day.rawValue.hasPrefix(rawValue) }

    /// The month after this one.
    public func next(calendar: Calendar = .current) -> MonthKey {
        let start = firstDay.startDate(calendar: calendar)
        let next = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return MonthKey(date: next, calendar: calendar)
    }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let month = MonthKey(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid month \(raw)"))
        }
        self = month
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One of a month's three quests: a track and how much of it to do in
/// that month, in the track's unit (minutes for focus).
public struct MonthlyQuest: Hashable, Sendable {
    public var track: ProgressTrack
    public var target: Int

    public init(track: ProgressTrack, target: Int) {
        self.track = track
        self.target = target
    }

    /// The quest as the banner says it: "Focus for 10 hours".
    public var title: String {
        switch track {
        case .focusHours: String(localized: "Focus for \(target / 60) hours", bundle: .tabbi)
        case .studyDays: String(localized: "Study on \(target) days", bundle: .tabbi)
        case .sessions: String(localized: "Finish \(target) focus sessions", bundle: .tabbi)
        case .cards: String(localized: "Review \(target) flashcards", bundle: .tabbi)
        case .tasks: String(localized: "Check off \(target) tasks", bundle: .tabbi)
        case .breakMoves: String(localized: "Do \(target) break moves with your pet", bundle: .tabbi)
        case .party: String(localized: "Finish \(target) Party sessions with friends", bundle: .tabbi)
        case .water: String(localized: "Log \(target) glasses of water", bundle: .tabbi)
        case .gentleStreak, .methods, .steadyWeeks, .monthlyQuests: track.displayName
        }
    }

    /// "6/10 h" for `value` done this month.
    public func progressLabel(value: Int) -> String {
        track.progressLabel(value: value, goal: target)
    }
}

/// A quest with what this month has done toward it.
public struct MonthlyQuestProgress: Hashable, Sendable {
    public var quest: MonthlyQuest
    public var value: Int

    public var isDone: Bool { value >= quest.target }
    public var fraction: Double { quest.target > 0 ? min(1, Double(value) / Double(quest.target)) : 0 }
    public var label: String { quest.progressLabel(value: value) }
}

/// Three small goals each calendar month, optional and gentle: well under
/// the typical habit (about 27 focused hours a month), one always about
/// focus, the other two from what the user already does. A track like
/// flashcards joins the pool only once the user did it before the month
/// began, so nobody is asked to review cards without Anki, and the quests
/// stay put all month. The pick is a fixed hash of the month (FNV-1a), the
/// same on every Mac and on Windows.
///
/// Finishing all three counts the month toward the Monthly quests badge.
/// Months need not be in a row, and no month has an item of its own, so a
/// missed month costs nothing.
public enum MonthlyQuests {
    /// Each quest track and how much of it a month asks for.
    public static let targets: [ProgressTrack: Int] = [
        .focusHours: 10 * 60, .studyDays: 10, .sessions: 20,
        .cards: 600, .tasks: 20, .breakMoves: 8, .party: 2, .water: 30,
    ]

    /// Tracks every month can offer; one of them is always among the three.
    public static let core: [ProgressTrack] = [.focusHours, .studyDays, .sessions]
    /// Tracks offered once the user has done them before the month.
    public static let extras: [ProgressTrack] = [.cards, .tasks, .breakMoves, .party, .water]

    /// How many quests a month has.
    public static let count = 3

    /// `month`'s quests: the core track that hashes lowest first, then the
    /// two lowest of the rest of the pool.
    public static func quests(for month: MonthKey, tally: ProgressTally) -> [MonthlyQuest] {
        let start = month.firstDay
        let available = extras.filter { track in tally.firstDay(of: track).map { $0 < start } ?? false }
        let order = { (track: ProgressTrack) in hash("\(month.rawValue)|\(track.rawValue)") }
        let ranked = (core + available).sorted { (order($0), $0.rawValue) < (order($1), $1.rawValue) }
        guard let first = ranked.first(where: core.contains) else { return [] }
        let picked = [first] + ranked.filter { $0 != first }.prefix(count - 1)
        return picked.map { MonthlyQuest(track: $0, target: targets[$0] ?? 0) }
    }

    /// How far `month` got on each of its quests.
    public static func progress(for month: MonthKey, tally: ProgressTally) -> [MonthlyQuestProgress] {
        quests(for: month, tally: tally).map {
            MonthlyQuestProgress(quest: $0, value: tally.total(of: $0.track) { month.contains($0) })
        }
    }

    public static func isComplete(_ month: MonthKey, tally: ProgressTally) -> Bool {
        let progress = progress(for: month, tally: tally)
        return !progress.isEmpty && progress.allSatisfy(\.isDone)
    }

    /// Every month up to and including `today`'s whose quests the log
    /// shows finished, oldest first.
    public static func completedMonths(_ tally: ProgressTally, through today: Date,
                                       calendar: Calendar = .current) -> [MonthKey] {
        let last = MonthKey(date: today, calendar: calendar)
        let months = Set(tally.days.keys.map(MonthKey.init(day:))).filter { $0 <= last }
        return months.sorted().filter { isComplete($0, tally: tally) }
    }

    /// 32-bit FNV-1a over the UTF-8 bytes, so the Windows port picks the
    /// same quests.
    public static func hash(_ text: String) -> UInt32 {
        var value: UInt32 = 0x811C_9DC5
        for byte in text.utf8 {
            value ^= UInt32(byte)
            value = value &* 0x0100_0193
        }
        return value
    }
}
