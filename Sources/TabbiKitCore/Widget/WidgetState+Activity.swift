import Foundation

extension WidgetState {
    /// The state the app shares, from what it knows now: the pet's look, the
    /// running clock (`Timer(_:)` of the shared focus clock) and the days
    /// with focus in the activity log.
    ///
    /// - Parameters:
    ///   - todayRecords: the activity log's records for the day of `now`.
    ///   - focusDays: the days with focus, at least as far back as the
    ///     streak reaches (`focusDays(endingOn:records:)` collects them).
    public init(pet: PetProfile, timer: Timer?, todayRecords: [ActivityRecord],
                focusDays: Set<PlannerDayKey>, now: Date, calendar: Calendar = .current) {
        let today = PlannerDayKey(date: now, calendar: calendar)
        let streak = Self.streak(focusDays: focusDays, today: today, calendar: calendar)
        self.init(pet: pet, day: today, focusMinutes: Self.focusMinutes(in: todayRecords),
                  streakDays: streak.days, lastFocusDay: streak.last, timer: timer)
    }

    /// Whether a record is time spent focusing. Stretches stopped early
    /// count too, as they do in Wrap Up's study minutes.
    public static func isFocus(_ record: ActivityRecord) -> Bool {
        record.kind == .focusCompleted && (record.quantity ?? 0) > 0
    }

    /// Whole minutes focused across `records`.
    public static func focusMinutes(in records: [ActivityRecord]) -> Int {
        Int(records.filter(isFocus).reduce(0) { $0 + ($1.quantity ?? 0) })
    }

    /// The days with focus that a streak ending on `today` (or on the day
    /// before, which still keeps it) can reach, read one day at a time
    /// from `records(day)` and stopping at the first day without focus, so
    /// a long history costs only as many reads as the streak is long.
    /// `limit` bounds the walk.
    public static func focusDays(endingOn today: PlannerDayKey, calendar: Calendar = .current, limit: Int = 3660,
                                 records: (PlannerDayKey) -> [ActivityRecord]) -> Set<PlannerDayKey> {
        var days: Set<PlannerDayKey> = []
        var day = today
        for step in 0..<max(limit, 1) {
            if records(day).contains(where: isFocus) {
                days.insert(day)
            } else if step > 0 || !days.isEmpty {
                // Today may have no focus yet; yesterday's streak still counts.
                break
            }
            day = day.adding(days: -1, calendar: calendar)
        }
        return days
    }
}
