import { wallTime } from "../calendar/zonedCalendar";
import type { Instant } from "../time";

/*
 * Calendar days the way AnkiConnect reports them. Wall-clock conversions go
 * through core/calendar/zonedCalendar, which names an IANA zone each time.
 */

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
  const parts = wallTime(instant - rolloverHour * 3600, timeZone);
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
