import { formatISODate, parseISODate } from "../activity/isoDate";
import { documentName, type DocumentStore } from "../persistence/documentStore";
import { isJSONObject, type JSONObject } from "../persistence/json";
import { VersionedJSON } from "../persistence/versionedJson";
import type { Instant } from "../time";
import { PlannerDay, plannerItem, type PlannerItem } from "./plannerDay";
import { isPlannerDayKey, type PlannerDayKey } from "./plannerDayKey";
import { parseUUID } from "./uuid";

/**
 * The day file format. Version 1 added the `schemaVersion` key; version 2
 * added `isPlannedAhead`, false for every older file because each one was
 * created by `open` with its carry-over already taken in.
 */
export const PLANNER_DAY_SCHEMA = new VersionedJSON(2, [
  {
    version: 2,
    migrate: (document) => {
      if (document.isPlannedAhead === undefined) document.isPlannedAhead = false;
    },
  },
]);

function date(value: unknown, key: string): Instant {
  const instant = typeof value === "string" ? parseISODate(value) : undefined;
  if (instant === undefined) throw new TypeError(`Invalid ${key}`);
  return instant;
}

function decodeItem(json: unknown): PlannerItem {
  if (!isJSONObject(json)) throw new TypeError("Invalid item");
  const id = typeof json.id === "string" ? parseUUID(json.id) : undefined;
  if (id === undefined) throw new TypeError("Invalid item id");
  if (typeof json.title !== "string") throw new TypeError("Invalid item title");
  if (typeof json.isDone !== "boolean") throw new TypeError("Invalid item isDone");
  const completed = json.completedAt;
  return plannerItem({
    id,
    title: json.title,
    isDone: json.isDone,
    createdAt: date(json.createdAt, "createdAt"),
    completedAt: completed === undefined || completed === null ? undefined : date(completed, "completedAt"),
  });
}

/** Reads a day the way the Mac decodes one (lenient about `isPlannedAhead`); throws on a malformed file. */
export function decodePlannerDay(document: JSONObject): PlannerDay {
  const key = document.date;
  if (typeof key !== "string" || !isPlannerDayKey(key)) throw new TypeError("Invalid date");
  if (!Array.isArray(document.items)) throw new TypeError("Invalid items");
  const plannedAhead = document.isPlannedAhead;
  if (plannedAhead !== undefined && plannedAhead !== null && typeof plannedAhead !== "boolean") {
    throw new TypeError("Invalid isPlannedAhead");
  }
  return new PlannerDay(key, document.items.map(decodeItem), plannedAhead === true);
}

/** The day as the Mac encodes it: ISO 8601 dates in whole seconds, nil fields left out. */
export function encodePlannerDay(day: PlannerDay): JSONObject {
  return {
    date: day.date,
    isPlannedAhead: day.isPlannedAhead,
    items: day.items.map((item) => {
      const json: JSONObject = {
        id: item.id,
        title: item.title,
        isDone: item.isDone,
        createdAt: formatISODate(item.createdAt),
      };
      if (item.completedAt !== undefined) json.completedAt = formatISODate(item.completedAt);
      return json;
    }),
  };
}

/**
 * Port of PlannerRepository: one JSON file per day (`yyyy-MM-dd.json`) in
 * the edition's `Planner` folder, the same files the Mac writes. Plain
 * files keep the data readable, easy to back up and safe to edit by hand.
 */
export class PlannerRepository {
  /** The folder in an edition's storage. */
  static readonly folderName = "Planner";

  constructor(
    private readonly store: DocumentStore,
    readonly folder: string = PlannerRepository.folderName,
  ) {}

  documentName(date: PlannerDayKey): string {
    return documentName(this.folder, `${date}.json`);
  }

  /**
   * The saved day, or undefined if none exists. Rejects when the file is
   * unreadable or corrupt, so callers never mistake bad data for an empty
   * day and overwrite it. The file name is authoritative: a copied file
   * never masquerades as another day.
   */
  async load(date: PlannerDayKey): Promise<PlannerDay | undefined> {
    const text = await this.store.read(this.documentName(date));
    if (text === undefined) return undefined;
    const day = PLANNER_DAY_SCHEMA.decode(text, decodePlannerDay);
    return day.date === date ? day : new PlannerDay(date, day.items, day.isPlannedAhead);
  }

  async save(day: PlannerDay): Promise<void> {
    await this.store.write(
      this.documentName(day.date),
      PLANNER_DAY_SCHEMA.encode(encodePlannerDay(day), { pretty: true, sortedKeys: true }),
    );
  }

  /** Every day with a file, oldest first; unrelated files are ignored. */
  async savedDays(): Promise<PlannerDayKey[]> {
    const names = await this.store.list(this.folder);
    return names
      .filter((name) => name.endsWith(".json"))
      .map((name) => name.slice(0, -5))
      .filter(isPlannerDayKey)
      .sort();
  }

  /**
   * Loads `date` as today. On its first open the day takes in the
   * unfinished items of the most recent earlier day with a file, ahead of
   * anything planned for it, and is saved right away so carry-over
   * happens exactly once.
   */
  async open(date: PlannerDayKey): Promise<PlannerDay> {
    const { day, isNew } = await this.opening(date);
    if (isNew) await this.save(day);
    return day;
  }

  /** What `open` returns, without creating or updating the day's file (a snapshot run leaves no trace). */
  async preview(date: PlannerDayKey): Promise<PlannerDay> {
    return (await this.opening(date)).day;
  }

  /**
   * Loads a day other than today to look at or plan, without creating a
   * file: yesterday as it was left, or tomorrow's plan so far (an empty
   * planned-ahead day until the first task is saved).
   */
  async peek(date: PlannerDayKey, today: PlannerDayKey): Promise<PlannerDay> {
    return (await this.load(date)) ?? new PlannerDay(date, [], date > today);
  }

  private async opening(date: PlannerDayKey): Promise<{ day: PlannerDay; isNew: boolean }> {
    const existing = await this.load(date);
    if (existing !== undefined && !existing.isPlannedAhead) return { day: existing, isNew: false };
    const day = existing ?? new PlannerDay(date);
    day.takeCarryOver(await this.mostRecentDay(date));
    return { day, isNew: true };
  }

  /**
   * The latest readable day before `date`, walking back past corrupt files
   * rather than failing the whole day. A day planned ahead but never opened
   * first takes in its own predecessor (in memory), so skipping it loses
   * none of the older leftovers.
   */
  private async mostRecentDay(date: PlannerDayKey): Promise<PlannerDay | undefined> {
    const days = (await this.savedDays()).reverse();
    for (const previous of days) {
      if (!(previous < date)) continue;
      let source: PlannerDay | undefined;
      try {
        source = await this.load(previous);
      } catch {
        continue;
      }
      if (source === undefined) continue;
      if (source.isPlannedAhead) source.takeCarryOver(await this.mostRecentDay(previous));
      return source;
    }
    return undefined;
  }
}
