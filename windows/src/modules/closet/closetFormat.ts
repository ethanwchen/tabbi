/*
 * The dates the Closet writes, in the user's language and zone: a day key
 * as "Tue, Oct 6" over the chart, "October 6" for an event's start, "Oct"
 * over a column and the weekday initials under the streak's dots. Day keys
 * name local days, so they are formatted at noon UTC of that date, which no
 * zone can move to another day.
 */

import { currentLanguage } from "../../core/localization/tr";
import type { DayKey } from "../../core/streaks/dayCalendar";
import { dateFromInstant, type Instant } from "../../core/time";

function civil(day: DayKey): Date {
  return new Date(`${day}T12:00:00Z`);
}

function format(options: Intl.DateTimeFormatOptions, locale: string = currentLanguage()): Intl.DateTimeFormat {
  return new Intl.DateTimeFormat(locale, { timeZone: "UTC", ...options });
}

/** "Tue, Oct 6" (with the year when asked), the chart's hovered day. */
export function dayTitle(day: DayKey, year = false): string {
  return format({ weekday: "short", month: "short", day: "numeric", ...(year ? { year: "numeric" } : {}) }).format(civil(day));
}

/** "Tuesday, October 6", a streak dot's tooltip. */
export function dayLongTitle(day: DayKey): string {
  return format({ weekday: "long", month: "long", day: "numeric" }).format(civil(day));
}

/** "October 6", a week's start in a tooltip. */
export function monthDayLong(day: DayKey): string {
  return format({ month: "long", day: "numeric" }).format(civil(day));
}

/** "Oct", a month's name over the chart. */
export function monthShort(day: DayKey): string {
  return format({ month: "short" }).format(civil(day));
}

/** "Oct 6", an event's last or first day, from an instant in the user's zone. */
export function monthDayAt(instant: Instant, timeZone: string): string {
  return format({ month: "short", day: "numeric", timeZone }).format(dateFromInstant(instant));
}

/** "October 6", from an instant in the user's zone. */
export function monthDayLongAt(instant: Instant, timeZone: string): string {
  return format({ month: "long", day: "numeric", timeZone }).format(dateFromInstant(instant));
}

/** The locale's one-letter weekday names (`veryShortStandaloneWeekdaySymbols`), Sunday first. */
export function weekdayInitials(locale: string = currentLanguage()): string[] {
  const narrow = format({ weekday: "narrow" }, locale);
  /* 2026-10-04 is a Sunday. */
  return Array.from({ length: 7 }, (_, offset) => narrow.format(new Date(Date.UTC(2026, 9, 4 + offset, 12))));
}

/** The locale's short weekday names ("Mon"), Sunday first. */
export function weekdayShortNames(locale: string = currentLanguage()): string[] {
  const short = format({ weekday: "short" }, locale);
  return Array.from({ length: 7 }, (_, offset) => short.format(new Date(Date.UTC(2026, 9, 4 + offset, 12))));
}

/** The weekday (1 Sunday to 7 Saturday) of a day key. */
export function weekdayOf(day: DayKey): number {
  return civil(day).getUTCDay() + 1;
}
