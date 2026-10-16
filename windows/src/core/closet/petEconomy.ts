import { tr } from "../localization/tr";
import { PetPointsRules } from "../pets/petPointsRules";

/*
 * Port of PetEconomy and PetPriceTier: the study habit the Closet's prices
 * are set against (three 25 minute blocks a day, five days a week) and the
 * tiers that follow from it. docs/economy.md walks through the math.
 */
export const PetEconomy = {
  /** Finished focus blocks on a typical study day. */
  typicalBlocksPerDay: 3,
  /** The length of a typical focus block, in minutes. */
  typicalBlockMinutes: PetPointsRules.bonusMinutes,
  /** Days with some studying in a typical week. */
  typicalStudyDaysPerWeek: 5,

  /** Points for one typical finished focus block (35). */
  pointsPerTypicalBlock(): number {
    return PetPointsRules.points(PetEconomy.typicalBlockMinutes, true);
  },

  /** Points for a typical study day (105). */
  pointsPerTypicalDay(): number {
    return PetEconomy.typicalBlocksPerDay * PetEconomy.pointsPerTypicalBlock();
  },

  /** Points for a typical study week (525). */
  pointsPerTypicalWeek(): number {
    return PetEconomy.typicalStudyDaysPerWeek * PetEconomy.pointsPerTypicalDay();
  },

  /** Typical study days `points` take to earn, rounded up; 0 for nothing to earn. */
  typicalDays(points: number): number {
    return points > 0 ? Math.ceil(points / PetEconomy.pointsPerTypicalDay()) : 0;
  },

  /** Typical focus blocks `points` take to earn, rounded up. */
  typicalBlocks(points: number): number {
    return points > 0 ? Math.ceil(points / PetEconomy.pointsPerTypicalBlock()) : 0;
  },

  /** Typical study weeks `points` take to earn, rounded up. */
  typicalWeeks(points: number): number {
    return points > 0 ? Math.ceil(points / PetEconomy.pointsPerTypicalWeek()) : 0;
  },

  /**
   * The study it takes to earn `points`, in the unit a student plans in:
   * focus blocks within a day, study days within a week, weeks beyond.
   * Empty for nothing to earn.
   */
  studyToEarn(points: number): string {
    if (!(points > 0)) return "";
    if (points <= PetEconomy.pointsPerTypicalDay()) return tr("%lld focus blocks", PetEconomy.typicalBlocks(points));
    if (points <= PetEconomy.pointsPerTypicalWeek()) return tr("about %lld study days", PetEconomy.typicalDays(points));
    return tr("about %lld weeks", PetEconomy.typicalWeeks(points));
  },
} as const;

/** How long an item takes to earn at the typical pace, cheapest first. */
export const PET_PRICE_TIERS = ["free", "starter", "midTier", "showpiece"] as const;
export type PetPriceTier = (typeof PET_PRICE_TIERS)[number];

/** The prices the tier allows, in points (both ends included). */
export function tierPriceRange(tier: PetPriceTier): { lower: number; upper: number } {
  const day = PetEconomy.pointsPerTypicalDay();
  const week = PetEconomy.pointsPerTypicalWeek();
  switch (tier) {
    case "free":
      return { lower: 0, upper: 0 };
    case "starter":
      return { lower: 1, upper: day };
    case "midTier":
      return { lower: 2 * day, upper: week };
    case "showpiece":
      return { lower: 2 * week, upper: 4 * week };
  }
}

/** The tier whose range holds `cost`, or undefined for a price in a gap. */
export function tierForCost(cost: number): PetPriceTier | undefined {
  return PET_PRICE_TIERS.find((tier) => {
    const range = tierPriceRange(tier);
    return cost >= range.lower && cost <= range.upper;
  });
}
