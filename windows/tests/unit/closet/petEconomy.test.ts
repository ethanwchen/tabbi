import { describe, expect, it } from "vitest";
import { PET_PRICE_TIERS, PetEconomy, tierForCost, tierPriceRange } from "../../../src/core/closet/petEconomy";
import { setLookup } from "../../../src/core/localization/tr";
import { accessoryItem } from "../../../src/core/pets/petItem";
import { SHOP_ITEMS, isFree, itemCost, itemTier } from "../../../src/core/pets/petUnlocks";

// Port of PetEconomyTests.
describe("PetEconomy", () => {
  it("the typical pace follows the points rules", () => {
    expect(PetEconomy.pointsPerTypicalBlock(), "25 focused minutes plus the completion bonus").toBe(35);
    expect(PetEconomy.pointsPerTypicalDay(), "three blocks a day").toBe(105);
    expect(PetEconomy.pointsPerTypicalWeek(), "five study days a week").toBe(525);
  });

  it("time to earn rounds up", () => {
    expect(PetEconomy.typicalDays(0)).toBe(0);
    expect(PetEconomy.typicalDays(-5)).toBe(0);
    expect(PetEconomy.typicalDays(1)).toBe(1);
    expect(PetEconomy.typicalDays(105)).toBe(1);
    expect(PetEconomy.typicalDays(106)).toBe(2);
    expect(PetEconomy.typicalBlocks(35)).toBe(1);
    expect(PetEconomy.typicalBlocks(36)).toBe(2);
    expect(PetEconomy.typicalBlocks(0)).toBe(0);
  });

  it("study to earn speaks in blocks, then days, then weeks", () => {
    expect(PetEconomy.studyToEarn(0)).toBe("");
    // "1 focus block" comes from the catalog's plural variations, which the
    // English-only tr() does not apply yet; stand in for that lookup here.
    setLookup((key, args) => (key === "%lld focus blocks" && args[0] === 1 ? "%lld focus block" : undefined));
    try {
      expect(PetEconomy.studyToEarn(1)).toBe("1 focus block");
      expect(PetEconomy.studyToEarn(35)).toBe("1 focus block");
    } finally {
      setLookup(() => undefined);
    }
    expect(PetEconomy.studyToEarn(36)).toBe("2 focus blocks");
    expect(PetEconomy.studyToEarn(105), "a day's points stay in blocks").toBe("3 focus blocks");
    expect(PetEconomy.studyToEarn(106)).toBe("about 2 study days");
    expect(PetEconomy.studyToEarn(525)).toBe("about 5 study days");
    expect(PetEconomy.studyToEarn(526)).toBe("about 2 weeks");
    expect(PetEconomy.typicalWeeks(1050)).toBe(2);
    expect(PetEconomy.studyToEarn(2100), "the priciest item takes about a month").toBe("about 4 weeks");
  });

  it("tiers do not overlap and leave gaps", () => {
    const ranges = PET_PRICE_TIERS.map(tierPriceRange);
    for (let i = 1; i < ranges.length; i++) {
      expect((ranges[i - 1]?.upper ?? 0) < (ranges[i]?.lower ?? 0)).toBe(true);
    }
    expect(tierForCost(150), "between a day and two days is no tier").toBeUndefined();
    expect(tierForCost(800), "between a week and two weeks is no tier").toBeUndefined();
    expect(tierForCost(5000), "beyond four weeks is no tier").toBeUndefined();
  });

  it("every price sits inside a tier", () => {
    for (const item of SHOP_ITEMS) {
      expect(tierForCost(itemCost(item)), `${item} costs ${itemCost(item)}, outside every tier`).toBeDefined();
      expect(itemTier(item), item).toBe(tierForCost(itemCost(item)));
    }
  });

  it("the first finished block buys a starter", () => {
    const cheapest = Math.min(...SHOP_ITEMS.filter((item) => !isFree(item)).map(itemCost));
    expect(cheapest).toBe(PetEconomy.pointsPerTypicalBlock());
  });

  it("every tier has several items and the tiers rise in shop order", () => {
    const tiers = SHOP_ITEMS.map(itemTier);
    const order = tiers.map((tier) => PET_PRICE_TIERS.indexOf(tier));
    expect(order, "the shop lists cheaper tiers first").toEqual([...order].sort((a, b) => a - b));
    for (const tier of PET_PRICE_TIERS) {
      expect(tiers.filter((value) => value === tier).length, `${tier} needs a few items`).toBeGreaterThanOrEqual(3);
    }
  });

  it("time to earn each tier at the typical pace", () => {
    for (const item of SHOP_ITEMS) {
      const days = PetEconomy.typicalDays(itemCost(item));
      switch (itemTier(item)) {
        case "free":
          expect(days, item).toBe(0);
          break;
        case "starter":
          expect(days, item).toBe(1);
          break;
        case "midTier":
          expect(days >= 2 && days <= 5, item).toBe(true);
          break;
        case "showpiece":
          expect(days >= 10 && days <= 20, `${item}: 2 to 4 weeks of 5 days`).toBe(true);
          break;
      }
    }
    expect(itemTier(accessoryItem("graduationCap"))).toBe("showpiece");
    expect(itemTier(accessoryItem("beanie"))).toBe("starter");
  });
});
