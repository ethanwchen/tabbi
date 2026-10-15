/*
 * Port of StreakMilestone (Motion/StreakMilestone.swift on the Mac): the
 * round streak lengths worth a small celebration.
 */

/** Milestones in the first year. */
export const STREAK_MILESTONE_DAYS: readonly number[] = [7, 14, 30, 50, 100, 200, 365];

/** Whether `length` is a milestone: a round length, and past a year every hundred days and every year. */
export function isStreakMilestone(length: number): boolean {
  if (!(length > 0)) return false;
  if (STREAK_MILESTONE_DAYS.includes(length)) return true;
  return length > 365 && (length % 100 === 0 || length % 365 === 0);
}

/**
 * The milestone a streak growing from `old` to `next` reached, the largest
 * once for a jump past several, or undefined. No baseline (`old` undefined),
 * a streak holding, or a broken one reaches nothing.
 */
export function streakMilestoneReached(old: number | undefined, next: number): number | undefined {
  if (old === undefined || !(next > old)) return undefined;
  for (let length = next; length >= Math.max(old + 1, 1); length--) {
    if (isStreakMilestone(length)) return length;
  }
  return undefined;
}
