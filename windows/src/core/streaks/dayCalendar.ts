import { instantOf, wallTime } from "../calendar/zonedCalendar";
import type { PlannerDayKey } from "../planner/plannerDayKey";
import type { Instant } from "../time";

/*
 * The calendar days streaks, reminders, the heatmap and the pet's night are
 * counted in: local days in a named IANA time zone, with a first weekday,
 * like the Mac's `Calendar`. Days are PlannerDayKeys, and every wall-clock
 * conversion goes through core/calendar/zonedCalendar, the one zoned
 * implementation; the machine's own zone is never read.
 */

/** A calendar for day math: the IANA zone and the first day of the week (1 is Sunday, 2 is Monday). */
export interface DayCalendar {
  readonly timeZone: string;
  readonly firstWeekday: number;
}

/** A local calendar day as `yyyy-MM-dd`, which sorts in date order: the planner's day key. */
export type DayKey = PlannerDayKey;

interface Civil {
  readonly year: number;
  readonly month: number;
  readonly day: number;
}

function civil(key: DayKey): Civil {
  const [year, month, day] = key.split("-").map(Number);
  return { year: year ?? 1970, month: month ?? 1, day: day ?? 1 };
}

function keyOf(value: Civil): DayKey {
  const pad = (n: number, width: number) => String(n).padStart(width, "0");
  return `${pad(value.year, 4)}-${pad(value.month, 2)}-${pad(value.day, 2)}`;
}

/** The day containing `instant` in the calendar's zone. */
export function dayKey(instant: Instant, calendar: DayCalendar): DayKey {
  const wall = wallTime(instant, calendar.timeZone);
  return keyOf(wall);
}

/** Accepts only well-formed `yyyy-MM-dd` strings that name a real date. */
export function parseDayKey(raw: string): DayKey | undefined {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return undefined;
  const { year, month, day } = civil(raw);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return undefined;
  return raw;
}

/** Midnight at the start of `key` in the calendar's zone. */
export function startOfDay(key: DayKey, calendar: DayCalendar): Instant {
  const { year, month, day } = civil(key);
  return instantOf({ year, month, day }, calendar.timeZone);
}

/** The start of the day containing `instant`. */
export function startOfDayAt(instant: Instant, calendar: DayCalendar): Instant {
  return startOfDay(dayKey(instant, calendar), calendar);
}

/** The day `days` calendar days after `key` (before it when negative). */
export function addDays(key: DayKey, days: number): DayKey {
  const { year, month, day } = civil(key);
  const date = new Date(Date.UTC(year, month - 1, day + days));
  return keyOf({ year: date.getUTCFullYear(), month: date.getUTCMonth() + 1, day: date.getUTCDate() });
}

/** Whole calendar days from `from` to `to`. */
export function daysBetween(from: DayKey, to: DayKey): number {
  const a = civil(from);
  const b = civil(to);
  return Math.round((Date.UTC(b.year, b.month - 1, b.day) - Date.UTC(a.year, a.month - 1, a.day)) / 86400000);
}

/** The weekday of `key`, 1 for Sunday through 7 for Saturday, as Foundation counts. */
export function weekday(key: DayKey): number {
  const { year, month, day } = civil(key);
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay() + 1;
}

/** The first day of the week holding `key`, by the calendar's first weekday. */
export function weekStart(key: DayKey, calendar: DayCalendar): DayKey {
  const back = (weekday(key) - calendar.firstWeekday + 7) % 7;
  return addDays(key, -back);
}

/** The local hour of `instant` (0 to 23). */
export function hourOf(instant: Instant, timeZone: string): number {
  return wallTime(instant, timeZone).hour;
}

/**
 * The first moment strictly after `instant` whose wall clock reads
 * `hour:minute:00`, moving a skipped time to the end of its gap.
 */
export function nextDateMatching(instant: Instant, hour: number, minute: number, calendar: DayCalendar): Instant {
  let key = addDays(dayKey(instant, calendar), -1);
  for (let i = 0; i < 4; i++) {
    const { year, month, day } = civil(key);
    const candidate = instantOf({ year, month, day, hour, minute }, calendar.timeZone);
    if (candidate > instant) return candidate;
    key = addDays(key, 1);
  }
  return instant + 86400;
}
