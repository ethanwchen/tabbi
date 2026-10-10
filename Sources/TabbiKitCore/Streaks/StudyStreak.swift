import Foundation

/// The rules for streak freezes, kept in one place so the UI, the shop and
/// docs/economy.md all describe the same thing.
///
/// A missed day is protected automatically: first by the week's free
/// freeze, then by an extra freeze bought with points. A frozen day keeps
/// the streak going but does not add to its length, so freezes forgive a
/// day off without counting it as study.
public enum StreakFreezeRules {
    /// Free freezes per calendar week (the user's locale decides the first
    /// day of the week).
    public static let freePerWeek = 1
    /// An extra freeze costs one typical study day's points (105), so a
    /// protected day off is paid for by a day of study.
    public static var price: Int { PetEconomy.pointsPerTypicalDay }
    /// The most extra freezes held at once, so points keep flowing into the
    /// Closet and a streak can never be bought outright.
    public static let maxHeld = 2
}

/// A study streak computed from the days with enough focused study and the
/// extra freezes bought, replayed day by day so the result is the same on
/// every launch and needs no stored "freeze used" state.
///
/// Rules, walking from the first study day to yesterday:
/// - A study day adds one to the streak.
/// - A missed day while a streak is running uses the free freeze of that
///   day's calendar week if it is still unused, otherwise the oldest extra
///   freeze bought before that day, otherwise the streak ends.
/// - Today is never frozen or missed: it still has time for study, so a
///   streak stays up until a whole day passes without study or freeze.
///
/// Days are local calendar days (`PlannerDayKey`) in `calendar`'s time
/// zone, the same days the activity log groups records by.
public struct StudyStreak: Hashable, Sendable {
    /// Study days in the current run, today included once studied.
    public private(set) var length: Int
    /// Whether today already has enough study to count.
    public private(set) var studiedToday: Bool
    /// Every day a freeze protected, in the current run or earlier ones, so
    /// a history view can show a snowflake on each.
    public private(set) var frozenDays: Set<PlannerDayKey>
    /// Whether this week's free freeze is still unused.
    public private(set) var freeFreezeAvailable: Bool
    /// Extra freezes bought and not used yet.
    public private(set) var extraFreezes: Int
    /// The study days up to today, for `recentDays`.
    private var studied: Set<PlannerDayKey>
    private var today: PlannerDayKey

    /// - Parameters:
    ///   - studyDays: days with enough focused study
    ///     (`PetMilestoneProgress.studyDays`). Days after today are ignored.
    ///   - freezePurchases: when each extra freeze was bought. A freeze
    ///     protects only days after the day it was bought, so it cannot
    ///     repair a streak that already ended.
    public init(studyDays: some Sequence<PlannerDayKey>, freezePurchases: some Sequence<Date> = [Date](),
                today: Date, calendar: Calendar = .current) {
        let todayKey = PlannerDayKey(date: today, calendar: calendar)
        let studied = Set(studyDays.filter { $0 <= todayKey })
        var purchases = freezePurchases.map { PlannerDayKey(date: $0, calendar: calendar) }.sorted()[...]
        var bought = 0
        var run = 0
        var frozen: Set<PlannerDayKey> = []
        var freeUsedWeeks: Set<PlannerDayKey> = []

        func week(of day: PlannerDayKey) -> PlannerDayKey {
            let start = day.startDate(calendar: calendar)
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
            return PlannerDayKey(date: weekStart, calendar: calendar)
        }

        if var day = studied.min() {
            while day < todayKey {
                // Freezes bought before this day are now in reserve.
                while let next = purchases.first, next < day {
                    purchases.removeFirst()
                    bought += 1
                }
                if studied.contains(day) {
                    run += 1
                } else if run > 0 {
                    if freeUsedWeeks.insert(week(of: day)).inserted {
                        frozen.insert(day)
                    } else if bought > 0 {
                        bought -= 1
                        frozen.insert(day)
                    } else {
                        run = 0
                    }
                }
                day = day.adding(days: 1, calendar: calendar)
            }
        }
        // Freezes bought up to today are held, ready for the next miss.
        bought += purchases.prefix { $0 <= todayKey }.count

        self.studied = studied
        self.today = todayKey
        studiedToday = studied.contains(todayKey)
        length = run + (studiedToday ? 1 : 0)
        frozenDays = frozen
        freeFreezeAvailable = !freeUsedWeeks.contains(week(of: todayKey))
        extraFreezes = bought
    }

    /// Whether a streak is running (today studied, or kept up to yesterday).
    public var isActive: Bool { length > 0 }

    /// Whether the streak is running but today has no study yet, the one
    /// moment a gentle reminder is worth sending.
    public var needsStudyToday: Bool { isActive && !studiedToday }

    /// Whether another extra freeze can be bought (fewer than `maxHeld`).
    public var canBuyFreeze: Bool { extraFreezes < StreakFreezeRules.maxHeld }

    /// Freezes ready for the next missed day: this week's free one, if
    /// unused, plus the extras held.
    public var freezesReady: Int { (freeFreezeAvailable ? StreakFreezeRules.freePerWeek : 0) + extraFreezes }

    /// The last `count` days, oldest first and ending today, each with what
    /// happened on it, for the streak's day strip.
    public func recentDays(_ count: Int, calendar: Calendar = .current) -> [StreakDay] {
        guard count > 0 else { return [] }
        return (0..<count).reversed().map { offset in
            let day = today.adding(days: -offset, calendar: calendar)
            let state: StreakDay.State = if studied.contains(day) {
                .studied
            } else if frozenDays.contains(day) {
                .frozen
            } else if day == today {
                .today
            } else {
                .missed
            }
            return StreakDay(day: day, state: state)
        }
    }
}

/// One day in the streak's day strip.
public struct StreakDay: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        /// Enough focused study to count.
        case studied
        /// Missed, but a freeze kept the streak (shown with a snowflake).
        case frozen
        /// Missed and not protected.
        case missed
        /// Today, with no study yet: still open, so neither missed nor frozen.
        case today
    }

    public var day: PlannerDayKey
    public var state: State
}
