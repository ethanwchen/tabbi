import type { Instant } from "../time";
import { addingDays, isWeekend, startOfDay } from "../calendar/zonedCalendar";
import type { MeetingLink } from "../planner/meetingLink";
import type { ProvidedTask } from "../planner/providedWork";
import type { EventColor } from "../planner/upcomingEvent";
import { scheduleItem, type ScheduleItem, type ScheduleItemKind } from "./scheduleDay";
import { clockTime } from "./schedulePlanner";

/*
 * Port of ScheduleSampleData: the Schedule's demo day, a few meetings, a
 * run and two blocks Tabbi planned, at fixed clock times on the day
 * containing `date`, seen from 11:20. Fixed times keep the timeline
 * realistic whatever hour a demo or snapshot runs.
 */

const WORK: EventColor = { red: 0.2, green: 0.55, blue: 0.98 };
const PERSONAL: EventColor = { red: 0.98, green: 0.62, blue: 0.2 };

/** The moment the demo day is seen from: 11:20 on `date`'s day. */
export function scheduleSampleNow(date: Instant, timeZone: string): Instant {
  return clockTime(11 * 60 + 20, date, timeZone);
}

export function scheduleSampleItems(date: Instant, timeZone: string): ScheduleItem[] {
  const item = (
    id: string,
    title: string,
    start: number,
    end: number,
    options: { kind?: ScheduleItemKind; color?: EventColor; reason?: string; link?: MeetingLink } = {},
  ) =>
    scheduleItem({
      id: `demo-${id}`,
      title,
      start: clockTime(start, date, timeZone),
      end: clockTime(end, date, timeZone),
      kind: options.kind ?? "event",
      calendarColor: options.color,
      reason: options.reason,
      meetingLink: options.link,
    });
  return [
    item("reviews", "Anki reviews", 9 * 60 + 15, 9 * 60 + 50, { kind: "planned", reason: "Reviews first while you're fresh" }),
    item("standup", "Design standup", 10 * 60, 10 * 60 + 30, {
      color: WORK,
      link: { provider: "googleMeet", url: "https://meet.google.com/abc-defg-hij" },
    }),
    item("deck", "Draft the launch deck", 10 * 60 + 45, 12 * 60, { kind: "planned", reason: "High priority, due today" }),
    item("lunch", "Lunch with Sam", 12 * 60 + 30, 13 * 60 + 30, { color: PERSONAL }),
    item("review", "Beta review", 14 * 60, 15 * 60, { color: WORK, link: { provider: "zoom", url: "https://zoom.us/j/5551234567" } }),
    item("sync", "Partner sync", 14 * 60 + 30, 15 * 60 + 15, { color: WORK }),
    item("run", "30-minute run", 17 * 60 + 15, 17 * 60 + 45, { color: PERSONAL }),
    scheduleItem({
      id: "demo-holiday",
      title: "Payday",
      start: clockTime(0, date, timeZone),
      end: clockTime(24 * 60, date, timeZone),
      isAllDay: true,
    }),
  ];
}

/** Seven days from `date`'s: today's items, then a plausible week, with work kept off weekends. */
export function scheduleSampleWeekItems(date: Instant, timeZone: string): ScheduleItem[] {
  const result = scheduleSampleItems(date, timeZone);
  const first = startOfDay(date, timeZone);
  for (let offset = 1; offset < 7; offset++) {
    const day = addingDays(first, offset, timeZone);
    const item = (id: string, title: string, start: number, end: number, kind: ScheduleItemKind = "event", color?: EventColor) =>
      scheduleItem({
        id: `demo-${offset}-${id}`,
        title,
        start: clockTime(start, day, timeZone),
        end: clockTime(end, day, timeZone),
        kind,
        calendarColor: color,
      });
    if (isWeekend(day, timeZone)) {
      result.push(item("brunch", "Brunch", 11 * 60, 12 * 60 + 30, "event", PERSONAL), item("hike", "Hike", 14 * 60, 17 * 60, "event", PERSONAL));
      continue;
    }
    result.push(item("standup", "Design standup", 10 * 60, 10 * 60 + 30, "event", WORK));
    switch (offset % 3) {
      case 1:
        result.push(
          item("focus", "Write the spec", 9 * 60, 9 * 60 + 50, "planned"),
          item("1on1", "1:1 with Alex", 11 * 60, 11 * 60 + 30, "event", WORK),
          item("workshop", "Roadmap workshop", 13 * 60, 15 * 60 + 30, "event", WORK),
        );
        break;
      case 2:
        result.push(
          item("interview", "Interview", 11 * 60 + 30, 12 * 60 + 30, "event", WORK),
          item("reviews", "Anki reviews", 13 * 60 + 30, 14 * 60, "planned"),
          item("gym", "Gym", 17 * 60 + 30, 18 * 60 + 30, "event", PERSONAL),
        );
        break;
      default:
        result.push(
          item("planning", "Sprint planning", 13 * 60, 14 * 60 + 30, "event", WORK),
          item("dentist", "Dentist", 16 * 60, 17 * 60, "event", PERSONAL),
        );
    }
  }
  return result;
}

/** The day before `date`'s, as the demo looks back on it: a full working day, all over. */
export function scheduleSampleYesterdayItems(date: Instant, timeZone: string): ScheduleItem[] {
  const day = addingDays(startOfDay(date, timeZone), -1, timeZone);
  const item = (id: string, title: string, start: number, end: number, kind: ScheduleItemKind = "event", color?: EventColor) =>
    scheduleItem({
      id: `demo-yesterday-${id}`,
      title,
      start: clockTime(start, day, timeZone),
      end: clockTime(end, day, timeZone),
      kind,
      calendarColor: color,
    });
  return [
    item("reviews", "Anki reviews", 9 * 60, 9 * 60 + 30, "planned"),
    item("standup", "Design standup", 10 * 60, 10 * 60 + 30, "event", WORK),
    item("research", "User interviews", 10 * 60 + 45, 12 * 60, "event", WORK),
    item("lunch", "Lunch", 12 * 60 + 30, 13 * 60 + 15, "event", PERSONAL),
    item("spec", "Write the spec", 13 * 60 + 30, 15 * 60, "planned"),
    item("retro", "Team retro", 15 * 60 + 30, 16 * 60 + 15, "event", WORK),
  ];
}

/** Open tasks for the demo's Plan button: they fill the afternoon gap and leave the last one over. */
export const SCHEDULE_SAMPLE_TASKS: readonly ProvidedTask[] = [
  { id: "demo-pr", source: "planner", title: "Review PR #142", isDone: false, estimatedMinutes: 30 },
  { id: "demo-email", source: "planner", title: "Reply to Priya", isDone: false, estimatedMinutes: 15 },
  { id: "demo-notes", source: "planner", title: "Prep beta review notes", isDone: false, estimatedMinutes: 45 },
  { id: "demo-roadmap", source: "planner", title: "Outline the Q4 roadmap", isDone: false, estimatedMinutes: 60 },
];

/** The demo's open tasks for planning the week: today's, plus larger work that spills into the next days. */
export const SCHEDULE_SAMPLE_WEEK_TASKS: readonly ProvidedTask[] = [
  ...SCHEDULE_SAMPLE_TASKS,
  { id: "demo-doc", source: "planner", title: "Write the sync design doc", isDone: false, estimatedMinutes: 180 },
  { id: "demo-study", source: "planner", title: "Study for the AWS exam", isDone: false, estimatedMinutes: 120 },
  { id: "demo-backlog", source: "planner", title: "Clean up the backlog", isDone: false, estimatedMinutes: 45 },
];
