import type { Instant } from "../time";
import { settingTime } from "../calendar/zonedCalendar";
import { tr } from "../localization/tr";
import { DEFAULT_DAY_START_HOUR } from "./dayPlan";
import { addingDaysToKey, dayKeyStart, plannerDayKeyOf, type PlannerDayKey } from "./plannerDayKey";

/**
 * Port of PlannerViewedDay: which day Today's checklist shows. Today is the
 * default; the header steps one day back to look at what yesterday left,
 * or one day ahead to plan tomorrow. Further days are out of reach on
 * purpose, so the panel stays a daily tool rather than a calendar.
 */
export type PlannerViewedDay = "yesterday" | "today" | "tomorrow";

export const PLANNER_VIEWED_DAYS: readonly PlannerViewedDay[] = ["yesterday", "today", "tomorrow"];

const OFFSETS: Readonly<Record<PlannerViewedDay, number>> = { yesterday: -1, today: 0, tomorrow: 1 };

/** Days from today: -1, 0 or 1 (the Swift raw value). */
export function viewedDayOffset(day: PlannerViewedDay): number {
  return OFFSETS[day];
}

/** The day this names, counted from `today`. */
export function viewedDayKey(day: PlannerViewedDay, today: PlannerDayKey): PlannerDayKey {
  return day === "today" ? today : addingDaysToKey(today, OFFSETS[day]);
}

/** One day earlier, or undefined at yesterday. */
export function previousViewedDay(day: PlannerViewedDay): PlannerViewedDay | undefined {
  return day === "tomorrow" ? "today" : day === "today" ? "yesterday" : undefined;
}

/** One day later, or undefined at tomorrow. */
export function nextViewedDay(day: PlannerViewedDay): PlannerViewedDay | undefined {
  return day === "yesterday" ? "today" : day === "today" ? "tomorrow" : undefined;
}

/** The header title for a day other than today; undefined for today, which shows its date. */
export function viewedDayTitle(day: PlannerViewedDay): string | undefined {
  switch (day) {
    case "yesterday":
      return tr("Yesterday");
    case "today":
      return undefined;
    case "tomorrow":
      return tr("Tomorrow");
  }
}

/**
 * How the header writes this day's date, widest first, so a narrow panel
 * can fall back to a shorter one (undefined leaves the date out). Without
 * dates (demo mode, whose screenshots must not show one) today names only
 * its weekday and the other days only their title.
 */
export function viewedDayHeaderDateStyles(day: PlannerViewedDay, showsDates = true): (Intl.DateTimeFormatOptions | undefined)[] {
  if (day === "today") {
    return showsDates
      ? [
          { weekday: "short", month: "short", day: "numeric" },
          { weekday: "short", day: "numeric" },
        ]
      : [{ weekday: "long" }, { weekday: "short" }];
  }
  return showsDates ? [{ month: "short", day: "numeric" }, undefined] : [undefined];
}

/** The caption of the calendar card beside the list: what's next today, or the whole of the other day. */
export function viewedDayCalendarTitle(day: PlannerViewedDay): string {
  switch (day) {
    case "yesterday":
      return tr("Yesterday's calendar");
    case "today":
      return tr("Up next");
    case "tomorrow":
      return tr("Tomorrow's calendar");
  }
}

/** Whether the list can be changed here; yesterday is a record of what happened. */
export function viewedDayIsEditable(day: PlannerViewedDay): boolean {
  return day !== "yesterday";
}

/**
 * Where Plan my day starts planning this day: `now` for today, the start
 * of the working day (`startHour`) for tomorrow, so it can be planned the
 * evening before. Undefined for yesterday, which is over.
 */
export function viewedDayPlanStart(
  day: PlannerViewedDay,
  now: Instant,
  timeZone: string,
  startHour: number = DEFAULT_DAY_START_HOUR,
): Instant | undefined {
  switch (day) {
    case "yesterday":
      return undefined;
    case "today":
      return now;
    case "tomorrow": {
      const start = dayKeyStart(viewedDayKey(day, plannerDayKeyOf(now, timeZone)), timeZone);
      return settingTime(start, Math.min(Math.max(startHour, 0), 23), 0, 0, timeZone);
    }
  }
}

/** The Plan my day button's title for this day. */
export function viewedDayPlanTitle(day: PlannerViewedDay): string {
  return day === "tomorrow" ? tr("Plan tomorrow") : tr("Plan my day");
}
