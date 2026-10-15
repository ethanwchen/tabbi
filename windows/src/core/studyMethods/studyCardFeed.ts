import type { ModuleID } from "../modules/moduleId";

/** The unit a progress goal counts flashcards in, e.g. Anki's reviews. */
export const CARD_UNIT = "cards";

/** The fields of a shared progress goal this reads; the providers port owns the full ProgressItem. */
export interface CardProgress {
  readonly source: ModuleID;
  readonly unit: string;
  readonly completed: number;
}

/**
 * Port of ProviderSnapshot.cardsReviewedToday(excluding:): cards reviewed
 * today across the card goals other modules share, or undefined when none
 * does. An Anki sprint feeds this to `StudySession.recordReviewedToday`, so
 * the Study timer counts cards without knowing which module reviews them.
 */
export function cardsReviewedToday(progress: readonly CardProgress[], excluding: ModuleID): number | undefined {
  const goals = progress.filter((item) => item.source !== excluding && item.unit === CARD_UNIT);
  if (goals.length === 0) return undefined;
  return goals.reduce((sum, item) => sum + Math.max(item.completed, 0), 0);
}
