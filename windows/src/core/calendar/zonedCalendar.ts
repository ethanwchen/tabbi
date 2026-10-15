import type { Instant, Seconds } from "../time";

/*
 * Wall-clock math in a named time zone, the parts of Foundation's
 * `Calendar` that Today, the planners, the Schedule and the ICS reader
 * use. Every function takes an IANA zone name and goes through
 * `Intl.DateTimeFormat`, so the result never depends on the machine's zone.
 *
 * Local times that a daylight saving change skips resolve to the next
 * existing moment, and times it repeats to their first occurrence, as
 * Foundation's `date(bySettingHour:...)` and `date(from:)` do by default.
 */

/** The Gregorian wall-clock fields of an instant. `weekday` is 1 for Sunday through 7 for Saturday, as Foundation counts. */
export interface WallTime {
  readonly year: number;
  readonly month: number;
  readonly day: number;
  readonly hour: number;
  readonly minute: number;
  readonly second: number;
  readonly weekday: number;
}

/** Fields that name a local time; out-of-range values roll over (month 13 is January of the next year). */
export interface LocalTime {
  readonly year: number;
  readonly month: number;
  readonly day: number;
  readonly hour?: number;
  readonly minute?: number;
  readonly second?: number;
}

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatter(timeZone: string): Intl.DateTimeFormat {
  let cached = formatters.get(timeZone);
  if (!cached) {
    cached = new Intl.DateTimeFormat("en-US", {
      timeZone,
      calendar: "gregory",
      numberingSystem: "latn",
      hourCycle: "h23",
      era: "short",
      year: "numeric",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
      weekday: "short",
    });
    formatters.set(timeZone, cached);
  }
  return cached;
}

const WEEKDAYS: Readonly<Record<string, number>> = { Sun: 1, Mon: 2, Tue: 3, Wed: 4, Thu: 5, Fri: 6, Sat: 7 };

/** Whether `timeZone` is a zone name this runtime knows. */
export function isKnownTimeZone(timeZone: string): boolean {
  if (timeZone.trim() === "") return false;
  try {
    formatter(timeZone);
    return true;
  } catch {
    return false;
  }
}

/** The wall-clock fields of `instant` in `timeZone`. */
export function wallTime(instant: Instant, timeZone: string): WallTime {
  const whole = Math.floor(instant);
  const fields: Record<string, string> = {};
  for (const part of formatter(timeZone).formatToParts(new Date(whole * 1000))) {
    if (part.type !== "literal") fields[part.type] = part.value;
  }
  const number = (key: string) => Number(fields[key] ?? "0");
  const era = fields.era ?? "AD";
  const year = era === "BC" || era === "B" ? 1 - number("year") : number("year");
  return {
    year,
    month: number("month"),
    day: number("day"),
    hour: number("hour") % 24,
    minute: number("minute"),
    second: number("second"),
    weekday: WEEKDAYS[fields.weekday ?? "Sun"] ?? 1,
  };
}

/* Seconds since 1970 of a wall time read as if it were UTC. */
function wallSeconds(time: LocalTime): number {
  const date = new Date(0);
  date.setUTCFullYear(time.year, time.month - 1, time.day);
  date.setUTCHours(time.hour ?? 0, time.minute ?? 0, 0, 0);
  return date.getTime() / 1000 + (time.second ?? 0);
}

/** How far `timeZone`'s wall clock is ahead of UTC at `instant`, in seconds. */
export function utcOffset(instant: Instant, timeZone: string): Seconds {
  const whole = Math.floor(instant);
  const wall = wallTime(whole, timeZone);
  return wallSeconds(wall) - whole;
}

/**
 * The instant `time` happens in `timeZone`. A time a daylight saving jump
 * skips becomes the first moment after the jump; a repeated time is its
 * first occurrence. Fractional seconds are kept.
 */
export function instantOf(time: LocalTime, timeZone: string): Instant {
  const local = wallSeconds(time);
  const whole = Math.floor(local);
  const fraction = local - whole;
  const before = utcOffset(whole - 86_400, timeZone);
  const after = utcOffset(whole + 86_400, timeZone);
  const candidates = [...new Set([before, after])]
    .map((offset) => whole - offset)
    .filter((candidate) => utcOffset(candidate, timeZone) === whole - candidate);
  if (candidates.length > 0) return Math.min(...candidates) + fraction;
  /* Skipped: search for the jump between the two readings of the time. */
  let low = Math.min(whole - before, whole - after);
  let high = Math.max(whole - before, whole - after);
  const lowOffset = utcOffset(low, timeZone);
  while (high - low > 1) {
    const middle = Math.floor((low + high) / 2);
    if (utcOffset(middle, timeZone) === lowOffset) low = middle;
    else high = middle;
  }
  return high;
}

/** Midnight at the start of the day containing `instant` (the first moment of that day when midnight is skipped). */
export function startOfDay(instant: Instant, timeZone: string): Instant {
  const wall = wallTime(instant, timeZone);
  return instantOf({ year: wall.year, month: wall.month, day: wall.day }, timeZone);
}

/** `hour:minute:second` on the day containing `day`, like `Calendar.date(bySettingHour:minute:second:of:)`. */
export function settingTime(day: Instant, hour: number, minute: number, second: number, timeZone: string): Instant {
  const wall = wallTime(day, timeZone);
  return instantOf({ year: wall.year, month: wall.month, day: wall.day, hour, minute, second }, timeZone);
}

/** `days` calendar days after `instant` at the same wall-clock time (before it when negative). */
export function addingDays(instant: Instant, days: number, timeZone: string): Instant {
  const wall = wallTime(instant, timeZone);
  const fraction = instant - Math.floor(instant);
  return (
    instantOf(
      { year: wall.year, month: wall.month, day: wall.day + days, hour: wall.hour, minute: wall.minute, second: wall.second },
      timeZone,
    ) + fraction
  );
}

/** The start of the clock hour containing `instant`. */
export function startOfHour(instant: Instant, timeZone: string): Instant {
  const wall = wallTime(instant, timeZone);
  return Math.floor(instant) - wall.minute * 60 - wall.second;
}

/** Minutes after midnight on the wall clock (hours and minutes only). */
export function minuteOfDay(instant: Instant, timeZone: string): number {
  const wall = wallTime(instant, timeZone);
  return wall.hour * 60 + wall.minute;
}

/** Whether `instant` falls on a Saturday or Sunday in `timeZone`. */
export function isWeekend(instant: Instant, timeZone: string): boolean {
  const weekday = wallTime(instant, timeZone).weekday;
  return weekday === 1 || weekday === 7;
}

/** `HH:mm` on a 24-hour clock with Latin digits, the way the planner's prompts write times. */
export function clockText(instant: Instant, timeZone: string): string {
  const wall = wallTime(instant, timeZone);
  return `${String(wall.hour).padStart(2, "0")}:${String(wall.minute).padStart(2, "0")}`;
}

/** Days in `month` of `year` (1 to 12). */
export function daysInMonth(year: number, month: number): number {
  const date = new Date(0);
  date.setUTCFullYear(year, month, 0);
  return date.getUTCDate();
}
