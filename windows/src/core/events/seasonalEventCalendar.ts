import { wallTime } from "../calendar/zonedCalendar";
import type { DayKey } from "../streaks/dayCalendar";
import type { Instant } from "../time";

/*
 * Port of SeasonalEventCalendar and SeasonalEventDay: the calendar an
 * event's dates are written in, and a month and day in it. Lunar New Year
 * moves on the Gregorian calendar every year but sits on the first day of
 * the first month of the Chinese calendar, so its dates are written there.
 *
 * Everything here works on local days (`yyyy-MM-dd` day keys): an event
 * starts at local midnight wherever the user is, so the zone only decides
 * which day an instant falls on, and the Chinese date of a day is the same
 * in every zone (it is reckoned in China's time, as Foundation does).
 *
 * The Chinese calendar comes from Intl (ICU), except for the start of each
 * year: ICU versions disagree with the official dates when the new moon
 * falls minutes from midnight in Beijing (ICU 76 puts 2027 on February 7
 * and 2030 on February 2; the Hong Kong Observatory says February 6 and 3,
 * and the Mac's tests pin 2027 on February 6). Lunar New Year is the only Chinese date the
 * bundled events use, so its days come from a table of the official dates,
 * and the rest of the year from Intl.
 */

/** The first day of the first Chinese month, by the Gregorian year it falls in (Hong Kong Observatory). */
const LUNAR_NEW_YEAR: Readonly<Record<number, string>> = {
  2020: "01-25", 2021: "02-12", 2022: "02-01", 2023: "01-22", 2024: "02-10", 2025: "01-29", 2026: "02-17",
  2027: "02-06", 2028: "01-26", 2029: "02-13", 2030: "02-03", 2031: "01-23", 2032: "02-11", 2033: "01-31",
  2034: "02-19", 2035: "02-08", 2036: "01-28", 2037: "02-15", 2038: "02-04", 2039: "01-24", 2040: "02-12",
  2041: "02-01", 2042: "01-22", 2043: "02-10", 2044: "01-30", 2045: "02-17", 2046: "02-06", 2047: "01-26",
  2048: "02-14", 2049: "02-02", 2050: "01-23",
};

function lunarNewYear(year: number): DayKey | undefined {
  const day = LUNAR_NEW_YEAR[year];
  return day === undefined ? undefined : `${year}-${day}`;
}

export const SEASONAL_EVENT_CALENDARS = ["gregorian", "chinese"] as const;
export type SeasonalEventCalendar = (typeof SEASONAL_EVENT_CALENDARS)[number];

/** A month and day an event starts or ends on, the same every year in its calendar. Port of SeasonalEventDay. */
export interface SeasonalEventDay {
  readonly month: number;
  readonly day: number;
}

function pad(value: number, width: number): string {
  return String(value).padStart(width, "0");
}

function keyOf(year: number, month: number, day: number): DayKey {
  return `${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}`;
}

/** The local day containing `instant` in `timeZone`. */
export function localDay(instant: Instant, timeZone: string): DayKey {
  const wall = wallTime(instant, timeZone);
  return keyOf(wall.year, wall.month, wall.day);
}

/** The Chinese calendar date of a civil day: its related Gregorian year, month, whether the month is a leap month, and day. */
interface ChineseDate {
  readonly year: number;
  readonly month: number;
  readonly isLeapMonth: boolean;
  readonly day: number;
}

const chineseFormatter = new Intl.DateTimeFormat("en-US-u-ca-chinese-nu-latn", {
  timeZone: "UTC",
  year: "numeric",
  month: "numeric",
  day: "numeric",
});

const chineseDates = new Map<DayKey, ChineseDate>();

function civilDate(key: DayKey): Date {
  const [year, month, day] = key.split("-").map(Number);
  const date = new Date(0);
  date.setUTCFullYear(year ?? 1970, (month ?? 1) - 1, day ?? 1);
  date.setUTCHours(12, 0, 0, 0);
  return date;
}

function nextKey(key: DayKey, days: number): DayKey {
  const date = civilDate(key);
  date.setUTCDate(date.getUTCDate() + days);
  return keyOf(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate());
}

/* The Chinese date of `key`, read at noon UTC of that civil day, so no zone shifts it. */
function chineseDate(key: DayKey): ChineseDate {
  const cached = chineseDates.get(key);
  if (cached) return cached;
  const fields: Record<string, string> = {};
  for (const part of chineseFormatter.formatToParts(civilDate(key))) fields[part.type] = part.value;
  /* A leap month reads like "6bis"; the related year is the Gregorian year the Chinese year starts in. */
  const monthText = fields.month ?? "1";
  const result: ChineseDate = {
    year: Number(fields.relatedYear ?? fields.year ?? "0"),
    month: Number.parseInt(monthText, 10),
    isLeapMonth: /bis$/.test(monthText),
    day: Number(fields.day ?? "1"),
  };
  chineseDates.set(key, result);
  return result;
}

const chineseDays = new Map<string, DayKey | undefined>();

/*
 * The civil day of `month`/`day` (never in a leap month, which Foundation's
 * `isLeapMonth = false` also skips) in the Chinese year that starts in
 * Gregorian `year`. Lunar New Year always falls between January 21 and
 * February 20, so the search starts just before that and walks one year.
 */
function chineseDay(year: number, month: number, day: number): DayKey | undefined {
  /* The first month has at least 29 days, so any valid day of it follows from the new year. */
  const newYear = lunarNewYear(year);
  if (month === 1 && newYear !== undefined) return nextKey(newYear, day - 1);
  const memo = `${year}-${month}-${day}`;
  if (chineseDays.has(memo)) return chineseDays.get(memo);
  let found: DayKey | undefined;
  let key = keyOf(year, 1, 19);
  for (let step = 0; step < 420; step++) {
    const date = chineseDate(key);
    if (date.year > year) break;
    if (date.year === year && !date.isLeapMonth && date.month === month && date.day === day) {
      found = key;
      break;
    }
    key = nextKey(key, 1);
  }
  chineseDays.set(memo, found);
  return found;
}

/**
 * The local day `day` falls on in `year`: the Gregorian year, or for the
 * Chinese calendar the Chinese year that starts in that Gregorian year.
 * Undefined when that year has no such day.
 */
export function eventDayIn(calendar: SeasonalEventCalendar, day: SeasonalEventDay, year: number): DayKey | undefined {
  switch (calendar) {
    case "gregorian": {
      const date = new Date(Date.UTC(2000, day.month - 1, day.day));
      date.setUTCFullYear(year);
      if (date.getUTCMonth() !== day.month - 1 || date.getUTCDate() !== day.day) return undefined;
      return keyOf(year, day.month, day.day);
    }
    case "chinese":
      return chineseDay(year, day.month, day.day);
  }
}

/** The year `key` falls in, counted the way `eventDayIn` takes it. */
export function eventYearOf(calendar: SeasonalEventCalendar, key: DayKey): number {
  switch (calendar) {
    case "gregorian":
      return Number(key.slice(0, 4));
    case "chinese": {
      const year = Number(key.slice(0, 4));
      const newYear = lunarNewYear(year);
      if (newYear !== undefined) return key >= newYear ? year : year - 1;
      return chineseDate(key).year;
    }
  }
}

/**
 * Whether every year has `day`: months 1 to 12 and days up to the shortest
 * length that month can have (28 for February, 29 for any Chinese month,
 * which has 29 or 30 days).
 */
export function isValidEventDay(day: SeasonalEventDay, calendar: SeasonalEventCalendar): boolean {
  if (!Number.isInteger(day.month) || !Number.isInteger(day.day)) return false;
  if (day.month < 1 || day.month > 12 || day.day < 1) return false;
  switch (calendar) {
    case "gregorian": {
      const shortest = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][day.month - 1] ?? 0;
      return day.day <= shortest;
    }
    case "chinese":
      return day.day <= 29;
  }
}
