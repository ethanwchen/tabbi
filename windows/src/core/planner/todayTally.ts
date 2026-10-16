import { tr } from "../localization/tr";
import type { PlannerDay } from "./plannerDay";
import type { SharedTodayItem } from "../providers/sharedTodayItem";

/**
 * Port of TodayTally: how much of today is done, counting the user's own
 * checklist and the rows other modules share alike. A shared goal counts
 * as one item that checks itself once its work hits zero.
 */
export class TodayTally {
  readonly doneCount: number;
  readonly totalCount: number;

  constructor(day: PlannerDay, shared: readonly SharedTodayItem[]) {
    this.doneCount = day.doneCount + shared.filter((item) => item.isDone).length;
    this.totalCount = day.items.length + shared.length;
  }

  /** Fraction of items done, 0 when there is nothing to do. */
  get progress(): number {
    return this.totalCount === 0 ? 0 : this.doneCount / this.totalCount;
  }

  /** Short caption for the panel header, e.g. "3 of 6 done". */
  get summary(): string {
    if (this.totalCount === 0) return tr("Nothing planned");
    if (this.doneCount === this.totalCount) return tr("All %lld done", this.totalCount);
    return tr("%lld of %lld done", this.doneCount, this.totalCount);
  }

  /** The caption for a day that hasn't started, e.g. "2 planned". */
  get plannedSummary(): string {
    return this.totalCount === 0 ? tr("Nothing planned") : tr("%lld planned", this.totalCount);
  }

  /** The summary for a narrow header, e.g. "3/6". */
  get shortSummary(): string {
    if (this.totalCount === 0) return tr("Nothing planned");
    return `${this.doneCount}/${this.totalCount}`;
  }
}
