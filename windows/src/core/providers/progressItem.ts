import { durationQuantity } from "../formatting/durationFormat";
import { tr } from "../localization/tr";
import type { ModuleID } from "../modules/moduleId";

/**
 * Port of ProvidedAction: a one-click action a module offers on something it
 * shares, such as Anki's "Study Spanish verbs" on its reviews goal. Today's
 * row and the closed island run it on click (and still open the module), so
 * a module's most common action works from anywhere without the shared
 * views knowing what it does. The app hands `id` back to the module.
 */
export interface ProvidedAction {
  /** Meaningful only to the module that offered it. */
  readonly id: string;
  /** What a click does, e.g. "Study Spanish verbs", for tooltips. */
  readonly title: string;
}

export interface ProgressItemInit {
  id: string;
  source: ModuleID;
  title: string;
  completed: number;
  target: number;
  unit: string;
  action?: ProvidedAction | undefined;
  waitsForStart?: boolean;
}

/**
 * Port of ProgressItem: a countable goal for today, such as Anki cards due
 * or practice questions answered. The ProgressSource role of a module:
 * Today and the ticker show it without knowing which module it came from.
 */
export class ProgressItem {
  /** Stable within its source module. */
  readonly id: string;
  /** The module that provided it; `ProviderSnapshot` sets it when merging. */
  readonly source: ModuleID;
  readonly title: string;
  readonly completed: number;
  /** Today's goal; 0 means there is nothing to do today. */
  readonly target: number;
  /** Plural noun for the counts, e.g. "cards". */
  readonly unit: string;
  /** What a click on the goal does, beyond opening its module. */
  readonly action: ProvidedAction | undefined;
  /**
   * A goal the user aims for rather than work that is due (a daily focus
   * time goal, not cards due). The closed island shows it only once the day
   * has some progress, so a fresh day never opens on "2h left" for a goal
   * the user may not even know about.
   */
  readonly waitsForStart: boolean;

  constructor(init: ProgressItemInit) {
    this.id = init.id;
    this.source = init.source;
    this.title = init.title;
    this.completed = init.completed;
    this.target = init.target;
    this.unit = init.unit;
    this.action = init.action;
    this.waitsForStart = init.waitsForStart ?? false;
  }

  /** The same goal from `source`, as `ProviderSnapshot` stamps it when merging. */
  withSource(source: ModuleID): ProgressItem {
    return new ProgressItem({ ...this, source });
  }

  get remaining(): number {
    return Math.max(this.target - this.completed, 0);
  }

  /** What is left, e.g. "84 cards left" or "1h 15m left", with plain counts written in `locale`. */
  remainingText(locale: string): string {
    return tr("%@ left", this.amount(this.remaining, locale));
  }

  /**
   * A count in this goal's unit, e.g. "320 cards". Minutes read as a
   * duration ("45 min", "2h", "1h 15m"), so a two-hour goal never shows as
   * "120 min".
   */
  amount(count: number, locale: string): string {
    return durationQuantity(count, this.unit, locale);
  }

  get isComplete(): boolean {
    return this.remaining === 0;
  }

  /**
   * Whether the closed island has something worth saying about this goal:
   * work left, and for a goal that `waitsForStart`, some already done.
   */
  get showsBesideNotch(): boolean {
    return !this.isComplete && (this.completed > 0 || !this.waitsForStart);
  }

  /** Share of the goal done, clamped to 0...1; a goal of 0 counts as done. */
  get fraction(): number {
    return this.target > 0 ? Math.min(Math.max(this.completed / this.target, 0), 1) : 1;
  }

  equals(other: ProgressItem): boolean {
    return (
      this.id === other.id &&
      this.source === other.source &&
      this.title === other.title &&
      this.completed === other.completed &&
      this.target === other.target &&
      this.unit === other.unit &&
      this.action?.id === other.action?.id &&
      this.action?.title === other.action?.title &&
      this.waitsForStart === other.waitsForStart
    );
  }
}
