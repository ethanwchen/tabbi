/*
 * The calendar the Closet counts days in: the user's IANA zone and the
 * language's first weekday, the Mac's `Calendar.current`. Read on every
 * use, so a zone change moves the streak's days and the heatmap's columns
 * at once. The core takes a DayCalendar explicitly; this is where the app
 * works one out.
 */

import { currentLanguage } from "../../core/localization/tr";
import type { DayCalendar } from "../../core/streaks/dayCalendar";

/* Intl numbers weekdays Monday 1 to Sunday 7; the calendar numbers Sunday 1 to Saturday 7, like Foundation. */
function firstWeekday(language: string): number {
  try {
    const locale = new Intl.Locale(language) as Intl.Locale & { getWeekInfo?: () => { firstDay: number }; weekInfo?: { firstDay: number } };
    const info = locale.getWeekInfo?.() ?? locale.weekInfo;
    const firstDay = info?.firstDay;
    if (firstDay !== undefined && firstDay >= 1 && firstDay <= 7) return (firstDay % 7) + 1;
  } catch {
    /* An unknown tag: Sunday, as a fresh en-US system has it. */
  }
  return 1;
}

/** The calendar for `timeZone` in the language `tr` reads. */
export function closetCalendar(timeZone: string, language: string = currentLanguage()): DayCalendar {
  return { timeZone, firstWeekday: firstWeekday(language) };
}
