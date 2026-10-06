import Foundation

/// One thing on the Schedule's timeline: a calendar event, or a block
/// Tabbi planned (one already written to the calendar, or a proposal).
public struct ScheduleItem: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Anything on the calendar that Tabbi didn't plan.
        case event
        /// A focus, review or study block from Plan my day.
        case planned
        /// A block the planner offers that isn't on the calendar yet.
        case proposed
    }

    public let id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var kind: Kind
    public var isAllDay: Bool
    public var calendarColor: EventColor?
    /// Why a planned block sits where it does, when the planner said.
    public var reason: String?
    public var meetingLink: MeetingLink?

    public init(id: String, title: String, start: Date, end: Date, kind: Kind = .event, isAllDay: Bool = false,
                calendarColor: EventColor? = nil, reason: String? = nil, meetingLink: MeetingLink? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.kind = kind
        self.isAllDay = isAllDay
        self.calendarColor = calendarColor
        self.reason = reason
        self.meetingLink = meetingLink
    }

    /// A calendar event; one whose notes carry Tabbi's planned marker is a
    /// planned block.
    public init(event: UpcomingEvent, notes: String? = nil) {
        let planned = notes?.contains(DayPlanner.eventNote) == true
        self.init(id: event.id, title: event.title, start: event.start, end: event.end,
                  kind: planned ? .planned : .event, isAllDay: event.isAllDay,
                  calendarColor: event.calendarColor, meetingLink: event.meetingLink)
    }

    /// A block from a local plan, with its reason.
    public init(scheduled: ScheduledBlock) {
        self.init(id: scheduled.id.uuidString, title: scheduled.block.title, start: scheduled.block.start,
                  end: scheduled.block.end, kind: .planned, reason: scheduled.reason)
    }

    /// The item as an event the planner keeps clear of.
    public var upcomingEvent: UpcomingEvent {
        UpcomingEvent(id: id, title: title, start: start, end: end, isAllDay: isAllDay,
                      calendarColor: calendarColor, meetingLink: meetingLink)
    }

    public var minutes: Int { max(Int(end.timeIntervalSince(start) / 60), 0) }
}

/// The Schedule's Day view, laid out: which hours the timeline spans, where
/// each item sits along it, and which row (lane) it takes so overlapping
/// items stack instead of covering each other.
public struct ScheduleDayLayout: Hashable, Sendable {
    /// An item with its place on the timeline, as fractions of its width.
    public struct Placed: Identifiable, Hashable, Sendable {
        public var item: ScheduleItem
        public var x: Double
        public var width: Double
        /// Row within its group of overlapping items, and how many rows that
        /// group needs (at most `maximumLanes`).
        public var lane: Int
        public var lanes: Int
        /// How much of the width the item's label may use: its own width,
        /// stretched over the free track after it up to the next item in its
        /// row, so a short block still gets a readable title.
        public var labelWidth: Double

        public var id: String { item.id }
    }

    /// What is happening at a moment, for the line under the timeline.
    public enum Status: Hashable, Sendable {
        /// Inside an item until its end.
        case busy(ScheduleItem)
        /// Free until the next item starts, or for the rest of the working
        /// day when nothing else is on.
        case free(until: Date?, next: ScheduleItem?)
        /// The working day has ended.
        case dayOver
    }

    /// Most rows a group of overlapping items gets; more items share the last.
    public static let maximumLanes = 3

    /// Midnight of the day shown.
    public var day: Date
    /// Whole hours the timeline spans: the working hours, stretched to show
    /// any timed item outside them.
    public var range: DateInterval
    /// Each hour mark inside `range`, its start included.
    public var hours: [Date]
    public var placed: [Placed]
    public var allDay: [ScheduleItem]
    /// Free time left in the working day after `now`, buffers kept, on the
    /// planner's five-minute grid.
    public var freeMinutes: Int
    /// When the working day ends, after which an empty rest of the day is over.
    public var workEnd: Date

    public init(day: Date, now: Date, items: [ScheduleItem],
                preferences: SchedulePreferences = SchedulePreferences(), calendar: Calendar = .current) {
        let midnight = calendar.startOfDay(for: day)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight.addingTimeInterval(86_400)
        let timed = items
            .filter { !$0.isAllDay && $0.end > $0.start && $0.end > midnight && $0.start < nextMidnight }
            .sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        let workStart = SchedulePlanner.clockTime(preferences.workdayStartMinute, on: midnight, calendar: calendar)
        let workEnd = SchedulePlanner.clockTime(preferences.workdayEndMinute, on: midnight, calendar: calendar)
        let first = max(min(timed.first?.start ?? workStart, workStart), midnight)
        let last = min(max(timed.map(\.end).max() ?? workEnd, workEnd), nextMidnight)
        let start = Self.hour(first, roundingUp: false, calendar: calendar)
        var end = Self.hour(last, roundingUp: true, calendar: calendar)
        if end <= start { end = start.addingTimeInterval(3_600) }
        self.day = midnight
        self.workEnd = workEnd
        self.range = DateInterval(start: start, end: end)
        var hours: [Date] = []
        var mark = start
        while mark <= end {
            hours.append(mark)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: mark), next > mark else { break }
            mark = next
        }
        self.hours = hours
        self.placed = Self.place(timed, in: range)
        self.allDay = items.filter { $0.isAllDay && $0.end > midnight && $0.start < nextMidnight }
        let free = SchedulePlanner.freeTime(day: midnight, now: now, events: timed.map(\.upcomingEvent),
                                            preferences: preferences, calendar: calendar)
        self.freeMinutes = free.reduce(0) { $0 + Int($1.duration / 60) }
    }

    /// Where `date` falls along the timeline (0 at its start, 1 at its end),
    /// or nil outside it.
    public func position(of date: Date) -> Double? {
        guard range.contains(date) else { return nil }
        return date.timeIntervalSince(range.start) / range.duration
    }

    /// What is on at `now`: the item under way (the one ending soonest when
    /// several are), else the free time until the next one.
    public func status(at now: Date) -> Status {
        let items = placed.map(\.item)
        if let current = items.filter({ $0.start <= now && now < $0.end }).min(by: { $0.end < $1.end }) {
            return .busy(current)
        }
        let next = items.filter { $0.start > now }.min { $0.start < $1.start }
        if next == nil, now >= workEnd { return .dayOver }
        return .free(until: next?.start, next: next)
    }

    /// Positions and lanes: items that overlap (directly or through a chain)
    /// form a group, and each takes the first row free at its start.
    static func place(_ items: [ScheduleItem], in range: DateInterval) -> [Placed] {
        var result: [Placed] = []
        var groups: [Int] = []
        var group: [Placed] = []
        var groupEnd = Date.distantPast
        var laneEnds: [Date] = []
        func closeGroup() {
            let lanes = (group.map(\.lane).max() ?? 0) + 1
            result += group.map { var placed = $0; placed.lanes = lanes; return placed }
            groups += Array(repeating: (groups.last ?? -1) + 1, count: group.count)
            group = []
            laneEnds = []
        }
        for item in items {
            if item.start >= groupEnd, !group.isEmpty { closeGroup() }
            let start = max(item.start, range.start)
            let end = min(item.end, range.end)
            var lane = laneEnds.firstIndex { $0 <= item.start } ?? laneEnds.count
            if lane >= maximumLanes {
                lane = maximumLanes - 1
            }
            if lane < laneEnds.count { laneEnds[lane] = max(laneEnds[lane], item.end) } else { laneEnds.append(item.end) }
            groupEnd = max(groupEnd, item.end)
            group.append(Placed(item: item, x: start.timeIntervalSince(range.start) / range.duration,
                                width: max(end.timeIntervalSince(start), 0) / range.duration, lane: lane, lanes: 1,
                                labelWidth: 0))
        }
        if !group.isEmpty { closeGroup() }
        // A label runs until the next item that shares its row: a later one in
        // the same lane of its group, or the first of any later group, which
        // spans every row.
        for index in result.indices {
            let placed = result[index]
            let next = result.indices
                .filter { $0 > index && (groups[$0] > groups[index] || result[$0].lane == placed.lane) }
                .map { result[$0].x }
                .filter { $0 >= placed.x }
                .min() ?? 1
            result[index].labelWidth = max(placed.width, next - placed.x)
        }
        return result
    }

    private static func hour(_ date: Date, roundingUp: Bool, calendar: Calendar) -> Date {
        let floored = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        guard roundingUp, floored < date else { return floored }
        return calendar.date(byAdding: .hour, value: 1, to: floored) ?? date
    }
}

/// The Schedule's words for times, lengths and what is on now.
public enum ScheduleFormat {
    /// "45 min", "2 h", "1 h 15 min".
    public static func duration(minutes: Int) -> String {
        let minutes = max(minutes, 0)
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// "10:45-12:00" in the user's clock style, without AM/PM.
    public static func range(_ start: Date, _ end: Date, locale: Locale = .current,
                             timeZone: TimeZone = .current) -> String {
        UpcomingEventFormat.startTime(start, locale: locale, timeZone: timeZone) + "-"
            + UpcomingEventFormat.startTime(end, locale: locale, timeZone: timeZone)
    }

    /// The line under the timeline: what is on now, or how long is free.
    public static func status(_ status: ScheduleDayLayout.Status, now: Date, locale: Locale = .current,
                              timeZone: TimeZone = .current) -> String {
        func time(_ date: Date) -> String { UpcomingEventFormat.startTime(date, locale: locale, timeZone: timeZone) }
        switch status {
        case .busy(let item):
            return "Now: \(title(item)), until \(time(item.end))"
        case .free(let until?, let next?):
            let minutes = Int((until.timeIntervalSince(now) / 60).rounded(.up))
            return "Free for \(duration(minutes: minutes)), then \(title(next)) at \(time(until))"
        case .free:
            return "Free for the rest of the day"
        case .dayOver:
            return "Your working day is over"
        }
    }

    /// Empty-title events (common for quick-adds) still need a label.
    public static func title(_ item: ScheduleItem) -> String {
        let trimmed = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled event" : trimmed
    }
}

/// The Schedule's Week view, laid out: one row per day from today on, all
/// sharing the same span of clock hours so busy times line up down the
/// week, each with its free time.
public struct ScheduleWeekLayout: Hashable, Sendable {
    public struct Day: Identifiable, Hashable, Sendable {
        /// Midnight of the day.
        public var date: Date
        /// The day's span on the shared clock hours.
        public var range: DateInterval
        /// Timed items, as fractions of `range`, in lanes like the Day view.
        public var placed: [ScheduleDayLayout.Placed]
        public var allDay: [ScheduleItem]
        /// Free working time after the moment the layout was made for,
        /// buffers kept, on the planner's grid.
        public var freeMinutes: Int
        public var isToday: Bool

        public var id: Date { date }

        /// Timed events, planned blocks left out.
        public var eventCount: Int { placed.filter { $0.item.kind == .event }.count }
        public var plannedCount: Int { placed.filter { $0.item.kind == .planned }.count }

        /// Where `date` falls along the row, or nil outside it.
        public func position(of date: Date) -> Double? {
            guard range.contains(date) else { return nil }
            return date.timeIntervalSince(range.start) / range.duration
        }
    }

    public var days: [Day]
    /// The clock hours every row spans, as minutes after midnight: the
    /// working hours, stretched to whole hours around any earlier or later
    /// timed item that week.
    public var startMinute: Int
    public var endMinute: Int
    /// Free working time left across the week.
    public var freeMinutes: Int

    /// Each whole hour inside the span, as minutes after midnight.
    public var hourMarks: [Int] { Array(stride(from: startMinute, through: endMinute, by: 60)) }

    /// Where a clock time (minutes after midnight) falls along every row.
    public func position(ofMinute minute: Int) -> Double {
        Double(minute - startMinute) / Double(max(endMinute - startMinute, 1))
    }

    /// Lays out `dayCount` days starting with the day containing `now`.
    public init(now: Date, days dayCount: Int = 7, items: [ScheduleItem],
                preferences: SchedulePreferences = SchedulePreferences(), calendar: Calendar = .current) {
        let first = calendar.startOfDay(for: now)
        let midnights = (0..<max(dayCount, 1)).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        let last = midnights.last.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? first
        let timed = items
            .filter { !$0.isAllDay && $0.end > $0.start && $0.end > first && $0.start < last }
            .sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }

        // Clock minutes of each timed item, clipped to its own day.
        func minuteOfDay(_ date: Date) -> Int {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        var earliest = preferences.workdayStartMinute
        var latest = preferences.workdayEndMinute
        for item in timed {
            let startDay = calendar.startOfDay(for: item.start)
            earliest = min(earliest, startDay < first ? 0 : minuteOfDay(item.start))
            // Ending at or past the next midnight runs to the end of the day.
            latest = max(latest, calendar.startOfDay(for: item.end) > startDay ? 24 * 60 : minuteOfDay(item.end))
        }
        let startMinute = earliest / 60 * 60
        var endMinute = min((latest + 59) / 60 * 60, 24 * 60)
        if endMinute <= startMinute { endMinute = min(startMinute + 60, 24 * 60) }
        self.startMinute = startMinute
        self.endMinute = endMinute

        let events = timed.map(\.upcomingEvent)
        let today = first
        days = midnights.map { midnight in
            func time(_ minutes: Int) -> Date { SchedulePlanner.clockTime(minutes, on: midnight, calendar: calendar) }
            let range = DateInterval(start: time(startMinute), end: max(time(endMinute), time(startMinute)))
            let next = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight.addingTimeInterval(86_400)
            let dayItems = timed.filter { $0.end > range.start && $0.start < range.end }
            let free = SchedulePlanner.freeTime(day: midnight, now: now, events: events,
                                                preferences: preferences, calendar: calendar)
            return Day(date: midnight, range: range, placed: ScheduleDayLayout.place(dayItems, in: range),
                       allDay: items.filter { $0.isAllDay && $0.end > midnight && $0.start < next },
                       freeMinutes: free.reduce(0) { $0 + Int($1.duration / 60) }, isToday: midnight == today)
        }
        freeMinutes = days.reduce(0) { $0 + $1.freeMinutes }
    }
}
