import { CARD_UNIT } from "../formatting/durationFormat";
import type { ModuleID } from "../modules/moduleId";
import type { ProgressItem } from "../providers/progressItem";

/**
 * Port of ProviderSnapshot.cardsReviewedToday(excluding:): cards reviewed
 * today across the card goals other modules share, or undefined when none
 * does. An Anki sprint feeds this to `StudySession.recordReviewedToday`, so
 * the Study timer counts cards without knowing which module reviews them.
 */
export function cardsReviewedToday(progress: readonly ProgressItem[], excluding: ModuleID): number | undefined {
  const goals = progress.filter((item) => item.source !== excluding && item.unit === CARD_UNIT);
  if (goals.length === 0) return undefined;
  return goals.reduce((sum, item) => sum + Math.max(item.completed, 0), 0);
}
