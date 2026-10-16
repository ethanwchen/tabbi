import type { ProgressItem } from "../providers/progressItem";

/**
 * Port of GoalCompletionWatch: notices the moment a goal for today is
 * reached, so the pet can put on a crown (a `crown` PetCheer) for it.
 *
 * It follows the ProgressItems every module shares (Anki reviews, a daily
 * focus time goal) and reports a goal only when it was seen with work left
 * and is now done. So a launch, a module switched on, or a day that starts
 * with nothing due never crowns anything, and a goal crowns once until it
 * has work left again (the next day's reviews).
 */
export class GoalCompletionWatch {
  /** Whether each goal seen last time was done; undefined before the first look. */
  private done: Map<string, boolean> | undefined;

  /** Takes the goals shared now and returns the ones reached since the last call. The first call only sets the baseline. */
  reached(progress: readonly ProgressItem[]): ProgressItem[] {
    const previous = this.done;
    const next = new Map<string, boolean>();
    const reached: ProgressItem[] = [];
    for (const item of progress) {
      const key = JSON.stringify([item.source, item.id]);
      /* A goal of 0 has nothing to reach: it counts as done, quietly. */
      const isDone = item.isComplete;
      next.set(key, isDone);
      if (isDone && item.target > 0 && previous?.get(key) === false) reached.push(item);
    }
    this.done = next;
    return reached;
  }
}
