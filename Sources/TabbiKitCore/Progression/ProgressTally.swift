import Foundation

/// Everything the Goals section counts, read from the activity log one
/// record at a time and kept per local day, so lifetime totals and one
/// month's totals (`MonthlyQuests`) come from the same numbers.
///
/// It reads only `ActivityRecord`s, never another module's store:
/// `focus.completed` (minutes, outcome, study method and Party friends),
/// `cards.reviewed`, `task.completed`, `break.move` and `water.logged`.
/// Adding the same record twice counts it once, so the Closet can replay
/// the whole log at launch and then follow new records.
public struct ProgressTally: Hashable, Sendable {
    /// One local day's counts. A record counts toward the day it ended.
    public struct Day: Hashable, Sendable {
        public var focusMinutes: Double = 0
        public var sessions = 0
        public var cards: Double = 0
        /// Ids of the tasks checked off, so one checked twice counts once.
        public var taskIDs: Set<String> = []
        /// Tasks checked off without an id, each counted on its own.
        public var unnamedTasks = 0
        public var breakMoves = 0
        public var partySessions = 0
        public var water: Double = 0
        /// Named study methods used that day (`StudyMethodKind` raw values).
        public var methods: Set<String> = []

        public init() {}

        /// Whether the day has enough focus to count as a study day.
        public var isStudyDay: Bool { focusMinutes >= PetMilestoneProgress.minutesForStudyDay }
    }

    /// The study methods the methods badge counts: the named ones in the
    /// Study tab's menu (and the Focus tab's Pomodoro). A custom timer and
    /// the plain countdown are not methods to try.
    public static let namedMethods: [StudyMethodKind] = [
        .pomodoro, .fiftyTwoSeventeen, .ultradian, .flowtime, .ankiSprint, .questionBlock,
    ]
    private static let namedMethodIDs = Set(namedMethods.map(\.rawValue))

    public private(set) var days: [PlannerDayKey: Day] = [:]
    private var seen: Set<UUID> = []

    public init() {}

    public init(records: some Sequence<ActivityRecord>, calendar: Calendar = .current) {
        for record in records { add(record, calendar: calendar) }
    }

    /// Counts `record` once; records of other kinds are ignored.
    public mutating func add(_ record: ActivityRecord, calendar: Calendar = .current) {
        guard !seen.contains(record.id) else { return }
        let day = record.day(calendar: calendar)
        var counts = days[day] ?? Day()
        switch record.kind {
        case .focusCompleted:
            guard record.unit == .minutes, let minutes = record.quantity, minutes.isFinite, minutes > 0 else { return }
            counts.focusMinutes += minutes
            if record.countsAsFinishedSession { counts.sessions += 1 }
            if let method = record.metadata[ActivityMetadata.method], Self.namedMethodIDs.contains(method) {
                counts.methods.insert(method)
            }
            if record.source == .party, record.metadata[ActivityMetadata.outcome] == StudyPhaseOutcome.completed.rawValue,
               (record.metadata[PartySessionCompletion.friendsKey].flatMap(Int.init) ?? 0) > 0 {
                counts.partySessions += 1
            }
        case .cardsReviewed:
            guard let cards = record.quantity, cards.isFinite, cards > 0 else { return }
            counts.cards += cards
        case .taskCompleted:
            if let subject = record.subject { counts.taskIDs.insert(subject) } else { counts.unnamedTasks += 1 }
        case WaterTally.moveKind:
            counts.breakMoves += 1
        case WaterTally.waterKind:
            let glasses = record.quantity ?? 1
            guard glasses.isFinite, glasses > 0 else { return }
            counts.water += glasses
        default:
            return
        }
        seen.insert(record.id)
        days[day] = counts
    }

    /// The days with enough focus to count, oldest first.
    public var studyDays: [PlannerDayKey] {
        days.filter { $0.value.isStudyDay }.keys.sorted()
    }

    /// The track's count over the days `include` lets through (every day
    /// when nil), in its unit. `gentleStreak`, `steadyWeeks` and
    /// `monthlyQuests` span days, so they are counted by
    /// `PetProgression` instead and read 0 here.
    public func total(of track: ProgressTrack, where include: ((PlannerDayKey) -> Bool)? = nil) -> Int {
        let picked = include.map { include in days.filter { include($0.key) } } ?? days
        let values = picked.values
        switch track {
        case .focusHours: return Int(values.reduce(0) { $0 + $1.focusMinutes })
        case .studyDays: return values.filter(\.isStudyDay).count
        case .sessions: return values.reduce(0) { $0 + $1.sessions }
        case .cards: return Int(values.reduce(0) { $0 + $1.cards })
        case .tasks:
            let named = values.reduce(into: Set<String>()) { $0.formUnion($1.taskIDs) }
            return named.count + values.reduce(0) { $0 + $1.unnamedTasks }
        case .breakMoves: return values.reduce(0) { $0 + $1.breakMoves }
        case .party: return values.reduce(0) { $0 + $1.partySessions }
        case .methods: return values.reduce(into: Set<String>()) { $0.formUnion($1.methods) }.count
        case .water: return Int(values.reduce(0) { $0 + $1.water })
        case .gentleStreak, .steadyWeeks, .monthlyQuests: return 0
        }
    }

    /// Monday to Sunday weeks (the weekly recap's) with at least
    /// `ProgressTrack.steadyWeekDays` study days.
    public func steadyWeeks(calendar: Calendar = .current) -> Int {
        var counts: [RecapWeek: Int] = [:]
        for day in studyDays {
            counts[RecapWeek(containing: day.startDate(calendar: calendar), calendar: calendar), default: 0] += 1
        }
        return counts.values.filter { $0 >= ProgressTrack.steadyWeekDays }.count
    }

    /// The first day the user did something the track counts, or nil
    /// when they never have. Monthly quests offer a track only to someone
    /// who did it before the month began.
    public func firstDay(of track: ProgressTrack) -> PlannerDayKey? {
        days.filter { $0.value.counts(toward: track) }.keys.min()
    }
}

extension ProgressTally.Day {
    /// Whether the day holds anything for `track`.
    func counts(toward track: ProgressTrack) -> Bool {
        switch track {
        case .focusHours, .gentleStreak, .steadyWeeks, .monthlyQuests: focusMinutes > 0
        case .studyDays: isStudyDay
        case .sessions: sessions > 0
        case .cards: cards > 0
        case .tasks: !taskIDs.isEmpty || unnamedTasks > 0
        case .breakMoves: breakMoves > 0
        case .party: partySessions > 0
        case .methods: !methods.isEmpty
        case .water: water > 0
        }
    }
}

/// The longest run of study days, with the same freezes the Streak section
/// uses (`StudyStreak`): a missed day while a run goes on uses that week's
/// free freeze, then the oldest extra freeze bought before it, and
/// otherwise ends the run. Today counts once studied and is never missed.
/// It is the longest run ever, so a streak that broke never takes away a
/// badge it earned.
public enum GentleStreak {
    public static func longest(studyDays: some Sequence<PlannerDayKey>, freezePurchases: some Sequence<Date> = [Date](),
                               today: Date, calendar: Calendar = .current) -> Int {
        let todayKey = PlannerDayKey(date: today, calendar: calendar)
        let studied = Set(studyDays.filter { $0 <= todayKey })
        guard var day = studied.min() else { return 0 }
        var purchases = freezePurchases.map { PlannerDayKey(date: $0, calendar: calendar) }.sorted()[...]
        var bought = 0
        var run = 0
        var longest = 0
        var freeUsedWeeks: Set<PlannerDayKey> = []

        func week(of day: PlannerDayKey) -> PlannerDayKey {
            let start = day.startDate(calendar: calendar)
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
            return PlannerDayKey(date: weekStart, calendar: calendar)
        }

        while day < todayKey {
            while let next = purchases.first, next < day {
                purchases.removeFirst()
                bought += 1
            }
            if studied.contains(day) {
                run += 1
                longest = max(longest, run)
            } else if run > 0 {
                if freeUsedWeeks.insert(week(of: day)).inserted {
                    // Frozen: the run goes on without growing.
                } else if bought > 0 {
                    bought -= 1
                } else {
                    run = 0
                }
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        if studied.contains(todayKey) { longest = max(longest, run + 1) }
        return longest
    }
}
