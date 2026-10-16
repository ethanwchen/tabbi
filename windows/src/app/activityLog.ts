/*
 * Port of ActivityLog: the shared, append-only log of what happened (focus
 * stretches, breaks, cards reviewed, tasks done), for streaks, insights and
 * the pet. A module logs its own events with `record`, its own id as the
 * source, and anyone reads them back by day or follows `recorded`, so
 * nothing reaches into another module's store to learn what the user did.
 * Records persist as one versioned JSON file per local day in the edition's
 * `Activity` folder; demo and snapshot runs keep them in memory.
 */

import { ActivityLogRepository } from "../core/activity/activityLogRepository";
import { activityDay, type ActivityRecord } from "../core/activity/activityRecord";
import type { PlannerDayKey } from "../core/planner/plannerDayKey";
import { Emitter } from "./store";

export class ActivityLog {
  /** Every record in demo and snapshot runs; otherwise only those a day file refused, so reads in this run still see them. */
  private unsaved: ActivityRecord[] = [];
  /** Appends run one after another, so two records for the same day never race on its file. */
  private queue: Promise<unknown> = Promise.resolve();
  private readonly recordedEmitter = new Emitter<ActivityRecord>();

  /**
   * A log saved by `repository`, or kept in memory when it is undefined.
   * `timeZone` names the user's zone, read on every call so days follow a zone change.
   */
  constructor(
    private readonly repository: ActivityLogRepository | undefined,
    private readonly timeZone: () => string,
  ) {}

  /** Each record as it is logged. */
  readonly recorded = this.recordedEmitter.on;

  /**
   * Appends records and tells followers about each (at once, before the file
   * is written). Resolves true when they are on disk, false when they only
   * live in memory for this run (demo and snapshot runs, or a day file that
   * can't be written).
   */
  record(records: ActivityRecord | readonly ActivityRecord[]): Promise<boolean> {
    const list: readonly ActivityRecord[] = Array.isArray(records) ? records : [records as ActivityRecord];
    for (const record of list) this.recordedEmitter.emit(record);
    const repository = this.repository;
    if (list.length === 0) return Promise.resolve(repository !== undefined);
    if (repository === undefined) {
      this.unsaved.push(...list);
      return Promise.resolve(false);
    }
    const saved = this.queue.then(
      () => repository.append(list).then(() => true),
      () => repository.append(list).then(() => true),
    ).catch(() => {
      this.unsaved.push(...list);
      return false;
    });
    this.queue = saved;
    return saved;
  }

  /** The records that count toward `day`, oldest first. */
  records(day: PlannerDayKey): Promise<ActivityRecord[]> {
    return this.recordsBetween(day, day);
  }

  /** The records of every day from `first` through `last`, oldest first, once pending appends have landed. */
  async recordsBetween(first: PlannerDayKey, last: PlannerDayKey): Promise<ActivityRecord[]> {
    await this.queue.catch(() => undefined);
    const stored = this.repository ? await this.repository.recordsBetween(first, last) : [];
    const known = new Set(stored.map((record) => record.id));
    const zone = this.timeZone();
    const pending = this.unsaved.filter((record) => {
      const day = activityDay(record, zone);
      return day >= first && day <= last && !known.has(record.id);
    });
    /* Stable, so records that end together keep the order they were logged in. */
    return [...stored, ...pending].sort((a, b) => a.end - b.end);
  }
}
