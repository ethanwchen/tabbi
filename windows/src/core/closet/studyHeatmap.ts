import { durationMinutes } from "../formatting/durationFormat";
import { tr } from "../localization/tr";
import { addDays, dayKey, weekStart, type DayCalendar, type DayKey } from "../streaks/dayCalendar";
import type { Instant } from "../time";

/*
 * Port of StudyHeatmap: the Closet's GitHub-style study chart, a column per
 * week and a row per weekday ending with today, each day shaded by how
 * long it was studied. It reads the same minutes per day as streaks and
 * points, so they never disagree.
 */

/** Shades in the chart, the empty one included. */
export const HEATMAP_LEVEL_COUNT = 5;
/** The fewest minutes for levels 2, 3 and 4. */
export const HEATMAP_LEVEL_THRESHOLDS: readonly number[] = [15, 45, 90];
/** The weekdays GitHub names beside its rows: Monday, Wednesday and Friday. */
export const HEATMAP_LABELED_WEEKDAYS: ReadonlySet<number> = new Set([2, 4, 6]);

/** 0 for no study, then 1 under 15 minutes, 2 under 45, 3 under 90 and 4 from 90 on. */
export function heatmapLevel(minutes: number): number {
  if (!(minutes > 0)) return 0;
  return 1 + HEATMAP_LEVEL_THRESHOLDS.filter((threshold) => minutes >= threshold).length;
}

/** One day's cell. */
export interface HeatmapDay {
  readonly key: DayKey;
  /** Focused minutes that day, rounded to the minute. */
  readonly minutes: number;
  readonly isToday: boolean;
}

/** "No study" or "1h 25m studied", the tooltip's exact value, so levels never rely on color alone. */
export function heatmapDayLabel(day: HeatmapDay): string {
  return day.minutes > 0 ? tr("%@ studied", durationMinutes(day.minutes)) : tr("No study");
}

/** One column: the seven weekdays from the first weekday, undefined for days after today. */
export interface HeatmapWeek {
  readonly start: DayKey;
  readonly days: readonly (HeatmapDay | undefined)[];
}

export function weekMinutes(week: HeatmapWeek): number {
  return week.days.reduce((sum, day) => sum + (day?.minutes ?? 0), 0);
}

/** Days in the week with any study. */
export function weekStudiedDays(week: HeatmapWeek): number {
  return week.days.filter((day) => (day?.minutes ?? 0) > 0).length;
}

/** A month's name over the first column whose week starts in that month. */
export interface HeatmapMonthLabel {
  readonly week: number;
  readonly start: DayKey;
}

export class StudyHeatmap {
  /** Oldest first; the last week holds today. */
  readonly weeks: readonly HeatmapWeek[];
  readonly today: DayKey;
  /** Each row's weekday (1 is Sunday), from the calendar's first weekday. */
  readonly weekdays: readonly number[];
  /** Focused minutes over the 30 days ending today. */
  readonly lastThirtyDaysMinutes: number;
  /** The most studied day up to today (the latest on a tie), or undefined before any study. */
  readonly bestDay: HeatmapDay | undefined;

  /**
   * @param minutesByDay focused minutes per day; days after today are ignored.
   * @param count how many columns fit; at least one, the current week.
   */
  constructor(minutesByDay: ReadonlyMap<DayKey, number>, count: number, today: Instant, calendar: DayCalendar) {
    const todayKey = dayKey(today, calendar);
    const minutes = (key: DayKey) => {
      const value = minutesByDay.get(key) ?? 0;
      return Number.isFinite(value) ? Math.max(0, roundHalfAway(value)) : 0;
    };
    const day = (key: DayKey): HeatmapDay => ({ key, minutes: minutes(key), isToday: key === todayKey });
    const first = weekStart(todayKey, calendar);
    const weeks: HeatmapWeek[] = [];
    for (let back = Math.max(1, count) - 1; back >= 0; back--) {
      const start = addDays(first, -7 * back);
      const days: (HeatmapDay | undefined)[] = [];
      for (let offset = 0; offset < 7; offset++) {
        const key = addDays(start, offset);
        days.push(key <= todayKey ? day(key) : undefined);
      }
      weeks.push({ start, days });
    }
    this.weeks = weeks;
    this.today = todayKey;
    this.weekdays = Array.from({ length: 7 }, (_, offset) => ((calendar.firstWeekday - 1 + offset) % 7) + 1);
    let lastThirty = 0;
    for (let back = 0; back < 30; back++) lastThirty += minutes(addDays(todayKey, -back));
    this.lastThirtyDaysMinutes = lastThirty;
    let best: HeatmapDay | undefined;
    for (const key of minutesByDay.keys()) {
      if (key > todayKey) continue;
      const candidate = day(key);
      if (!(candidate.minutes > 0)) continue;
      if (!best || candidate.minutes > best.minutes || (candidate.minutes === best.minutes && candidate.key > best.key)) {
        best = candidate;
      }
    }
    this.bestDay = best;
  }

  /**
   * The month labels, leaving out any that would crowd the next one or run
   * past the last column: a label needs `minimumWeeks` columns of its own.
   */
  monthLabels(minimumWeeks: number): HeatmapMonthLabel[] {
    const starts = this.weeks.flatMap((week, index) => {
      const previous = this.weeks[index - 1];
      return index === 0 || !previous || week.start.slice(0, 7) !== previous.start.slice(0, 7) ? [index] : [];
    });
    return starts.flatMap((index, offset) => {
      const next = starts[offset + 1] ?? this.weeks.length;
      const week = this.weeks[index];
      return week && next - index >= Math.max(1, minimumWeeks) ? [{ week: index, start: week.start }] : [];
    });
  }
}

/** Swift's `.rounded()`: half away from zero. */
function roundHalfAway(value: number): number {
  return value < 0 ? -Math.round(-value) : Math.round(value);
}
