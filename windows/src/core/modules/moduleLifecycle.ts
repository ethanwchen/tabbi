import type { ModuleID } from "./moduleId";

/** What one `update` asks the caller to do. */
export interface ModuleLifecycleChanges {
  /** Newly enabled modules, in tab order. */
  readonly start: readonly ModuleID[];
  /** Modules no longer enabled, in the order they were started. */
  readonly stop: readonly ModuleID[];
}

export function isEmptyChanges(changes: ModuleLifecycleChanges): boolean {
  return changes.start.length === 0 && changes.stop.length === 0;
}

/**
 * Port of ModuleLifecycle: which modules are running, and which to start or
 * stop when the enabled tabs change. A module runs while it is enabled (not
 * only while its panel shows), so background work feeding Today or the
 * ticker can live in its lifecycle.
 */
export class ModuleLifecycle {
  private runningList: ModuleID[] = [];

  /** Running modules, in the order they were started. */
  get running(): readonly ModuleID[] {
    return this.runningList;
  }

  /** Moves to `enabled` (duplicates ignored) and returns the difference. Reordering changes nothing. */
  update(enabled: readonly ModuleID[]): ModuleLifecycleChanges {
    const seen = new Set(enabled);
    const target = [...seen];
    const stop = this.runningList.filter((id) => !seen.has(id));
    const start = target.filter((id) => !this.runningList.includes(id));
    this.runningList = [...this.runningList.filter((id) => seen.has(id)), ...start];
    return { start, stop };
  }

  /** Stops everything, e.g. when the app quits. */
  stopAll(): ModuleLifecycleChanges {
    const stop = this.runningList;
    this.runningList = [];
    return { start: [], stop };
  }
}
