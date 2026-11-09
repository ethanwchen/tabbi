import { tr } from "../localization/tr";

/*
 * Port of ProgressTrack.swift: the habits the Closet's Goals section
 * counts, each with a ladder of four badge tiers, and the badges' ids,
 * names and labels. docs/design/progression.md explains the goals.
 */

export const PROGRESS_TRACKS = [
  "focusHours",
  "studyDays",
  "gentleStreak",
  "sessions",
  "cards",
  "tasks",
  "breakMoves",
  "party",
  "methods",
  "steadyWeeks",
  "water",
  "monthlyQuests",
] as const;
export type ProgressTrack = (typeof PROGRESS_TRACKS)[number];

/** Badge tiers, Bronze first; Starlight is the rare one. Port of ProgressTier. */
export const PROGRESS_TIERS = ["bronze", "silver", "gold", "starlight"] as const;
export type ProgressTier = (typeof PROGRESS_TIERS)[number];

/** The tier's number, 1 for Bronze through 4 for Starlight, as the Mac's raw values. */
export function tierNumber(tier: ProgressTier): number {
  return PROGRESS_TIERS.indexOf(tier) + 1;
}

export function tierFromNumber(value: number): ProgressTier | undefined {
  return Number.isInteger(value) ? PROGRESS_TIERS[value - 1] : undefined;
}

export function nextTier(tier: ProgressTier): ProgressTier | undefined {
  return PROGRESS_TIERS[tierNumber(tier)];
}

export function tierDisplayName(tier: ProgressTier): string {
  /* Keyed by id: "Silver" is also a fur color, which some languages say as an adjective. */
  return tr(`badge.tier.${tier}`);
}

/** What each tier asks for, Bronze first, in the track's unit (minutes for focus). */
export function trackThresholds(track: ProgressTrack): readonly number[] {
  switch (track) {
    case "focusHours":
      return [10 * 60, 50 * 60, 200 * 60, 500 * 60];
    case "studyDays":
      return [7, 30, 100, 250];
    case "gentleStreak":
      return [7, 30, 90, 180];
    case "sessions":
      return [10, 50, 200, 600];
    case "cards":
      return [500, 2500, 10000, 50000];
    case "tasks":
      return [10, 50, 200, 500];
    case "breakMoves":
      return [10, 50, 150, 400];
    case "party":
      return [1, 5, 20, 60];
    case "methods":
      return [2, 3, 4, 6];
    case "steadyWeeks":
      return [2, 4, 12, 26];
    case "water":
      return [20, 100, 300, 1000];
    case "monthlyQuests":
      return [1, 3, 6, 12];
  }
}

export function trackGoal(track: ProgressTrack, tier: ProgressTier): number {
  return trackThresholds(track)[tierNumber(tier) - 1] ?? 0;
}

/** The highest tier `value` reaches, or undefined below Bronze. */
export function tierFor(track: ProgressTrack, value: number): ProgressTier | undefined {
  let reached: ProgressTier | undefined;
  for (const tier of PROGRESS_TIERS) if (value >= trackGoal(track, tier)) reached = tier;
  return reached;
}

/** Weeks need this many study days to count as steady. */
export const STEADY_WEEK_DAYS = 3;

export function trackDisplayName(track: ProgressTrack): string {
  switch (track) {
    case "focusHours":
      return tr("Focus time");
    case "studyDays":
      return tr("Study days");
    case "gentleStreak":
      return tr("Gentle streak");
    case "sessions":
      return tr("Sessions");
    case "cards":
      return tr("Flashcards");
    case "tasks":
      return tr("Tasks");
    case "breakMoves":
      return tr("Break moves");
    case "party":
      return tr("Party");
    case "methods":
      return tr("Study methods");
    case "steadyWeeks":
      return tr("Steady weeks");
    case "water":
      return tr("Water");
    case "monthlyQuests":
      return tr("Monthly quests");
  }
}

/** How to reach `goal` in the track's unit, as one sentence: "Focus for 200 hours in total." */
export function howToReach(track: ProgressTrack, goal: number): string {
  switch (track) {
    case "focusHours":
      return tr("Focus for %lld hours in total.", Math.trunc(goal / 60));
    case "studyDays":
      return tr("Study on %lld different days.", goal);
    case "gentleStreak":
      return tr("Keep a %lld-day streak. Freezes count.", goal);
    case "sessions":
      return tr("Finish %lld focus sessions.", goal);
    case "cards":
      return tr("Review %lld flashcards.", goal);
    case "tasks":
      return tr("Check off %lld tasks.", goal);
    case "breakMoves":
      return tr("Do %lld break moves with your pet.", goal);
    case "party":
      return tr("Finish %lld Party sessions with friends.", goal);
    case "methods":
      return tr("Try %lld different study methods.", goal);
    case "steadyWeeks":
      return tr("Study 3 days or more in %lld different weeks.", goal);
    case "water":
      return tr("Log %lld glasses of water.", goal);
    case "monthlyQuests":
      return tr("Finish every monthly quest in %lld months.", goal);
  }
}

/** A count as a tile shows it: as is below 10,000, then in whole thousands ("12k"). */
export function shortCount(count: number): string {
  if (count < 10_000) return String(count);
  return tr("%lldk", Math.trunc(count / 1000));
}

/**
 * How far along `value` is toward `goal`, short enough for a tile: "142/200 h",
 * "23/30", "4210/10k". Hours round down and the value is capped at the goal.
 */
export function progressLabel(track: ProgressTrack, valueIn: number, goal: number): string {
  const value = Math.max(0, Math.min(valueIn, goal));
  if (track === "focusHours") return tr("%lld/%lld h", Math.trunc(value / 60), Math.trunc(goal / 60));
  return `${shortCount(value)}/${shortCount(goal)}`;
}

/** One badge: a track at a tier. Port of ProgressBadge. */
export interface ProgressBadge {
  readonly track: ProgressTrack;
  readonly tier: ProgressTier;
}

/** The badge's stable id, such as `focusHours.3`. */
export function badgeID(badge: ProgressBadge): string {
  return `${badge.track}.${tierNumber(badge.tier)}`;
}

export function badgeFromID(id: string): ProgressBadge | undefined {
  const parts = id.split(".");
  if (parts.length !== 2) return undefined;
  const track = PROGRESS_TRACKS.find((candidate) => candidate === parts[0]);
  const raw = parts[1] ?? "";
  if (!track || !/^-?\d+$/.test(raw)) return undefined;
  const tier = tierFromNumber(Number(raw));
  return tier ? { track, tier } : undefined;
}

export function badgeGoal(badge: ProgressBadge): number {
  return trackGoal(badge.track, badge.tier);
}

export function badgeHowToEarn(badge: ProgressBadge): string {
  return howToReach(badge.track, badgeGoal(badge));
}

/** "Focus time Gold". */
export function badgeDisplayName(badge: ProgressBadge): string {
  return tr("%@ %@", trackDisplayName(badge.track), tierDisplayName(badge.tier));
}

/** Every badge, track by track, Bronze first: the order badges sort in. */
export const ALL_BADGES: readonly ProgressBadge[] = PROGRESS_TRACKS.flatMap((track) =>
  PROGRESS_TIERS.map((tier) => ({ track, tier })),
);

const BADGE_ORDER = new Map(ALL_BADGES.map((badge, index) => [badgeID(badge), index]));

export function compareBadges(a: ProgressBadge, b: ProgressBadge): number {
  return (BADGE_ORDER.get(badgeID(a)) ?? 0) - (BADGE_ORDER.get(badgeID(b)) ?? 0);
}
