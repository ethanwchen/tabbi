import Foundation

/// How much a piece of work matters, from the To-do list or a shared task.
public enum SchedulePriority: Int, Comparable, Hashable, Sendable, CaseIterable {
    case low
    case normal
    case high

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One piece of work the local planner can schedule: a To-do item, another
/// module's shared task, or a review queue such as today's Anki cards.
public struct ScheduleWork: Identifiable, Hashable, Sendable {
    /// Stable for the work, so a plan's blocks and overflow rows point back
    /// to it (a checklist item's UUID string, a shared task's id).
    public var id: String
    public var title: String
    /// How long it takes; nil uses `SchedulePreferences.defaultTaskMinutes`.
    public var estimatedMinutes: Int?
    public var priority: SchedulePriority
    /// When it must be finished; time-sensitive work is placed first and
    /// never after this.
    public var due: Date?
    /// The checklist item a block for this work links to, if any.
    public var linkedTaskID: UUID?
    /// `.reviews` for a review queue (placed early by default), `.focus`
    /// for tasks, `.study` for open study time.
    public var kind: PlanBlockKind

    public init(id: String, title: String, estimatedMinutes: Int? = nil, priority: SchedulePriority = .normal,
                due: Date? = nil, linkedTaskID: UUID? = nil, kind: PlanBlockKind = .focus) {
        self.id = id
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.due = due
        self.linkedTaskID = linkedTaskID
        self.kind = kind
    }
}

public extension ScheduleWork {
    /// A review queue (say, Anki cards due) as plannable work.
    init(reviews: StudyReviewWork, id: String) {
        self.init(id: id, title: reviews.title, estimatedMinutes: reviews.minutes, kind: .reviews)
    }

    /// An unfinished checklist item; a To-do item has no estimate of its own.
    init(task: PlannerItem, priority: SchedulePriority = .normal) {
        self.init(id: task.id.uuidString, title: task.title, priority: priority, linkedTaskID: task.id)
    }
}

/// The user's planning rhythm. Every value has an everyday default, so the
/// planner needs no setup; the study method can supply block and break
/// lengths (`init(method:)`).
public struct SchedulePreferences: Hashable, Sendable {
    /// Working hours as minutes after midnight (9:00 to 18:00 by default).
    public var workdayStartMinute: Int
    public var workdayEndMinute: Int
    /// Length assumed for work without an estimate.
    public var defaultTaskMinutes: Int
    /// Longest single block; longer work is split across blocks.
    public var maximumBlockMinutes: Int
    /// Rest after each block, and the longer one after every
    /// `longBreakEvery`-th block (none when nil).
    public var breakMinutes: Int
    public var longBreakMinutes: Int
    public var longBreakEvery: Int?
    /// Most focus time planned in one day, reviews included.
    public var maximumFocusMinutes: Int
    /// Free time kept clear before and after every timed event.
    public var eventBufferMinutes: Int
    /// Review queues go before other work (spaced repetition works best
    /// while fresh); false puts them after it.
    public var reviewsFirst: Bool

    public init(
        workdayStartMinute: Int = 9 * 60,
        workdayEndMinute: Int = 18 * 60,
        defaultTaskMinutes: Int = 30,
        maximumBlockMinutes: Int = 90,
        breakMinutes: Int = 5,
        longBreakMinutes: Int = 15,
        longBreakEvery: Int? = 4,
        maximumFocusMinutes: Int = 6 * 60,
        eventBufferMinutes: Int = 10,
        reviewsFirst: Bool = true
    ) {
        let minimum = SchedulePlanner.minimumBlockMinutes
        let start = min(max(workdayStartMinute, 0), 24 * 60 - minimum)
        self.workdayStartMinute = start
        self.workdayEndMinute = min(max(workdayEndMinute, start + minimum), 24 * 60)
        self.defaultTaskMinutes = min(max(defaultTaskMinutes, minimum), 8 * 60)
        self.maximumBlockMinutes = min(max(maximumBlockMinutes, minimum), 4 * 60)
        self.breakMinutes = min(max(breakMinutes, 0), 60)
        self.longBreakMinutes = min(max(longBreakMinutes, 0), 120)
        self.longBreakEvery = longBreakEvery.map { max($0, 2) }
        self.maximumFocusMinutes = min(max(maximumFocusMinutes, minimum), 24 * 60)
        self.eventBufferMinutes = min(max(eventBufferMinutes, 0), 120)
        self.reviewsFirst = reviewsFirst
    }

    /// Block and break lengths from the user's study method, so a planned
    /// block matches what the timer runs (`StudyDayPreferences(method:)`
    /// covers methods without a fixed length).
    public init(method: StudyMethod, workdayStartMinute: Int = 9 * 60, workdayEndMinute: Int = 18 * 60,
                maximumFocusMinutes: Int = 6 * 60, eventBufferMinutes: Int = 10, reviewsFirst: Bool = true) {
        let study = StudyDayPreferences(method: method)
        self.init(workdayStartMinute: workdayStartMinute, workdayEndMinute: workdayEndMinute,
                  defaultTaskMinutes: study.studyMinutes, maximumBlockMinutes: max(study.studyMinutes, 25),
                  breakMinutes: study.breakMinutes, longBreakMinutes: study.longBreakMinutes ?? 15,
                  longBreakEvery: study.longBreakEvery, maximumFocusMinutes: maximumFocusMinutes,
                  eventBufferMinutes: eventBufferMinutes, reviewsFirst: reviewsFirst)
    }
}

/// One block of a local plan. `block` is what Plan My Day offers and writes;
/// `reason` says in a few words why it sits where it does.
public struct ScheduledBlock: Identifiable, Hashable, Sendable {
    public var block: PlanBlock
    /// The `ScheduleWork.id` it works on.
    public var workID: String
    public var reason: String
    /// Which piece of split work this is (1-based), and of how many.
    public var part: Int
    public var parts: Int

    public var id: PlanBlock.ID { block.id }

    public init(block: PlanBlock, workID: String, reason: String, part: Int = 1, parts: Int = 1) {
        self.block = block
        self.workID = workID
        self.reason = reason
        self.part = part
        self.parts = parts
    }
}

/// Work the plan could not (fully) fit, and why.
public struct UnplacedWork: Hashable, Sendable {
    public var work: ScheduleWork
    /// Minutes still unplanned.
    public var minutes: Int
    public var reason: String

    public init(work: ScheduleWork, minutes: Int, reason: String) {
        self.work = work
        self.minutes = minutes
        self.reason = reason
    }
}

/// A day planned on device: blocks in time order, the rests between them,
/// and what didn't fit.
public struct SchedulePlan: Hashable, Sendable {
    /// Midnight of the planned day.
    public var day: Date
    public var blocks: [ScheduledBlock]
    /// Rests between consecutive blocks that no event interrupts.
    public var breaks: [DateInterval]
    public var unplaced: [UnplacedWork]

    public init(day: Date, blocks: [ScheduledBlock], breaks: [DateInterval], unplaced: [UnplacedWork]) {
        self.day = day
        self.blocks = blocks
        self.breaks = breaks
        self.unplaced = unplaced
    }

    /// Planned focus time, in minutes.
    public var focusMinutes: Int {
        blocks.reduce(0) { $0 + Int($1.block.end.timeIntervalSince($1.block.start) / 60) }
    }

    /// The blocks as Plan My Day's proposal, breaks included.
    public var proposal: DayPlanProposal {
        DayPlanProposal(blocks: blocks.map(\.block), breaks: breaks)
    }
}

/// Several days planned together: unfinished work spread across the free
/// time of each day in turn, and what still didn't fit by the end.
public struct ScheduleWeekPlan: Hashable, Sendable {
    /// One plan per day, in order; their `unplaced` lists are empty since
    /// leftovers move on to the next day.
    public var days: [SchedulePlan]
    public var unplaced: [UnplacedWork]

    public init(days: [SchedulePlan], unplaced: [UnplacedWork]) {
        self.days = days
        self.unplaced = unplaced
    }
}

/// Plans a day (or a week) on device, without Claude or the network.
///
/// Deterministic and explainable: work is ordered review queues first (or
/// last, by preference), then time-sensitive work by due time, then by
/// priority and list order, and each piece takes the earliest free time
/// left. Free time is the working hours after `now`, minus every timed
/// event and its buffer, on the five-minute grid. Long work is split into
/// blocks of at most `maximumBlockMinutes`, each followed by its break, and
/// the day stops at `maximumFocusMinutes`. Everything that doesn't fit is
/// listed with the reason. Work already on the calendar in the planned
/// days (a block added from an earlier plan, or an event of the same
/// title) is left out, so planning again never books it twice.
public enum SchedulePlanner {
    /// Shortest block worth planning.
    public static let minimumBlockMinutes = DayPlanner.minimumBlockMinutes
    static let slot: TimeInterval = TimeInterval(DayPlanner.slotMinutes * 60)
    static let minute: TimeInterval = 60

    /// Plans the day containing `now` from `now` on.
    ///
    /// - Parameters:
    ///   - events: The calendar; all-day events never block time.
    ///   - locale: Only for the clock times in reasons ("Due by 3:00").
    public static func planDay(
        now: Date,
        events: [UpcomingEvent],
        work: [ScheduleWork],
        preferences: SchedulePreferences = SchedulePreferences(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> SchedulePlan {
        let day = calendar.startOfDay(for: now)
        let window = DateInterval(start: day, end: calendar.date(byAdding: .day, value: 1, to: day) ?? day)
        var pending = ordered(notScheduled(work, events: events, in: window), preferences: preferences)
        var plan = plan(day: day, now: now, events: events, pending: &pending,
                        preferences: preferences, calendar: calendar, locale: locale)
        plan.unplaced = pending.map { UnplacedWork(work: $0.work, minutes: $0.minutesLeft,
                                                   reason: $0.reason ?? "No free time left today") }
        return plan
    }

    /// Spreads `work` across `days` days starting with the one containing
    /// `now`: each day takes what still fits, and the rest moves on.
    public static func planWeek(
        now: Date,
        days: Int = 7,
        events: [UpcomingEvent],
        work: [ScheduleWork],
        preferences: SchedulePreferences = SchedulePreferences(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> ScheduleWeekPlan {
        let first = calendar.startOfDay(for: now)
        let window = DateInterval(start: first,
                                  end: calendar.date(byAdding: .day, value: max(days, 1), to: first) ?? first)
        var pending = ordered(notScheduled(work, events: events, in: window), preferences: preferences)
        let plans = (0..<max(days, 1)).compactMap { offset -> SchedulePlan? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            // A reason only explains the final day's leftovers.
            for index in pending.indices { pending[index].reason = nil }
            return plan(day: day, now: max(now, day), events: events, pending: &pending,
                        preferences: preferences, calendar: calendar, locale: locale)
        }
        return ScheduleWeekPlan(days: plans, unplaced: pending.map {
            UnplacedWork(work: $0.work, minutes: $0.minutesLeft, reason: $0.reason ?? "No free time left this week")
        })
    }

    /// Free intervals of the working day containing `day`, after `now`,
    /// with every timed event and its buffer cut out, on the five-minute
    /// grid, and none shorter than a block.
    public static func freeTime(
        day: Date,
        now: Date,
        events: [UpcomingEvent],
        preferences: SchedulePreferences = SchedulePreferences(),
        calendar: Calendar = .current
    ) -> [DateInterval] {
        let start = max(floorSlot(clockTime(preferences.workdayStartMinute, on: day, calendar: calendar)),
                        DayPlanner.nextSlot(onOrAfter: now))
        let end = floorSlot(clockTime(preferences.workdayEndMinute, on: day, calendar: calendar))
        guard end > start else { return [] }
        let buffer = TimeInterval(preferences.eventBufferMinutes) * minute
        let busy = events
            .filter { !$0.isAllDay && $0.end > $0.start }
            .map { DateInterval(start: $0.start.addingTimeInterval(-buffer), end: $0.end.addingTimeInterval(buffer)) }
        return subtract(busy, from: [DateInterval(start: start, end: end)])
    }

    // MARK: - Planning

    /// Work waiting for time, with how much of it is left.
    struct Pending {
        var work: ScheduleWork
        var minutesLeft: Int
        var placed = 0
        /// Why the last attempt left it out, once one did.
        var reason: String?
    }

    /// `work` without what a timed event in `window` already covers,
    /// matched by title (case and spacing aside).
    static func notScheduled(_ work: [ScheduleWork], events: [UpcomingEvent], in window: DateInterval) -> [ScheduleWork] {
        func key(_ title: String) -> String? { PlannerDay.normalized(title)?.lowercased() }
        let booked = Set(events
            .filter { !$0.isAllDay && $0.end > $0.start && $0.start < window.end && $0.end > window.start }
            .compactMap { key($0.title) })
        return work.filter { key($0.title).map { !booked.contains($0) } ?? true }
    }

    /// Review queues first (or last), then work with a due time, earliest
    /// first, then the rest by priority; ties keep list order.
    static func ordered(_ work: [ScheduleWork], preferences: SchedulePreferences) -> [Pending] {
        let indexed = work.enumerated().filter { PlannerDay.normalized($0.element.title) != nil }
        func group(_ work: ScheduleWork) -> Int {
            if work.kind == .reviews { return preferences.reviewsFirst ? 0 : 3 }
            return work.due == nil ? 2 : 1
        }
        let sorted = indexed.sorted { lhs, rhs in
            let (a, b) = (lhs.element, rhs.element)
            if group(a) != group(b) { return group(a) < group(b) }
            if a.due != b.due { return (a.due ?? .distantFuture) < (b.due ?? .distantFuture) }
            if a.priority != b.priority { return a.priority > b.priority }
            return lhs.offset < rhs.offset
        }
        return sorted.map { entry in
            var work = entry.element
            work.title = PlannerDay.normalized(work.title) ?? work.title
            let minutes = work.estimatedMinutes ?? preferences.defaultTaskMinutes
            // Rounded up to the grid, and never shorter than a block.
            let rounded = Int((Double(max(minutes, minimumBlockMinutes)) / 5).rounded(.up)) * 5
            return Pending(work: work, minutesLeft: min(rounded, 24 * 60))
        }
    }

    /// Fills one day from `pending`, removing what it places.
    static func plan(
        day: Date,
        now: Date,
        events: [UpcomingEvent],
        pending: inout [Pending],
        preferences: SchedulePreferences,
        calendar: Calendar,
        locale: Locale
    ) -> SchedulePlan {
        let minimum = TimeInterval(minimumBlockMinutes) * minute
        var free = freeTime(day: day, now: now, events: events, preferences: preferences, calendar: calendar)
        var placed: [(block: ScheduledBlock, rest: TimeInterval, index: Int)] = []
        var focusLeft = TimeInterval(preferences.maximumFocusMinutes) * minute

        func restAfter(blockNumber: Int) -> TimeInterval {
            if let every = preferences.longBreakEvery, blockNumber % every == 0 {
                return TimeInterval(preferences.longBreakMinutes) * minute
            }
            return TimeInterval(preferences.breakMinutes) * minute
        }

        for index in pending.indices {
            let work = pending[index].work
            let deadline = work.due.map(floorSlot)
            while pending[index].minutesLeft > 0 {
                let left = TimeInterval(pending[index].minutesLeft) * minute
                guard focusLeft >= minimum else {
                    pending[index].reason = "Over your \(hours(preferences.maximumFocusMinutes)) focus limit"
                    break
                }
                let want = min(left, TimeInterval(preferences.maximumBlockMinutes) * minute, floorDuration(focusLeft))
                let usable = free.compactMap { gap -> DateInterval? in
                    guard let deadline else { return gap }
                    guard gap.start < deadline else { return nil }
                    return DateInterval(start: gap.start, end: min(gap.end, deadline))
                }
                guard let piece = pieceToPlace(want: want, left: left, usable: usable, minimum: minimum) else {
                    pending[index].reason = deadline.map {
                        "No free time before \(UpcomingEventFormat.startTime($0, locale: locale, timeZone: calendar.timeZone))"
                    }
                    break
                }
                let block = PlanBlock(start: piece.start, end: piece.end, title: work.title,
                                      linkedTaskID: work.linkedTaskID, kind: work.kind)
                let rest = restAfter(blockNumber: placed.count + 1)
                placed.append((ScheduledBlock(block: block, workID: work.id,
                                              reason: reason(for: work, preferences: preferences,
                                                             calendar: calendar, locale: locale)),
                               rest, index))
                free = subtract([DateInterval(start: piece.start, end: ceilSlot(piece.end.addingTimeInterval(rest)))],
                                from: free)
                pending[index].minutesLeft -= Int((piece.duration / minute).rounded())
                pending[index].placed += 1
                focusLeft -= piece.duration
            }
        }

        // Number the pieces of split work in time order.
        var ordered = placed.sorted { $0.block.block.start < $1.block.block.start }
        var seen: [Int: Int] = [:]
        for position in ordered.indices {
            let index = ordered[position].index
            let parts = pending[index].placed
            guard parts > 1 else { continue }
            seen[index, default: 0] += 1
            ordered[position].block.part = seen[index]!
            ordered[position].block.parts = parts
        }
        pending.removeAll { $0.minutesLeft <= 0 }
        for index in pending.indices { pending[index].placed = 0 }

        let busy = events.filter { !$0.isAllDay && $0.end > $0.start }
        let breaks = zip(ordered, ordered.dropFirst()).compactMap { pair -> DateInterval? in
            let (previous, next) = (pair.0.block.block, pair.1.block.block)
            guard pair.0.rest > 0, next.start > previous.end else { return nil }
            let rest = DateInterval(start: previous.end,
                                    end: min(next.start, ceilSlot(previous.end.addingTimeInterval(pair.0.rest))))
            let interrupted = busy.contains { $0.start < next.start && $0.end > previous.end }
            return interrupted ? nil : rest
        }
        return SchedulePlan(day: calendar.startOfDay(for: day), blocks: ordered.map(\.block), breaks: breaks,
                            unplaced: [])
    }

    /// Where the next piece of work goes: the earliest gap that holds
    /// `want` whole, otherwise as much as the earliest gap holds, as long as
    /// neither that piece nor what remains after it is shorter than
    /// `minimum`. Nil when no gap can take a piece.
    static func pieceToPlace(want: TimeInterval, left: TimeInterval, usable: [DateInterval],
                             minimum: TimeInterval) -> DateInterval? {
        guard want >= minimum else { return nil }
        var want = want
        if left - want > 0, left - want < minimum, left - minimum >= minimum { want = left - minimum }
        if let gap = usable.first(where: { $0.duration >= want }) {
            return DateInterval(start: gap.start, duration: want)
        }
        for gap in usable {
            var length = floorDuration(gap.duration)
            if left - length > 0, left - length < minimum { length = left - minimum }
            if length >= minimum { return DateInterval(start: gap.start, duration: length) }
        }
        return nil
    }

    /// A few words on why a block sits where it does.
    static func reason(for work: ScheduleWork, preferences: SchedulePreferences, calendar: Calendar,
                       locale: Locale) -> String {
        if work.kind == .reviews {
            return preferences.reviewsFirst ? "Reviews first, while you are fresh" : "Reviews after the main work"
        }
        if let due = work.due {
            return "Due by \(UpcomingEventFormat.startTime(due, locale: locale, timeZone: calendar.timeZone))"
        }
        switch work.priority {
        case .high: return "High priority"
        case .normal: return "Next on your list"
        case .low: return "Low priority, after the rest"
        }
    }

    // MARK: - Helpers

    /// The wall-clock time `minutes` after midnight on the day containing
    /// `day` (24:00 is the next midnight), so working hours keep their
    /// clock times on a daylight saving change.
    public static func clockTime(_ minutes: Int, on day: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: day)
        guard minutes < 24 * 60 else {
            return calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight.addingTimeInterval(86_400)
        }
        let minutes = max(minutes, 0)
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: midnight) ?? midnight
    }

    /// `intervals` with every interval in `busy` cut out, dropping pieces
    /// shorter than a block.
    static func subtract(_ busy: [DateInterval], from intervals: [DateInterval]) -> [DateInterval] {
        let minimum = TimeInterval(minimumBlockMinutes) * minute
        var free = intervals
        for taken in busy {
            free = free.flatMap { gap -> [DateInterval] in
                guard taken.start < gap.end, gap.start < taken.end else { return [gap] }
                var pieces: [DateInterval] = []
                if gap.start < taken.start { pieces.append(DateInterval(start: gap.start, end: floorSlot(taken.start))) }
                if taken.end < gap.end { pieces.append(DateInterval(start: ceilSlot(taken.end), end: gap.end)) }
                return pieces.filter { $0.end > $0.start }
            }
        }
        return free.filter { $0.duration >= minimum }.sorted { $0.start < $1.start }
    }

    static func floorSlot(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / slot).rounded(.down) * slot)
    }

    static func ceilSlot(_ date: Date) -> Date { DayPlanner.nextSlot(onOrAfter: date) }

    static func floorDuration(_ duration: TimeInterval) -> TimeInterval { (duration / slot).rounded(.down) * slot }

    /// "6 h" or "4 h 30 min".
    static func hours(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) h" : minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
