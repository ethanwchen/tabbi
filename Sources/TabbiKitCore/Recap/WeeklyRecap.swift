import Foundation

/// A Monday-through-Sunday week, identified by its Monday.
///
/// The recap is ready on Sunday evening, so the week always ends on a
/// Sunday whatever the locale's first weekday is. Days are local calendar
/// days (`PlannerDayKey`), like the activity log's day files.
public struct RecapWeek: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    /// The Monday the week starts on.
    public let start: PlannerDayKey

    /// The week that contains `date` in `calendar`'s time zone.
    public init(containing date: Date, calendar: Calendar = .current) {
        let day = PlannerDayKey(date: date, calendar: calendar)
        // `weekday` is 1 for Sunday through 7 for Saturday.
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        start = day.adding(days: -((weekday + 5) % 7), calendar: calendar)
    }

    /// The week starting on `monday`; nil when that day is not a Monday.
    public init?(start monday: PlannerDayKey, calendar: Calendar = .current) {
        guard calendar.component(.weekday, from: monday.startDate(calendar: calendar)) == 2 else { return nil }
        start = monday
    }

    /// The Sunday the week ends on.
    public func end(calendar: Calendar = .current) -> PlannerDayKey { start.adding(days: 6, calendar: calendar) }

    /// The seven days, Monday first.
    public func days(calendar: Calendar = .current) -> [PlannerDayKey] {
        (0..<7).map { start.adding(days: $0, calendar: calendar) }
    }

    /// The week `weeks` weeks later (earlier when negative).
    public func adding(weeks: Int, calendar: Calendar = .current) -> RecapWeek {
        RecapWeek(uncheckedStart: start.adding(days: 7 * weeks, calendar: calendar))
    }

    private init(uncheckedStart: PlannerDayKey) { start = uncheckedStart }

    /// When the week's recap is ready: `readyHour` o'clock on its Sunday.
    public func readyDate(readyHour: Int = RecapWeek.defaultReadyHour, calendar: Calendar = .current) -> Date {
        // A wall-clock time, so a daylight saving change that Sunday still
        // lands on `readyHour` o'clock rather than an hour off.
        let sunday = end(calendar: calendar).startDate(calendar: calendar)
        return calendar.date(bySettingHour: readyHour, minute: 0, second: 0, of: sunday) ?? sunday
    }

    /// The most recent week whose recap is ready at `now`: this week from
    /// Sunday at `readyHour` on, otherwise last week.
    public static func latestReady(at now: Date, readyHour: Int = defaultReadyHour,
                                   calendar: Calendar = .current) -> RecapWeek {
        let current = RecapWeek(containing: now, calendar: calendar)
        return now >= current.readyDate(readyHour: readyHour, calendar: calendar)
            ? current : current.adding(weeks: -1, calendar: calendar)
    }

    /// Sunday evening, 6 pm: late enough to count the weekend, early enough
    /// to see the recap before the new week starts.
    public static let defaultReadyHour = 18

    public var description: String { start.rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.start < rhs.start }

    public init(from decoder: Decoder) throws {
        start = try decoder.singleValueContainer().decode(PlannerDayKey.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(start)
    }
}

/// What one week of study added up to, built from the activity log.
///
/// It reads only `ActivityRecord`s, so it counts whatever any module
/// logged (the Pomodoro, Study, Party, Anki, Today) without knowing about
/// their stores. A recap is saved once it is built, so past weeks stay
/// browsable even after the log's day files are deleted.
public struct WeeklyRecap: Hashable, Codable, Sendable, Identifiable {
    public let week: RecapWeek
    /// Minutes focused each day, Monday first (always seven entries).
    public let minutesByDay: [Int]
    /// Focus stretches that ran to their end (`countsAsFinishedSession`).
    public let sessions: Int
    public let cardsReviewed: Int
    /// Distinct tasks checked off, so one checked twice counts once.
    public let tasksDone: Int
    /// Study points the week's focus earned, by `PetPointsRules`.
    public let points: Int
    /// The longest run of consecutive active days in the week (see
    /// `isActive(minutes:cards:tasks:)`).
    public let longestStreak: Int

    public var id: RecapWeek { week }

    public init(week: RecapWeek, minutesByDay: [Int], sessions: Int, cardsReviewed: Int, tasksDone: Int,
                points: Int, longestStreak: Int) {
        self.week = week
        let days = minutesByDay.prefix(7).map { max($0, 0) }
        self.minutesByDay = days + Array(repeating: 0, count: 7 - days.count)
        self.sessions = max(sessions, 0)
        self.cardsReviewed = max(cardsReviewed, 0)
        self.tasksDone = max(tasksDone, 0)
        self.points = max(points, 0)
        self.longestStreak = min(max(longestStreak, 0), 7)
    }

    /// Builds `week`'s recap from `records`. Records outside the week are
    /// ignored, as are duplicates (same id), so a caller can pass a few
    /// days' slack around it. Each record counts toward the local day it
    /// ended on, like the log's day files.
    public init(week: RecapWeek, records: some Sequence<ActivityRecord>, calendar: Calendar = .current) {
        let days = week.days(calendar: calendar)
        let index = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1, $0) })
        var minutes = Array(repeating: 0.0, count: 7)
        var cards = Array(repeating: 0, count: 7)
        var tasks = Array(repeating: 0, count: 7)
        var sessions = 0
        var points = 0
        var cardsReviewed = 0
        var taskSubjects: Set<String> = []
        var anonymousTasks = 0
        var seen: Set<UUID> = []
        for record in records {
            guard let day = index[record.day(calendar: calendar)], seen.insert(record.id).inserted else { continue }
            switch record.kind {
            case .focusCompleted:
                guard record.unit == .minutes, let quantity = record.quantity, quantity.isFinite, quantity > 0 else {
                    continue
                }
                minutes[day] += quantity
                if record.countsAsFinishedSession { sessions += 1 }
                points += Self.points(for: record, minutes: Int(quantity))
            case .cardsReviewed:
                guard let quantity = record.quantity, quantity.isFinite, quantity > 0 else { continue }
                cards[day] += Int(quantity)
                cardsReviewed += Int(quantity)
            case .taskCompleted:
                tasks[day] += 1
                if let subject = record.subject { taskSubjects.insert(subject) } else { anonymousTasks += 1 }
            default:
                continue
            }
        }
        let wholeMinutes = minutes.map { Int($0.rounded()) }
        var streak = 0
        var run = 0
        for day in 0..<7 {
            run = Self.isActive(minutes: wholeMinutes[day], cards: cards[day], tasks: tasks[day]) ? run + 1 : 0
            streak = max(streak, run)
        }
        self.init(week: week, minutesByDay: wholeMinutes, sessions: sessions, cardsReviewed: cardsReviewed,
                  tasksDone: taskSubjects.count + anonymousTasks, points: points, longestStreak: streak)
    }

    /// Points for one focus record, as the pet's ledger credited it: a
    /// Party stay by `sharedPoints` with the friends who studied along,
    /// anything else by `points(forMinutes:completed:)`.
    private static func points(for record: ActivityRecord, minutes: Int) -> Int {
        let finished = record.countsAsFinishedSession
        if record.source == .party {
            let friends = record.metadata[PartySessionCompletion.friendsKey].flatMap(Int.init) ?? 0
            let outcome = record.metadata[ActivityMetadata.outcome].flatMap(StudyPhaseOutcome.init(rawValue:))
            return PetPointsRules.sharedPoints(forMinutes: minutes, friends: friends,
                                               finished: outcome == .completed || outcome == nil)
        }
        return PetPointsRules.points(forMinutes: minutes, completed: finished)
    }

    /// A day counts toward the streak when it had a real focus stretch
    /// (`PetPointsRules.minimumMinutes`), any cards reviewed or any task
    /// done, so a day of flashcards or errands keeps it going too.
    public static func isActive(minutes: Int, cards: Int, tasks: Int) -> Bool {
        minutes >= PetPointsRules.minimumMinutes || cards > 0 || tasks > 0
    }

    public var focusMinutes: Int { minutesByDay.reduce(0, +) }

    /// The day with the most focus, Monday first on a tie; nil when no day
    /// had any.
    public func bestDay(calendar: Calendar = .current) -> (day: PlannerDayKey, minutes: Int)? {
        guard let best = minutesByDay.max(), best > 0, let index = minutesByDay.firstIndex(of: best) else {
            return nil
        }
        return (week.start.adding(days: index, calendar: calendar), best)
    }

    /// Nothing at all was logged this week.
    public var isEmpty: Bool { focusMinutes == 0 && cardsReviewed == 0 && tasksDone == 0 }

    /// The warm line for this week, measured against `earlier` recaps
    /// (any order; weeks on or after this one are ignored).
    public func cheer(comparedTo earlier: some Sequence<WeeklyRecap>, calendar: Calendar = .current) -> RecapCheer {
        guard !isEmpty else { return .rest }
        let before = earlier.filter { $0.week < week && !$0.isEmpty }
        let previous = before.max { $0.week < $1.week }
        if focusMinutes < RecapCheer.lightWeekMinutes { return .light }
        guard previous != nil else { return .firstWeek }
        if focusMinutes > before.map(\.focusMinutes).max() ?? 0 { return .bestYet }
        if let previous, previous.week == week.adding(weeks: -1, calendar: calendar), focusMinutes > previous.focusMinutes {
            return .moreThanLastWeek
        }
        return .steady
    }
}

/// The one warm line on a recap card. Always kind: a light or empty week
/// gets encouragement, never a comparison that could sting.
public enum RecapCheer: String, Hashable, Codable, Sendable, CaseIterable {
    /// More focus than any earlier week.
    case bestYet
    /// More focus than the week before, without being the best.
    case moreThanLastWeek
    /// The first week with a recap to compare against nothing.
    case firstWeek
    /// A solid week that set no record.
    case steady
    /// Under `lightWeekMinutes` of focus, but something happened.
    case light
    /// Nothing logged.
    case rest

    /// Below an hour of focus a week reads as light, whatever came before.
    public static let lightWeekMinutes = 60

    public var line: String {
        switch self {
        case .bestYet: "Your best week yet!"
        case .moreThanLastWeek: "More focus than last week. Nice climb!"
        case .firstWeek: "A lovely first week together."
        case .steady: "Another steady week. Keep it cozy."
        case .light: "A lighter week. Every minute counts."
        case .rest: "A restful week. A fresh start awaits."
        }
    }
}
