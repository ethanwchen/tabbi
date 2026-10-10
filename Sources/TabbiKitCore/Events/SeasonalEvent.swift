import Foundation

/// The calendar an event's dates are written in. Lunar New Year moves on
/// the Gregorian calendar every year but sits on the first day of the first
/// month of the Chinese calendar, so its dates are written there.
public enum SeasonalEventCalendar: String, Codable, CaseIterable, Sendable {
    case gregorian
    case chinese

    /// A calendar of this kind in `base`'s time zone and locale, so an
    /// event starts at local midnight wherever the user is.
    func calendar(matching base: Calendar) -> Calendar {
        var calendar = Calendar(identifier: self == .gregorian ? .gregorian : .chinese)
        calendar.timeZone = base.timeZone
        calendar.locale = base.locale
        return calendar
    }
}

/// A month and day an event starts or ends on, the same every year in its
/// `SeasonalEventCalendar`.
public struct SeasonalEventDay: Hashable, Codable, Sendable {
    public var month: Int
    public var day: Int

    public init(month: Int, day: Int) {
        self.month = month
        self.day = day
    }

    var components: DateComponents {
        var components = DateComponents(month: month, day: day, hour: 0, minute: 0, second: 0)
        components.isLeapMonth = false
        return components
    }
}

/// An item an event offers, and the focused minutes during the event that
/// earn it. Earned with time, never with money or points.
public struct SeasonalEventReward: Hashable, Sendable {
    public var item: PetItem
    public var focusMinutes: Int

    public init(item: PetItem, focusMinutes: Int) {
        self.item = item
        self.focusMinutes = focusMinutes
    }
}

/// A seasonal event, such as Halloween: a window of local days that comes
/// back every year, a short line of copy, and the limited items earnable by
/// focusing while it runs. Earned items stay owned after the event; an item
/// not earned in time can be earned when the event returns next year.
public struct SeasonalEvent: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// One gentle line for the Closet banner.
    public var tagline: String
    public var calendar: SeasonalEventCalendar
    /// The first day, from its local midnight.
    public var start: SeasonalEventDay
    /// The last day, through its end. Earlier in the year than `start` when
    /// the event runs over New Year.
    public var end: SeasonalEventDay
    /// The items to earn, cheapest first; the last one is the headline item.
    public var rewards: [SeasonalEventReward]

    public init(id: String, name: String, tagline: String, calendar: SeasonalEventCalendar = .gregorian,
                start: SeasonalEventDay, end: SeasonalEventDay, rewards: [SeasonalEventReward]) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.calendar = calendar
        self.start = start
        self.end = end
        self.rewards = rewards
    }

    /// The event's headline item, the one with a subtle effect.
    public var headline: PetItem? { rewards.last?.item }

    /// The run of the event that `date` falls in, or nil between runs.
    /// `calendar` gives the time zone: an event starts and ends at local
    /// midnight.
    public func occurrence(containing date: Date, calendar base: Calendar = .current) -> SeasonalEventOccurrence? {
        let calendar = self.calendar.calendar(matching: base)
        // The latest start at or before `date`, then that run's end.
        guard let start = calendar.nextDate(after: date.addingTimeInterval(1), matching: start.components,
                                            matchingPolicy: .nextTime, direction: .backward),
              let occurrence = occurrence(startingAt: start, in: calendar) else { return nil }
        return occurrence.contains(date) ? occurrence : nil
    }

    /// The next run that starts after `date`.
    public func nextOccurrence(after date: Date, calendar base: Calendar = .current) -> SeasonalEventOccurrence? {
        let calendar = self.calendar.calendar(matching: base)
        guard let start = calendar.nextDate(after: date, matching: start.components, matchingPolicy: .nextTime) else {
            return nil
        }
        return occurrence(startingAt: start, in: calendar)
    }

    private func occurrence(startingAt start: Date, in calendar: Calendar) -> SeasonalEventOccurrence? {
        guard let lastDay = calendar.nextDate(after: start.addingTimeInterval(-1), matching: end.components,
                                              matchingPolicy: .nextTime),
              let end = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return nil }
        return SeasonalEventOccurrence(event: self, start: start, end: calendar.startOfDay(for: end))
    }
}

/// One year's run of a `SeasonalEvent`, as absolute dates.
public struct SeasonalEventOccurrence: Hashable, Sendable {
    public var event: SeasonalEvent
    /// Local midnight of the first day.
    public var start: Date
    /// Local midnight after the last day; not part of the run.
    public var end: Date

    public func contains(_ date: Date) -> Bool { start <= date && date < end }

    /// A stable id for this year's run, such as `halloween-2026`, from the
    /// Gregorian year it starts in.
    public func id(calendar: Calendar = .current) -> String {
        "\(event.id)-\(calendar.component(.year, from: start))"
    }
}

/// The focused minutes logged during one run of an event, and what they
/// earn. Built from the activity log like `PetMilestoneProgress`: any
/// `focus.completed` record that ended inside the run counts, and adding the
/// same record twice counts it once. A new run starts from zero, so an item
/// missed one year can be earned the next.
public struct SeasonalEventProgress: Hashable, Sendable {
    public let occurrence: SeasonalEventOccurrence
    public private(set) var focusMinutes: Double = 0
    private var seen: Set<UUID> = []

    public init(occurrence: SeasonalEventOccurrence, records: some Sequence<ActivityRecord> = [ActivityRecord]()) {
        self.occurrence = occurrence
        for record in records { add(record) }
    }

    public mutating func add(_ record: ActivityRecord) {
        guard record.kind == .focusCompleted, record.unit == .minutes, let quantity = record.quantity,
              quantity.isFinite, quantity > 0, occurrence.contains(record.end),
              seen.insert(record.id).inserted else { return }
        focusMinutes += quantity
    }

    /// The rewards whose minutes this run has reached, in event order.
    public var earned: [PetItem] {
        occurrence.event.rewards.filter { Int(focusMinutes) >= $0.focusMinutes }.map(\.item)
    }

    /// The first reward not reached yet, the one to show progress toward.
    public var nextReward: SeasonalEventReward? {
        occurrence.event.rewards.first { Int(focusMinutes) < $0.focusMinutes }
    }

    /// Progress toward `reward`, in whole minutes capped at its goal, with
    /// a label in minutes under two hours ("45/90 min") and whole hours,
    /// rounded down, above ("3/5 h"). The catalog keeps goals of two hours
    /// or more to whole hours, so the label never shows a fraction.
    public func progress(of reward: SeasonalEventReward) -> PetLimitedProgress {
        let goal = reward.focusMinutes
        let value = max(0, min(Int(focusMinutes), goal))
        let label = goal < Self.hourLabelMinutes ? "\(value)/\(goal) min" : "\(value / 60)/\(goal / 60) h"
        return PetLimitedProgress(value: value, goal: goal, label: label)
    }

    /// Goals from this many minutes up read in hours.
    static let hourLabelMinutes = 120
}

/// The focused minutes logged during every run of every event in a
/// catalog, kept per run (`SeasonalEventProgress`). The Closet replays the
/// whole activity log into it on launch and then follows new records, so an
/// item is earned even when the run's focus time was logged while the Closet
/// was not watching, and a past run's earned items can be granted late.
public struct SeasonalEventTally: Hashable, Sendable {
    public let catalog: SeasonalEventCatalog
    /// Gives the time zone that decides which local days a record ends on.
    public let calendar: Calendar
    /// Each run with some focus logged, by its id (`halloween-2026`).
    public private(set) var runs: [String: SeasonalEventProgress] = [:]

    public init(catalog: SeasonalEventCatalog = .bundled, calendar: Calendar = .current,
                records: some Sequence<ActivityRecord> = [ActivityRecord]()) {
        self.catalog = catalog
        self.calendar = calendar
        for record in records { add(record) }
    }

    /// Counts `record` toward every run going on when it ended; adding the
    /// same record twice counts it once.
    public mutating func add(_ record: ActivityRecord) {
        guard record.kind == .focusCompleted else { return }
        for occurrence in catalog.active(at: record.end, calendar: calendar) {
            let id = occurrence.id(calendar: calendar)
            runs[id, default: SeasonalEventProgress(occurrence: occurrence)].add(record)
        }
    }

    /// Every item some run has earned, in catalog order.
    public var earned: [PetItem] {
        let items = Set(runs.values.flatMap(\.earned))
        return catalog.events.flatMap { $0.rewards.map(\.item) }.filter(items.contains)
    }

    /// The runs going on at `date`, the one ending soonest first, each with
    /// the focus logged so far (none yet for a run that just started).
    public func active(at date: Date) -> [SeasonalEventProgress] {
        catalog.active(at: date, calendar: calendar).map {
            runs[$0.id(calendar: calendar)] ?? SeasonalEventProgress(occurrence: $0)
        }
    }

    /// Progress toward `item` while its event runs at `date`, for the
    /// Limited shelf; nil between runs, when there is nothing to count.
    public func progress(of item: PetItem, at date: Date) -> PetLimitedProgress? {
        for run in active(at: date) {
            if let reward = run.occurrence.event.rewards.first(where: { $0.item == item }) {
                return run.progress(of: reward)
            }
        }
        return nil
    }
}
