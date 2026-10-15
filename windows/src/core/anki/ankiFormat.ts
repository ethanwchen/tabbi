import { tr } from "../localization/tr";
import type { Instant } from "../time";
import type { AnkiDayCount } from "./ankiConnectModels";
import { type AnkiDay, addingDays, ankiDayText, sameAnkiDay } from "./ankiDay";
import { type AnkiSummary, summaryDueTotal } from "./ankiSummary";

/** Heatmap shades, from no reviews (0) to the busiest day (4). */
export const HEAT_LEVELS = 4;

/**
 * Port of AnkiFormat.heatLevels: one shade per day of `history`, scaled to
 * the busiest day so a light week still shows its shape. Any day with
 * reviews gets at least 1, so a short session never looks like a missed day.
 */
export function heatLevels(history: readonly AnkiDayCount[]): number[] {
  const busiest = Math.max(0, ...history.map((entry) => entry.count));
  if (busiest <= 0) return history.map(() => 0);
  return history.map((entry) => {
    if (entry.count <= 0) return 0;
    const scaled = Math.ceil((entry.count / busiest) * HEAT_LEVELS);
    return Math.min(Math.max(scaled, 1), HEAT_LEVELS);
  });
}

/** "12-day streak", "1-day streak", or "No streak yet". */
export function streakText(days: number): string {
  return days > 0 ? tr("%lld-day streak", days) : tr("No streak yet");
}

/** "Today", "Yesterday", or a short weekday and date ("Mon, Sep 30"). */
export function dayName(day: AnkiDay, today: AnkiDay, locale = "en-US"): string {
  if (sameAnkiDay(day, today)) return "Today";
  if (sameAnkiDay(day, addingDays(today, -1))) return "Yesterday";
  const noon = new Date(Date.UTC(day.year, day.month - 1, day.day, 12));
  if (Number.isNaN(noon.getTime())) return ankiDayText(day);
  return new Intl.DateTimeFormat(locale, { timeZone: "UTC", weekday: "short", month: "short", day: "numeric" }).format(noon);
}

/** Tooltip for one heatmap cell: "Today · 112 reviews", "Mon, Sep 30 · No reviews". */
export function dayHelp(entry: AnkiDayCount, today: AnkiDay, locale = "en-US"): string {
  const count = entry.count === 0 ? "No reviews" : entry.count === 1 ? "1 review" : `${entry.count} reviews`;
  return `${dayName(entry.day, today, locale)} · ${count}`;
}

/** The ring's tooltip: "112 of 432 cards reviewed today". */
export function progressHelp(summary: AnkiSummary): string {
  const due = summaryDueTotal(summary);
  if (due === 0) {
    return summary.reviewedToday > 0 ? tr("All %lld cards done for today", summary.reviewedToday) : tr("Nothing due today");
  }
  return tr("%lld of %lld cards reviewed today", summary.reviewedToday, summary.reviewedToday + due);
}

/** How old the numbers are: "just now", "5m ago", "2h ago", "3d ago". */
export function ageText(date: Instant, now: Instant): string {
  const seconds = Math.max(now - date, 0);
  if (seconds < 60) return tr("just now");
  if (seconds < 3600) return tr("%lldm ago", Math.trunc(seconds / 60));
  if (seconds < 86_400) return tr("%lldh ago", Math.trunc(seconds / 3600));
  return tr("%lldd ago", Math.trunc(seconds / 86_400));
}
