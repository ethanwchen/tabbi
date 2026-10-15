import type { UpcomingEvent } from "../planner/upcomingEvent";
import type { Instant, Seconds } from "../time";
import type { TickerSources } from "./tickerSources";

/* Seconds from 1970 to 2001, the Mac's reference date, which its nudge keys count from. */
const REFERENCE_DATE_OFFSET = 978_307_200;

/* A Double as Swift's description writes it in this range: "12.5", or "12.0" for a whole number. */
function swiftDouble(value: number): string {
  return Number.isInteger(value) ? `${value}.0` : String(value);
}

/**
 * Port of MeetingNudge: the "leave now" moment before a meeting. When one
 * comes within the pin lead (about five minutes), the closed island's
 * meeting preview glows gently for `duration`, with a Join button when the
 * event has a call. A value, like PetCheer, so the ticker can tell when it
 * is over without a timer of its own.
 */
export class MeetingNudge {
  /** Long enough for a few soft breaths, short enough to stay polite. */
  static readonly duration: Seconds = 4;

  constructor(
    /** The meeting it is for (`MeetingNudgeWatch.key`). */
    readonly key: string,
    readonly startedAt: Instant,
  ) {}

  get endsAt(): Instant {
    return this.startedAt + MeetingNudge.duration;
  }

  /** Whether the glow is on screen at `date`; a clock set back before the start shows nothing. */
  isShowing(date: Instant): boolean {
    return date >= this.startedAt && date < this.endsAt;
  }
}

/**
 * Port of MeetingNudgeWatch: remembers which meetings already had their
 * nudge, so each meeting pulses at most once, however often the ticker
 * refreshes or the island opens and closes. A moved meeting is a new one and
 * gets a nudge of its own.
 */
export class MeetingNudgeWatch {
  /** Each nudged meeting's key and start, dropped once it has started. */
  private nudged = new Map<string, Instant>();

  /** The meeting's identity for nudging: its event and its start, so rescheduling it counts as a new meeting. */
  static key(event: UpcomingEvent): string {
    return `${event.id}@${swiftDouble(event.start - REFERENCE_DATE_OFFSET)}`;
  }

  /**
   * Starts the nudge for `sources`' imminent meeting at `now` and records it,
   * or returns undefined: no meeting starts within the lead time, or this
   * one already had its nudge.
   */
  nudge(sources: TickerSources, now: Instant): MeetingNudge | undefined {
    for (const [key, start] of this.nudged) if (!(start > now)) this.nudged.delete(key);
    const event = sources.imminentMeeting(now);
    if (event === undefined) return undefined;
    const key = MeetingNudgeWatch.key(event);
    if (this.nudged.has(key)) return undefined;
    this.nudged.set(key, event.start);
    return new MeetingNudge(key, now);
  }
}
