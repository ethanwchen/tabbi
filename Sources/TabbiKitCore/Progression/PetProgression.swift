import Foundation

/// The Goals section's state: the tally read from the activity log and the
/// save that remembers it (`ProgressionSave`), joined into each track's
/// count, the badge tiers reached, this month's quests and what is new.
///
/// A count is the larger of what the log shows now and the best the save
/// remembers, so deleting old day files never takes progress back, and a
/// tier once reached stays reached.
public struct PetProgression: Hashable, Sendable {
    public private(set) var tally: ProgressTally
    public private(set) var save: ProgressionSave
    /// Each track's count at the last `refresh`.
    public private(set) var values: [ProgressTrack: Int] = [:]

    public init(save: ProgressionSave = ProgressionSave(), tally: ProgressTally = ProgressTally()) {
        self.save = save
        self.tally = tally
        values = save.best
    }

    /// Counts a record; call `refresh` to see what it earned.
    public mutating func add(_ record: ActivityRecord, calendar: Calendar = .current) {
        tally.add(record, calendar: calendar)
    }

    /// What one `refresh` added: badge tiers reached and months of quests
    /// finished for the first time.
    public struct Change: Hashable, Sendable {
        public var badges: [ProgressBadge] = []
        public var months: [MonthKey] = []

        public init(badges: [ProgressBadge] = [], months: [MonthKey] = []) {
            self.badges = badges
            self.months = months
        }

        public var isEmpty: Bool { badges.isEmpty && months.isEmpty }
    }

    /// Recounts every track at `now` and records new bests, tiers and
    /// finished months in the save. `freezePurchases` are the extra streak
    /// freezes bought (from the pet's ledger), which the gentle streak
    /// honors like the Streak section does.
    @discardableResult
    public mutating func refresh(at now: Date, freezePurchases: [Date] = [], calendar: Calendar = .current) -> Change {
        var change = Change()
        for month in MonthlyQuests.completedMonths(tally, through: now, calendar: calendar)
        where save.completedMonths.insert(month).inserted {
            change.months.append(month)
        }
        for track in ProgressTrack.allCases {
            let live: Int = switch track {
            case .gentleStreak:
                GentleStreak.longest(studyDays: tally.studyDays, freezePurchases: freezePurchases, today: now,
                                     calendar: calendar)
            case .steadyWeeks: tally.steadyWeeks(calendar: calendar)
            case .monthlyQuests: save.completedMonths.count
            default: tally.total(of: track)
            }
            let value = max(live, save.best[track] ?? 0)
            values[track] = value
            if value > 0 { save.best[track] = value }
            for tier in ProgressTier.allCases where value >= track.goal(for: tier) {
                let badge = ProgressBadge(track, tier)
                if save.reached[badge] == nil {
                    save.reached[badge] = now
                    change.badges.append(badge)
                }
            }
        }
        return change
    }

    /// The track's count, in its unit.
    public func value(of track: ProgressTrack) -> Int { values[track] ?? 0 }

    /// The highest tier reached on `track`, or nil before Bronze.
    public func tier(of track: ProgressTrack) -> ProgressTier? {
        ProgressTier.allCases.last { save.reached[ProgressBadge(track, $0)] != nil }
    }

    public func isReached(_ badge: ProgressBadge) -> Bool { save.reached[badge] != nil }

    /// The tier `track` is working toward, or nil once Starlight is reached.
    public func nextTier(of track: ProgressTrack) -> ProgressTier? {
        guard let tier = tier(of: track) else { return .bronze }
        return tier.next
    }

    /// How far along `badge` is, for a tile or a medallion's ring.
    public func progress(of badge: ProgressBadge) -> PetLimitedProgress {
        let goal = badge.goal
        let value = min(value(of: badge.track), goal)
        return PetLimitedProgress(value: value, goal: goal,
                                  label: badge.track.progressLabel(value: value, goal: goal))
    }

    /// Badge tiers reached and not seen yet on the Goals shelf.
    public var unseen: Set<ProgressBadge> {
        Set(save.reached.keys).subtracting(save.seen)
    }

    /// Marks every tier reached so far as seen; returns whether anything changed.
    @discardableResult
    public mutating func markSeen() -> Bool {
        let unseen = unseen
        guard !unseen.isEmpty else { return false }
        save.seen.formUnion(unseen)
        return true
    }

    /// How many badge tiers are reached, out of `ProgressBadge.allCases`.
    public var reachedCount: Int { save.reached.count }

    /// This month's quests at `now` and how far along each is.
    public func quests(at now: Date, calendar: Calendar = .current) -> [MonthlyQuestProgress] {
        MonthlyQuests.progress(for: MonthKey(date: now, calendar: calendar), tally: tally)
    }
}
