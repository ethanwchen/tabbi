import { durationCountdown } from "../formatting/durationFormat";
import { tr } from "../localization/tr";
import type { Instant } from "../time";

/*
 * The calendar event as the providers and the ticker read it: the fields of
 * the Mac's UpcomingEvent (Planner/UpcomingEvent.swift) that ModuleProvision,
 * ProviderSnapshot and TickerSources touch, and the few UpcomingEvent helpers
 * the ticker calls (upNext, timing, UpcomingEventFormat's badge and title).
 *
 * Structural on purpose: the planner port owns UpcomingEvent, and its type
 * fits here as is. Once both are merged, this file should re-export the
 * planner's UpcomingEvent, EventTiming and helpers instead of declaring them.
 */

/** Port of MeetingLink's fields: a video call found in an event. */
export interface ProvidedMeetingLink {
  /** `zoom`, `googleMeet` or `teams`. */
  readonly provider: string;
  readonly url: string;
}

/** The fields of the Mac's UpcomingEvent that providers and the ticker read. */
export interface ProvidedEvent {
  /** The calendar's own identifier, so two modules reading one calendar list a meeting once. */
  readonly id: string;
  readonly title: string;
  readonly start: Instant;
  readonly end: Instant;
  readonly isAllDay: boolean;
  /** The call to join, when the event carries one. */
  readonly meetingLink?: ProvidedMeetingLink | undefined;
}

/** Port of EventTiming: where an event stands relative to now. */
export type EventTiming =
  /** Under way right now. */
  | { readonly kind: "now" }
  /** Starts in this many whole minutes (rounded up, at least 1). */
  | { readonly kind: "startsIn"; readonly minutes: number };

/* Swift's tuple ordering on (start, end, title, id). */
function compareEvents(a: ProvidedEvent, b: ProvidedEvent): number {
  if (a.start !== b.start) return a.start < b.start ? -1 : 1;
  if (a.end !== b.end) return a.end < b.end ? -1 : 1;
  if (a.title !== b.title) return a.title < b.title ? -1 : 1;
  if (a.id !== b.id) return a.id < b.id ? -1 : 1;
  return 0;
}

/**
 * Port of UpcomingEvent.upNext(from:at:limit:): timed events that haven't
 * ended yet, soonest first, capped at `limit`. All-day events have no "next"
 * moment, so they never show.
 */
export function upNextEvents<Event extends ProvidedEvent>(events: readonly Event[], now: Instant, limit = 3): Event[] {
  return events
    .filter((event) => !event.isAllDay && event.end > now)
    .sort(compareEvents)
    .slice(0, Math.max(limit, 0));
}

/** Port of UpcomingEvent.timing(at:). */
export function eventTiming(event: ProvidedEvent, now: Instant): EventTiming {
  if (event.start <= now) return { kind: "now" };
  const minutes = Math.ceil((event.start - now) / 60);
  return { kind: "startsIn", minutes: Math.max(minutes, 1) };
}

/** Port of UpcomingEventFormat.badge: "now", "in 12 min", "in 1h", "in 2h 5m". */
export function eventBadge(timing: EventTiming): string {
  return timing.kind === "now" ? tr("now") : durationCountdown(timing.minutes);
}

/** Port of UpcomingEventFormat.title: an empty title (a quick add) still reads as something. */
export function eventTitle(event: ProvidedEvent): string {
  const trimmed = event.title.trim();
  return trimmed === "" ? tr("Untitled event") : trimmed;
}
