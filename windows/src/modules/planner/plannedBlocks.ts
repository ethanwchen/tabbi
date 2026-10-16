/*
 * Where accepted plan blocks go on Windows. The Mac writes them to the
 * user's calendar; Windows reads calendars from ICS feeds, which cannot be
 * written to, so "Add" keeps the blocks in Today instead: one versioned
 * JSON file per day in the edition's Planner folder, which Up next, the
 * Schedule's timeline (as planned blocks) and the ticker's meeting preview
 * read beside the calendar. Today owns the store and declares it as a
 * shared service, so the Schedule reads the same one.
 */

import type { ModuleContext } from "../../app/context";
import { serviceKey } from "../../app/sharedServices";
import { Store } from "../../app/store";
import { formatISODate, parseISODate } from "../../core/activity/isoDate";
import { isEphemeral } from "../../core/modules/runMode";
import { documentName, type DocumentStore } from "../../core/persistence/documentStore";
import { isJSONObject, type JSONObject } from "../../core/persistence/json";
import { VersionedJSON } from "../../core/persistence/versionedJson";
import type { PlanCalendarWriting, PlannedCalendarEvent } from "../../core/planner/dayPlanProposal";
import { addingDaysToKey, dayKeyStart, isPlannerDayKey, plannerDayKeyOf, type PlannerDayKey } from "../../core/planner/plannerDayKey";
import { newUUID, parseUUID } from "../../core/planner/uuid";
import { upcomingEvent, type UpcomingEvent } from "../../core/planner/upcomingEvent";
import type { Instant } from "../../core/time";

/** One block the user accepted, as kept in Today. */
export interface PlannedBlock {
  readonly id: string;
  readonly title: string;
  readonly start: Instant;
  readonly end: Instant;
  /** The note Plan my day puts on every block ("Planned with Tabbi"). */
  readonly notes: string;
}

/** The day file format. Version 1 is the first. */
export const PLANNED_BLOCKS_SCHEMA = new VersionedJSON(1);

function instant(value: unknown, key: string): Instant {
  const parsed = typeof value === "string" ? parseISODate(value) : undefined;
  if (parsed === undefined) throw new TypeError(`Invalid ${key}`);
  return parsed;
}

export function decodePlannedBlocks(document: JSONObject): { date: PlannerDayKey; blocks: PlannedBlock[] } {
  const date = document.date;
  if (typeof date !== "string" || !isPlannerDayKey(date)) throw new TypeError("Invalid date");
  if (!Array.isArray(document.blocks)) throw new TypeError("Invalid blocks");
  const blocks = document.blocks.map((json): PlannedBlock => {
    if (!isJSONObject(json)) throw new TypeError("Invalid block");
    const id = typeof json.id === "string" ? parseUUID(json.id) : undefined;
    if (id === undefined) throw new TypeError("Invalid block id");
    if (typeof json.title !== "string") throw new TypeError("Invalid block title");
    return {
      id,
      title: json.title,
      start: instant(json.start, "start"),
      end: instant(json.end, "end"),
      notes: typeof json.notes === "string" ? json.notes : "",
    };
  });
  return { date, blocks };
}

export function encodePlannedBlocks(date: PlannerDayKey, blocks: readonly PlannedBlock[]): JSONObject {
  return {
    date,
    blocks: blocks.map((block) => ({
      id: block.id,
      title: block.title,
      start: formatISODate(block.start),
      end: formatISODate(block.end),
      notes: block.notes,
    })),
  };
}

/** One file per day, `Plans/yyyy-MM-dd.json`, inside the edition's Planner folder. */
export class PlannedBlocksRepository {
  static readonly folderName = "Plans";

  constructor(private readonly store: DocumentStore) {}

  documentName(date: PlannerDayKey): string {
    return documentName(PlannedBlocksRepository.folderName, `${date}.json`);
  }

  /** The day's blocks, empty when none were kept; rejects when the file is corrupt. */
  async load(date: PlannerDayKey): Promise<PlannedBlock[]> {
    const text = await this.store.read(this.documentName(date));
    if (text === undefined) return [];
    return PLANNED_BLOCKS_SCHEMA.decode(text, decodePlannedBlocks).blocks;
  }

  async save(date: PlannerDayKey, blocks: readonly PlannedBlock[]): Promise<void> {
    await this.store.write(this.documentName(date), PLANNED_BLOCKS_SCHEMA.encode(encodePlannedBlocks(date, blocks), { pretty: true, sortedKeys: true }));
  }
}

interface PlannedBlocksState {
  /** The days read so far, each with its blocks in time order. */
  readonly days: ReadonlyMap<PlannerDayKey, readonly PlannedBlock[]>;
}

/** The event id of a kept block, so readers can tell it from a calendar event. */
export const PLANNED_BLOCK_ID_PREFIX = "planned:";

export function isPlannedBlockEvent(event: Pick<UpcomingEvent, "id">): boolean {
  return event.id.startsWith(PLANNED_BLOCK_ID_PREFIX);
}

/** A kept block as the calendar card shows it: an event with no calendar color (the accent stands in). */
export function plannedBlockEvent(block: PlannedBlock): UpcomingEvent {
  return upcomingEvent({ id: `${PLANNED_BLOCK_ID_PREFIX}${block.id}`, title: block.title, start: block.start, end: block.end });
}

/**
 * The accepted blocks, by day. Reads a day's file the first time it is
 * asked for and keeps it; demo and snapshot runs keep everything in memory.
 * Writes go through `writer()`, which keeps every block or none, like the
 * Mac's calendar writer.
 */
export class PlannedBlocksStore extends Store<PlannedBlocksState> {
  private readonly loads = new Map<PlannerDayKey, Promise<readonly PlannedBlock[]>>();

  constructor(
    private readonly repository: PlannedBlocksRepository | undefined,
    private readonly timeZone: () => string,
  ) {
    super({ days: new Map() });
  }

  /** The day's blocks once read. A corrupt file counts as an empty day, so planning still works. */
  async blocks(date: PlannerDayKey): Promise<readonly PlannedBlock[]> {
    const known = this.state.days.get(date);
    if (known !== undefined) return known;
    let pending = this.loads.get(date);
    if (pending === undefined) {
      pending = (this.repository?.load(date) ?? Promise.resolve([])).catch((): PlannedBlock[] => []).then((blocks) => {
        this.loads.delete(date);
        this.put(date, blocks);
        return blocks;
      });
      this.loads.set(date, pending);
    }
    return pending;
  }

  /** The blocks already read for `date`, without waiting; empty until `blocks` has run. */
  known(date: PlannerDayKey): readonly PlannedBlock[] {
    return this.state.days.get(date) ?? [];
  }

  /** Blocks touching `[from, to)` as events, days read on demand. */
  async events(from: Instant, to: Instant): Promise<UpcomingEvent[]> {
    const timeZone = this.timeZone();
    const result: UpcomingEvent[] = [];
    const last = plannerDayKeyOf(Math.max(to - 1, from), timeZone);
    for (let day = plannerDayKeyOf(from, timeZone); day <= last; day = addingDaysToKey(day, 1)) {
      for (const block of await this.blocks(day)) {
        if (block.start < to && block.end > from) result.push(plannedBlockEvent(block));
      }
    }
    return result;
  }

  /** The writer Plan my day and the Schedule hand their proposals: every event lands in Today or none does. */
  writer(): PlanCalendarWriting {
    return {
      write: (events: readonly PlannedCalendarEvent[]) => this.add(events),
    };
  }

  /** Keeps `events` as blocks on their days, in time order, and saves each day touched. */
  async add(events: readonly PlannedCalendarEvent[]): Promise<void> {
    const timeZone = this.timeZone();
    const byDay = new Map<PlannerDayKey, PlannedBlock[]>();
    for (const event of events) {
      const day = plannerDayKeyOf(event.start, timeZone);
      const list = byDay.get(day) ?? [...(await this.blocks(day))];
      list.push({ id: newUUID(), title: event.title, start: event.start, end: event.end, notes: event.notes });
      byDay.set(day, list);
    }
    /* Saved before shown, so a failed write leaves the proposal as it was. */
    for (const [day, blocks] of byDay) {
      blocks.sort((a, b) => a.start - b.start || a.end - b.end);
      await this.repository?.save(day, blocks);
    }
    for (const [day, blocks] of byDay) this.put(day, blocks);
  }

  private put(date: PlannerDayKey, blocks: readonly PlannedBlock[]): void {
    const days = new Map(this.state.days);
    days.set(date, blocks);
    this.setState({ days });
  }
}

/** Midnight to midnight of `date`, for readers that ask by day. */
export function dayRange(date: PlannerDayKey, timeZone: string): { readonly from: Instant; readonly to: Instant } {
  return { from: dayKeyStart(date, timeZone), to: dayKeyStart(addingDaysToKey(date, 1), timeZone) };
}

const PLANNED_BLOCKS = serviceKey<PlannedBlocksStore>("planner.plannedBlocks");

/** The one store of accepted blocks: on disk in a live run, in memory in demo and snapshot runs. */
export function plannedBlocks(context: ModuleContext): PlannedBlocksStore {
  return context.shared.resolve(PLANNED_BLOCKS, () => {
    const repository = isEphemeral(context.runMode) ? undefined : new PlannedBlocksRepository(context.storage.folder("Planner"));
    return new PlannedBlocksStore(repository, () => context.timeZone());
  });
}
