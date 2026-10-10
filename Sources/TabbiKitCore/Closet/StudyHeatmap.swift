import Foundation

/// The Closet's GitHub-style study chart: a column per week and a row per
/// weekday, ending with today, each day shaded by how long it was studied.
///
/// It reads the focused minutes per day that streaks, points and the
/// limited edition milestones already count (`PetMilestoneProgress
/// .minutesByDay`), so the chart, the streak and the points never disagree
/// and nothing new is tracked or stored.
public struct StudyHeatmap: Hashable, Sendable {
    /// One day's cell.
    public struct Day: Hashable, Sendable, Identifiable {
        public let key: PlannerDayKey
        /// Focused minutes that day, rounded to the minute.
        public let minutes: Int
        public let isToday: Bool

        public var id: PlannerDayKey { key }
        /// How dark the cell is, from 0 (no study) to `levelCount - 1`.
        public var level: Int { StudyHeatmap.level(forMinutes: minutes) }

        /// "No study", "25 min studied" or "1h 25m studied", the tooltip's
        /// exact value, so the levels never rely on color alone.
        public var studiedLabel: String {
            minutes > 0 ? "\(DurationFormat.minutes(minutes)) studied" : "No study"
        }
    }

    /// One column: the seven weekdays from the calendar's first weekday,
    /// with nil for the days after today in the current week.
    public struct Week: Hashable, Sendable, Identifiable {
        public let start: PlannerDayKey
        public let days: [Day?]

        public var id: PlannerDayKey { start }
        public var minutes: Int { days.reduce(0) { $0 + ($1?.minutes ?? 0) } }
        /// Days in the week with any study.
        public var studiedDays: Int { days.filter { ($0?.minutes ?? 0) > 0 }.count }
    }

    /// Shades in the chart, the empty one included.
    public static let levelCount = 5
    /// The fewest minutes for levels 2, 3 and 4: a short review, a real
    /// session, and a long day (GitHub's five shades, sized for study).
    public static let levelThresholds = [15, 45, 90]

    /// 0 for no study, then 1 under 15 minutes, 2 under 45, 3 under 90 and
    /// 4 from 90 on.
    public static func level(forMinutes minutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        return 1 + levelThresholds.filter { minutes >= $0 }.count
    }

    /// Oldest first; the last week holds today.
    public let weeks: [Week]
    public let today: PlannerDayKey
    /// Focused minutes over the 30 days ending today, for the summary line.
    public let lastThirtyDaysMinutes: Int
    /// The most studied day ever up to today (the latest one on a tie), or
    /// nil before any study.
    public let bestDay: Day?

    /// - Parameters:
    ///   - minutesByDay: focused minutes per day
    ///     (`PetMilestoneProgress.minutesByDay`). Days after today are
    ///     ignored.
    ///   - weeks: how many columns fit; at least one, the current week.
    public init(minutesByDay: [PlannerDayKey: Double], weeks count: Int, today: Date,
                calendar: Calendar = .current) {
        let todayKey = PlannerDayKey(date: today, calendar: calendar)
        func minutes(on key: PlannerDayKey) -> Int {
            let value = minutesByDay[key] ?? 0
            return value.isFinite ? max(0, Int(value.rounded())) : 0
        }
        func day(_ key: PlannerDayKey) -> Day {
            Day(key: key, minutes: minutes(on: key), isToday: key == todayKey)
        }

        let start = calendar.startOfDay(for: today)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        let first = PlannerDayKey(date: thisWeek, calendar: calendar)
        weeks = (0..<max(1, count)).reversed().map { back in
            let weekStart = first.adding(days: -7 * back, calendar: calendar)
            let days = (0..<7).map { offset -> Day? in
                let key = weekStart.adding(days: offset, calendar: calendar)
                return key <= todayKey ? day(key) : nil
            }
            return Week(start: weekStart, days: days)
        }
        self.today = todayKey

        lastThirtyDaysMinutes = (0..<30).reduce(0) { $0 + minutes(on: todayKey.adding(days: -$1, calendar: calendar)) }
        bestDay = minutesByDay.keys
            .filter { $0 <= todayKey }
            .map(day)
            .filter { $0.minutes > 0 }
            .max { ($0.minutes, $0.key) < ($1.minutes, $1.key) }
    }
}
