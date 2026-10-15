import type { Instant } from "../time";

/*
 * The calendar days streaks, reminders, the heatmap and the pet's night are
 * counted in: local days in a named IANA time zone, with a first weekday,
 * like the Mac's `Calendar` and `PlannerDayKey`. Wall-clock math goes
 * through `Intl.DateTimeFormat`; the machine's own zone is never read.
 *
 * A narrow local stand-in for the planner's day key and the shared calendar
 * helpers, which other ports own; the shapes match the Mac so they can be
 * swapped for the shared ones without changing callers.
 */

/** A calendar for day math: the IANA zone and the first day of the week (1 is Sunday, 2 is Monday). */
export interface DayCalendar {
  readonly timeZone: string;
  readonly firstWeekday: number;
}

/** A local calendar day as `yyyy-MM-dd`, which sorts in date order. Port of PlannerDayKey's raw value. */
export type DayKey = string;

interface Civil {
  readonly year: number;
  readonly month: number;
  readonly day: number;
}

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatter(timeZone: string): Intl.DateTimeFormat {
  let format = formatters.get(timeZone);
  if (!format) {
    format = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
    });
    formatters.set(timeZone, format);
  }
  return format;
}

/** The wall-clock fields of `instant` in `timeZone`. */
export function wallClock(
  instant: Instant,
  timeZone: string,
): { year: number; month: number; day: number; hour: number; minute: number; second: number } {
  const parts = formatter(timeZone).formatToParts(new Date(Math.floor(instant) * 1000));
  const field = (type: Intl.DateTimeFormatPartTypes) => Number(parts.find((part) => part.type === type)?.value ?? 0);
  return {
    year: field("year"),
    month: field("month"),
    day: field("day"),
    hour: field("hour"),
    minute: field("minute"),
    second: field("second"),
  };
}

/** Seconds the zone's wall clock is ahead of UTC at `instant`. */
function offset(instant: Instant, timeZone: string): number {
  const wall = wallClock(instant, timeZone);
  const asUTC = Date.UTC(wall.year, wall.month - 1, wall.day, wall.hour, wall.minute, wall.second) / 1000;
  return asUTC - Math.floor(instant);
}

/**
 * The instant a local wall-clock time names in `timeZone`. A time that a
 * daylight saving change skips moves to the next moment that exists (the
 * end of the gap), and a time that happens twice is its first occurrence,
 * as Foundation's `.nextTime` policy does.
 */
export function zonedInstant(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  second: number,
  timeZone: string,
): Instant {
  const target = Date.UTC(year, month - 1, day, hour, minute, second) / 1000;
  const before = offset(target - 86400, timeZone);
  const after = offset(target + 86400, timeZone);
  const candidates = [target - before, target - after].sort((a, b) => a - b);
  for (const candidate of candidates) {
    if (target - offset(candidate, timeZone) === candidate) return candidate;
  }
  /* In a gap: the wall clock jumps over the target, so the next valid moment is the jump itself. */
  let low = Math.min(...candidates);
  let high = Math.max(...candidates);
  const wallAt = (instant: Instant) => instant + offset(instant, timeZone);
  while (high - low > 1) {
    const mid = Math.floor((low + high) / 2);
    if (wallAt(mid) >= target) high = mid;
    else low = mid;
  }
  return high;
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
  const wall = wallClock(instant, calendar.timeZone);
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
  return zonedInstant(year, month, day, 0, 0, 0, calendar.timeZone);
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
  return wallClock(instant, timeZone).hour;
}

/**
 * The first moment strictly after `instant` whose wall clock reads
 * `hour:minute:00`, moving a skipped time to the end of its gap.
 */
export function nextDateMatching(instant: Instant, hour: number, minute: number, calendar: DayCalendar): Instant {
  let key = addDays(dayKey(instant, calendar), -1);
  for (let i = 0; i < 4; i++) {
    const { year, month, day } = civil(key);
    const candidate = zonedInstant(year, month, day, hour, minute, 0, calendar.timeZone);
    if (candidate > instant) return candidate;
    key = addDays(key, 1);
  }
  return instant + 86400;
}
