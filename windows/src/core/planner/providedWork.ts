import type { ModuleID } from "../modules/moduleId";
import { tr } from "../localization/tr";
import { durationMinutes, durationQuantity } from "../formatting/durationFormat";

/*
 * Narrow stand-ins for the provider types Today and the planners read
 * (`TabbiKitCore/Providers`: ProvidedTask, ProgressItem, StudyDayTally,
 * SharedTodayItem and the two ProviderSnapshot helpers they use). The
 * providers port owns the full types; these have the same fields and
 * rules, so switching over is an import change.
 */

/** Stand-in for ProvidedTask: something to do today that a module shares. */
export interface ProvidedTask {
  readonly id: string;
  readonly source: ModuleID;
  readonly title: string;
  readonly isDone: boolean;
  /** A rough size for Plan my day, when the source knows one. */
  readonly estimatedMinutes?: number;
}

/** Stand-in for ProgressItem: a countable goal for today, such as Anki cards due. */
export interface ProgressItem {
  readonly id: string;
  readonly source: ModuleID;
  readonly title: string;
  readonly completed: number;
  /** Today's goal; 0 means there is nothing to do today. */
  readonly target: number;
  /** Plural noun for the counts, e.g. "cards". */
  readonly unit: string;
  /** A goal the user aims for rather than work that is due (a daily focus goal). */
  readonly waitsForStart: boolean;
}

/** Stand-in for StudyDayTally: today's study minutes, finished sessions and points. */
export interface StudyDayTally {
  readonly minutes: number;
  readonly sessions: number;
  readonly points: number;
}

/** The part of SharedTodayItem that TodayTally counts. */
export interface SharedTodayItemState {
  readonly isDone: boolean;
}

export function progressRemaining(item: ProgressItem): number {
  return Math.max(item.target - item.completed, 0);
}

export function progressIsComplete(item: ProgressItem): boolean {
  return progressRemaining(item) === 0;
}

/** A count in the goal's unit, "320 cards" or "1h 15m" for minutes. */
export function progressAmount(item: ProgressItem, count: number, locale = "en-US"): string {
  return durationQuantity(count, item.unit, locale);
}

/** What is left, "84 cards left" or "1h 15m left". */
export function progressRemainingText(item: ProgressItem, locale = "en-US"): string {
  return tr("%@ left", progressAmount(item, progressRemaining(item), locale));
}

/** Tasks shared by the modules in tab order, without repeats of one module's id (as ProviderSnapshot merges them). */
export function mergedTasks(byModule: readonly (readonly [ModuleID, readonly ProvidedTask[]])[]): ProvidedTask[] {
  const seen = new Set<string>();
  const result: ProvidedTask[] = [];
  for (const [module, tasks] of byModule) {
    for (const task of tasks) {
      const key = JSON.stringify([module, task.id]);
      if (seen.has(key)) continue;
      seen.add(key);
      result.push({ ...task, source: module });
    }
  }
  return result;
}

/** Goals shared by the modules in tab order, without repeats of one module's id. */
export function mergedProgress(byModule: readonly (readonly [ModuleID, readonly ProgressItem[]])[]): ProgressItem[] {
  const seen = new Set<string>();
  const result: ProgressItem[] = [];
  for (const [module, items] of byModule) {
    for (const item of items) {
      const key = JSON.stringify([module, item.id]);
      if (seen.has(key)) continue;
      seen.add(key);
      result.push({ ...item, source: module });
    }
  }
  return result;
}

/**
 * Port of ProviderSnapshot.plannableWork(excluding:): unfinished work that
 * modules other than `module` share, phrased for Plan my day's prompt,
 * "Anki reviews (320 cards left)" or "LeetCode daily (about 30 min)", goals
 * first, each in tab order.
 */
export function plannableWork(
  progress: readonly ProgressItem[],
  tasks: readonly ProvidedTask[],
  excluding: ModuleID,
  locale = "en-US",
): string[] {
  const goals = progress
    .filter((item) => item.source !== excluding && !progressIsComplete(item))
    .map((item) => `${item.title} (${progressRemainingText(item, locale)})`);
  const open = tasks
    .filter((task) => !task.isDone && task.source !== excluding)
    .map((task) => (task.estimatedMinutes === undefined ? task.title : `${task.title} (about ${task.estimatedMinutes} min)`));
  return [...goals, ...open];
}

/** A shared task's detail line on Today, its estimate as a duration. */
export function providedTaskDetail(task: ProvidedTask): string | undefined {
  return task.estimatedMinutes === undefined ? undefined : durationMinutes(task.estimatedMinutes);
}
