import eventsFile from "@mac/Events/events.json";
import type { ActivityRecord } from "../activity/activityRecord";
import { ACTIVITY_KINDS } from "../activity/activityRecord";
import { PET_LIMITED_EDITIONS, editionItem, type PetLimitedProgress } from "../closet/petLimited";
import { itemFromID, type PetItem } from "../pets/petItem";
import type { Instant } from "../time";
import {
  HOUR_LABEL_MINUTES,
  SeasonalEventProgress,
  nextOccurrence,
  occurrenceContaining,
  occurrenceID,
  type SeasonalEvent,
  type SeasonalEventCalendar,
  type SeasonalEventDay,
  type SeasonalEventOccurrence,
  type SeasonalEventReward,
} from "./seasonalEvent";

/*
 * Port of SeasonalEventCatalog.swift, PetLimitedShelf.swift and
 * SeasonalEventTally: the year of seasonal events read from the Mac's
 * `events.json` (an `events.v1` file), which runs go on at a moment, the
 * Limited section's shelves, and the focus logged per run.
 */

/** Why an events file was refused. Port of SeasonalEventCatalog.LoadError. */
export class SeasonalEventCatalogError extends Error {}

const SCHEMA_NAME = "events.v1";
const ID_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const SHORTEST_MONTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

/** Whether every year has `day`: up to the shortest length its month can have (29 for any Chinese month). */
function isValidDay(day: SeasonalEventDay, calendar: SeasonalEventCalendar): boolean {
  if (!Number.isInteger(day.month) || !Number.isInteger(day.day) || day.month < 1 || day.month > 12 || day.day < 1) {
    return false;
  }
  return day.day <= (calendar === "gregorian" ? (SHORTEST_MONTHS[day.month - 1] ?? 0) : 29);
}

function record(value: unknown, path: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new SeasonalEventCatalogError(`${path}: must be an object`);
  }
  return value as Record<string, unknown>;
}

function text(value: unknown, path: string): string {
  if (typeof value !== "string") throw new SeasonalEventCatalogError(`${path}: must be a string`);
  return value;
}

function integer(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) throw new SeasonalEventCatalogError(`${path}: must be a whole number`);
  return value;
}

function list(value: unknown, path: string): unknown[] {
  if (!Array.isArray(value)) throw new SeasonalEventCatalogError(`${path}: must be a list`);
  return value;
}

function eventDay(value: unknown, path: string): SeasonalEventDay {
  const object = record(value, path);
  return { month: integer(object.month, `${path}.month`), day: integer(object.day, `${path}.day`) };
}

export class SeasonalEventCatalog {
  static readonly schemaName = SCHEMA_NAME;

  /** Every event, in file order. */
  constructor(readonly events: readonly SeasonalEvent[]) {}

  /**
   * Parses and checks a file: its schema, unique ids, real dates, a name and
   * tagline, and at least one known item per event, each offered by one
   * event only, with goals that rise through the event and read cleanly.
   */
  static decode(raw: unknown): SeasonalEventCatalog {
    const file = record(raw, "the top level");
    const schema = text(file.schema, "schema");
    if (schema !== SCHEMA_NAME) {
      throw new SeasonalEventCatalogError(`Unsupported schema "${schema}"; expected "${SCHEMA_NAME}"`);
    }
    const require = (condition: boolean, path: string, reason: string) => {
      if (!condition) throw new SeasonalEventCatalogError(`${path}: ${reason}`);
    };
    const ids = new Set<string>();
    const offered = new Set<PetItem>();
    const events = list(file.events, "events").map((value, index): SeasonalEvent => {
      const path = `events[${index}]`;
      const entry = record(value, path);
      const id = text(entry.id, `${path}.id`);
      const name = text(entry.name, `${path}.name`);
      const tagline = text(entry.tagline, `${path}.tagline`);
      const calendarValue = text(entry.calendar, `${path}.calendar`);
      if (calendarValue !== "gregorian" && calendarValue !== "chinese") {
        throw new SeasonalEventCatalogError(`${path}.calendar: unknown calendar "${calendarValue}"`);
      }
      const calendar: SeasonalEventCalendar = calendarValue;
      const start = eventDay(entry.start, `${path}.start`);
      const end = eventDay(entry.end, `${path}.end`);
      require(ID_PATTERN.test(id), `${path}.id`, "must be lowercase words joined by hyphens");
      require(!ids.has(id), `${path}.id`, `"${id}" is used twice`);
      ids.add(id);
      require(name.trim() !== "", `${path}.name`, "must not be empty");
      require(tagline.trim() !== "", `${path}.tagline`, "must not be empty");
      require(isValidDay(start, calendar), `${path}.start`, "not a day every year has");
      require(isValidDay(end, calendar), `${path}.end`, "not a day every year has");
      const rawRewards = list(entry.rewards, `${path}.rewards`);
      require(rawRewards.length > 0, `${path}.rewards`, "must offer at least one item");
      const rewards: SeasonalEventReward[] = [];
      rawRewards.forEach((rawReward, rewardIndex) => {
        const rewardPath = `${path}.rewards[${rewardIndex}]`;
        const rewardObject = record(rawReward, rewardPath);
        const itemID = text(rewardObject.item, `${rewardPath}.item`);
        const focusMinutes = integer(rewardObject.focusMinutes, `${rewardPath}.focusMinutes`);
        const item = itemFromID(itemID);
        if (!item) throw new SeasonalEventCatalogError(`${rewardPath}.item: no item "${itemID}"`);
        require(!offered.has(item), `${rewardPath}.item`, `"${itemID}" is offered twice`);
        offered.add(item);
        require(focusMinutes > 0, `${rewardPath}.focusMinutes`, "must be above 0");
        require(
          focusMinutes < HOUR_LABEL_MINUTES || focusMinutes % 60 === 0,
          `${rewardPath}.focusMinutes`,
          "goals of two hours or more must be whole hours",
        );
        const last = rewards[rewards.length - 1];
        require(last === undefined || last.focusMinutes < focusMinutes, `${rewardPath}.focusMinutes`, "must be above the item before it");
        rewards.push({ item, focusMinutes });
      });
      return { id, name, tagline, calendar, start, end, rewards };
    });
    return new SeasonalEventCatalog(events);
  }

  /** The year of events that ships with Tabbi, the Mac's own `events.json`. */
  static readonly bundled: SeasonalEventCatalog = SeasonalEventCatalog.decode(eventsFile);

  /** The event with `id`, if the catalog has one. */
  event(id: string): SeasonalEvent | undefined {
    return this.events.find((event) => event.id === id);
  }

  /** The event that offers `item`, if any. */
  eventOffering(item: PetItem): SeasonalEvent | undefined {
    return this.events.find((event) => event.rewards.some((reward) => reward.item === item));
  }

  /** The runs going on at `instant` in `timeZone`, the one ending soonest first. */
  active(instant: Instant, timeZone: string): SeasonalEventOccurrence[] {
    return this.events
      .flatMap((event) => occurrenceContaining(event, instant, timeZone) ?? [])
      .sort((a, b) => a.end - b.end || compareText(a.event.id, b.event.id));
  }

  /** The next run to start after `instant`. */
  next(instant: Instant, timeZone: string): SeasonalEventOccurrence | undefined {
    let best: SeasonalEventOccurrence | undefined;
    for (const event of this.events) {
      const occurrence = nextOccurrence(event, instant, timeZone);
      if (!occurrence) continue;
      if (!best || occurrence.start - best.start < 0 || (occurrence.start === best.start && compareText(occurrence.event.id, best.event.id) < 0)) {
        best = occurrence;
      }
    }
    return best;
  }

  /** The run the Limited section features: the one going on (the soonest to end), or else the next to start. */
  featured(instant: Instant, timeZone: string): { occurrence: SeasonalEventOccurrence; isActive: boolean } | undefined {
    const active = this.active(instant, timeZone)[0];
    if (active) return { occurrence: active, isActive: true };
    const next = this.next(instant, timeZone);
    return next ? { occurrence: next, isActive: false } : undefined;
  }

  /**
   * The Limited section's shelves at `instant`, each with at least one item
   * and together every limited item once: the featured event, the
   * milestones (the limited items that are not seasonal), then the other events'
   * items in the order their next runs start.
   */
  limitedShelves(instant: Instant, timeZone: string): PetLimitedShelf[] {
    const featured = this.featured(instant, timeZone);
    const featuredItems = featured?.occurrence.event.rewards.map((reward) => reward.item) ?? [];
    const later = this.events
      .filter((event) => event.id !== featured?.occurrence.event.id)
      .flatMap((event) => {
        const run = occurrenceContaining(event, instant, timeZone) ?? nextOccurrence(event, instant, timeZone);
        return run ? [{ event, start: run.start }] : [];
      })
      .sort((a, b) => a.start - b.start || compareText(a.event.id, b.event.id))
      .flatMap(({ event }) => event.rewards.map((reward) => reward.item));
    const seasonal = new Set(this.events.flatMap((event) => event.rewards.map((reward) => reward.item)));
    const milestones = PET_LIMITED_EDITIONS.map(editionItem).filter((item) => !seasonal.has(item));
    const shelves: PetLimitedShelf[] = [];
    if (featured) {
      shelves.push({ kind: { kind: "event", occurrence: featured.occurrence, isActive: featured.isActive }, items: featuredItems });
    }
    shelves.push({ kind: { kind: "milestones" }, items: milestones });
    shelves.push({ kind: { kind: "laterEvents" }, items: later });
    return shelves.filter((shelf) => shelf.items.length > 0);
  }
}

/** Plain code point order, like Swift's String comparison for ASCII ids. */
function compareText(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/** One shelf of the Closet's Limited section. Port of PetLimitedShelf. */
export interface PetLimitedShelf {
  readonly kind:
    | { readonly kind: "event"; readonly occurrence: SeasonalEventOccurrence; readonly isActive: boolean }
    | { readonly kind: "milestones" }
    | { readonly kind: "laterEvents" };
  readonly items: readonly PetItem[];
}

/**
 * The focused minutes logged during every run of every event, kept per run
 * by its id (`halloween-2026`). Port of SeasonalEventTally.
 */
export class SeasonalEventTally {
  readonly runs = new Map<string, SeasonalEventProgress>();

  constructor(
    readonly catalog: SeasonalEventCatalog,
    /** The IANA zone that decides which local days a record ends on. */
    readonly timeZone: string,
    records: Iterable<ActivityRecord> = [],
  ) {
    for (const entry of records) this.add(entry);
  }

  /** Counts `record` toward every run going on when it ended; the same record counts once. */
  add(entry: ActivityRecord): void {
    if (entry.kind !== ACTIVITY_KINDS.focusCompleted) return;
    for (const occurrence of this.catalog.active(entry.end, this.timeZone)) {
      const id = occurrenceID(occurrence, this.timeZone);
      let run = this.runs.get(id);
      if (!run) {
        run = new SeasonalEventProgress(occurrence);
        this.runs.set(id, run);
      }
      run.add(entry);
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

  /** Progress toward `item` while its event runs at `instant`; undefined between runs. */
  progress(item: PetItem, instant: Instant): PetLimitedProgress | undefined {
    for (const run of this.active(instant)) {
      const reward = run.occurrence.event.rewards.find((candidate) => candidate.item === item);
      if (reward) return run.progress(reward);
    }
    return undefined;
  }
}
