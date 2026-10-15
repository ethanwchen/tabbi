import type { Instant } from "../time";
import { instantOf, wallTime } from "../calendar/zonedCalendar";

/**
 * Port of PlannerDayKey: a calendar day as its local `yyyy-MM-dd` string.
 *
 * The string doubles as the day file's name (checklists, reviews, the
 * activity log) and sorts chronologically, so "the most recent earlier day"
 * is a plain string comparison. It is the one day key in the core.
 */
export type PlannerDayKey = string;

interface DayFields {
  readonly year: number;
  readonly month: number;
  readonly day: number;
}

/* The fields of a well-formed key naming a real date; rejects 2026-02-30 instead of rolling it over. */
function parse(raw: string): DayFields | undefined {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (!match) return undefined;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (month < 1 || month > 12 || day < 1) return undefined;
  const last = new Date(0);
  last.setUTCFullYear(year, month, 0);
  return day <= last.getUTCDate() ? { year, month, day } : undefined;
}

function format(fields: DayFields): PlannerDayKey {
  const pad = (value: number, width: number) => String(value).padStart(width, "0");
  return `${pad(fields.year, 4)}-${pad(fields.month, 2)}-${pad(fields.day, 2)}`;
}

/** Whether `raw` is a well-formed `yyyy-MM-dd` naming a real date (`PlannerDayKey(rawValue:)`). */
export function isPlannerDayKey(raw: string): raw is PlannerDayKey {
  return parse(raw) !== undefined;
}

/** The key for `raw`, or undefined when it isn't one. */
export function plannerDayKey(raw: string): PlannerDayKey | undefined {
  return isPlannerDayKey(raw) ? raw : undefined;
}

/** The day containing `instant` on the wall clock of the IANA zone `timeZone`. */
export function plannerDayKeyOf(instant: Instant, timeZone: string): PlannerDayKey {
  const wall = wallTime(instant, timeZone);
  return format(wall);
}

/** Midnight at the start of `key` in `timeZone`. Throws for a string that isn't a key. */
export function dayKeyStart(key: PlannerDayKey, timeZone: string): Instant {
  const fields = parse(key);
  if (fields === undefined) throw new RangeError(`Invalid day ${key}`);
  return instantOf(fields, timeZone);
}

/**
 * The day `days` calendar days after `key` (before it when negative), so
 * stepping across a month end or a daylight saving change lands on the
 * right date. Throws for a string that isn't a key.
 */
export function addingDaysToKey(key: PlannerDayKey, days: number): PlannerDayKey {
  const fields = parse(key);
  if (fields === undefined) throw new RangeError(`Invalid day ${key}`);
  const date = new Date(0);
  date.setUTCFullYear(fields.year, fields.month - 1, fields.day + days);
  return format({ year: date.getUTCFullYear(), month: date.getUTCMonth() + 1, day: date.getUTCDate() });
}
