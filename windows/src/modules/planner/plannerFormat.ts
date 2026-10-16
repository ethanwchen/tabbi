/*
 * Dates and times as the Today and Schedule panels write them, with Intl
 * in the user's language and zone. The Mac formats with Foundation's
 * styles; the one place Intl disagrees is a weekday with a day of the
 * month in English ("10 Sat"), which reads here as the Mac's "Sat 10".
 */

import { durationMinutes } from "../../core/formatting/durationFormat";
import { tr } from "../../core/localization/tr";
import type { DateInterval } from "../../core/planner/dateInterval";
import type { PlanBlock } from "../../core/planner/dayPlan";
import { eventStartTime, roundHalfAwayFromZero } from "../../core/planner/upcomingEvent";
import type { Instant } from "../../core/time";

const formats = new Map<string, Intl.DateTimeFormat>();

function format(locale: string, timeZone: string, options: Intl.DateTimeFormatOptions): Intl.DateTimeFormat {
  const key = `${locale}|${timeZone}|${JSON.stringify(options)}`;
  let cached = formats.get(key);
  if (cached === undefined) {
    try {
      cached = new Intl.DateTimeFormat(locale, { timeZone, ...options });
    } catch {
      cached = new Intl.DateTimeFormat("en", { timeZone: "UTC", ...options });
    }
    formats.set(key, cached);
  }
  return cached;
}

function parts(instant: Instant, locale: string, timeZone: string, options: Intl.DateTimeFormatOptions): Intl.DateTimeFormatPart[] {
  return format(locale, timeZone, options).formatToParts(new Date(Math.floor(instant) * 1000));
}

/** `instant` in `options`, as Intl writes it for `locale`. */
export function formatDate(instant: Instant, options: Intl.DateTimeFormatOptions, locale: string, timeZone: string): string {
  if (options.weekday !== undefined && options.day !== undefined && options.month === undefined && options.year === undefined) {
    return weekdayAndDay(instant, options, locale, timeZone);
  }
  return format(locale, timeZone, options).format(new Date(Math.floor(instant) * 1000));
}

/*
 * A weekday with the day of the month. Intl puts the day first in English
 * ("10 Sat") although the same locale writes "Sat, Oct 10" with a month, so
 * when the full date starts with the weekday and the short one does not,
 * the short one is rebuilt weekday first, the way the Mac writes "Sat 10".
 */
function weekdayAndDay(instant: Instant, options: Intl.DateTimeFormatOptions, locale: string, timeZone: string): string {
  const short = parts(instant, locale, timeZone, options);
  const full = parts(instant, locale, timeZone, { ...options, month: "short" });
  const firstType = (list: Intl.DateTimeFormatPart[]) => list.find((part) => part.type !== "literal")?.type;
  if (firstType(short) === "weekday" || firstType(full) !== "weekday") return short.map((part) => part.value).join("");
  const weekday = short.find((part) => part.type === "weekday")?.value;
  const day = short.find((part) => part.type === "day")?.value;
  if (weekday === undefined || day === undefined) return short.map((part) => part.value).join("");
  return `${weekday} ${day}`;
}

/** The clock hour alone ("9 AM", "14"), for the Schedule's axis. */
export function hourLabel(instant: Instant, locale: string, timeZone: string): string {
  return format(locale, timeZone, { hour: "numeric" }).format(new Date(Math.floor(instant) * 1000));
}

/** "10:45-11:30", the proposal row's time column. */
export function blockRange(block: Pick<PlanBlock, "start" | "end">, locale: string, timeZone: string): string {
  return `${eventStartTime(block.start, locale, timeZone)}-${eventStartTime(block.end, locale, timeZone)}`;
}

/** "5 min", "17 min", "1h 30m", the same style as every other duration. */
export function breakLength(rest: DateInterval): string {
  return durationMinutes(roundHalfAwayFromZero((rest.end - rest.start) / 60));
}

/** The planning shimmer's tooltip: who plans, around which day's events. */
export function planningHelp(byAI: boolean, assistant: string, tomorrow: boolean): string {
  if (byAI) return tomorrow ? tr("%@ is fitting your tasks around tomorrow's events", assistant) : tr("%@ is fitting your tasks around today's events", assistant);
  return tomorrow ? tr("Fitting your work and breaks around tomorrow's events") : tr("Fitting your work and breaks around today's events");
}
