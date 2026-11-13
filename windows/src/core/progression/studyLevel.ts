import { colorFromHex, type PetColor } from "../pets/petPalette";
import { tr } from "../localization/tr";

/*
 * Port of StudyLevel.swift: the pet's Study Level, an endless level earned
 * only from total focus hours (the Focus time badge's minutes). It never
 * resets and never goes down, and it pays no study points. Every 5 levels
 * unlock a nameplate color, every 10 a rank. docs/design/progression.md has
 * the curve's table; shared/fixtures/progression/levels.json pins it.
 */

/** Hours at level 1, and how steeply the curve grows. */
export const CURVE_SCALE = 4;
export const CURVE_EXPONENT = 1.6;
export const LEVELS_PER_NAMEPLATE = 5;
export const LEVELS_PER_RANK = 10;
/** The highest level friends are told and the server keeps. */
export const MAX_SHARED_LEVEL = 999;

/** Whole hours of focus in total to reach `level`: round(4 * n^1.6); 0 at level 0 and below. */
export function hoursToReach(level: number): number {
  if (level <= 0) return 0;
  return Math.round(CURVE_SCALE * level ** CURVE_EXPONENT);
}

export function minutesToReach(level: number): number {
  return hoursToReach(level) * 60;
}

/** The level `focusMinutes` reach: the highest n whose minutesToReach(n) is covered. */
export function levelFromMinutes(focusMinutes: number): number {
  let level = 0;
  while (minutesToReach(level + 1) <= focusMinutes) level++;
  return level;
}

/** How far `focusMinutes` are from `level` to the next, 0 to 1. */
export function levelFraction(level: number, focusMinutes: number): number {
  const start = minutesToReach(level);
  const end = minutesToReach(level + 1);
  if (end <= start) return 0;
  return Math.min(1, Math.max(0, (focusMinutes - start) / (end - start)));
}

/** "Lv 12". */
export function levelShortLabel(level: number): string {
  return tr("Lv %lld", level);
}

/** "Level 12". */
export function levelLabel(level: number): string {
  return tr("Level %lld", level);
}

export function levelUnlocksNameplate(level: number): boolean {
  return level > 0 && level % LEVELS_PER_NAMEPLATE === 0 && nameplateUnlockedAt(level) !== undefined;
}

export function levelStartsRank(level: number): boolean {
  return level > 0 && level % LEVELS_PER_RANK === 0;
}

// MARK: Ranks

export const RANK_TIERS = ["spark", "ember", "comet", "nova", "nebula", "galaxy"] as const;
export type RankTier = (typeof RANK_TIERS)[number];
export const MAX_PIPS = 4;

export interface StudyRank {
  readonly tier: RankTier;
  /** 1 for every named rank; 2 for Galaxy II and so on. */
  readonly numeral: number;
}

export function makeRank(tier: RankTier, numeral = 1): StudyRank {
  return { tier, numeral: tier === "galaxy" ? Math.max(1, numeral) : 1 };
}

export function rankForLevel(level: number): StudyRank {
  const band = Math.trunc(Math.max(0, level) / LEVELS_PER_RANK);
  const tier = RANK_TIERS[band];
  if (tier !== undefined) return makeRank(tier);
  return makeRank("galaxy", band - RANK_TIERS.length + 2);
}

export function rankFirstLevel(rank: StudyRank): number {
  return (RANK_TIERS.indexOf(rank.tier) + rank.numeral - 1) * LEVELS_PER_RANK;
}

export function nextRank(rank: StudyRank): StudyRank {
  return rankForLevel(rankFirstLevel(rank) + LEVELS_PER_RANK);
}

/** `spark`, `galaxy`, `galaxy-2`. */
export function rankID(rank: StudyRank): string {
  return rank.numeral > 1 ? `${rank.tier}-${rank.numeral}` : rank.tier;
}

export function rankPips(rank: StudyRank): number {
  return Math.min(Math.max(rank.numeral - 1, 0), MAX_PIPS);
}

export function rankTierName(tier: RankTier): string {
  return tr(`rank.${tier}`);
}

/** "Ember", "Galaxy II". */
export function rankName(rank: StudyRank): string {
  if (rank.numeral <= 1) return rankTierName(rank.tier);
  return tr("rank.numbered %@ %@", rankTierName(rank.tier), romanNumeral(rank.numeral));
}

/** Roman numerals below 4,000, digits above. */
export function romanNumeral(n: number): string {
  if (n <= 0 || n >= 4000) return String(n);
  const table: [number, string][] = [
    [1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"],
    [50, "L"], [40, "XL"], [10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"],
  ];
  let left = n;
  let text = "";
  for (const [value, letters] of table) {
    while (left >= value) {
      text += letters;
      left -= value;
    }
  }
  return text;
}

// MARK: Nameplates

export const NAMEPLATES = [
  "plain", "peach", "ember", "honey", "sky", "mint", "rose", "lilac", "nebula", "coral", "gold", "aurora", "starlight",
] as const;
export type Nameplate = (typeof NAMEPLATES)[number];

const NAMEPLATE_HEX: Record<Nameplate, string> = {
  plain: "#F5F5F7",
  peach: "#FFC2A6",
  ember: "#FFA06B",
  honey: "#FFD873",
  sky: "#9AD8FF",
  mint: "#8FE8C0",
  rose: "#FFA3C9",
  lilac: "#CDB4FF",
  nebula: "#B5A3FF",
  coral: "#FF9E94",
  gold: "#FFCF4D",
  aurora: "#7FF2DC",
  starlight: "#ECE4FF",
};

export function isNameplate(value: unknown): value is Nameplate {
  return typeof value === "string" && (NAMEPLATES as readonly string[]).includes(value);
}

export function nameplateUnlockLevel(nameplate: Nameplate): number {
  return NAMEPLATES.indexOf(nameplate) * LEVELS_PER_NAMEPLATE;
}

export function nameplateUnlockedAt(level: number): Nameplate | undefined {
  if (level < 0 || level % LEVELS_PER_NAMEPLATE !== 0) return undefined;
  return NAMEPLATES[level / LEVELS_PER_NAMEPLATE];
}

export function unlockedNameplates(level: number): Nameplate[] {
  return NAMEPLATES.filter((nameplate) => nameplateUnlockLevel(nameplate) <= level);
}

export function nextNameplate(level: number): Nameplate | undefined {
  return NAMEPLATES.find((nameplate) => nameplateUnlockLevel(nameplate) > level);
}

export function nameplateHex(nameplate: Nameplate): string {
  return NAMEPLATE_HEX[nameplate];
}

export function nameplateColor(nameplate: Nameplate): PetColor {
  const color = colorFromHex(NAMEPLATE_HEX[nameplate]);
  if (!color) throw new Error(nameplate);
  return color;
}

/** The rarer colors, from Level 40, glow softly around the name. */
export function nameplateGlows(nameplate: Nameplate): boolean {
  return nameplateUnlockLevel(nameplate) >= 40;
}

export function nameplateName(nameplate: Nameplate): string {
  return tr(`nameplate.${nameplate}`);
}

// MARK: Standing

/** What friends see in Party: the level (the rank follows) and the nameplate. */
export interface StudyStanding {
  readonly level: number;
  readonly nameplate: Nameplate;
}

/** "Level 12, Ember". */
export function standingHelp(standing: StudyStanding): string {
  return tr("%@, %@", levelLabel(standing.level), rankName(rankForLevel(standing.level)));
}
