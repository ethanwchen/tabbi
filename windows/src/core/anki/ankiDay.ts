import type { Instant } from "../time";

/*
 * Calendar days the way AnkiConnect reports them, plus the two wall-clock
 * conversions the Anki port needs. The core never reads the machine's zone,
 * so every conversion names an IANA zone and goes through Intl.
 */

/** Year, month (1 to 12), day, hour, minute and second of an instant in a zone. */
export interface ZonedParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
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
      year: "numeric",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
    });
    formatters.set(timeZone, cached);
  }
  return cached;
}

/** The wall-clock fields of `instant` in `timeZone`. */
export function zonedParts(instant: Instant, timeZone: string): ZonedParts {
  const parts: Record<string, number> = {};
  for (const part of formatter(timeZone).formatToParts(new Date(Math.floor(instant) * 1000))) {
    if (part.type !== "literal") parts[part.type] = Number(part.value);
  }
  const field = (key: string) => parts[key] ?? 0;
  return {
    year: field("year"),
    month: field("month"),
    day: field("day"),
    hour: field("hour") % 24,
    minute: field("minute"),
    second: field("second"),
  };
}

/**
 * The instant a wall-clock time happens in `timeZone`. A time skipped by a
 * daylight saving jump resolves forward, a repeated one to its first
 * occurrence, like Foundation's `Calendar.date(from:)`.
 */
export function instantFromZoned(
  year: number,
  month: number,
  day: number,
  hour: number,
  timeZone: string,
  minute = 0,
  second = 0,
): Instant {
  const wall = Date.UTC(year, month - 1, day, hour, minute, second) / 1000;
  const offsetAt = (instant: Instant) => {
    const p = zonedParts(instant, timeZone);
    return Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) / 1000 - Math.floor(instant);
  };
  const first = wall - offsetAt(wall);
  const refined = wall - offsetAt(first);
  const candidates = [first, refined].filter((candidate) => wall - offsetAt(candidate) === candidate);
  if (candidates.length > 0) return Math.min(...candidates);
  /* A skipped wall-clock time: move forward by the jump. */
  return Math.max(first, refined);
}

/**
 * Port of AnkiDay: a calendar day as AnkiConnect reports it ("2026-09-30"),
 * already shifted by the user's rollover hour. Plain components, so streak
 * math never crosses a time zone.
 */
export interface AnkiDay {
  readonly year: number;
  readonly month: number;
  readonly day: number;
}

export function ankiDay(year: number, month: number, day: number): AnkiDay {
  return { year, month, day };
}

/** Parses `yyyy-MM-dd`; undefined for anything else. */
export function parseAnkiDay(text: string): AnkiDay | undefined {
  const parts = text.split("-");
  if (parts.length !== 3) return undefined;
  const numbers = parts.map((part) => (/^[+-]?\d+$/.test(part) ? Number(part) : NaN));
  const [year, month, day] = numbers;
  if (year === undefined || month === undefined || day === undefined) return undefined;
  if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day)) return undefined;
  if (month < 1 || month > 12 || day < 1 || day > 31) return undefined;
  return { year, month, day };
}

/**
 * The Anki day containing `instant` in `timeZone`, after shifting back by
 * Anki's rollover hour (a review at 2am with a 4am rollover belongs to the
 * previous day).
 */
export function ankiDayAt(instant: Instant, timeZone: string, rolloverHour = 4): AnkiDay {
  const parts = zonedParts(instant - rolloverHour * 3600, timeZone);
  return { year: parts.year, month: parts.month, day: parts.day };
}

/** "2026-09-30". */
export function ankiDayText(day: AnkiDay): string {
  const pad = (value: number, width: number) => String(value).padStart(width, "0");
  return `${pad(day.year, 4)}-${pad(day.month, 2)}-${pad(day.day, 2)}`;
}

/** The day `offset` days later (negative for earlier). */
export function addingDays(day: AnkiDay, offset: number): AnkiDay {
  const moved = new Date(Date.UTC(day.year, day.month - 1, day.day) + offset * 86_400_000);
  return { year: moved.getUTCFullYear(), month: moved.getUTCMonth() + 1, day: moved.getUTCDate() };
}

export function sameAnkiDay(a: AnkiDay | undefined, b: AnkiDay | undefined): boolean {
  if (!a || !b) return a === b;
  return a.year === b.year && a.month === b.month && a.day === b.day;
}

export function compareAnkiDays(a: AnkiDay, b: AnkiDay): number {
  return a.year - b.year || a.month - b.month || a.day - b.day;
}
