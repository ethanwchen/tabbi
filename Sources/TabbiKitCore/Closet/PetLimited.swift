import Foundation

/// A subtle animated effect a costume item can carry, as a hook for the pet
/// renderer: the item says which effect it has, and the renderer decides how
/// to draw it (a few pixels of the item's `effect` color changing over a
/// short loop). Items without one stay still.
public enum PetItemEffect: String, CaseIterable, Codable, Sendable {
    /// A soft glint that sweeps across gold.
    case shimmer
    /// A flame that flickers.
    case flicker
    /// A small sparkle that blinks now and then.
    case sparkle
}

/// A study milestone that unlocks a limited edition item by itself, read
/// from the activity log (`PetMilestoneProgress`).
public enum PetMilestone: String, CaseIterable, Codable, Sendable {
    /// Seven days in a row with some focused study.
    case weekStreak
    /// 50 hours focused in total.
    case fiftyHours
    /// A Party shared session finished with the user in it.
    case firstParty

    /// The goal in the milestone's own unit: days, minutes or sessions.
    public var goal: Int {
        switch self {
        case .weekStreak: 7
        case .fiftyHours: 50 * 60
        case .firstParty: 1
        }
    }
}

/// How a limited edition item is earned.
public enum PetLimitedSource: Hashable, Sendable {
    /// Unlocks on its own once the milestone is reached.
    case milestone(PetMilestone)
    /// Granted per account by the Tabbi server for taking part in an event,
    /// such as the launch week. `id` is the event's stable name.
    case event(id: String)
}

/// The limited edition items: never sold for points and never tied to
/// money. Each one is earned from a study milestone or granted for free for
/// an event, keeps its own shelf in the Closet, and says how to earn it.
public enum PetLimitedEdition: String, CaseIterable, Sendable {
    case launchWeekCap
    case streakFlame
    case focusLaurel
    case partyMedal

    public var item: PetItem {
        switch self {
        case .launchWeekCap: .accessory(.backwardsCap)
        case .streakFlame: .accessory(.flameHeadband)
        case .focusLaurel: .accessory(.goldenLaurel)
        case .partyMedal: .accessory(.teamMedal)
        }
    }

    public init?(item: PetItem) {
        guard let edition = Self.allCases.first(where: { $0.item == item }) else { return nil }
        self = edition
    }

    public var source: PetLimitedSource {
        switch self {
        case .launchWeekCap: .event(id: "launch-week")
        case .streakFlame: .milestone(.weekStreak)
        case .focusLaurel: .milestone(.fiftyHours)
        case .partyMedal: .milestone(.firstParty)
        }
    }

    public var milestone: PetMilestone? {
        if case .milestone(let milestone) = source { return milestone }
        return nil
    }

    /// One line on how to earn it, for the tile's tooltip and detail.
    public var howToEarn: String {
        switch self {
        case .launchWeekCap: "Given to everyone who used Tabbi in its launch week."
        case .streakFlame: "Study 7 days in a row."
        case .focusLaurel: "Focus for 50 hours in total."
        case .partyMedal: "Finish a Party session with friends."
        }
    }

    public var effect: PetItemEffect? {
        switch self {
        case .launchWeekCap: .sparkle
        case .streakFlame: .flicker
        case .focusLaurel: .shimmer
        case .partyMedal: .sparkle
        }
    }
}

extension PetItem {
    /// The limited edition this item belongs to, or nil for a shop item.
    public var limitedEdition: PetLimitedEdition? { PetLimitedEdition(item: self) }

    public var isLimited: Bool { limitedEdition != nil }

    /// The item's animated effect, if it has one (`PetItemEffect`).
    public var effect: PetItemEffect? { limitedEdition?.effect }
}

/// The user's progress toward every `PetMilestone`, built from the activity
/// log: focused minutes (any `focus.completed` record, from any module,
/// finished or not), the days with some focused study, and the Party
/// sessions finished. Adding the same record twice counts it once, so the
/// app can replay the log on launch and then follow new records.
public struct PetMilestoneProgress: Hashable, Sendable {
    /// A day counts toward a streak once it has this many focused minutes,
    /// the same floor that earns points (`PetPointsRules.minimumMinutes`).
    public static let minutesForStudyDay = Double(PetPointsRules.minimumMinutes)

    public private(set) var focusMinutes: Double = 0
    public private(set) var minutesByDay: [PlannerDayKey: Double] = [:]
    public private(set) var finishedPartySessions = 0
    private var seen: Set<UUID> = []

    public init() {}

    public init(records: some Sequence<ActivityRecord>, calendar: Calendar = .current) {
        for record in records { add(record, calendar: calendar) }
    }

    public mutating func add(_ record: ActivityRecord, calendar: Calendar = .current) {
        guard record.kind == .focusCompleted, record.unit == .minutes, let quantity = record.quantity,
              quantity.isFinite, quantity > 0, seen.insert(record.id).inserted else { return }
        focusMinutes += quantity
        minutesByDay[record.day(calendar: calendar), default: 0] += quantity
        let outcome = record.metadata[ActivityMetadata.outcome].flatMap(StudyPhaseOutcome.init(rawValue:))
        if record.source == .party, outcome == .completed {
            finishedPartySessions += 1
        }
    }

    /// The days with enough focused study, oldest first.
    public var studyDays: [PlannerDayKey] {
        minutesByDay.filter { $0.value >= Self.minutesForStudyDay }.keys.sorted()
    }

    /// The longest run of consecutive study days ever.
    public func longestStreak(calendar: Calendar = .current) -> Int {
        var longest = 0
        var run = 0
        var previous: Date?
        for day in studyDays {
            let start = day.startDate(calendar: calendar)
            let follows = previous.map { calendar.dateComponents([.day], from: $0, to: start).day == 1 } ?? false
            run = follows ? run + 1 : 1
            longest = max(longest, run)
            previous = start
        }
        return longest
    }

    /// The run of study days ending today, or yesterday when today has no
    /// study yet, so a streak still shows in the morning.
    public func currentStreak(today: Date, calendar: Calendar = .current) -> Int {
        let days = Set(studyDays)
        var date = calendar.startOfDay(for: today)
        if !days.contains(PlannerDayKey(date: date, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return 0 }
            date = yesterday
        }
        var streak = 0
        while days.contains(PlannerDayKey(date: date, calendar: calendar)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return streak
    }

    /// How far along a milestone is, in its own unit, capped at its goal.
    /// The streak counts the current run, since a broken one starts over.
    public func value(of milestone: PetMilestone, today: Date, calendar: Calendar = .current) -> Int {
        let value = switch milestone {
        case .weekStreak: currentStreak(today: today, calendar: calendar)
        case .fiftyHours: Int(focusMinutes)
        case .firstParty: finishedPartySessions
        }
        return min(value, milestone.goal)
    }

    public func isReached(_ milestone: PetMilestone, calendar: Calendar = .current) -> Bool {
        switch milestone {
        case .weekStreak: longestStreak(calendar: calendar) >= milestone.goal
        case .fiftyHours: Int(focusMinutes) >= milestone.goal
        case .firstParty: finishedPartySessions >= milestone.goal
        }
    }
}

extension PetMilestoneProgress {
    /// The `TABBI_DEMO=1` progress: a 4 day streak and 40 hours focused, so
    /// the Limited shelf shows milestones part of the way, and no Party
    /// session yet. The study streak (`StudyStreak`) runs on through a
    /// frozen day 4 days ago, so its day strip shows a snowflake. Before it,
    /// about five months of study that grows denser toward today, with rest
    /// days and no run long enough to reach the week streak, give the
    /// Closet's study chart (`StudyHeatmap`) a believable history.
    public static func demo(today: Date, calendar: Calendar = .current) -> PetMilestoneProgress {
        let start = calendar.startOfDay(for: today)
        func record(daysAgo: Int, minutes: Double) -> ActivityRecord? {
            guard minutes > 0, let day = calendar.date(byAdding: .day, value: -daysAgo, to: start),
                  let end = calendar.date(byAdding: .hour, value: 10, to: day) else { return nil }
            return ActivityRecord(source: "focus", kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60),
                                  end: end, quantity: minutes, unit: .minutes)
        }
        // Minutes studied 14, 15, 16 and so on days ago. The week of empty
        // days before, 7 to 13 days ago, ends any earlier run before it can
        // spend the free freeze of the week 4 days ago, so the current
        // streak is 6 days whatever weekday today is.
        let earlier: [Double] = [
            0, 0, 0, 5, 50, 0, 95, 95,
            0, 25, 0, 60, 90, 0, 30, 0, 30, 70, 0, 0, 0, 25,
            85, 30, 5, 0, 25, 0, 45, 10, 30, 30, 45, 0, 25, 0,
            0, 0, 65, 65, 20, 45, 45, 0, 0, 0, 45, 0, 0, 5,
            30, 0, 0, 0, 10, 75, 0, 0, 0, 0, 75, 75, 40, 15,
            0, 0, 0, 0, 55, 40, 0, 10, 0, 0, 40, 70, 0, 0,
            0, 0, 0, 0, 0, 20, 0, 0, 0, 45, 5, 30, 0, 0,
            0, 0, 0, 50, 0, 5, 0, 0, 0, 5, 5, 0, 0, 5,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 40, 50, 5, 5,
        ]
        let history = earlier.enumerated().compactMap { record(daysAgo: 14 + $0.offset, minutes: $0.element) }
        let beforeFreeze = [(5, 50.0), (6, 80.0)].compactMap { record(daysAgo: $0.0, minutes: $0.1) }
        let streak = [35.0, 95, 60, 120].enumerated().compactMap { record(daysAgo: $0.offset, minutes: $0.element) }
        return PetMilestoneProgress(records: history + beforeFreeze + streak, calendar: calendar)
    }
}

/// How far a limited item is from being earned, as the Limited shelf shows
/// it: a fraction for the tile's progress bar and a short count in the
/// milestone's own unit.
public struct PetLimitedProgress: Hashable, Sendable {
    public var value: Int
    public var goal: Int
    /// The tile label, such as "4/7 days" or "31/50 h".
    public var label: String

    public var fraction: Double { goal > 0 ? min(1, Double(value) / Double(goal)) : 0 }
}

extension PetMilestone {
    /// The progress label for `value` (capped at the goal). Hours round
    /// down, so the label never shows the goal before it is reached.
    public func progress(value: Int) -> PetLimitedProgress {
        let value = max(0, min(value, goal))
        let label = switch self {
        case .weekStreak: "\(value)/\(goal) days"
        case .fiftyHours: "\(value / 60)/\(goal / 60) h"
        case .firstParty: "\(value)/\(goal) session"
        }
        return PetLimitedProgress(value: value, goal: goal, label: label)
    }
}

extension PetMilestoneProgress {
    /// The Limited shelf's progress for `edition`, or nil for an event item,
    /// which has nothing to count: it is granted, not earned step by step.
    public func progress(of edition: PetLimitedEdition, today: Date,
                         calendar: Calendar = .current) -> PetLimitedProgress? {
        guard let milestone = edition.milestone else { return nil }
        return milestone.progress(value: value(of: milestone, today: today, calendar: calendar))
    }
}
