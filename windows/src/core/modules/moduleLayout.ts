import type { ModuleCatalog } from "./moduleCatalog";
import type { ModuleID } from "./moduleId";

/**
 * Port of ModuleLayout: the user's tab bar, which modules are shown and in
 * what order.
 *
 * Every module in the catalog always has a slot in `order`, so a module that
 * ships in a later version (and is missing from saved data) is appended at
 * the end, switched off: an update must not add tabs nobody asked for. At
 * least one module always stays enabled, so the panel never opens empty.
 *
 * Mutating methods change this layout in place, like the Swift value's
 * `mutating` methods; `clone()` gives an independent copy first.
 */
export class ModuleLayout {
  private orderList: ModuleID[];
  private disabledSet: Set<ModuleID>;
  /** The letter keys of modules opened from the header instead of a tab. */
  private readonly headerKeys: ReadonlyMap<ModuleID, string>;

  /**
   * Builds a layout from possibly stale or partial data: ids not in
   * `catalog` and duplicates are dropped, missing modules are appended
   * switched off, and if that would leave nothing enabled the first module
   * is re-enabled.
   */
  constructor(order: readonly ModuleID[], disabled: Iterable<ModuleID>, catalog: ModuleCatalog) {
    const seen = new Set<ModuleID>();
    const normalized: ModuleID[] = [];
    for (const id of order) {
      if (!catalog.contains(id) || seen.has(id)) continue;
      seen.add(id);
      normalized.push(id);
    }
    const missing = catalog.ids.filter((id) => !seen.has(id));
    normalized.push(...missing);
    const normalizedSet = new Set(normalized);
    const disabledSet = new Set([...disabled].filter((id) => normalizedSet.has(id)));
    for (const id of missing) disabledSet.add(id);
    const first = normalized[0];
    if (first !== undefined && normalized.every((id) => disabledSet.has(id))) disabledSet.delete(first);
    this.orderList = normalized;
    this.disabledSet = disabledSet;
    const keys = new Map<ModuleID, string>();
    for (const descriptor of catalog.descriptors) {
      if (descriptor.headerShortcut) keys.set(descriptor.id, descriptor.headerShortcut.key);
    }
    this.headerKeys = keys;
  }

  /** Every module in `catalog`, in canonical order, all on: the last resort when nothing else says otherwise. */
  static all(catalog: ModuleCatalog): ModuleLayout {
    return new ModuleLayout(catalog.ids, [], catalog);
  }

  /** A layout with exactly `modules` on, in that order, and every other module off. */
  static enabling(modules: readonly ModuleID[], catalog: ModuleCatalog): ModuleLayout {
    const on = new Set(modules);
    return new ModuleLayout(
      modules,
      catalog.ids.filter((id) => !on.has(id)),
      catalog,
    );
  }

  /**
   * Parses a comma-separated list of module ids (`study,planner,anki`) into
   * `enabling`, or undefined when it names no module the catalog knows.
   */
  static enablingList(list: string, catalog: ModuleCatalog): ModuleLayout | undefined {
    const ids = list
      .split(",")
      .map((id) => id.trim())
      .filter((id) => catalog.contains(id));
    return ids.length === 0 ? undefined : ModuleLayout.enabling(ids, catalog);
  }

  /** An independent copy. */
  clone(): ModuleLayout {
    const copy = Object.create(ModuleLayout.prototype) as ModuleLayout;
    Object.assign(copy, {
      orderList: [...this.orderList],
      disabledSet: new Set(this.disabledSet),
      headerKeys: this.headerKeys,
    });
    return copy;
  }

  /** Same order, same switched-off modules and same header modules. */
  equals(other: ModuleLayout): boolean {
    return (
      sameList(this.orderList, other.orderList) &&
      sameSet(this.disabledSet, other.disabledSet) &&
      this.headerKeys.size === other.headerKeys.size &&
      [...this.headerKeys].every(([id, key]) => other.headerKeys.get(id) === key)
    );
  }

  /** Every known module, in the user's order. */
  get order(): readonly ModuleID[] {
    return this.orderList;
  }

  /** Modules the user turned off. */
  get disabled(): ReadonlySet<ModuleID> {
    return this.disabledSet;
  }

  /** The modules that are on, in order: the tabs plus any header shortcut. Never empty. */
  get enabled(): ModuleID[] {
    return this.orderList.filter((id) => !this.disabledSet.has(id));
  }

  /** The modules shown in the tab bar, in order: the enabled ones minus those opened from the header. */
  get tabs(): ModuleID[] {
    return this.enabled.filter((id) => !this.headerKeys.has(id));
  }

  /** The enabled modules opened from a header button instead of a tab, in order. */
  get headerShortcuts(): ModuleID[] {
    return this.enabled.filter((id) => this.headerKeys.has(id));
  }

  /** The letter key that opens `module` from the header, or undefined for a tab or a disabled module. */
  headerKey(module: ModuleID): string | undefined {
    return this.isEnabled(module) ? this.headerKeys.get(module) : undefined;
  }

  /** The enabled header module that letter `key` opens, if any. */
  moduleForHeaderKey(key: string): ModuleID | undefined {
    const lower = key.toLowerCase();
    return this.headerShortcuts.find((id) => this.headerKeys.get(id) === lower);
  }

  isEnabled(module: ModuleID): boolean {
    return !this.disabledSet.has(module);
  }

  /** Whether `module` may be turned off (it isn't the last enabled one). */
  canDisable(module: ModuleID): boolean {
    return !this.isEnabled(module) || this.enabled.length > 1;
  }

  /** Turns a module on or off. Refuses (returns false) to disable the last enabled module. */
  setEnabled(module: ModuleID, isEnabled: boolean): boolean {
    if (isEnabled) {
      this.disabledSet.delete(module);
      return true;
    }
    if (!this.canDisable(module)) return false;
    this.disabledSet.add(module);
    return true;
  }

  /** The modules that aren't tabs, in the user's order: what the "Add more" library offers. */
  get available(): ModuleID[] {
    return this.orderList.filter((id) => this.disabledSet.has(id));
  }

  /**
   * Adds `module` from the library as the last tab, so adding never
   * reshuffles the tabs the user has. Does nothing for a module that is
   * already a tab or that the layout doesn't know.
   */
  add(module: ModuleID): void {
    const index = this.orderList.indexOf(module);
    if (!this.disabledSet.has(module) || index < 0) return;
    this.orderList.splice(index, 1);
    let lastTab = -1;
    this.orderList.forEach((id, i) => {
      if (!this.disabledSet.has(id)) lastTab = i;
    });
    this.orderList.splice(lastTab + 1, 0, module);
    this.disabledSet.delete(module);
  }

  /** Puts `module` back in the library. Refuses (returns false) to remove the last tab. */
  remove(module: ModuleID): boolean {
    return this.setEnabled(module, false);
  }

  /**
   * Reorders the tabs alone, with list-move offsets into `tabs` (SwiftUI's
   * `onMove`). Library modules and header shortcuts keep their slots.
   */
  moveTabs(source: Iterable<number>, destination: number): void {
    const tabs = this.tabs;
    const offsets = normalizedOffsets(source);
    const moving = pick(tabs, offsets);
    if (moving.length === 0) return;
    const insertAt = destination - offsets.filter((offset) => offset < destination).length;
    const remaining = tabs.filter((_, offset) => !offsets.includes(offset));
    remaining.splice(Math.min(Math.max(insertAt, 0), remaining.length), 0, ...moving);
    let next = 0;
    this.orderList = this.orderList.map((id) => {
      if (this.disabledSet.has(id) || this.headerKeys.has(id)) return id;
      return remaining[next++] ?? id;
    });
  }

  /**
   * Moves the tab `module` so it lands at `index` among `tabs`, what a drop
   * onto a slot hands over. Returns whether anything moved.
   */
  moveTab(module: ModuleID, index: number): boolean {
    const list = this.tabs;
    const from = list.indexOf(module);
    if (from < 0) return false;
    const target = Math.min(Math.max(index, 0), list.length - 1);
    if (target === from) return false;
    this.moveTabs([from], target > from ? target + 1 : target);
    return true;
  }

  /** Moves the tab `module` by `offset` slots, stopping at either end: keyboard moves. */
  moveTabBy(module: ModuleID, offset: number): boolean {
    const from = this.tabs.indexOf(module);
    if (from < 0) return false;
    return this.moveTab(module, from + offset);
  }

  /** Whether `moveTabBy` would move `module`: false for a header shortcut, a library module or a tab at that end. */
  canMoveTab(module: ModuleID, offset: number): boolean {
    const from = this.tabs.indexOf(module);
    if (offset === 0 || from < 0) return false;
    return from + offset >= 0 && from + offset < this.tabs.length;
  }

  /** Moves modules in `order` with the same semantics as SwiftUI's `onMove`. */
  move(source: Iterable<number>, destination: number): void {
    const offsets = normalizedOffsets(source);
    const moving = pick(this.orderList, offsets);
    if (moving.length === 0) return;
    const insertAt = destination - offsets.filter((offset) => offset < destination).length;
    const remaining = this.orderList.filter((_, offset) => !offsets.includes(offset));
    remaining.splice(Math.min(Math.max(insertAt, 0), remaining.length), 0, ...moving);
    this.orderList = remaining;
  }

  /** `module` if it's enabled, otherwise the first enabled module. */
  resolvedSelection(module: ModuleID): ModuleID {
    return this.isEnabled(module) ? module : (this.enabled[0] ?? module);
  }

  /** The tab after `module`, wrapping around; from a header module, the first tab. */
  moduleAfter(module: ModuleID): ModuleID {
    return this.step(module, 1);
  }

  /** The tab before `module`, wrapping around; from a header module, the last tab. */
  moduleBefore(module: ModuleID): ModuleID {
    return this.step(module, -1);
  }

  /** Number keys reach at most this many tabs (1-9). */
  static readonly maxShortcutTabs = 9;

  /** The tab number key `number` (1-based) jumps to, or undefined. */
  moduleForShortcut(number: number): ModuleID | undefined {
    const list = this.tabs;
    if (!Number.isInteger(number) || number < 1 || number > ModuleLayout.maxShortcutTabs || number > list.length) {
      return undefined;
    }
    return list[number - 1];
  }

  /** The number key (1-9) that jumps to `module`, or undefined. */
  shortcut(module: ModuleID): number | undefined {
    const index = this.tabs.indexOf(module);
    return index < 0 || index >= ModuleLayout.maxShortcutTabs ? undefined : index + 1;
  }

  private step(module: ModuleID, delta: number): ModuleID {
    const list = this.tabs;
    const first = list[0];
    const last = list[list.length - 1];
    if (first === undefined || last === undefined) return module;
    const index = list.indexOf(module);
    if (index < 0) return delta > 0 ? first : last;
    return list[(index + delta + list.length) % list.length] ?? module;
  }
}

/** The elements at `offsets` that exist, in offset order. */
function pick<T>(list: readonly T[], offsets: readonly number[]): T[] {
  return offsets.flatMap((offset) => (offset >= 0 && offset < list.length ? [list[offset] as T] : []));
}

/** An IndexSet's offsets: unique and ascending. */
function normalizedOffsets(source: Iterable<number>): number[] {
  return [...new Set(source)].sort((a, b) => a - b);
}

function sameList<T>(a: readonly T[], b: readonly T[]): boolean {
  return a.length === b.length && a.every((value, i) => value === b[i]);
}

function sameSet<T>(a: ReadonlySet<T>, b: ReadonlySet<T>): boolean {
  return a.size === b.size && [...a].every((value) => b.has(value));
}
