import type { Instant } from "../time";
import { detectMeetingLink } from "../planner/meetingLink";
import { upcomingEvent, type EventColor, type UpcomingEvent } from "../planner/upcomingEvent";
import { parseComponents, properties, property, unescapeText, type IcsComponent } from "./icsLexer";
import { expandRecurrence, parseRecurrenceRule, type RecurrenceRule } from "./icsRecurrence";
import {
  ianaZone,
  parseDuration,
  propertyDates,
  resolveTZID,
  UTC_ZONE,
  wallSeconds,
  type EventZone,
  type IcsDate,
  type IcsDateValue,
  type IcsDuration,
  type IcsWall,
} from "./icsTime";

/*
 * Reads an ICS subscription feed (RFC 5545), the calendar Windows reads
 * in place of the Mac's EventKit: Google Calendar's secret address, an
 * Outlook or Microsoft 365 published calendar, an iCloud public calendar.
 *
 * `parseICS` keeps the feed's events as written; `eventsInRange` expands
 * recurrences and turns them into the UpcomingEvents Today and the Schedule
 * show. Neither ever throws: a feed that isn't one has no events, and an
 * event that can't be read is skipped on its own.
 */

/** One VEVENT as written in the feed. */
export interface IcsEvent {
  readonly uid: string;
  readonly summary: string;
  readonly location?: string;
  readonly description?: string;
  /** Candidate join URLs: URL, then the conference properties Google and Microsoft add. */
  readonly urls: readonly string[];
  readonly cancelled: boolean;
  readonly start: IcsDateValue;
  readonly end?: IcsDateValue;
  readonly duration?: IcsDuration;
  readonly rule?: RecurrenceRule;
  readonly exceptions: readonly IcsDateValue[];
  readonly extraDates: readonly IcsDateValue[];
  /** Set on an override of one occurrence of a recurring event. */
  readonly recurrenceID?: IcsDateValue;
}

/** A feed: its events and the zones it defines. */
export interface IcsCalendar {
  /** `X-WR-CALNAME`, the name the feed gives itself. */
  readonly name?: string;
  readonly events: readonly IcsEvent[];
  readonly timeZones: ReadonlyMap<string, IcsComponent>;
}

/** Most occurrences one event yields in a range, and most periods its rule is followed for. */
export const MAX_INSTANCES_PER_EVENT = 1000;
export const MAX_RECURRENCE_PERIODS = 20_000;

function readEvent(component: IcsComponent, index: number): IcsEvent | undefined {
  const startProperty = property(component, "DTSTART");
  if (startProperty === undefined) return undefined;
  const start = propertyDates(startProperty)[0];
  if (start === undefined) return undefined;
  const text = (name: string) => {
    const value = property(component, name)?.value;
    return value === undefined ? undefined : unescapeText(value);
  };
  const endProperty = property(component, "DTEND");
  const end = endProperty === undefined ? undefined : propertyDates(endProperty)[0];
  const durationText = property(component, "DURATION")?.value;
  const duration = durationText === undefined ? undefined : parseDuration(durationText);
  const ruleText = property(component, "RRULE")?.value;
  const rule = ruleText === undefined ? undefined : parseRecurrenceRule(ruleText);
  const recurrenceProperty = property(component, "RECURRENCE-ID");
  const recurrenceID = recurrenceProperty === undefined ? undefined : propertyDates(recurrenceProperty)[0];
  const urls = ["URL", "X-GOOGLE-CONFERENCE", "X-MICROSOFT-SKYPETEAMSMEETINGURL", "X-MICROSOFT-ONLINEMEETINGEXTERNALLINK"]
    .map((name) => property(component, name)?.value.trim())
    .filter((value): value is string => value !== undefined && value !== "");
  const event: { -readonly [Key in keyof IcsEvent]: IcsEvent[Key] } = {
    uid: property(component, "UID")?.value.trim() || `event-${index}`,
    summary: text("SUMMARY") ?? "",
    urls,
    cancelled: property(component, "STATUS")?.value.trim().toUpperCase() === "CANCELLED",
    start,
    exceptions: properties(component, "EXDATE").flatMap(propertyDates),
    extraDates: properties(component, "RDATE").flatMap(propertyDates),
  };
  const location = text("LOCATION");
  const description = text("DESCRIPTION");
  if (location !== undefined) event.location = location;
  if (description !== undefined) event.description = description;
  if (end !== undefined) event.end = end;
  if (duration !== undefined) event.duration = duration;
  if (rule !== undefined) event.rule = rule;
  if (recurrenceID !== undefined) event.recurrenceID = recurrenceID;
  return event;
}

/** Reads a feed. Never throws; text that isn't iCalendar gives a calendar with no events. */
export function parseICS(text: string): IcsCalendar {
  try {
    const root = parseComponents(text);
    const all: IcsComponent[] = [];
    const collect = (component: IcsComponent) => {
      for (const child of component.components) {
        all.push(child);
        if (child.name === "VCALENDAR") collect(child);
      }
    };
    collect(root);
    const timeZones = new Map<string, IcsComponent>();
    for (const component of all) {
      const id = component.name === "VTIMEZONE" ? property(component, "TZID")?.value.trim().replace(/^"|"$/g, "") : undefined;
      if (id !== undefined && !timeZones.has(id)) timeZones.set(id, component);
    }
    const events: IcsEvent[] = [];
    all.forEach((component, index) => {
      if (component.name !== "VEVENT") return;
      try {
        const event = readEvent(component, index);
        if (event !== undefined) events.push(event);
      } catch {
        /* A broken event is skipped on its own. */
      }
    });
    const name = all.map((component) => property(component, "X-WR-CALNAME")?.value).find((value) => value !== undefined);
    return name === undefined ? { events, timeZones } : { name: unescapeText(name), events, timeZones };
  } catch {
    return { events: [], timeZones: new Map() };
  }
}

export interface RangeOptions {
  readonly from: Instant;
  readonly to: Instant;
  /** The user's IANA zone: all-day dates and floating times are read in it. */
  readonly timeZone: string;
  readonly calendarColor?: EventColor;
  /** Put in front of every event id (`<prefix>/<uid>`), so two calendars never share one. */
  readonly idPrefix?: string;
}

/* The zone a value's local time is read in. */
function zoneFor(value: IcsDateValue, calendar: IcsCalendar, userZone: EventZone): EventZone {
  if (value.kind === "date") return userZone;
  if (value.utc) return UTC_ZONE;
  if (value.tzid !== undefined) return resolveTZID(value.tzid, calendar.timeZones) ?? userZone;
  return userZone;
}

function wallOf(value: IcsDateValue): IcsWall {
  return value.kind === "date" ? { ...value.date, hour: 0, minute: 0, second: 0 } : value.wall;
}

function dateKey(date: IcsDate): string {
  return `${String(date.year).padStart(4, "0")}${String(date.month).padStart(2, "0")}${String(date.day).padStart(2, "0")}`;
}

/* The key an occurrence is known by: its instant, or its local date for a DATE value. */
function occurrenceKeys(value: IcsDateValue, zone: EventZone): string[] {
  if (value.kind === "date") return [`D${dateKey(value.date)}`];
  return [`T${zone.instant(value.wall)}`];
}

interface Occurrence {
  readonly start: Instant;
  readonly end: Instant;
  readonly key: string;
}

/* The end of an occurrence starting at local `wall`. */
function endFor(event: IcsEvent, wall: IcsWall, start: Instant, zone: EventZone, calendar: IcsCalendar, userZone: EventZone): Instant {
  if (event.start.kind === "date") {
    const days =
      event.end?.kind === "date"
        ? Math.round((wallSeconds(event.end.date) - wallSeconds(event.start.date)) / 86_400)
        : event.duration !== undefined
          ? event.duration.days + Math.ceil(event.duration.seconds / 86_400)
          : 1;
    return zone.instant({ year: wall.year, month: wall.month, day: wall.day + Math.max(days, 1) });
  }
  if (event.end !== undefined) {
    const endZone = zoneFor(event.end, calendar, userZone);
    const firstStart = zone.instant(wallOf(event.start));
    const firstEnd = endZone.instant(wallOf(event.end));
    return start + Math.max(firstEnd - firstStart, 0);
  }
  if (event.duration !== undefined) {
    const days = zone.instant({ ...wall, day: wall.day + event.duration.days });
    return Math.max(days + event.duration.seconds, start);
  }
  return start;
}

/* Every occurrence of `event` that could touch the range, with the keys overrides and EXDATEs use. */
function occurrences(event: IcsEvent, calendar: IcsCalendar, options: RangeOptions, userZone: EventZone): Occurrence[] {
  const zone = zoneFor(event.start, calendar, userZone);
  const first = wallOf(event.start);
  const make = (wall: IcsWall): Occurrence => {
    const start = zone.instant(wall);
    const value: IcsDateValue = event.start.kind === "date" ? { kind: "date", date: wall } : { kind: "dateTime", wall, utc: false };
    return { start, end: endFor(event, wall, start, zone, calendar, userZone), key: occurrenceKeys(value, zone)[0] ?? "" };
  };
  if (event.rule === undefined && event.extraDates.length === 0) return [make(first)];
  const firstOccurrence = make(first);
  const length = Math.max(firstOccurrence.end - firstOccurrence.start, 0);
  const margin = 2 * 86_400;
  const localFrom = wallSeconds(zone.wall(options.from)) - length - margin;
  const localTo = wallSeconds(zone.wall(options.to)) + margin;
  const rule = event.rule;
  const until = rule?.until;
  const withinUntil = (wall: IcsWall): boolean => {
    if (until === undefined) return true;
    if (until.kind === "date") return dateKey(wall) <= dateKey(until.date);
    if (until.utc) return zone.instant(wall) <= UTC_ZONE.instant(until.wall);
    return wallSeconds(wall) <= wallSeconds(until.wall);
  };
  const walls =
    rule === undefined
      ? [first]
      : expandRecurrence(rule, first, {
          from: localFrom,
          to: localTo,
          withinUntil,
          maxInstances: MAX_INSTANCES_PER_EVENT,
          maxPeriods: MAX_RECURRENCE_PERIODS,
        });
  const extra = event.extraDates.map((value) => (value.kind === "date" ? { ...value.date, hour: first.hour, minute: first.minute, second: first.second } : value.wall));
  const seen = new Set<number>();
  const result: Occurrence[] = [];
  for (const wall of [...walls, ...extra]) {
    const seconds = wallSeconds(wall);
    if (seen.has(seconds)) continue;
    seen.add(seconds);
    result.push(make(wall));
  }
  return result.sort((a, b) => a.start - b.start).slice(0, MAX_INSTANCES_PER_EVENT);
}

function overlaps(start: Instant, end: Instant, from: Instant, to: Instant): boolean {
  return end > start ? start < to && end > from : start >= from && start < to;
}

/** The events of `calendar` that touch `[from, to)`, recurrences expanded, sorted by start. Never throws. */
export function eventsInRange(calendar: IcsCalendar, options: RangeOptions): UpcomingEvent[] {
  let userZone: EventZone;
  try {
    userZone = ianaZone(options.timeZone);
    userZone.wall(options.from);
  } catch {
    userZone = UTC_ZONE;
  }
  const prefix = options.idPrefix === undefined || options.idPrefix === "" ? "" : `${options.idPrefix}/`;
  const overridden = new Map<string, Set<string>>();
  for (const event of calendar.events) {
    if (event.recurrenceID === undefined) continue;
    try {
      const keys = occurrenceKeys(event.recurrenceID, zoneFor(event.recurrenceID, calendar, userZone));
      const set = overridden.get(event.uid) ?? new Set<string>();
      for (const key of keys) set.add(key);
      overridden.set(event.uid, set);
    } catch {
      /* An unreadable override leaves the occurrence as the series has it. */
    }
  }
  const result: UpcomingEvent[] = [];
  const ids = new Set<string>();
  const add = (event: IcsEvent, occurrence: Occurrence, id: string) => {
    if (ids.has(id) || !overlaps(occurrence.start, occurrence.end, options.from, options.to)) return;
    ids.add(id);
    const link = detectMeetingLink({
      ...(event.urls[0] === undefined ? {} : { url: event.urls[0] }),
      ...(event.location === undefined ? {} : { location: event.location }),
      notes: [...event.urls.slice(1), event.description ?? ""].join("\n"),
    });
    result.push(
      upcomingEvent({
        id,
        title: event.summary,
        start: occurrence.start,
        end: Math.max(occurrence.end, occurrence.start),
        isAllDay: event.start.kind === "date",
        calendarColor: options.calendarColor,
        meetingLink: link,
      }),
    );
  };
  for (const event of calendar.events) {
    try {
      if (event.cancelled) continue;
      if (event.recurrenceID !== undefined) {
        const zone = zoneFor(event.start, calendar, userZone);
        const wall = wallOf(event.start);
        const start = zone.instant(wall);
        const originalKey = occurrenceKeys(event.recurrenceID, zoneFor(event.recurrenceID, calendar, userZone))[0] ?? "";
        add(event, { start, end: endFor(event, wall, start, zone, calendar, userZone), key: originalKey }, `${prefix}${event.uid}#${originalKey}`);
        continue;
      }
      const isSeries = event.rule !== undefined || event.extraDates.length > 0;
      const zone = zoneFor(event.start, calendar, userZone);
      const excluded = new Set(event.exceptions.flatMap((value) => occurrenceKeys(value, zoneFor(value, calendar, userZone))));
      const overrides = overridden.get(event.uid);
      for (const occurrence of occurrences(event, calendar, options, userZone)) {
        const localDate = `D${dateKey(zone.wall(occurrence.start))}`;
        const keys = event.start.kind === "date" ? [occurrence.key] : [occurrence.key, localDate];
        if (keys.some((key) => excluded.has(key))) continue;
        if (overrides !== undefined && keys.some((key) => overrides.has(key))) continue;
        add(event, occurrence, isSeries ? `${prefix}${event.uid}#${occurrence.key}` : `${prefix}${event.uid}`);
      }
    } catch {
      /* One unreadable event never hides the rest. */
    }
  }
  return result.sort((a, b) => a.start - b.start || a.end - b.end || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

/** Parses `text` and lists its events in a range, in one step. */
export function icsEvents(text: string, options: RangeOptions): UpcomingEvent[] {
  return eventsInRange(parseICS(text), options);
}
