import Foundation

/// Plan My Day on device: Today's checklist, other modules' open tasks and
/// review goals, planned by `SchedulePlanner` with the kit's buffer, review
/// order and end of day. No Claude and no network.
public extension TodayPlanSettings {
    /// When a planned day starts, unless the kit's day ends earlier.
    static let workdayStartMinute = 9 * 60

    /// The local planner's preferences for the day containing `now`:
    /// everyday block and break lengths, working hours from 9:00 until
    /// `DayPlanner.dayEnd` (so planning late still leaves a couple of
    /// hours), and the kit's event buffer and review order.
    func schedulePreferences(now: Date, calendar: Calendar = .current) -> SchedulePreferences {
        let end = DayPlanner.dayEnd(now: now, calendar: calendar, endHour: dayEndHour)
        let parts = calendar.dateComponents([.hour, .minute], from: end)
        let endMinute = (parts.hour ?? dayEndHour) * 60 + (parts.minute ?? 0)
        // An early kit end hour moves the start back too, so the day never collapses.
        let startMinute = min(Self.workdayStartMinute, max(endMinute - 2 * 60, 0))
        return SchedulePreferences(workdayStartMinute: startMinute, workdayEndMinute: endMinute,
                                   eventBufferMinutes: eventBufferMinutes, reviewsFirst: reviewsFirst)
    }

    /// What there is to plan: review goals still due (sized at
    /// `secondsPerCard` per unit), then unfinished checklist items, then
    /// other modules' open tasks with their estimates. Goals the user only
    /// aims for (`waitsForStart`, like a daily focus goal) aren't work to
    /// schedule and are left out.
    func localWork(tasks: [PlannerItem], sharedTasks: [ProvidedTask] = [],
                   progress: [ProgressItem] = []) -> [ScheduleWork] {
        let reviews = progress.filter { !$0.waitsForStart }.compactMap { goal in
            goal.reviewWork(secondsPerUnit: secondsPerCard)
                .map { ScheduleWork(reviews: $0, id: "\(goal.source.rawValue)/\(goal.id)") }
        }
        let checklist = tasks.filter { !$0.isDone }.map { ScheduleWork(task: $0) }
        let shared = sharedTasks.filter { !$0.isDone }.map {
            ScheduleWork(id: "\($0.source.rawValue)/\($0.id)", title: $0.title, estimatedMinutes: $0.estimatedMinutes)
        }
        return reviews + checklist + shared
    }

    /// The rest of today planned around `events`, with
    /// `schedulePreferences(now:calendar:)` unless `preferences` is given.
    func localPlan(now: Date, events: [UpcomingEvent], tasks: [PlannerItem], sharedTasks: [ProvidedTask] = [],
                   progress: [ProgressItem] = [], preferences: SchedulePreferences? = nil,
                   calendar: Calendar = .current, locale: Locale = .current) -> SchedulePlan {
        SchedulePlanner.planDay(now: now, events: events,
                                work: localWork(tasks: tasks, sharedTasks: sharedTasks, progress: progress),
                                preferences: preferences ?? schedulePreferences(now: now, calendar: calendar),
                                calendar: calendar, locale: locale)
    }

    /// Today and the `days - 1` days after it planned around `events`:
    /// unfinished work spread over each day's free time in turn, with the
    /// usual working hours every day (planning late doesn't stretch them).
    func localWeekPlan(now: Date, days: Int = 7, events: [UpcomingEvent], tasks: [PlannerItem],
                       sharedTasks: [ProvidedTask] = [], progress: [ProgressItem] = [],
                       calendar: Calendar = .current, locale: Locale = .current) -> ScheduleWeekPlan {
        SchedulePlanner.planWeek(now: now, days: days, events: events,
                                 work: localWork(tasks: tasks, sharedTasks: sharedTasks, progress: progress),
                                 preferences: schedulePreferences(now: calendar.startOfDay(for: now), calendar: calendar),
                                 calendar: calendar, locale: locale)
    }

    /// Demo mode's plan: `events` are samples placed around `now`, so the
    /// day is planned as if it were 9:40 am (with the samples moved along)
    /// and then moved back to `now`. A snapshot taken in the evening still
    /// shows a full, realistic day around the sample calendar.
    func sampleLocalPlan(now: Date, events: [UpcomingEvent], tasks: [PlannerItem],
                         sharedTasks: [ProvidedTask] = [], progress: [ProgressItem] = [],
                         calendar: Calendar = .current, locale: Locale = .current) -> SchedulePlan {
        let morning = calendar.date(bySettingHour: 9, minute: 40, second: 0, of: now) ?? now
        let offset = morning.timeIntervalSince(now)
        let moved = events.map { event in
            var event = event
            event.start += offset
            event.end += offset
            return event
        }
        var plan = localPlan(now: morning, events: moved, tasks: tasks, sharedTasks: sharedTasks,
                             progress: progress, preferences: schedulePreferences(now: morning, calendar: calendar),
                             calendar: calendar, locale: locale)
        for index in plan.blocks.indices {
            plan.blocks[index].block.start -= offset
            plan.blocks[index].block.end -= offset
        }
        plan.breaks = plan.breaks.map { DateInterval(start: $0.start - offset, end: $0.end - offset) }
        return plan
    }
}
