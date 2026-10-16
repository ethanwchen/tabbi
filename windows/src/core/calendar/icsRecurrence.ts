import { wallFromSeconds, wallSeconds, type IcsDate, type IcsDateValue, type IcsWall } from "./icsTime";
import { parseDateValue } from "./icsTime";

/*
 * RRULE expansion (RFC 5545 section 3.3.10) on local wall-clock times: the
 * rule runs on the event's own calendar, and the caller turns each local
 * start into an instant in the event's zone, so a weekly 9:00 meeting stays
 * at 9:00 across a daylight saving change.
 *
 * Covered: FREQ DAILY, WEEKLY, MONTHLY and YEARLY with INTERVAL, COUNT,
 * UNTIL, BYDAY (with ordinals such as 2MO and -1FR), BYMONTHDAY (negative
 * counts from the month's end), BYMONTH, BYSETPOS and WKST. Rules with
 * finer frequencies (HOURLY and below) are read as DAILY.
 */

export type RecurrenceFrequency = "DAILY" | "WEEKLY" | "MONTHLY" | "YEARLY";

/** A BYDAY entry: a weekday (1 Sunday ... 7 Saturday) and an optional ordinal (2MO is 2, -1FR is -1). */
export interface RecurrenceDay {
  readonly weekday: number;
  readonly ordinal?: number;
}

export interface RecurrenceRule {
  readonly frequency: RecurrenceFrequency;
  readonly interval: number;
  readonly count?: number;
  readonly until?: IcsDateValue;
  readonly byDay: readonly RecurrenceDay[];
  readonly byMonthDay: readonly number[];
  readonly byMonth: readonly number[];
  readonly bySetPos: readonly number[];
  /** First day of the week, 1 Sunday ... 7 Saturday; Monday by default. */
  readonly weekStart: number;
}

const WEEKDAYS: Readonly<Record<string, number>> = { SU: 1, MO: 2, TU: 3, WE: 4, TH: 5, FR: 6, SA: 7 };

function numbers(text: string | undefined, valid: (value: number) => boolean): number[] {
  if (text === undefined) return [];
  return text
    .split(",")
    .map((piece) => Number(piece.trim()))
    .filter((value) => Number.isInteger(value) && valid(value));
}

/** Reads an RRULE value, or undefined when it has no usable FREQ. */
export function parseRecurrenceRule(text: string): RecurrenceRule | undefined {
  const parts = new Map<string, string>();
  for (const piece of text.trim().replace(/^RRULE:/i, "").split(";")) {
    const separator = piece.indexOf("=");
    if (separator > 0) parts.set(piece.slice(0, separator).trim().toUpperCase(), piece.slice(separator + 1).trim());
  }
  const rawFrequency = parts.get("FREQ")?.toUpperCase();
  const frequency: RecurrenceFrequency | undefined =
    rawFrequency === "DAILY" || rawFrequency === "WEEKLY" || rawFrequency === "MONTHLY" || rawFrequency === "YEARLY"
      ? rawFrequency
      : rawFrequency === "HOURLY" || rawFrequency === "MINUTELY" || rawFrequency === "SECONDLY"
        ? "DAILY"
        : undefined;
  if (frequency === undefined) return undefined;
  const interval = Number(parts.get("INTERVAL") ?? "1");
  const count = parts.has("COUNT") ? Number(parts.get("COUNT")) : undefined;
  const untilText = parts.get("UNTIL");
  const until = untilText === undefined ? undefined : parseDateValue(untilText);
  const byDay: RecurrenceDay[] = [];
  for (const piece of (parts.get("BYDAY") ?? "").split(",")) {
    const match = /^([+-]?\d{1,2})?(SU|MO|TU|WE|TH|FR|SA)$/i.exec(piece.trim());
    if (!match) continue;
    const weekday = WEEKDAYS[(match[2] ?? "").toUpperCase()];
    if (weekday === undefined) continue;
    const ordinal = match[1] === undefined ? undefined : Number(match[1]);
    byDay.push(ordinal === undefined || ordinal === 0 ? { weekday } : { weekday, ordinal });
  }
  const rule: { -readonly [Key in keyof RecurrenceRule]: RecurrenceRule[Key] } = {
    frequency,
    interval: Number.isInteger(interval) && interval > 0 ? Math.min(interval, 10_000) : 1,
    byDay,
    byMonthDay: numbers(parts.get("BYMONTHDAY"), (value) => value !== 0 && Math.abs(value) <= 31),
    byMonth: numbers(parts.get("BYMONTH"), (value) => value >= 1 && value <= 12),
    bySetPos: numbers(parts.get("BYSETPOS"), (value) => value !== 0 && Math.abs(value) <= 366),
    weekStart: WEEKDAYS[(parts.get("WKST") ?? "MO").toUpperCase()] ?? 2,
  };
  if (count !== undefined && Number.isInteger(count) && count > 0) rule.count = count;
  if (until !== undefined) rule.until = until;
  return rule;
}

const DAY = 86_400;

function weekdayOf(date: IcsDate): number {
  return new Date(wallSeconds(date) * 1000).getUTCDay() + 1;
}

function monthLength(year: number, month: number): number {
  const date = new Date(0);
  date.setUTCFullYear(year, month, 0);
  return date.getUTCDate();
}

/* Moves a month count from (year, month) by `months`. */
function addMonths(year: number, month: number, months: number): { year: number; month: number } {
  const index = year * 12 + (month - 1) + months;
  return { year: Math.floor(index / 12), month: (index % 12) + 1 };
}

/* The days of a month a MONTHLY (or YEARLY with BYMONTH) period offers. */
function monthDays(rule: RecurrenceRule, year: number, month: number, defaultDay: number): IcsDate[] {
  const length = monthLength(year, month);
  if (rule.byMonthDay.length > 0) {
    const days = rule.byMonthDay
      .map((day) => (day > 0 ? day : length + day + 1))
      .filter((day) => day >= 1 && day <= length)
      .map((day) => ({ year, month, day }));
    return rule.byDay.length > 0 ? days.filter((date) => rule.byDay.some((entry) => entry.weekday === weekdayOf(date))) : days;
  }
  if (rule.byDay.length > 0) {
    const result: IcsDate[] = [];
    for (const entry of rule.byDay) {
      const matching: number[] = [];
      for (let day = 1; day <= length; day++) if (weekdayOf({ year, month, day }) === entry.weekday) matching.push(day);
      if (entry.ordinal === undefined) result.push(...matching.map((day) => ({ year, month, day })));
      else {
        const day = entry.ordinal > 0 ? matching[entry.ordinal - 1] : matching[matching.length + entry.ordinal];
        if (day !== undefined) result.push({ year, month, day });
      }
    }
    return result;
  }
  return defaultDay <= length ? [{ year, month, day: defaultDay }] : [];
}

/* The candidate dates of period `index`, before BYSETPOS. */
function periodDates(rule: RecurrenceRule, start: IcsWall, index: number): IcsDate[] {
  const step = index * rule.interval;
  switch (rule.frequency) {
    case "DAILY": {
      const date = wallFromSeconds(wallSeconds({ year: start.year, month: start.month, day: start.day }) + step * DAY);
      const ok =
        (rule.byMonth.length === 0 || rule.byMonth.includes(date.month)) &&
        (rule.byMonthDay.length === 0 ||
          rule.byMonthDay.some((day) => (day > 0 ? day : monthLength(date.year, date.month) + day + 1) === date.day)) &&
        (rule.byDay.length === 0 || rule.byDay.some((entry) => entry.weekday === weekdayOf(date)));
      return ok ? [date] : [];
    }
    case "WEEKLY": {
      const startDay = wallSeconds({ year: start.year, month: start.month, day: start.day });
      const offset = (weekdayOf(start) - rule.weekStart + 7) % 7;
      const weekBegin = startDay - offset * DAY + step * 7 * DAY;
      const weekdays = rule.byDay.length > 0 ? rule.byDay.map((entry) => entry.weekday) : [weekdayOf(start)];
      const dates: IcsDate[] = [];
      for (let day = 0; day < 7; day++) {
        const date = wallFromSeconds(weekBegin + day * DAY);
        if (weekdays.includes(weekdayOf(date)) && (rule.byMonth.length === 0 || rule.byMonth.includes(date.month))) {
          dates.push(date);
        }
      }
      return dates;
    }
    case "MONTHLY": {
      const { year, month } = addMonths(start.year, start.month, step);
      if (rule.byMonth.length > 0 && !rule.byMonth.includes(month)) return [];
      return monthDays(rule, year, month, start.day);
    }
    case "YEARLY": {
      const year = start.year + step;
      if (rule.byMonth.length > 0) return rule.byMonth.flatMap((month) => monthDays(rule, year, month, start.day));
      if (rule.byMonthDay.length > 0) {
        return Array.from({ length: 12 }, (_unused, index) => index + 1).flatMap((month) =>
          monthDays({ ...rule, byDay: rule.byDay }, year, month, start.day),
        );
      }
      if (rule.byDay.length > 0) {
        const result: IcsDate[] = [];
        const days = Math.round((wallSeconds({ year: year + 1, month: 1, day: 1 }) - wallSeconds({ year, month: 1, day: 1 })) / DAY);
        for (const entry of rule.byDay) {
          const matching: IcsDate[] = [];
          for (let day = 0; day < days; day++) {
            const date = wallFromSeconds(wallSeconds({ year, month: 1, day: 1 }) + day * DAY);
            if (weekdayOf(date) === entry.weekday) matching.push(date);
          }
          if (entry.ordinal === undefined) result.push(...matching);
          else {
            const date = entry.ordinal > 0 ? matching[entry.ordinal - 1] : matching[matching.length + entry.ordinal];
            if (date !== undefined) result.push(date);
          }
        }
        return result;
      }
      return start.day <= monthLength(year, start.month) ? [{ year, month: start.month, day: start.day }] : [];
    }
  }
}

/* How many whole periods lie between the start and `wall`, for skipping ahead. */
function periodsBefore(rule: RecurrenceRule, start: IcsWall, wall: IcsWall): number {
  const days = (wallSeconds({ year: wall.year, month: wall.month, day: wall.day }) - wallSeconds({ year: start.year, month: start.month, day: start.day })) / DAY;
  const units =
    rule.frequency === "DAILY"
      ? days
      : rule.frequency === "WEEKLY"
        ? days / 7
        : rule.frequency === "MONTHLY"
          ? (wall.year - start.year) * 12 + (wall.month - start.month)
          : wall.year - start.year;
  return Math.max(Math.floor(units / rule.interval) - 1, 0);
}

export interface ExpansionLimits {
  /** Local starts before this (wall seconds) are not returned. */
  readonly from: number;
  /** Expansion stops after this local start (wall seconds). */
  readonly to: number;
  /** Whether a local start is still within UNTIL (the caller knows the event's zone). */
  readonly withinUntil: (wall: IcsWall) => boolean;
  /** Most starts returned. */
  readonly maxInstances: number;
  /** Most periods looked at, so a rule that never matches still ends. */
  readonly maxPeriods: number;
}

/** Local starts of every occurrence of `rule` from `start` (itself included) within `limits`, in order. */
export function expandRecurrence(rule: RecurrenceRule, start: IcsWall, limits: ExpansionLimits): IcsWall[] {
  const startSeconds = wallSeconds(start);
  const time = start.hour * 3600 + start.minute * 60 + start.second;
  const result: IcsWall[] = [];
  let produced = 0;
  const take = (seconds: number): boolean => {
    const wall = wallFromSeconds(seconds);
    if (!limits.withinUntil(wall)) return false;
    produced++;
    if (rule.count !== undefined && produced > rule.count) return false;
    if (seconds > limits.to) return false;
    if (seconds >= limits.from) result.push(wall);
    return result.length < limits.maxInstances;
  };
  if (!take(startSeconds)) return result;
  const first = rule.count === undefined && limits.from > startSeconds ? periodsBefore(rule, start, wallFromSeconds(limits.from)) : 0;
  for (let index = first, looked = 0; looked < limits.maxPeriods; index++, looked++) {
    let dates = periodDates(rule, start, index)
      .map((date) => wallSeconds(date) + time)
      .sort((a, b) => a - b);
    dates = dates.filter((seconds, position) => dates.indexOf(seconds) === position);
    if (rule.bySetPos.length > 0) {
      const picked = rule.bySetPos
        .map((position) => (position > 0 ? dates[position - 1] : dates[dates.length + position]))
        .filter((seconds): seconds is number => seconds !== undefined);
      dates = [...new Set(picked)].sort((a, b) => a - b);
    }
    for (const seconds of dates) {
      if (seconds <= startSeconds) continue;
      if (!take(seconds)) return result;
    }
    /* Past the window: every later period starts later still. */
    const periodStart = periodDates({ ...rule, byDay: [], byMonthDay: [], byMonth: [], bySetPos: [] }, start, index)[0];
    if (periodStart !== undefined && wallSeconds(periodStart) > limits.to + 7 * DAY) return result;
  }
  return result;
}
