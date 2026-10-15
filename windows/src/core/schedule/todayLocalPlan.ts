import type { Instant } from "../time";
import { settingTime, startOfDay, wallTime } from "../calendar/zonedCalendar";
import { SLOT_MINUTES, dayEnd } from "../planner/dayPlan";
import type { PlannerItem } from "../planner/plannerDay";
import type { ProgressItem, ProvidedTask } from "../planner/providedWork";
import { reviewWork } from "../planner/studyDayPlan";
import type { TodayPlanSettings } from "../planner/todayPlanSettings";
import type { UpcomingEvent } from "../planner/upcomingEvent";
import {
  planScheduleDay,
  planScheduleWeek,
  reviewScheduleWork,
  scheduleWork,
  schedulePreferences,
  schedulePreferencesForMethod,
  taskScheduleWork,
  type ScheduleClock,
  type SchedulePlan,
  type SchedulePreferences,
  type ScheduleWeekPlan,
  type ScheduleWork,
} from "./schedulePlanner";

/*
 * Port of TodayLocalPlan (the TodayPlanSettings extension): Plan my day on
 * device, Today's checklist, other modules' open tasks and review goals,
 * planned by the schedule planner with the kit's buffer, review order and
 * end of day. No AI and no network.
 */

/** When a planned day starts, unless the kit's day ends earlier. */
export const WORKDAY_START_MINUTE = 9 * 60;

/**
 * The local planner's preferences for the day containing `now`: the kit's
 * study method lengths (everyday ones when it has none, or only a plain
 * timer), working hours from 9:00 until the planned day's end, and the
 * kit's event buffer and review order.
 */
export function localSchedulePreferences(settings: TodayPlanSettings, now: Instant, timeZone: string): SchedulePreferences {
  const end = wallTime(dayEnd(now, timeZone, settings.dayEndHour), timeZone);
  const endMinute = end.hour * 60 + end.minute;
  /* An early kit end hour moves the start back too, so the day never collapses. */
  const startMinute = Math.min(WORKDAY_START_MINUTE, Math.max(endMinute - 2 * 60, 0));
  const method = settings.studyMethod;
  const shared = {
    workdayStartMinute: startMinute,
    workdayEndMinute: endMinute,
    eventBufferMinutes: settings.eventBufferMinutes,
    reviewsFirst: settings.reviewsFirst,
  };
  if (method === undefined || !method.hasBreaks) return schedulePreferences(shared);
  return schedulePreferencesForMethod(method, shared);
}

/**
 * What there is to plan: review goals still due (sized at the kit's
 * seconds per card), then unfinished checklist items, then other modules'
 * open tasks with their estimates. Goals the user only aims for
 * (`waitsForStart`, like a daily focus goal) are left out.
 */
export function localWork(
  settings: TodayPlanSettings,
  tasks: readonly PlannerItem[],
  sharedTasks: readonly ProvidedTask[] = [],
  progress: readonly ProgressItem[] = [],
): ScheduleWork[] {
  const reviews: ScheduleWork[] = [];
  for (const goal of progress) {
    if (goal.waitsForStart) continue;
    const work = reviewWork(goal, settings.secondsPerCard);
    if (work !== undefined) reviews.push(reviewScheduleWork(work, `${goal.source}/${goal.id}`));
  }
  const checklist = tasks.filter((task) => !task.isDone).map((task) => taskScheduleWork(task));
  const shared = sharedTasks
    .filter((task) => !task.isDone)
    .map((task) => scheduleWork({ id: `${task.source}/${task.id}`, title: task.title, estimatedMinutes: task.estimatedMinutes }));
  return [...reviews, ...checklist, ...shared];
}

export interface LocalPlanInput {
  readonly now: Instant;
  readonly events: readonly UpcomingEvent[];
  readonly tasks: readonly PlannerItem[];
  readonly sharedTasks?: readonly ProvidedTask[];
  readonly progress?: readonly ProgressItem[];
  readonly preferences?: SchedulePreferences;
}

/** The rest of today planned around `events`, with `localSchedulePreferences` unless preferences are given. */
export function localPlan(settings: TodayPlanSettings, input: LocalPlanInput, clock: ScheduleClock): SchedulePlan {
  return planScheduleDay(
    input.now,
    input.events,
    localWork(settings, input.tasks, input.sharedTasks, input.progress),
    clock,
    input.preferences ?? localSchedulePreferences(settings, input.now, clock.timeZone),
  );
}

/**
 * Today and the `days - 1` days after it planned around `events`, with the
 * usual working hours every day (planning late doesn't stretch them).
 */
export function localWeekPlan(settings: TodayPlanSettings, input: LocalPlanInput, clock: ScheduleClock, days = 7): ScheduleWeekPlan {
  return planScheduleWeek(
    input.now,
    days,
    input.events,
    localWork(settings, input.tasks, input.sharedTasks, input.progress),
    clock,
    localSchedulePreferences(settings, startOfDay(input.now, clock.timeZone), clock.timeZone),
  );
}

/**
 * Demo mode's plan: the sample events sit around `now`, so the day is
 * planned as if it were about 9:40 (with the samples moved along) and then
 * moved back to `now`, in whole slots so blocks stay on five-minute marks.
 */
export function sampleLocalPlan(settings: TodayPlanSettings, input: LocalPlanInput, clock: ScheduleClock): SchedulePlan {
  const target = settingTime(input.now, 9, 40, 0, clock.timeZone);
  const slot = SLOT_MINUTES * 60;
  const offset = Math.floor((target - input.now) / slot) * slot;
  const morning = input.now + offset;
  const moved = input.events.map((event) => ({ ...event, start: event.start + offset, end: event.end + offset }));
  const plan = localPlan(
    settings,
    { ...input, now: morning, events: moved, preferences: localSchedulePreferences(settings, morning, clock.timeZone) },
    clock,
  );
  return {
    ...plan,
    blocks: plan.blocks.map((entry) => ({
      ...entry,
      block: { ...entry.block, start: entry.block.start - offset, end: entry.block.end - offset },
    })),
    breaks: plan.breaks.map((rest) => ({ start: rest.start - offset, end: rest.end - offset })),
  };
}
