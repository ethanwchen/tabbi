import { durationMinutes } from "../formatting/durationFormat";
import type { ModuleID } from "../modules/moduleId";
import type { ProvidedAction } from "./progressItem";
import type { ProviderSnapshot } from "./providerSnapshot";

/**
 * Port of SharedTodayItem: one row Today shows for another module's task or
 * progress goal, such as "Anki reviews, 320 cards left". Today lists these
 * above its own checklist, so a new provider appears there without Today
 * knowing about it.
 */
export interface SharedTodayItem {
  /** Unique across modules: the source id plus the item's own id. */
  readonly id: string;
  /** The module to open when the row is clicked. */
  readonly source: ModuleID;
  readonly title: string;
  /** A short count such as "320 cards left", or undefined for a plain task. */
  readonly detail: string | undefined;
  /** Share done, 0...1, for a progress bar; undefined for a plain task. */
  readonly fraction: number | undefined;
  readonly isDone: boolean;
  /** What a click runs besides opening `source`, e.g. Anki's "Study Spanish verbs". */
  readonly action: ProvidedAction | undefined;
}

/**
 * Port of ProviderSnapshot.sharedTodayItems(excluding:): what modules other
 * than `module` share for today, progress goals first (they are the day's
 * big blocks), then tasks, each in tab order. Goals with nothing to do today
 * are left out, since they would only add a finished row the user never saw
 * open. A goal's detail is what is left ("320 cards left") until it is met,
 * then the day's total. Plain counts are written in `locale`.
 */
export function sharedTodayItems(snapshot: ProviderSnapshot, module: ModuleID, locale: string): SharedTodayItem[] {
  const goals = snapshot.progress
    .filter((item) => item.source !== module && item.target > 0)
    .map(
      (item): SharedTodayItem => ({
        id: `${item.source}/progress/${item.id}`,
        source: item.source,
        title: item.title,
        detail: item.isComplete ? item.amount(item.target, locale) : item.remainingText(locale),
        fraction: item.fraction,
        isDone: item.isComplete,
        action: item.action,
      }),
    );
  const tasks = snapshot.tasks
    .filter((task) => task.source !== module)
    .map(
      (task): SharedTodayItem => ({
        id: `${task.source}/task/${task.id}`,
        source: task.source,
        title: task.title,
        detail: task.estimatedMinutes === undefined ? undefined : durationMinutes(task.estimatedMinutes),
        fraction: undefined,
        isDone: task.isDone,
        action: undefined,
      }),
    );
  return [...goals, ...tasks];
}

/**
 * Port of ProviderSnapshot.plannableWork(excluding:): unfinished work that
 * modules other than `module` share, phrased for Plan my day's prompt, e.g.
 * "Anki reviews (320 cards left)" or "LeetCode daily (about 30 min)". Same
 * order as `sharedTodayItems`, so the AI sees the day's big goals first.
 */
export function plannableWork(snapshot: ProviderSnapshot, module: ModuleID, locale: string): string[] {
  const goals = snapshot.progress
    .filter((item) => item.source !== module && !item.isComplete)
    .map((item) => `${item.title} (${item.remainingText(locale)})`);
  const tasks = snapshot.openTasks
    .filter((task) => task.source !== module)
    .map((task) => (task.estimatedMinutes === undefined ? task.title : `${task.title} (about ${task.estimatedMinutes} min)`));
  return [...goals, ...tasks];
}
