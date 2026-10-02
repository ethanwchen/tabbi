import Foundation

/// A review goal Plan My Day should fit in before (or after) study blocks,
/// such as "Anki reviews" with 320 cards left. Built from a shared
/// `ProgressItem`, so any module with a daily review queue gets a block.
public struct StudyReviewWork: Hashable, Sendable {
    public var title: String
    /// Planned length; `StudyDayPlanner` clamps it to a sensible block.
    public var minutes: Int

    public init(title: String, minutes: Int) {
        self.title = title
        self.minutes = minutes
    }
}

extension ProgressItem {
    /// Review work for what's left of this goal, at `secondsPerUnit` each
    /// (about 10 s per Anki card is typical), rounded up to five minutes.
    /// Nil when the goal is already met.
    public func reviewWork(secondsPerUnit: TimeInterval = StudyDayPreferences.defaultSecondsPerCard) -> StudyReviewWork? {
        guard remaining > 0 else { return nil }
        let minutes = (Double(remaining) * max(secondsPerUnit, 1) / 60 / 5).rounded(.up) * 5
        return StudyReviewWork(title: title, minutes: Int(minutes))
    }
}

/// How the user likes their study day laid out. Every default here is
/// generic; a kit's `moduleSettings` can change the wording and lengths.
public struct StudyDayPreferences: Hashable, Sendable {
    /// Typical time to answer one Anki card.
    public static let defaultSecondsPerCard: TimeInterval = 10
    /// Longest single review block; anything left over waits for later.
    public static let maximumReviewMinutes = 120

    /// Length of one study block.
    public var studyMinutes: Int
    /// Rest after a block before the next one starts.
    public var breakMinutes: Int
    /// A longer rest replacing every `longBreakEvery`-th break, if any.
    public var longBreakMinutes: Int?
    public var longBreakEvery: Int?
    /// Schedule reviews in the first free time (spaced repetition works
    /// best before new material); false puts them last.
    public var reviewsFirst: Bool
    /// Free time kept clear right before and after a calendar event, so a
    /// lecture or shift never runs straight into a block.
    public var eventBufferMinutes: Int
    /// Title for study blocks once every open task has one.
    public var studyTitle: String

    public init(
        studyMinutes: Int = 25,
        breakMinutes: Int = 5,
        longBreakMinutes: Int? = nil,
        longBreakEvery: Int? = nil,
        reviewsFirst: Bool = true,
        eventBufferMinutes: Int = 10,
        studyTitle: String = "Study block"
    ) {
        self.studyMinutes = min(max(studyMinutes, DayPlanner.minimumBlockMinutes), Self.maximumReviewMinutes)
        self.breakMinutes = max(breakMinutes, 0)
        self.longBreakMinutes = longBreakMinutes.map { max($0, 0) }
        self.longBreakEvery = longBreakEvery.map { max($0, 2) }
        self.reviewsFirst = reviewsFirst
        self.eventBufferMinutes = max(eventBufferMinutes, 0)
        self.studyTitle = PlannerDay.normalized(studyTitle) ?? "Study block"
    }

    /// Block and break lengths from the user's study method, so a planned
    /// block matches what the Study timer will run. Methods without a fixed
    /// length get a plannable stand-in: Flowtime 45 min with its matching
    /// break, an Anki sprint the sprint's break interval, and a question
    /// block its questions plus the review of their explanations.
    public init(method: StudyMethod, reviewsFirst: Bool = true, eventBufferMinutes: Int = 10,
                studyTitle: String = "Study block") {
        func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded()) }
        let focus: TimeInterval
        switch method.focus {
        case .duration(let length): focus = length + (method.review ?? 0)
        case .openEnded: focus = 45 * 60
        case .cards: focus = StudyMethod.sprintBreakInterval
        }
        self.init(
            studyMinutes: minutes(focus),
            breakMinutes: minutes(method.duration(of: .shortBreak, workedBeforeBreak: focus) ?? 5 * 60),
            longBreakMinutes: method.longBreak.map { minutes($0.duration) },
            longBreakEvery: method.longBreak?.every,
            reviewsFirst: reviewsFirst,
            eventBufferMinutes: eventBufferMinutes,
            studyTitle: studyTitle
        )
    }
}

/// A study-aware Plan My Day proposal: the blocks to offer, plus the breaks
/// left between them, so the panel can show the rhythm of the day.
public struct StudyDayPlan: Equatable, Sendable {
    /// Review and study blocks in time order, never overlapping each other
    /// or a timed event.
    public var blocks: [PlanBlock]
    /// Rests between consecutive blocks that no event interrupts.
    public var breaks: [DateInterval]

    public init(blocks: [PlanBlock], breaks: [DateInterval]) {
        self.blocks = blocks
        self.breaks = breaks
    }
}

/// Plans a study day without Claude: review blocks, study blocks of the
/// user's method length, and breaks, fitted around calendar events.
///
/// Deterministic, so the plan is instant, works offline, and its
/// constraints are testable: blocks stay inside `DayPlanContext.gaps` minus
/// the event buffer, never overlap, study blocks are exactly the method's
/// length, and reviews come first unless the user asked otherwise.
public enum StudyDayPlanner {
    public static func plan(
        context: DayPlanContext,
        reviews: [StudyReviewWork],
        preferences: StudyDayPreferences = StudyDayPreferences()
    ) -> StudyDayPlan {
        let minute: TimeInterval = 60
        let minimum = TimeInterval(DayPlanner.minimumBlockMinutes) * minute
        var free = bufferedGaps(context: context, buffer: TimeInterval(preferences.eventBufferMinutes) * minute)
        var placed: [(block: PlanBlock, rest: TimeInterval)] = []
        var studyCount = 0

        func restAfterStudy() -> TimeInterval {
            if let every = preferences.longBreakEvery, let long = preferences.longBreakMinutes, studyCount % every == 0 {
                return TimeInterval(long) * minute
            }
            return TimeInterval(preferences.breakMinutes) * minute
        }

        /// Takes `interval` plus the rest that follows it out of `free`. The
        /// rest runs to the next five-minute mark so later blocks stay on it.
        func reserve(_ interval: DateInterval, rest: TimeInterval) {
            let taken = DateInterval(start: interval.start,
                                     end: DayPlanner.nextSlot(onOrAfter: interval.end.addingTimeInterval(rest)))
            free = free.flatMap { gap -> [DateInterval] in
                guard taken.start < gap.end, gap.start < taken.end else { return [gap] }
                var pieces: [DateInterval] = []
                if gap.start < taken.start { pieces.append(DateInterval(start: gap.start, end: taken.start)) }
                if taken.end < gap.end { pieces.append(DateInterval(start: taken.end, end: gap.end)) }
                return pieces.filter { $0.duration >= minimum }
            }
        }

        // Reviews: one block each when a gap fits it whole: the earliest
        // such gap, or the latest when reviews go last. Otherwise the
        // review is split over consecutive gaps from that end of the day,
        // so a long queue still starts early instead of waiting for the
        // one big gap at night. No piece is shorter than a block.
        let reviewRest = TimeInterval(preferences.breakMinutes) * minute
        for work in reviews {
            guard let title = PlannerDay.normalized(work.title) else { continue }
            var remaining = TimeInterval(min(max(work.minutes, DayPlanner.minimumBlockMinutes),
                                             StudyDayPreferences.maximumReviewMinutes)) * minute
            let whole = preferences.reviewsFirst
                ? free.first { $0.duration >= remaining }
                : free.last { $0.duration >= remaining }
            while remaining > 0, placed.count < DayPlanner.maximumBlocks,
                  let gap = whole ?? (preferences.reviewsFirst ? free.first : free.last) {
                let length = max(min(remaining, gap.duration), minimum)
                let interval = preferences.reviewsFirst
                    ? DateInterval(start: gap.start, duration: length)
                    : DateInterval(start: gap.end.addingTimeInterval(-length), duration: length)
                placed.append((PlanBlock(start: interval.start, end: interval.end, title: title, kind: .reviews),
                               reviewRest))
                // A late review block still needs its rest before it, not after.
                if preferences.reviewsFirst {
                    reserve(interval, rest: reviewRest)
                } else {
                    reserve(DateInterval(start: interval.start.addingTimeInterval(-reviewRest), end: interval.end),
                            rest: 0)
                }
                remaining -= length
                if whole != nil { break }
            }
        }

        // Study: exact method-length blocks, earliest first, each followed
        // by its break. Open tasks name the first blocks, in list order.
        let length = TimeInterval(preferences.studyMinutes) * minute
        var tasks = context.tasks[...]
        while placed.count < DayPlanner.maximumBlocks, let gap = free.first(where: { $0.duration >= length }) {
            let interval = DateInterval(start: gap.start, duration: length)
            let task = tasks.popFirst()
            studyCount += 1
            let rest = restAfterStudy()
            placed.append((PlanBlock(start: interval.start, end: interval.end,
                                     title: task.flatMap { PlannerDay.normalized($0.title) } ?? preferences.studyTitle,
                                     linkedTaskID: task?.id, kind: .study), rest))
            reserve(interval, rest: rest)
        }

        let ordered = placed.sorted { $0.block.start < $1.block.start }
        let busy = context.events.filter { !$0.isAllDay && $0.end > $0.start }
        let breaks = zip(ordered, ordered.dropFirst()).compactMap { pair -> DateInterval? in
            let (previous, next) = pair
            guard previous.rest > 0, next.block.start > previous.block.end else { return nil }
            let rest = DateInterval(start: previous.block.end, end: min(
                next.block.start, DayPlanner.nextSlot(onOrAfter: previous.block.end.addingTimeInterval(previous.rest))))
            let interrupted = busy.contains { $0.start < next.block.start && $0.end > previous.block.end }
            return interrupted ? nil : rest
        }
        return StudyDayPlan(blocks: ordered.map(\.block), breaks: breaks)
    }

    /// `context.gaps` with `buffer` trimmed off every edge that touches a
    /// calendar event. The edge at `now` and the one at `dayEnd` stay put.
    static func bufferedGaps(context: DayPlanContext, buffer: TimeInterval) -> [DateInterval] {
        let minimum = TimeInterval(DayPlanner.minimumBlockMinutes * 60)
        let firstSlot = DayPlanner.nextSlot(onOrAfter: context.now)
        return context.gaps.compactMap { gap in
            let start = gap.start > firstSlot ? DayPlanner.nextSlot(onOrAfter: gap.start.addingTimeInterval(buffer)) : gap.start
            let end = gap.end < context.dayEnd ? gap.end.addingTimeInterval(-buffer) : gap.end
            guard end.timeIntervalSince(start) >= minimum else { return nil }
            return DateInterval(start: start, end: end)
        }
    }
}
