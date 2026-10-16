import { settingTime } from "../calendar/zonedCalendar";
import { addingDaysToKey, dayKeyStart, isPlannerDayKey, plannerDayKeyOf, type PlannerDayKey } from "../planner/plannerDayKey";
import { weekday } from "../streaks/dayCalendar";
import type { Instant } from "../time";

/*
 * Port of RecapWeek: a Monday-through-Sunday week, identified by its Monday.
 *
 * The recap is ready on Sunday evening, so the week always ends on a Sunday
 * whatever the calendar's first weekday is; only the time zone matters, and
 * it is passed in as an IANA name. A week is its Monday's day key, so weeks
 * compare and sort as strings and encode as the Mac's single string value.
 */
export type RecapWeek = PlannerDayKey;

/** Sunday evening, 6 pm: late enough to count the weekend, early enough to see the recap before the new week starts. */
export const RECAP_READY_HOUR = 18;

/** The week that contains `instant` in `timeZone`. */
export function recapWeekContaining(instant: Instant, timeZone: string): RecapWeek {
  const day = plannerDayKeyOf(instant, timeZone);
  /* `weekday` is 1 for Sunday through 7 for Saturday; Monday is 0 days back. */
  return addingDaysToKey(day, -((weekday(day) + 5) % 7));
}

/** The week starting on `monday`; undefined when that is not a day key or not a Monday. */
export function recapWeekStarting(monday: string): RecapWeek | undefined {
  return isPlannerDayKey(monday) && weekday(monday) === 2 ? monday : undefined;
}

/** The Sunday the week ends on. */
export function recapWeekEnd(week: RecapWeek): PlannerDayKey {
  return addingDaysToKey(week, 6);
}

/** The seven days, Monday first. */
export function recapWeekDays(week: RecapWeek): PlannerDayKey[] {
  return Array.from({ length: 7 }, (_, offset) => addingDaysToKey(week, offset));
}

/** The week `weeks` weeks later (earlier when negative). */
export function addingWeeks(week: RecapWeek, weeks: number): RecapWeek {
  return addingDaysToKey(week, 7 * weeks);
}

/**
 * When the week's recap is ready: `readyHour` o'clock on its Sunday. A
 * wall-clock time, so a daylight saving change that Sunday still lands on
 * `readyHour` o'clock rather than an hour off.
 */
export function recapReadyDate(week: RecapWeek, timeZone: string, readyHour = RECAP_READY_HOUR): Instant {
  const sunday = dayKeyStart(recapWeekEnd(week), timeZone);
  return settingTime(sunday, readyHour, 0, 0, timeZone);
}

/** The most recent week whose recap is ready at `now`: this week from Sunday at `readyHour` on, otherwise last week. */
export function latestReadyWeek(now: Instant, timeZone: string, readyHour = RECAP_READY_HOUR): RecapWeek {
  const current = recapWeekContaining(now, timeZone);
  return now >= recapReadyDate(current, timeZone, readyHour) ? current : addingWeeks(current, -1);
}
