import { dayRange } from "../formatting/dateRangeFormat";
import { tr } from "../localization/tr";
import { dayKeyStart, type PlannerDayKey } from "../planner/plannerDayKey";
import { recapWeekEnd, type RecapWeek } from "./recapWeek";
import type { WeeklyRecap } from "./weeklyRecap";

/*
 * Port of RecapStat and the recap's formatting extensions: the small
 * numbers on a recap card, the week's title and the day bars' initials.
 * Locales are BCP 47 tags (`en-US`), passed in like the time zone.
 */

export type RecapStatKind = "sessions" | "bestDay" | "streak" | "cards" | "tasks" | "points";

export const RECAP_STAT_KINDS: readonly RecapStatKind[] = ["sessions", "bestDay", "streak", "cards", "tasks", "points"];

/** One small number on a recap card, such as "18 sessions" or "Thu best day". */
export interface RecapStat {
  readonly kind: RecapStatKind;
  /** The number or day, drawn large: "18", "Thu", "1,240". */
  readonly value: string;
  /** What it counts, drawn small beneath: "sessions", "best day". */
  readonly label: string;
}

/* A day key's calendar date at noon UTC, so formatting it in UTC can never slip a day. */
function civilDate(day: PlannerDayKey): Date {
  return new Date(`${day}T12:00:00Z`);
}

/** "Thu": the day's short weekday name in `locale`. */
function weekdayName(day: PlannerDayKey, locale: string): string {
  return new Intl.DateTimeFormat(locale, { weekday: "short", timeZone: "UTC" }).format(civilDate(day));
}

/**
 * The numbers beside the hours focused, in a fixed order. A stat with
 * nothing to show is left out, so a light week reads as what it had rather
 * than a row of zeros, and a one-day streak is not called one.
 */
export function recapStats(recap: WeeklyRecap, locale: string): RecapStat[] {
  const number = new Intl.NumberFormat(locale);
  const count = (value: number) => number.format(value);
  const stats: RecapStat[] = [];
  if (recap.sessions > 0) {
    stats.push({ kind: "sessions", value: count(recap.sessions), label: recap.sessions === 1 ? tr("session") : tr("sessions") });
  }
  const best = recap.bestDay();
  if (best) stats.push({ kind: "bestDay", value: weekdayName(best.day, locale), label: tr("best day") });
  if (recap.longestStreak >= 2) stats.push({ kind: "streak", value: count(recap.longestStreak), label: tr("day streak") });
  if (recap.cardsReviewed > 0) {
    stats.push({ kind: "cards", value: count(recap.cardsReviewed), label: recap.cardsReviewed === 1 ? tr("card") : tr("cards") });
  }
  if (recap.tasksDone > 0) {
    stats.push({ kind: "tasks", value: count(recap.tasksDone), label: recap.tasksDone === 1 ? tr("task") : tr("tasks") });
  }
  if (recap.points > 0) {
    stats.push({ kind: "points", value: count(recap.points), label: recap.points === 1 ? tr("point") : tr("points") });
  }
  return stats;
}

/**
 * The week's dates for a card's corner: "Oct 5 - 11", or "Sep 28 - Oct 4"
 * when it spans two months (and both years across New Year), in the
 * locale's order.
 */
export function recapWeekTitle(week: RecapWeek, locale: string, timeZone: string): string {
  return dayRange(dayKeyStart(week, timeZone), dayKeyStart(recapWeekEnd(week), timeZone), locale, timeZone);
}

/** One-letter weekday names, Monday first, for the card's day bars. */
export function recapDayInitials(locale: string): string[] {
  const format = new Intl.DateTimeFormat(locale, { weekday: "narrow", timeZone: "UTC" });
  /* 2026-10-05 is a Monday. */
  return Array.from({ length: 7 }, (_, offset) => format.format(new Date(Date.UTC(2026, 9, 5 + offset, 12))));
}
