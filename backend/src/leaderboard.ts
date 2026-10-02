// Weekly study-minutes leaderboard among a user and their friends.
import type { Profile } from "./profile";

/** How long per-day study minutes are kept; enough for this week and last week, with slack. */
export const STUDY_DAY_RETENTION_DAYS = 28;

export interface LeaderboardEntry {
  rank: number;
  minutes: number;
  me: boolean;
  profile: Profile;
}

/**
 * Sorts by minutes (most first), then by name, and assigns standard competition ranks: equal minutes
 * share a rank and the next rank skips (1, 1, 3), so a tie never looks like one person is ahead.
 */
export function rankEntries(entries: { minutes: number; me: boolean; profile: Profile }[]): LeaderboardEntry[] {
  const sorted = [...entries].sort((a, b) =>
    b.minutes - a.minutes
    || a.profile.name.localeCompare(b.profile.name, undefined, { sensitivity: "base" })
    || a.profile.code.localeCompare(b.profile.code));
  let rank = 0;
  return sorted.map((e, i) => {
    if (i === 0 || e.minutes !== sorted[i - 1].minutes) rank = i + 1;
    return { rank, ...e };
  });
}
