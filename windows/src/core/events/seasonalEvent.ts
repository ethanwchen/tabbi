import { ACTIVITY_KINDS, ACTIVITY_UNITS, type ActivityRecord } from "../activity/activityRecord";
import { wallTime } from "../calendar/zonedCalendar";
import type { PetLimitedProgress } from "../closet/petLimited";
import { tr } from "../localization/tr";
import type { PetItem } from "../pets/petItem";
import { addDays, startOfDay, type DayCalendar, type DayKey } from "../streaks/dayCalendar";
import type { Instant } from "../time";
import {
  eventDayIn,
  eventYearOf,
  localDay,
  type SeasonalEventCalendar,
  type SeasonalEventDay,
} from "./seasonalEventCalendar";

/*
 * Port of SeasonalEvent.swift: a seasonal event (a window of local days
 * that comes back every year, a short line of copy, and the limited items
 * earned by focusing while it runs), one year's run of it, and the focused
 * minutes logged during runs. Earned items stay owned after the event; an
 * item not earned in time can be earned when the event returns next year.
 *
 * Where the Mac takes a `Calendar`, these take an IANA zone name: an event
 * starts and ends at local midnight in it.
 */

/** Goals from this many minutes up read in hours (SeasonalEventProgress.hourLabelMinutes). */
export const HOUR_LABEL_MINUTES = 120;

/** An item an event offers, and the focused minutes during the event that earn it. Port of SeasonalEventReward. */
export interface SeasonalEventReward {
  readonly item: PetItem;
  readonly focusMinutes: number;
}

/** The goal as a short label in the same units as its progress: "90 min" or "5 h". */
export function rewardGoalLabel(reward: SeasonalEventReward): string {
  return reward.focusMinutes < HOUR_LABEL_MINUTES
    ? tr("%lld min", reward.focusMinutes)
    : tr("%lld h", Math.trunc(reward.focusMinutes / 60));
}

/** Port of SeasonalEvent. */
export interface SeasonalEvent {
  readonly id: string;
  /** English, as `events.json` writes it; `eventDisplayName` translates it. */
  readonly name: string;
  /** One gentle line for the Closet banner, in English like `name`. */
  readonly tagline: string;
  readonly calendar: SeasonalEventCalendar;
  /** The first day, from its local midnight. */
  readonly start: SeasonalEventDay;
  /** The last day, through its end. Earlier in the year than `start` when the event runs over New Year. */
  readonly end: SeasonalEventDay;
  /** The items to earn, cheapest first; the last one is the headline item. */
  readonly rewards: readonly SeasonalEventReward[];
}

/**
 * The name in the user's language. `events.json` holds the English, which
 * the catalog is keyed by; a name the catalog lacks shows as written.
 */
export function eventDisplayName(event: SeasonalEvent): string {
  return tr(event.name);
}

/** The tagline in the user's language, looked up like `eventDisplayName`. */
export function eventDisplayTagline(event: SeasonalEvent): string {
  return tr(event.tagline);
}

/** The event's headline item, the one with a subtle effect. */
export function eventHeadline(event: SeasonalEvent): PetItem | undefined {
  return event.rewards.at(-1)?.item;
}

/** One year's run of a `SeasonalEvent`, as absolute instants. Port of SeasonalEventOccurrence. */
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

/** A stable id for this year's run, such as `halloween-2026`, from the Gregorian year it starts in. */
export function occurrenceID(occurrence: SeasonalEventOccurrence, timeZone: string): string {
  return `${occurrence.event.id}-${wallTime(occurrence.start, timeZone).year}`;
}

export function sameOccurrence(a: SeasonalEventOccurrence, b: SeasonalEventOccurrence): boolean {
  return a.event.id === b.event.id && a.start === b.start && a.end === b.end;
}

function dayCalendar(timeZone: string): DayCalendar {
  return { timeZone, firstWeekday: 1 };
}

/* The run that starts on `startKey`, which is `event.start` in `year`. */
function occurrenceStarting(event: SeasonalEvent, startKey: DayKey, year: number, timeZone: string): SeasonalEventOccurrence | undefined {
  let lastDay = eventDayIn(event.calendar, event.end, year);
  if (lastDay === undefined || lastDay < startKey) lastDay = eventDayIn(event.calendar, event.end, year + 1);
  if (lastDay === undefined) return undefined;
  const calendar = dayCalendar(timeZone);
  return { event, start: startOfDay(startKey, calendar), end: startOfDay(addDays(lastDay, 1), calendar) };
}

/** The run of `event` that `instant` falls in, or undefined between runs. */
export function occurrenceContaining(event: SeasonalEvent, instant: Instant, timeZone: string): SeasonalEventOccurrence | undefined {
  const today = localDay(instant, timeZone);
  const year = eventYearOf(event.calendar, today);
  /* The latest start on or before today, then that run's end. */
  for (const candidate of [year, year - 1]) {
    const start = eventDayIn(event.calendar, event.start, candidate);
    if (start === undefined || start > today) continue;
    const occurrence = occurrenceStarting(event, start, candidate, timeZone);
    return occurrence && occurrenceContains(occurrence, instant) ? occurrence : undefined;
  }
  return undefined;
}

/** The next run of `event` that starts after `instant`. */
export function nextOccurrence(event: SeasonalEvent, instant: Instant, timeZone: string): SeasonalEventOccurrence | undefined {
  const year = eventYearOf(event.calendar, localDay(instant, timeZone));
  for (const candidate of [year, year + 1, year + 2]) {
    const start = eventDayIn(event.calendar, event.start, candidate);
    if (start === undefined || startOfDay(start, dayCalendar(timeZone)) <= instant) continue;
    return occurrenceStarting(event, start, candidate, timeZone);
  }
  return undefined;
}

/**
 * Port of SeasonalEventProgress: the focused minutes logged during one run
 * of an event, and what they earn. Any `focus.completed` record in minutes
 * that ended inside the run counts, and adding the same record twice counts
 * it once. A new run starts from zero, so an item missed one year can be
 * earned the next.
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
    const minutes = Math.trunc(this.focusMinutes);
    return this.occurrence.event.rewards.filter((reward) => minutes >= reward.focusMinutes).map((reward) => reward.item);
  }

  /** The first reward not reached yet, the one to show progress toward. */
  get nextReward(): SeasonalEventReward | undefined {
    const minutes = Math.trunc(this.focusMinutes);
    return this.occurrence.event.rewards.find((reward) => minutes < reward.focusMinutes);
  }

  /**
   * Progress toward `reward`, in whole minutes capped at its goal, with a
   * label in minutes under two hours ("45/90 min") and whole hours, rounded
   * down, above ("3/5 h"). The catalog keeps goals of two hours or more to
   * whole hours, so the label never shows a fraction.
   */
  progress(reward: SeasonalEventReward): PetLimitedProgress {
    const goal = reward.focusMinutes;
    const value = Math.max(0, Math.min(Math.trunc(this.focusMinutes), goal));
    const label =
      goal < HOUR_LABEL_MINUTES ? tr("%lld/%lld min", value, goal) : tr("%lld/%lld h", Math.trunc(value / 60), Math.trunc(goal / 60));
    return { value, goal, label };
  }
}

/** The part of the events catalog a tally reads (`SeasonalEventCatalog` has it). */
export interface SeasonalEventRuns {
  readonly events: readonly SeasonalEvent[];
  active(at: Instant, timeZone: string): SeasonalEventOccurrence[];
}

/**
 * Port of SeasonalEventTally: the focused minutes logged during every run
 * of every event in a catalog, kept per run. The Closet replays the whole
 * activity log into it on launch and then follows new records, so an item
 * is earned even when the run's focus time was logged while the Closet was
 * not watching, and a past run's earned items can be granted late.
 */
export class SeasonalEventTally {
  /** Each run with some focus logged, by its id (`halloween-2026`). */
  readonly runs = new Map<string, SeasonalEventProgress>();

  constructor(
    readonly catalog: SeasonalEventRuns,
    /** Decides which local days a record ends on. */
    readonly timeZone: string,
    records: Iterable<ActivityRecord> = [],
  ) {
    for (const record of records) this.add(record);
  }

  /** Counts `record` toward every run going on when it ended; adding the same record twice counts it once. */
  add(record: ActivityRecord): void {
    if (record.kind !== ACTIVITY_KINDS.focusCompleted) return;
    for (const occurrence of this.catalog.active(record.end, this.timeZone)) {
      const id = occurrenceID(occurrence, this.timeZone);
      let run = this.runs.get(id);
      if (!run) {
        run = new SeasonalEventProgress(occurrence);
        this.runs.set(id, run);
      }
      run.add(record);
    }
  }

  /** Every item some run has earned, in catalog order. */
  get earned(): PetItem[] {
    const items = new Set([...this.runs.values()].flatMap((run) => run.earned));
    return this.catalog.events.flatMap((event) => event.rewards.map((reward) => reward.item)).filter((item) => items.has(item));
  }

  /** The runs going on at `instant`, the one ending soonest first, each with the focus logged so far. */
  active(instant: Instant): SeasonalEventProgress[] {
    return this.catalog
      .active(instant, this.timeZone)
      .map((occurrence) => this.runs.get(occurrenceID(occurrence, this.timeZone)) ?? new SeasonalEventProgress(occurrence));
  }

  /** Progress toward `item` while its event runs at `instant`, for the Limited shelf; undefined between runs. */
  progress(item: PetItem, instant: Instant): PetLimitedProgress | undefined {
    for (const run of this.active(instant)) {
      const reward = run.occurrence.event.rewards.find((candidate) => candidate.item === item);
      if (reward) return run.progress(reward);
    }
    return undefined;
  }
}
