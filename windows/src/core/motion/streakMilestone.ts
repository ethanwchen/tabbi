/*
 * Port of StreakMilestone: which streak lengths earn a milestone celebration.
 * Only round, meaningful lengths count, so a daily habit sparkles a handful
 * of times a year rather than every day.
 */

/** The milestone lengths up to a year, in days. */
export const STREAK_MILESTONE_DAYS: readonly number[] = [7, 14, 30, 50, 100, 200, 365];

/** One of the listed lengths, or past a year every further 100 days and every whole year. */
export function isStreakMilestone(length: number): boolean {
  if (length <= 0) return false;
  if (STREAK_MILESTONE_DAYS.includes(length)) return true;
  return length > 365 && (length % 100 === 0 || length % 365 === 0);
}

/**
 * The milestone a streak reached by growing from `old` to `next`, or
 * undefined. Without a baseline (`old` undefined, the first look after
 * launch) nothing is celebrated; when it grew by more than a day between two
 * looks, the largest milestone passed counts, once.
 */
export function streakMilestoneReached(old: number | undefined, next: number): number | undefined {
  if (old === undefined || next <= old) return undefined;
  for (let length = next; length >= Math.max(old + 1, 1); length--) {
    if (isStreakMilestone(length)) return length;
  }
  return undefined;
}
