import { ACTIVITY_KINDS, ACTIVITY_UNITS, type ActivityRecord } from "../activity/activityRecord";
import { addingDays, instantOf, startOfDay, wallTime } from "../calendar/zonedCalendar";
import { chineseMidnight } from "./chineseCalendar";
import type { PetLimitedProgress } from "../closet/petLimited";
import { tr } from "../localization/tr";
import type { PetItem } from "../pets/petItem";
import type { Instant } from "../time";

/*
 * Port of SeasonalEvent.swift: a window of local days that comes back every
 * year, the items earnable by focusing while it runs, one run of it as
 * absolute instants, and the focus logged during a run. Days are read in an
 * IANA time zone passed in, so an event starts at local midnight wherever
 * the user is.
 */

/** The calendar an event's dates are written in. Port of SeasonalEventCalendar. */
export type SeasonalEventCalendar = "gregorian" | "chinese";

/** A month and day an event starts or ends on, the same every year in its calendar. Port of SeasonalEventDay. */
export interface SeasonalEventDay {
  readonly month: number;
  readonly day: number;
}

/** Goals from this many minutes up read in hours (SeasonalEventProgress.hourLabelMinutes). */
export const HOUR_LABEL_MINUTES = 120;

/** An item an event offers and the focused minutes during the event that earn it. Port of SeasonalEventReward. */
export interface SeasonalEventReward {
  readonly item: PetItem;
  readonly focusMinutes: number;
}

/** The goal as a short label, in the same units as its progress: "90 min" or "5 h". */
export function rewardGoalLabel(reward: SeasonalEventReward): string {
  return reward.focusMinutes < HOUR_LABEL_MINUTES
    ? tr("%lld min", reward.focusMinutes)
    : tr("%lld h", Math.trunc(reward.focusMinutes / 60));
}

/** A seasonal event, such as Halloween. Port of SeasonalEvent. */
export interface SeasonalEvent {
  readonly id: string;
  /** The English name, which is also its catalog key. */
  readonly name: string;
  readonly tagline: string;
  readonly calendar: SeasonalEventCalendar;
  /** The first day, from its local midnight. */
  readonly start: SeasonalEventDay;
  /** The last day, through its end; earlier in the year than `start` when the event runs over New Year. */
  readonly end: SeasonalEventDay;
  /** The items to earn, cheapest first; the last one is the headline item. */
  readonly rewards: readonly SeasonalEventReward[];
}

/** The name in the user's language, looked up by its English text. */
export function eventDisplayName(event: SeasonalEvent): string {
  return tr(event.name);
}

/** The tagline in the user's language, looked up like the name. */
export function eventDisplayTagline(event: SeasonalEvent): string {
  return tr(event.tagline);
}

/** The event's headline item, the one with a subtle effect. */
export function eventHeadline(event: SeasonalEvent): PetItem | undefined {
  return event.rewards.at(-1)?.item;
}

/** One year's run of an event. Port of SeasonalEventOccurrence. */
export interface SeasonalEventOccurrence {
  readonly event: SeasonalEvent;
  /** Local midnight of the first day. */
  readonly start: Instant;
  /** Local midnight after the last day; not part of the run. */
  readonly end: Instant;
}

export function occurrenceContains(occurrence: SeasonalEventOccurrence, instant: Instant): boolean {
  return occurrence.start <= instant && instant < occurrence.end;
}

/** A stable id for this year's run, such as `halloween-2026`, from the Gregorian year it starts in `timeZone`. */
export function occurrenceID(occurrence: SeasonalEventOccurrence, timeZone: string): string {
  return `${occurrence.event.id}-${wallTime(occurrence.start, timeZone).year}`;
}

/**
 * The first local midnight on `day` strictly after `after` (or, `backward`,
 * the last one strictly before it), like Foundation's
 * `nextDate(after:matching:matchingPolicy: .nextTime)` for a month, a day
 * and 00:00:00. A skipped midnight becomes the first moment of the day.
 */
function nextMidnight(
  calendar: SeasonalEventCalendar,
  day: SeasonalEventDay,
  after: Instant,
  timeZone: string,
  backward = false,
): Instant | undefined {
  if (calendar === "gregorian") {
    const year = wallTime(after, timeZone).year;
    const years = backward ? [year + 1, year, year - 1, year - 2] : [year - 1, year, year + 1, year + 2];
    for (const candidateYear of years) {
      const candidate = instantOf({ year: candidateYear, month: day.month, day: day.day }, timeZone);
      if (backward ? candidate < after : candidate > after) return candidate;
    }
    return undefined;
  }
  return chineseMidnight(day.month, day.day, after, timeZone, backward);
}

/** The run that starts at `start`: its end is the midnight after the first matching last day. */
function occurrenceStartingAt(event: SeasonalEvent, start: Instant, timeZone: string): SeasonalEventOccurrence | undefined {
  const lastDay = nextMidnight(event.calendar, event.end, start - 1, timeZone);
  if (lastDay === undefined) return undefined;
  return { event, start, end: startOfDay(addingDays(lastDay, 1, timeZone), timeZone) };
}

/** The run of `event` that `instant` falls in, or undefined between runs. */
export function occurrenceContaining(
  event: SeasonalEvent,
  instant: Instant,
  timeZone: string,
): SeasonalEventOccurrence | undefined {
  /* The latest start at or before the moment, then that run's end. */
  const start = nextMidnight(event.calendar, event.start, instant + 1, timeZone, true);
  if (start === undefined) return undefined;
  const occurrence = occurrenceStartingAt(event, start, timeZone);
  return occurrence && occurrenceContains(occurrence, instant) ? occurrence : undefined;
}

/** The next run of `event` that starts after `instant`. */
export function nextOccurrence(event: SeasonalEvent, instant: Instant, timeZone: string): SeasonalEventOccurrence | undefined {
  const start = nextMidnight(event.calendar, event.start, instant, timeZone);
  return start === undefined ? undefined : occurrenceStartingAt(event, start, timeZone);
}

/**
 * The focused minutes logged during one run of an event: any
 * `focus.completed` record in minutes that ended inside the run, each id
 * once. Port of SeasonalEventProgress.
 */
export class SeasonalEventProgress {
  focusMinutes = 0;
  private readonly seen = new Set<string>();

  constructor(
    readonly occurrence: SeasonalEventOccurrence,
    records: Iterable<ActivityRecord> = [],
  ) {
    for (const record of records) this.add(record);
  }

  add(record: ActivityRecord): void {
    const quantity = record.quantity;
    if (record.kind !== ACTIVITY_KINDS.focusCompleted || record.unit !== ACTIVITY_UNITS.minutes) return;
    if (quantity === undefined || !Number.isFinite(quantity) || !(quantity > 0)) return;
    if (!occurrenceContains(this.occurrence, record.end) || this.seen.has(record.id)) return;
    this.seen.add(record.id);
    this.focusMinutes += quantity;
  }

  /** The rewards whose minutes this run has reached, in event order. */
  get earned(): PetItem[] {
    return this.occurrence.event.rewards
      .filter((reward) => Math.trunc(this.focusMinutes) >= reward.focusMinutes)
      .map((reward) => reward.item);
  }

  /** The first reward not reached yet, the one to show progress toward. */
  get nextReward(): SeasonalEventReward | undefined {
    return this.occurrence.event.rewards.find((reward) => Math.trunc(this.focusMinutes) < reward.focusMinutes);
  }

  /** Progress toward `reward` in whole minutes capped at its goal: "45/90 min" under two hours, "3/5 h" (rounded down) above. */
  progress(reward: SeasonalEventReward): PetLimitedProgress {
    const goal = reward.focusMinutes;
    const value = Math.max(0, Math.min(Math.trunc(this.focusMinutes), goal));
    const label =
      goal < HOUR_LABEL_MINUTES
        ? tr("%lld/%lld min", value, goal)
        : tr("%lld/%lld h", Math.trunc(value / 60), Math.trunc(goal / 60));
    return { value, goal, label };
  }
}
