import type { Instant } from "../time";
import type { ModuleID } from "../modules/moduleId";
import type { PlannerDayKey } from "./plannerDayKey";
import type { ProvidedTask } from "./providedWork";
import { newUUID } from "./uuid";

/** Port of PlannerItem: one checklist entry. */
export interface PlannerItem {
  /** An upper-case UUID. */
  readonly id: string;
  readonly title: string;
  readonly isDone: boolean;
  readonly createdAt: Instant;
  readonly completedAt?: Instant;
}

/** Builds an item with the Swift initializer's defaults (a fresh id, not done). */
export function plannerItem(input: {
  id?: string;
  title: string;
  isDone?: boolean;
  createdAt: Instant;
  completedAt?: Instant | undefined;
}): PlannerItem {
  const item: { -readonly [Key in keyof PlannerItem]: PlannerItem[Key] } = {
    id: (input.id ?? newUUID()).toUpperCase(),
    title: input.title,
    isDone: input.isDone ?? false,
    createdAt: input.createdAt,
  };
  if (input.completedAt !== undefined) item.completedAt = input.completedAt;
  return item;
}

/** This checklist item as Today's contribution to the shared task list. */
export function providedTaskFromItem(item: PlannerItem, module: ModuleID): ProvidedTask {
  return { id: item.id, source: module, title: item.title, isDone: item.isDone };
}

/**
 * Collapses internal whitespace runs (including pasted newlines) to a
 * single space; undefined when nothing visible remains.
 */
export function normalizedTitle(title: string): string | undefined {
  const collapsed = title
    .split(/\s+/u)
    .filter((piece) => piece !== "")
    .join(" ");
  return collapsed === "" ? undefined : collapsed;
}

function sameItem(a: PlannerItem, b: PlannerItem): boolean {
  return (
    a.id === b.id && a.title === b.title && a.isDone === b.isDone && a.createdAt === b.createdAt && a.completedAt === b.completedAt
  );
}

/**
 * Port of PlannerDay: a day's ordered checklist. Edits change this value
 * in place, like the Swift struct's mutating methods; `copy` gives an
 * independent value. Persistence lives in `PlannerRepository`.
 */
export class PlannerDay {
  readonly date: PlannerDayKey;
  private itemsValue: PlannerItem[];
  private plannedAheadValue: boolean;

  constructor(date: PlannerDayKey, items: readonly PlannerItem[] = [], isPlannedAhead = false) {
    this.date = date;
    this.itemsValue = [...items];
    this.plannedAheadValue = isPlannedAhead;
  }

  copy(): PlannerDay {
    return new PlannerDay(this.date, this.itemsValue, this.plannedAheadValue);
  }

  get items(): readonly PlannerItem[] {
    return this.itemsValue;
  }

  /**
   * Whether this day was started ahead of time (tasks added for tomorrow)
   * and hasn't yet taken in the unfinished items of the day before it.
   * `PlannerRepository.open` does that once, when the day comes.
   */
  get isPlannedAhead(): boolean {
    return this.plannedAheadValue;
  }

  get doneCount(): number {
    return this.itemsValue.filter((item) => item.isDone).length;
  }

  /** Fraction of items done, 0 when the list is empty. */
  get progress(): number {
    return this.itemsValue.length === 0 ? 0 : this.doneCount / this.itemsValue.length;
  }

  /** Appends a new item. Returns undefined (and changes nothing) for blank titles. */
  add(title: string, now: Instant): PlannerItem | undefined {
    const normalized = normalizedTitle(title);
    if (normalized === undefined) return undefined;
    const item = plannerItem({ title: normalized, createdAt: now });
    this.itemsValue.push(item);
    return item;
  }

  /**
   * Appends a kit's starter tasks, skipping blanks and any title already on
   * the list (ignoring case), so applying a kit twice never duplicates them.
   */
  addStarterTasks(titles: readonly string[], now: Instant): PlannerItem[] {
    const seen = new Set(this.itemsValue.map((item) => item.title.toLowerCase()));
    const added: PlannerItem[] = [];
    for (const raw of titles) {
      const title = normalizedTitle(raw);
      if (title === undefined || seen.has(title.toLowerCase())) continue;
      seen.add(title.toLowerCase());
      const item = this.add(title, now);
      if (item !== undefined) added.push(item);
    }
    return added;
  }

  /** Flips an item's done state, stamping or clearing `completedAt`. */
  toggle(id: string, now: Instant): void {
    const index = this.indexOf(id);
    const item = this.itemsValue[index];
    if (item === undefined) return;
    this.itemsValue[index] = plannerItem({
      id: item.id,
      title: item.title,
      isDone: !item.isDone,
      createdAt: item.createdAt,
      completedAt: item.isDone ? undefined : now,
    });
  }

  /** Renames an item; blank titles are ignored so an item can't vanish into an empty row. */
  rename(id: string, title: string): boolean {
    const index = this.indexOf(id);
    const item = this.itemsValue[index];
    const normalized = normalizedTitle(title);
    if (item === undefined || normalized === undefined || item.title === normalized) return false;
    this.itemsValue[index] = { ...item, title: normalized };
    return true;
  }

  delete(id: string): void {
    this.itemsValue = this.itemsValue.filter((item) => item.id !== id);
  }

  /**
   * Removes the items in `added` that are still exactly as they were added
   * (not renamed or checked off), so undoing a kit switch takes back its
   * starter tasks but never work the user has touched since.
   */
  removeUntouched(added: readonly PlannerItem[]): boolean {
    const before = this.itemsValue.length;
    this.itemsValue = this.itemsValue.filter((item) => !added.some((original) => sameItem(original, item)));
    return this.itemsValue.length !== before;
  }

  /** Moves the items at `offsets` to land before `destination`, like SwiftUI's `onMove`. */
  moveOffsets(offsets: Iterable<number>, destination: number): void {
    const valid = [...new Set(offsets)].filter((index) => index >= 0 && index < this.itemsValue.length).sort((a, b) => a - b);
    if (valid.length === 0) return;
    const moving = valid.map((index) => this.itemsValue[index]).filter((item): item is PlannerItem => item !== undefined);
    const clamped = Math.min(Math.max(destination, 0), this.itemsValue.length);
    const insertion = clamped - valid.filter((index) => index < clamped).length;
    const kept = this.itemsValue.filter((_, index) => !valid.includes(index));
    kept.splice(insertion, 0, ...moving);
    this.itemsValue = kept;
  }

  /** Moves one item to sit at `targetIndex` in the resulting list, for drag and drop onto a row. */
  move(id: string, targetIndex: number): void {
    const from = this.indexOf(id);
    const item = this.itemsValue[from];
    if (item === undefined) return;
    this.itemsValue.splice(from, 1);
    this.itemsValue.splice(Math.min(Math.max(targetIndex, 0), this.itemsValue.length), 0, item);
  }

  clearCompleted(): void {
    this.itemsValue = this.itemsValue.filter((item) => !item.isDone);
  }

  /**
   * This day's unfinished items that `other` doesn't list (by id or by
   * title, ignoring case), in order: what looking back at yesterday offers
   * to move to today, and exactly what `adopt` would add there.
   */
  unfinished(other: PlannerDay): PlannerItem[] {
    const ids = new Set(other.items.map((item) => item.id));
    const titles = new Set(other.items.map((item) => item.title.toLowerCase()));
    return this.itemsValue.filter((item) => !item.isDone && !ids.has(item.id) && !titles.has(item.title.toLowerCase()));
  }

  /**
   * Appends `incoming` items as they are (same id, title and creation date,
   * unfinished), skipping any whose id or title (ignoring case) is already
   * listed, so nothing is ever listed twice. Returns the items added.
   */
  adopt(incoming: readonly PlannerItem[]): PlannerItem[] {
    const ids = new Set(this.itemsValue.map((item) => item.id));
    const titles = new Set(this.itemsValue.map((item) => item.title.toLowerCase()));
    const added: PlannerItem[] = [];
    for (const item of incoming) {
      if (ids.has(item.id)) continue;
      ids.add(item.id);
      const title = item.title.toLowerCase();
      if (titles.has(title)) continue;
      titles.add(title);
      const moved = plannerItem({ id: item.id, title: item.title, isDone: false, createdAt: item.createdAt });
      this.itemsValue.push(moved);
      added.push(moved);
    }
    return added;
  }

  /**
   * Takes in the unfinished items of `previous` (the day before) ahead of
   * what was planned for this day, and marks the day as started. The
   * planned items stay exactly as they are; a leftover whose id or title is
   * already planned is not taken in again.
   */
  takeCarryOver(previous: PlannerDay | undefined): void {
    const leftovers = previous?.unfinished(this) ?? [];
    const planned = this.itemsValue;
    this.itemsValue = [];
    this.adopt(leftovers);
    this.itemsValue.push(...planned);
    this.plannedAheadValue = false;
  }

  private indexOf(id: string): number {
    return this.itemsValue.findIndex((item) => item.id === id);
  }
}
