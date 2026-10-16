import type { Instant } from "../time";
import { tr } from "../localization/tr";
import { durationCountdown, durationMinutes } from "../formatting/durationFormat";
import { wallTime } from "../calendar/zonedCalendar";
import type { MeetingLink } from "./meetingLink";

/** Port of EventColor: a calendar color as plain sRGB components, 0 to 1. */
export interface EventColor {
  readonly red: number;
  readonly green: number;
  readonly blue: number;
}

/**
 * Port of UpcomingEvent: one calendar event as Today's Up next card, the
 * planners and the Schedule see it. Calendar sources (ICS feeds, demo data)
 * map their events into this value so selection and badges are testable.
 */
export interface UpcomingEvent {
  readonly id: string;
  readonly title: string;
  readonly start: Instant;
  readonly end: Instant;
  readonly isAllDay: boolean;
  readonly calendarColor?: EventColor;
  /** Video call to join, found by `detectMeetingLink` in the event's fields. */
  readonly meetingLink?: MeetingLink;
}

/** Builds an event with the Swift initializer's defaults. */
export function upcomingEvent(input: {
  id: string;
  title: string;
  start: Instant;
  end: Instant;
  isAllDay?: boolean;
  calendarColor?: EventColor | undefined;
  meetingLink?: MeetingLink | undefined;
}): UpcomingEvent {
  const event: { -readonly [Key in keyof UpcomingEvent]: UpcomingEvent[Key] } = {
    id: input.id,
    title: input.title,
    start: input.start,
    end: input.end,
    isAllDay: input.isAllDay ?? false,
  };
  if (input.calendarColor !== undefined) event.calendarColor = input.calendarColor;
  if (input.meetingLink !== undefined) event.meetingLink = input.meetingLink;
  return event;
}

/** Whether the event is under way at `now` (started, not yet ended). */
export function isInProgress(event: UpcomingEvent, now: Instant): boolean {
  return event.start <= now && now < event.end;
}

function compareText(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/* Start, end, title, id: the order Up next and the agenda list events in. */
function compareEvents(a: UpcomingEvent, b: UpcomingEvent): number {
  return a.start - b.start || a.end - b.end || compareText(a.title, b.title) || compareText(a.id, b.id);
}

/**
 * The events worth showing under Up next: timed events that haven't ended,
 * soonest first, at most `limit`. All-day events have no "next" moment and
 * would push real meetings off a three-row card.
 */
export function upNext(events: readonly UpcomingEvent[], now: Instant, limit = 3): UpcomingEvent[] {
  return events
    .filter((event) => !event.isAllDay && event.end > now)
    .sort(compareEvents)
    .slice(0, Math.max(limit, 0));
}

/** Every timed event of a whole day looked back on or planned ahead, earliest first, at most `limit`. */
export function agenda(events: readonly UpcomingEvent[], limit = 3): UpcomingEvent[] {
  return events
    .filter((event) => !event.isAllDay)
    .sort(compareEvents)
    .slice(0, Math.max(limit, 0));
}

/** Port of EventTiming: where an event stands relative to now, for the row badge. */
export type EventTiming = { readonly kind: "now" } | { readonly kind: "startsIn"; readonly minutes: number };

export function eventTiming(event: UpcomingEvent, now: Instant): EventTiming {
  if (event.start <= now) return { kind: "now" };
  return { kind: "startsIn", minutes: Math.max(Math.ceil((event.start - now) / 60), 1) };
}

/** Badge text: "now", "in 12 min", "in 1h", "in 2h 5m". */
export function eventBadge(timing: EventTiming): string {
  return timing.kind === "now" ? tr("now") : durationCountdown(timing.minutes);
}

const clockFormats = new Map<string, Intl.DateTimeFormat>();

/* A formatter for `locale`'s clock style: "9:30" in 12-hour locales, "09:30" in 24-hour ones. */
function clockFormat(locale: string, timeZone: string): Intl.DateTimeFormat {
  const key = `${locale}|${timeZone}`;
  let cached = clockFormats.get(key);
  if (!cached) {
    let uses12Hour = false;
    try {
      const cycle = new Intl.DateTimeFormat(locale, { hour: "numeric" }).resolvedOptions().hourCycle;
      uses12Hour = cycle === "h12" || cycle === "h11";
    } catch {
      /* An unknown locale keeps the 24-hour form. */
    }
    cached = new Intl.DateTimeFormat(locale, {
      timeZone,
      hour: uses12Hour ? "numeric" : "2-digit",
      minute: "2-digit",
      hourCycle: uses12Hour ? "h12" : "h23",
    });
    clockFormats.set(key, cached);
  }
  return cached;
}

/**
 * Start time in the user's clock style, "9:30" or "21:30". The AM/PM marker
 * is dropped because a same-day list reads fine without it and the row is
 * narrow; 24-hour locales keep their format.
 */
export function eventStartTime(instant: Instant, locale: string, timeZone: string): string {
  try {
    const parts = clockFormat(locale, timeZone).formatToParts(new Date(Math.floor(instant) * 1000));
    const hour = parts.find((part) => part.type === "hour")?.value;
    const minute = parts.find((part) => part.type === "minute")?.value;
    if (hour !== undefined && minute !== undefined) return `${hour}:${minute}`;
  } catch {
    /* An unknown locale falls through to the plain 24-hour form. */
  }
  const wall = wallTime(instant, timeZone);
  return `${String(wall.hour).padStart(2, "0")}:${String(wall.minute).padStart(2, "0")}`;
}

/** How long the event runs ("30 min", "1h 30m"), which rows for another day show. */
export function eventLength(event: UpcomingEvent): string {
  return durationMinutes(roundHalfAwayFromZero((event.end - event.start) / 60));
}

/** Empty-title events (common for quick-adds) still need a readable row. */
export function eventTitle(event: UpcomingEvent): string {
  const trimmed = event.title.trim();
  return trimmed === "" ? tr("Untitled event") : trimmed;
}

/** Swift's `rounded()`: halves away from zero. */
export function roundHalfAwayFromZero(value: number): number {
  return Math.sign(value) * Math.round(Math.abs(value));
}
