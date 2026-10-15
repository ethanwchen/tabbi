import type { Instant } from "../time";
import { addingDays, startOfDay, startOfHour, wallTime } from "../calendar/zonedCalendar";
import { durationMinutes } from "../formatting/durationFormat";
import { intervalContains, intervalDuration, type DateInterval } from "../planner/dateInterval";
import { PLANNED_EVENT_NOTE } from "../planner/dayPlanProposal";
import type { MeetingLink } from "../planner/meetingLink";
import { eventStartTime, upcomingEvent, type EventColor, type UpcomingEvent } from "../planner/upcomingEvent";
import { clockTime, scheduleFreeTime, schedulePreferences, type ScheduledBlock, type SchedulePreferences } from "./schedulePlanner";

/** Port of ScheduleItem.Kind: a calendar event, a block Tabbi planned (on the calendar), or one still proposed. */
export type ScheduleItemKind = "event" | "planned" | "proposed";

/** Port of ScheduleItem: one thing on the Schedule's timeline. */
export interface ScheduleItem {
  readonly id: string;
  readonly title: string;
  readonly start: Instant;
  readonly end: Instant;
  readonly kind: ScheduleItemKind;
  readonly isAllDay: boolean;
  readonly calendarColor?: EventColor;
  /** Why a planned block sits where it does, when the planner said. */
  readonly reason?: string;
  readonly meetingLink?: MeetingLink;
}

/** Builds an item with the Swift initializer's defaults. */
export function scheduleItem(input: {
  id: string;
  title: string;
  start: Instant;
  end: Instant;
  kind?: ScheduleItemKind;
  isAllDay?: boolean;
  calendarColor?: EventColor | undefined;
  reason?: string | undefined;
  meetingLink?: MeetingLink | undefined;
}): ScheduleItem {
  const item: { -readonly [Key in keyof ScheduleItem]: ScheduleItem[Key] } = {
    id: input.id,
    title: input.title,
    start: input.start,
    end: input.end,
    kind: input.kind ?? "event",
    isAllDay: input.isAllDay ?? false,
  };
  if (input.calendarColor !== undefined) item.calendarColor = input.calendarColor;
  if (input.reason !== undefined) item.reason = input.reason;
  if (input.meetingLink !== undefined) item.meetingLink = input.meetingLink;
  return item;
}

/** A calendar event; one whose notes carry Tabbi's planned marker is a planned block. */
export function scheduleItemFromEvent(event: UpcomingEvent, notes?: string): ScheduleItem {
  return scheduleItem({
    id: event.id,
    title: event.title,
    start: event.start,
    end: event.end,
    kind: notes?.includes(PLANNED_EVENT_NOTE) === true ? "planned" : "event",
    isAllDay: event.isAllDay,
    calendarColor: event.calendarColor,
    meetingLink: event.meetingLink,
  });
}

/** A block from a local plan, with its reason. */
export function scheduleItemFromBlock(scheduled: ScheduledBlock): ScheduleItem {
  return scheduleItem({
    id: scheduled.block.id,
    title: scheduled.block.title,
    start: scheduled.block.start,
    end: scheduled.block.end,
    kind: "planned",
    reason: scheduled.reason,
  });
}

/** The item as an event the planner keeps clear of. */
export function scheduleItemEvent(item: ScheduleItem): UpcomingEvent {
  return upcomingEvent({
    id: item.id,
    title: item.title,
    start: item.start,
    end: item.end,
    isAllDay: item.isAllDay,
    calendarColor: item.calendarColor,
    meetingLink: item.meetingLink,
  });
}

export function scheduleItemMinutes(item: ScheduleItem): number {
  return Math.max(Math.trunc((item.end - item.start) / 60), 0);
}

/** Port of ScheduleDayLayout.Placed: an item with its place on the timeline, as fractions of its width. */
export interface PlacedScheduleItem {
  readonly item: ScheduleItem;
  readonly x: number;
  readonly width: number;
  /** Row within its group of overlapping items, and how many rows the group needs. */
  readonly lane: number;
  readonly lanes: number;
  /** How much width the label may use: its own, stretched over free track up to the next item in its row. */
  readonly labelWidth: number;
}

/** Port of ScheduleDayLayout.Status: what is happening at a moment. */
export type ScheduleStatus =
  | { readonly kind: "busy"; readonly item: ScheduleItem }
  | { readonly kind: "free"; readonly until?: Instant; readonly next?: ScheduleItem }
  | { readonly kind: "dayOver" };

/** Most rows a group of overlapping items gets; more items share the last. */
export const MAXIMUM_LANES = 3;

function compareText(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

function compareItems(a: ScheduleItem, b: ScheduleItem): number {
  return a.start - b.start || a.end - b.end || compareText(a.id, b.id);
}

/**
 * Positions and lanes: items that overlap (directly or through a chain)
 * form a group, and each takes the first row free at its start.
 */
export function placeScheduleItems(items: readonly ScheduleItem[], range: DateInterval): PlacedScheduleItem[] {
  const result: PlacedScheduleItem[] = [];
  const groups: number[] = [];
  let group: PlacedScheduleItem[] = [];
  let groupEnd = Number.NEGATIVE_INFINITY;
  let laneEnds: Instant[] = [];
  const span = intervalDuration(range);
  const closeGroup = () => {
    const lanes = Math.max(0, ...group.map((placed) => placed.lane)) + 1;
    const index = (groups.at(-1) ?? -1) + 1;
    for (const placed of group) {
      result.push({ ...placed, lanes });
      groups.push(index);
    }
    group = [];
    laneEnds = [];
  };
  for (const item of items) {
    if (item.start >= groupEnd && group.length > 0) closeGroup();
    const start = Math.max(item.start, range.start);
    const end = Math.min(item.end, range.end);
    let lane = laneEnds.findIndex((laneEnd) => laneEnd <= item.start);
    if (lane < 0) lane = laneEnds.length;
    if (lane >= MAXIMUM_LANES) lane = MAXIMUM_LANES - 1;
    if (lane < laneEnds.length) laneEnds[lane] = Math.max(laneEnds[lane] ?? item.end, item.end);
    else laneEnds.push(item.end);
    groupEnd = Math.max(groupEnd, item.end);
    group.push({ item, x: (start - range.start) / span, width: Math.max(end - start, 0) / span, lane, lanes: 1, labelWidth: 0 });
  }
  if (group.length > 0) closeGroup();
  /* A label runs until the next item that shares its row: a later one in its lane, or the first of a later group. */
  return result.map((placed, index) => {
    let next = 1;
    for (let other = index + 1; other < result.length; other++) {
      const candidate = result[other];
      if (candidate === undefined) continue;
      const sharesRow = (groups[other] ?? 0) > (groups[index] ?? 0) || candidate.lane === placed.lane;
      if (sharesRow && candidate.x >= placed.x) next = Math.min(next, candidate.x);
    }
    return { ...placed, labelWidth: Math.max(placed.width, next - placed.x) };
  });
}

function wholeHour(instant: Instant, roundingUp: boolean, timeZone: string): Instant {
  const floored = startOfHour(instant, timeZone);
  return roundingUp && floored < instant ? floored + 3600 : floored;
}

/**
 * Port of ScheduleDayLayout: the Schedule's Day view, laid out: which
 * hours the timeline spans, where each item sits and which lane it takes.
 */
export class ScheduleDayLayout {
  /** Midnight of the day shown. */
  readonly day: Instant;
  /** Whole hours the timeline spans: the working hours, stretched to show any timed item outside them. */
  readonly range: DateInterval;
  /** Each hour mark inside `range`, its start included. */
  readonly hours: readonly Instant[];
  readonly placed: readonly PlacedScheduleItem[];
  readonly allDay: readonly ScheduleItem[];
  /** Free time left in the working day after `now`, buffers kept, on the planner's grid. */
  readonly freeMinutes: number;
  /** When the working day ends. */
  readonly workEnd: Instant;

  constructor(
    day: Instant,
    now: Instant,
    items: readonly ScheduleItem[],
    timeZone: string,
    preferences: SchedulePreferences = schedulePreferences(),
  ) {
    const midnight = startOfDay(day, timeZone);
    const nextMidnight = addingDays(midnight, 1, timeZone);
    const timed = items
      .filter((item) => !item.isAllDay && item.end > item.start && item.end > midnight && item.start < nextMidnight)
      .sort(compareItems);
    const workStart = clockTime(preferences.workdayStartMinute, midnight, timeZone);
    const workEnd = clockTime(preferences.workdayEndMinute, midnight, timeZone);
    const first = Math.max(Math.min(timed[0]?.start ?? workStart, workStart), midnight);
    const latestEnd = timed.length === 0 ? workEnd : Math.max(...timed.map((item) => item.end));
    const last = Math.min(Math.max(latestEnd, workEnd), nextMidnight);
    const start = wholeHour(first, false, timeZone);
    let end = wholeHour(last, true, timeZone);
    if (end <= start) end = start + 3600;
    this.day = midnight;
    this.workEnd = workEnd;
    this.range = { start, end };
    const hours: Instant[] = [];
    for (let mark = start; mark <= end; mark += 3600) hours.push(mark);
    this.hours = hours;
    this.placed = placeScheduleItems(timed, this.range);
    this.allDay = items.filter((item) => item.isAllDay && item.end > midnight && item.start < nextMidnight);
    const free = scheduleFreeTime(midnight, now, timed.map(scheduleItemEvent), timeZone, preferences);
    this.freeMinutes = free.reduce((sum, gap) => sum + Math.trunc(intervalDuration(gap) / 60), 0);
  }

  /** Timed events, planned and proposed blocks left out. */
  get eventCount(): number {
    return this.placed.filter((placed) => placed.item.kind === "event").length;
  }

  /** Blocks planned with Tabbi earlier, already on the calendar. */
  get plannedCount(): number {
    return this.placed.filter((placed) => placed.item.kind === "planned").length;
  }

  /** Where `instant` falls along the timeline (0 at its start, 1 at its end), or undefined outside it. */
  position(instant: Instant): number | undefined {
    if (!intervalContains(this.range, instant)) return undefined;
    return (instant - this.range.start) / intervalDuration(this.range);
  }

  /** What is on at `now`: the item under way (the one ending soonest), else the free time until the next one. */
  status(now: Instant): ScheduleStatus {
    const items = this.placed.map((placed) => placed.item);
    let current: ScheduleItem | undefined;
    for (const item of items) {
      if (item.start <= now && now < item.end && (current === undefined || item.end < current.end)) current = item;
    }
    if (current !== undefined) return { kind: "busy", item: current };
    let next: ScheduleItem | undefined;
    for (const item of items) {
      if (item.start > now && (next === undefined || item.start < next.start)) next = item;
    }
    if (next === undefined && now >= this.workEnd) return { kind: "dayOver" };
    return next === undefined ? { kind: "free" } : { kind: "free", until: next.start, next };
  }
}

/** "45 min", "2h", "1h 15m". */
export function scheduleDuration(minutes: number): string {
  return durationMinutes(minutes);
}

/** "10:45-12:00" in the user's clock style, without AM/PM. */
export function scheduleRange(start: Instant, end: Instant, locale: string, timeZone: string): string {
  return `${eventStartTime(start, locale, timeZone)}-${eventStartTime(end, locale, timeZone)}`;
}

/** Empty-title events (common for quick-adds) still need a label. */
export function scheduleItemTitle(item: ScheduleItem): string {
  const trimmed = item.title.trim();
  return trimmed === "" ? "Untitled event" : trimmed;
}

/** The line under the timeline: what is on now, or how long is free. */
export function scheduleStatusText(status: ScheduleStatus, now: Instant, locale: string, timeZone: string): string {
  const time = (instant: Instant) => eventStartTime(instant, locale, timeZone);
  switch (status.kind) {
    case "busy":
      return `Now: ${scheduleItemTitle(status.item)}, until ${time(status.item.end)}`;
    case "free":
      if (status.until !== undefined && status.next !== undefined) {
        const minutes = Math.ceil((status.until - now) / 60);
        return `Free for ${scheduleDuration(minutes)}, then ${scheduleItemTitle(status.next)} at ${time(status.until)}`;
      }
      return "Free for the rest of the day";
    case "dayOver":
      return "Your working day is over";
  }
}

/**
 * The line under the timeline on a day other than today: what the day
 * held ("5 events, 2 planned blocks") when it is over, or what it holds
 * and when it starts when it is still to come ("4 events, the first at 10:00").
 */
export function scheduleDaySummary(layout: ScheduleDayLayout, isPast: boolean, locale: string, timeZone: string): string {
  const events = layout.eventCount;
  const planned = layout.plannedCount;
  if (events + planned === 0) return isPast ? "Nothing was on your calendar" : "Nothing on your calendar yet";
  const parts: string[] = [];
  if (events > 0) parts.push(events === 1 ? "1 event" : `${events} events`);
  if (planned > 0) parts.push(planned === 1 ? "1 planned block" : `${planned} planned blocks`);
  const counts = parts.join(", ");
  const starts = layout.placed.filter((placed) => placed.item.kind !== "proposed").map((placed) => placed.item.start);
  if (isPast || starts.length === 0) return counts;
  return `${counts}, the first at ${eventStartTime(Math.min(...starts), locale, timeZone)}`;
}

/** Port of ScheduleWeekLayout.Day: one row of the Week view. */
export interface ScheduleWeekDay {
  /** Midnight of the day. */
  readonly date: Instant;
  /** The day's span on the shared clock hours. */
  readonly range: DateInterval;
  readonly placed: readonly PlacedScheduleItem[];
  readonly allDay: readonly ScheduleItem[];
  /** Free working time after the layout's moment, buffers kept, on the planner's grid. */
  readonly freeMinutes: number;
  readonly isToday: boolean;
}

export function weekDayEventCount(day: ScheduleWeekDay): number {
  return day.placed.filter((placed) => placed.item.kind === "event").length;
}

export function weekDayPlannedCount(day: ScheduleWeekDay): number {
  return day.placed.filter((placed) => placed.item.kind === "planned").length;
}

/** Where `instant` falls along a week row, or undefined outside it. */
export function weekDayPosition(day: ScheduleWeekDay, instant: Instant): number | undefined {
  if (!intervalContains(day.range, instant)) return undefined;
  return (instant - day.range.start) / intervalDuration(day.range);
}

/**
 * Port of ScheduleWeekLayout: one row per day from today on, all sharing
 * the same span of clock hours so busy times line up down the week.
 */
export class ScheduleWeekLayout {
  readonly days: readonly ScheduleWeekDay[];
  /** The clock hours every row spans, as minutes after midnight. */
  readonly startMinute: number;
  readonly endMinute: number;
  /** Free working time left across the week. */
  readonly freeMinutes: number;

  constructor(
    now: Instant,
    dayCount: number,
    items: readonly ScheduleItem[],
    timeZone: string,
    preferences: SchedulePreferences = schedulePreferences(),
  ) {
    const first = startOfDay(now, timeZone);
    const midnights = Array.from({ length: Math.max(dayCount, 1) }, (_, offset) => addingDays(first, offset, timeZone));
    const lastMidnight = midnights.at(-1) ?? first;
    const last = addingDays(lastMidnight, 1, timeZone);
    const timed = items
      .filter((item) => !item.isAllDay && item.end > item.start && item.end > first && item.start < last)
      .sort(compareItems);
    const minuteOfDay = (instant: Instant) => {
      const wall = wallTime(instant, timeZone);
      return wall.hour * 60 + wall.minute;
    };
    let earliest = preferences.workdayStartMinute;
    let latest = preferences.workdayEndMinute;
    for (const item of timed) {
      const startDay = startOfDay(item.start, timeZone);
      earliest = Math.min(earliest, startDay < first ? 0 : minuteOfDay(item.start));
      /* Ending at or past the next midnight runs to the end of the day. */
      latest = Math.max(latest, startOfDay(item.end, timeZone) > startDay ? 24 * 60 : minuteOfDay(item.end));
    }
    const startMinute = Math.trunc(earliest / 60) * 60;
    let endMinute = Math.min(Math.trunc((latest + 59) / 60) * 60, 24 * 60);
    if (endMinute <= startMinute) endMinute = Math.min(startMinute + 60, 24 * 60);
    this.startMinute = startMinute;
    this.endMinute = endMinute;

    const events = timed.map(scheduleItemEvent);
    this.days = midnights.map((midnight) => {
      const rangeStart = clockTime(startMinute, midnight, timeZone);
      const range = { start: rangeStart, end: Math.max(clockTime(endMinute, midnight, timeZone), rangeStart) };
      const next = addingDays(midnight, 1, timeZone);
      const dayItems = timed.filter((item) => item.end > range.start && item.start < range.end);
      const free = scheduleFreeTime(midnight, now, events, timeZone, preferences);
      return {
        date: midnight,
        range,
        placed: placeScheduleItems(dayItems, range),
        allDay: items.filter((item) => item.isAllDay && item.end > midnight && item.start < next),
        freeMinutes: free.reduce((sum, gap) => sum + Math.trunc(intervalDuration(gap) / 60), 0),
        isToday: midnight === first,
      };
    });
    this.freeMinutes = this.days.reduce((sum, day) => sum + day.freeMinutes, 0);
  }

  /** Each whole hour inside the span, as minutes after midnight. */
  get hourMarks(): number[] {
    const marks: number[] = [];
    for (let minute = this.startMinute; minute <= this.endMinute; minute += 60) marks.push(minute);
    return marks;
  }

  /** Where a clock time (minutes after midnight) falls along every row. */
  positionOfMinute(minute: number): number {
    return (minute - this.startMinute) / Math.max(this.endMinute - this.startMinute, 1);
  }
}
