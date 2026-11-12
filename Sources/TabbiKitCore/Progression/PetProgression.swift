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
    /// finished for the first time, and the Study Levels gained.
    public struct Change: Hashable, Sendable {
        public var badges: [ProgressBadge] = []
        public var months: [MonthKey] = []
        /// Every Study Level reached for the first time, lowest first.
        public var levels: [StudyLevel] = []

        public init(badges: [ProgressBadge] = [], months: [MonthKey] = [], levels: [StudyLevel] = []) {
            self.badges = badges
            self.months = months
            self.levels = levels
        }

        public var isEmpty: Bool { badges.isEmpty && months.isEmpty && levels.isEmpty }

        /// Whether a level gained unlocked a nameplate color or a rank,
        /// the moments worth a sparkle over the panel.
        public var unlocksSomething: Bool { levels.contains { $0.unlocksNameplate || $0.startsRank } }
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
        let level = StudyLevel(focusMinutes: value(of: .focusHours))
        if level.value > save.level {
            change.levels = ((save.level + 1)...level.value).map { StudyLevel($0) }
            save.level = level.value
        }
        return change
    }

    // MARK: Study Level

    /// The Study Level: from every focused minute so far, and never below
    /// the highest the save remembers.
    public var studyLevel: StudyLevel {
        max(StudyLevel(focusMinutes: value(of: .focusHours)), StudyLevel(save.level))
    }

    /// Total focused minutes, the Study Level's measure.
    public var focusMinutes: Int { value(of: .focusHours) }

    /// The nameplate color shown: the one picked, if the level has it.
    public var nameplate: Nameplate {
        guard let picked = save.nameplate, picked.unlockLevel <= studyLevel.value else { return .plain }
        return picked
    }

    /// The level and nameplate friends see in Party.
    public var standing: StudyStanding { StudyStanding(level: studyLevel, nameplate: nameplate) }

    /// Picks a nameplate color; returns false (and changes nothing) when
    /// it is still locked or already picked.
    @discardableResult
    public mutating func pick(_ nameplate: Nameplate) -> Bool {
        guard nameplate.unlockLevel <= studyLevel.value, nameplate != self.nameplate else { return false }
        save.nameplate = nameplate == .plain ? nil : nameplate
        return true
    }

    /// Whether a level was reached that the Goals shelf has not shown yet.
    public var hasUnseenLevel: Bool { studyLevel.value > save.levelSeen }

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

    /// Marks every tier and the level reached so far as seen; returns
    /// whether anything changed.
    @discardableResult
    public mutating func markSeen() -> Bool {
        let unseen = unseen
        let level = studyLevel.value
        guard !unseen.isEmpty || level > save.levelSeen else { return false }
        save.seen.formUnion(unseen)
        save.level = max(save.level, level)
        save.levelSeen = max(save.levelSeen, level)
        return true
    }

    /// How many badge tiers are reached, out of `ProgressBadge.allCases`.
    public var reachedCount: Int { save.reached.count }

    /// This month's quests at `now` and how far along each is.
    public func quests(at now: Date, calendar: Calendar = .current) -> [MonthlyQuestProgress] {
        MonthlyQuests.progress(for: MonthKey(date: now, calendar: calendar), tally: tally)
    }
}
