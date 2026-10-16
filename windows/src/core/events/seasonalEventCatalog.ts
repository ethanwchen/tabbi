import eventsFile from "@mac/Events/events.json";
import { isJSONObject } from "../persistence/json";
import { itemFromID, type PetItem } from "../pets/petItem";
import type { Instant } from "../time";
import {
  HOUR_LABEL_MINUTES,
  nextOccurrence,
  occurrenceContaining,
  type SeasonalEvent,
  type SeasonalEventOccurrence,
  type SeasonalEventReward,
  type SeasonalEventRuns,
} from "./seasonalEvent";
import {
  SEASONAL_EVENT_CALENDARS,
  isValidEventDay,
  type SeasonalEventCalendar,
  type SeasonalEventDay,
} from "./seasonalEventCalendar";

/*
 * Port of SeasonalEventCatalog: the year of seasonal events, read from an
 * `events.v1` JSON file (shared/schemas/events.v1.schema.json). Events are
 * data so a new season is a JSON edit, and the Windows build reads the
 * Mac's own `events.json` in place, so both run the same calendar.
 */

export const SEASONAL_EVENTS_SCHEMA = "events.v1";

/** Why a file was refused. Port of SeasonalEventCatalog.LoadError. */
export class SeasonalEventCatalogError extends Error {
  private constructor(
    readonly kind: "unsupportedSchema" | "invalidValue",
    /** The schema found, or the path of the bad value (`events[1].rewards[0].item`). */
    readonly path: string,
    readonly reason: string,
  ) {
    super(kind === "unsupportedSchema" ? `Unsupported schema "${path}"; expected "${SEASONAL_EVENTS_SCHEMA}"` : `${path}: ${reason}`);
    this.name = "SeasonalEventCatalogError";
  }

  static unsupportedSchema(schema: string): SeasonalEventCatalogError {
    return new SeasonalEventCatalogError("unsupportedSchema", schema, "");
  }

  static invalidValue(path: string, reason: string): SeasonalEventCatalogError {
    return new SeasonalEventCatalogError("invalidValue", path, reason);
  }
}

function compare(a: readonly [number, string], b: readonly [number, string]): number {
  if (a[0] !== b[0]) return a[0] - b[0];
  return a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0;
}

export class SeasonalEventCatalog implements SeasonalEventRuns {
  /** Every event, in file order. */
  constructor(readonly events: readonly SeasonalEvent[]) {}

  /** The event with `id`, if the catalog has one. */
  event(id: string): SeasonalEvent | undefined {
    return this.events.find((event) => event.id === id);
  }

  /** The runs going on at `instant`, the one ending soonest first, so a short event inside a longer one gets the spotlight. */
  active(instant: Instant, timeZone: string): SeasonalEventOccurrence[] {
    return this.events
      .flatMap((event) => occurrenceContaining(event, instant, timeZone) ?? [])
      .sort((a, b) => compare([a.end, a.event.id], [b.end, b.event.id]));
  }

  /** The next run to start after `instant`. */
  next(instant: Instant, timeZone: string): SeasonalEventOccurrence | undefined {
    const runs = this.events.flatMap((event) => nextOccurrence(event, instant, timeZone) ?? []);
    return runs.sort((a, b) => compare([a.start, a.event.id], [b.start, b.event.id]))[0];
  }

  /** The event that offers `item`, if any. */
  eventOffering(item: PetItem): SeasonalEvent | undefined {
    return this.events.find((event) => event.rewards.some((reward) => reward.item === item));
  }

  /**
   * Parses and checks a file (its text or its parsed JSON): the schema
   * version, unique ids, real dates (never February 29, which most years
   * lack), a name and tagline, and at least one known item per event, each
   * offered by one event only, with goals that rise through the event and
   * read cleanly (`SeasonalEventProgress.progress`).
   */
  static decode(input: unknown): SeasonalEventCatalog {
    const file: unknown = typeof input === "string" ? JSON.parse(input) : input;
    const require = (condition: boolean, path: string, reason: string) => {
      if (!condition) throw SeasonalEventCatalogError.invalidValue(path, reason);
    };
    require(isJSONObject(file), "", "must be an object");
    const root = file as Record<string, unknown>;
    if (typeof root.schema !== "string") throw SeasonalEventCatalogError.invalidValue("schema", "must be a string");
    if (root.schema !== SEASONAL_EVENTS_SCHEMA) throw SeasonalEventCatalogError.unsupportedSchema(root.schema);
    require(Array.isArray(root.events), "events", "must be a list");
    const ids = new Set<string>();
    const offered = new Set<PetItem>();
    const events = (root.events as unknown[]).map((entry, index): SeasonalEvent => {
      const path = `events[${index}]`;
      require(isJSONObject(entry), path, "must be an object");
      const event = entry as Record<string, unknown>;
      const text = (key: string): string => {
        const value = event[key];
        require(typeof value === "string", `${path}.${key}`, "must be a string");
        return value as string;
      };
      const id = text("id");
      const name = text("name");
      const tagline = text("tagline");
      const calendar = text("calendar");
      require((SEASONAL_EVENT_CALENDARS as readonly string[]).includes(calendar), `${path}.calendar`, "unknown calendar");
      require(/^[a-z0-9]+(-[a-z0-9]+)*$/.test(id), `${path}.id`, "must be lowercase words joined by hyphens");
      require(!ids.has(id), `${path}.id`, `"${id}" is used twice`);
      ids.add(id);
      require(name.trim() !== "", `${path}.name`, "must not be empty");
      require(tagline.trim() !== "", `${path}.tagline`, "must not be empty");
      const day = (key: "start" | "end"): SeasonalEventDay => {
        const value = event[key];
        const fields = isJSONObject(value) ? value : {};
        const parsed = { month: Number(fields.month), day: Number(fields.day) };
        require(
          typeof fields.month === "number" && typeof fields.day === "number" && isValidEventDay(parsed, calendar as SeasonalEventCalendar),
          `${path}.${key}`,
          "not a day every year has",
        );
        return parsed;
      };
      const start = day("start");
      const end = day("end");
      require(Array.isArray(event.rewards) && event.rewards.length > 0, `${path}.rewards`, "must offer at least one item");
      const rewards: SeasonalEventReward[] = [];
      (event.rewards as unknown[]).forEach((value, rewardIndex) => {
        const rewardPath = `${path}.rewards[${rewardIndex}]`;
        const reward = isJSONObject(value) ? value : {};
        const itemID = typeof reward.item === "string" ? reward.item : "";
        const item = itemFromID(itemID);
        if (item === undefined) throw SeasonalEventCatalogError.invalidValue(`${rewardPath}.item`, `no item "${itemID}"`);
        require(!offered.has(item), `${rewardPath}.item`, `"${itemID}" is offered twice`);
        offered.add(item);
        const minutes = reward.focusMinutes;
        require(typeof minutes === "number" && Number.isInteger(minutes), `${rewardPath}.focusMinutes`, "must be a whole number");
        const focusMinutes = minutes as number;
        require(focusMinutes > 0, `${rewardPath}.focusMinutes`, "must be above 0");
        require(
          focusMinutes < HOUR_LABEL_MINUTES || focusMinutes % 60 === 0,
          `${rewardPath}.focusMinutes`,
          "goals of two hours or more must be whole hours",
        );
        const last = rewards.at(-1);
        require(last === undefined || last.focusMinutes < focusMinutes, `${rewardPath}.focusMinutes`, "must be above the item before it");
        rewards.push({ item, focusMinutes });
      });
      return { id, name, tagline, calendar: calendar as SeasonalEventCalendar, start, end, rewards };
    });
    return new SeasonalEventCatalog(events);
  }

  private static bundledCatalog: SeasonalEventCatalog | undefined;

  /**
   * The year of events that ships with Tabbi, the Mac's `events.json`. Read
   * once; a broken file is a build mistake, which the tests catch.
   */
  static get bundled(): SeasonalEventCatalog {
    SeasonalEventCatalog.bundledCatalog ??= SeasonalEventCatalog.decode(eventsFile);
    return SeasonalEventCatalog.bundledCatalog;
  }
}
