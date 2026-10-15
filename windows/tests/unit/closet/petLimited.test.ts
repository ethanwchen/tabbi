import { describe, expect, it } from "vitest";
import { PetCloset } from "../../../src/core/closet/petCloset";
import {
  PET_LIMITED_EDITIONS,
  PET_MILESTONES,
  PetMilestoneProgress,
  editionItem,
  editionMilestone,
  editionSource,
  howToEarn,
  isLimited,
  itemEffect,
  limitedEditionOf,
  limitedProgressFraction,
  milestoneProgress,
} from "../../../src/core/closet/petLimited";
import {
  FOCUS_COMPLETED,
  MINUTES_UNIT,
  OUTCOME_KEY,
  type StudyActivityRecord,
  type StudyPhaseOutcome,
} from "../../../src/core/closet/studyActivity";
import { accessorySlot } from "../../../src/core/pets/petCostume";
import { PET_ITEM_THEMES, itemIsNew, itemTheme, themeItems } from "../../../src/core/pets/petItemTheme";
import { accessoryItem, itemFromID, outfitItem } from "../../../src/core/pets/petItem";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { PetSave } from "../../../src/core/pets/petSave";
import { ALL_ITEMS, PetPointsLedger, PetPurchaseError, SHOP_ITEMS, isFree, itemCost } from "../../../src/core/pets/petUnlocks";
import { addDays, startOfDay, type DayCalendar } from "../../../src/core/streaks/dayCalendar";
import { loadRepoJson } from "../../support/fixtures";

// Port of PetLimitedTests.
const calendar: DayCalendar = { timeZone: "America/New_York", firstWeekday: 1 };

/** October 1, 2026 plus `offset` days, at `hour` in New York. */
function day(offset: number, hour = 10): number {
  return startOfDay(addDays("2026-10-01", offset), calendar) + hour * 3600;
}

let nextID = 0;

function focus(minutes: number, on: number, source = "focus", outcome: StudyPhaseOutcome = "completed"): StudyActivityRecord {
  nextID += 1;
  return {
    id: `record-${nextID}`,
    source,
    kind: FOCUS_COMPLETED,
    end: on,
    quantity: minutes,
    unit: MINUTES_UNIT,
    metadata: { [OUTCOME_KEY]: outcome },
  };
}

function tuxedoCloset(ledger = new PetPointsLedger()): PetCloset {
  return new PetCloset(new PetSave(new PetProfile("Kit", "tuxedo"), ledger));
}

/** The Founding Member badge is owning the Founder's Pin (the Mac's PetSave.isFoundingMember). */
function isFoundingMember(save: PetSave): boolean {
  return save.ledger.owns(editionItem("foundingMember"));
}

function purchaseError(run: () => void): PetPurchaseError {
  try {
    run();
  } catch (error) {
    if (error instanceof PetPurchaseError) return error;
    throw error;
  }
  throw new Error("expected a PetPurchaseError");
}

describe("limited editions: catalog", () => {
  // The server grants exactly the limited items the app can show, with the same source.
  it("the server grant list matches the limited editions", () => {
    const server = loadRepoJson<{
      items: { id: string; source: string; event?: string; milestone?: string; season?: string }[];
    }>("backend/shared/limited-items.json").items;
    expect(server.map((entry) => entry.id)).toEqual(PET_LIMITED_EDITIONS.map(editionItem));
    server.forEach((entry, index) => {
      const edition = PET_LIMITED_EDITIONS[index];
      if (!edition) throw new Error(`no edition for ${entry.id}`);
      const source = editionSource(edition);
      switch (source.kind) {
        case "event":
          expect(entry.source, entry.id).toBe("event");
          expect(entry.event, entry.id).toBe(source.id);
          break;
        case "milestone":
          expect(entry.source, entry.id).toBe("milestone");
          expect(entry.milestone, entry.id).toBe(source.milestone);
          break;
        case "season":
          expect(entry.source, entry.id).toBe("season");
          expect(entry.season, entry.id).toBe(source.id);
          break;
      }
    });
  });

  it("limited items are never sold or free", () => {
    for (const edition of PET_LIMITED_EDITIONS) {
      const item = editionItem(edition);
      expect(isLimited(item)).toBe(true);
      expect(isFree(item), `${item} must be earned, not owned from the start`).toBe(false);
      expect(PetCloset.wardrobe).not.toContain(item);
      expect(PET_ITEM_THEMES.some((theme) => themeItems(theme).includes(item))).toBe(false);
      expect(itemIsNew(item)).toBe(false);
      expect(itemFromID(item)).toBe(item);
      expect(howToEarn(edition)).not.toBe("");
    }
    expect(PetCloset.limitedShelf).toEqual(PET_LIMITED_EDITIONS.map(editionItem));
    expect(ALL_ITEMS.slice(-PET_LIMITED_EDITIONS.length)).toEqual(PetCloset.limitedShelf);
    expect([...SHOP_ITEMS, ...PetCloset.limitedShelf]).toEqual(ALL_ITEMS);
  });

  it("every milestone has one item and the cap is the launch week event", () => {
    const milestones = PET_LIMITED_EDITIONS.flatMap((edition) => editionMilestone(edition) ?? []);
    expect(new Set(milestones)).toEqual(new Set(PET_MILESTONES));
    expect(milestones.length).toBe(PET_MILESTONES.length);
    expect(editionSource("launchWeekCap")).toEqual({ kind: "event", id: "launch-week" });
    expect(editionItem("launchWeekCap")).toBe(accessoryItem("backwardsCap"));
  });

  it("limited copy never mentions payment", () => {
    const words = ["buy", "pay", "price", "donat", "purchase", "$", "money", "point"];
    for (const edition of PET_LIMITED_EDITIONS) {
      const text = howToEarn(edition).toLowerCase();
      for (const word of words) expect(text.includes(word), `${edition} mentions ${word}`).toBe(false);
    }
  });

  it("effects are declared for milestone items", () => {
    expect(itemEffect(accessoryItem("beanie"))).toBeUndefined();
    expect(itemEffect(accessoryItem("flameHeadband"))).toBe("flicker");
    expect(itemEffect(accessoryItem("goldenLaurel"))).toBe("shimmer");
    expect(itemEffect(accessoryItem("teamMedal"))).toBe("sparkle");
    expect(itemEffect(accessoryItem("backwardsCap"))).toBe("sparkle");
  });

  it("winter items are seasonal limited items", () => {
    const antlers = accessoryItem("reindeerAntlers");
    const scarf = accessoryItem("snowScarf");
    expect(editionItem("winterAntlers")).toBe(antlers);
    expect(editionItem("winterScarf")).toBe(scarf);
    for (const item of [antlers, scarf]) {
      const edition = limitedEditionOf(item);
      expect(edition && editionSource(edition)).toEqual({ kind: "season", id: "winter-holidays" });
      expect(itemTheme(item)).toBe("seasonal");
      expect(item, "the shop's scarf stays for sale").not.toBe(accessoryItem("scarf"));
    }
    expect(accessorySlot("snowScarf")).toBe(accessorySlot("scarf"));
    expect(itemEffect(antlers)).toBeUndefined();
    expect(itemEffect(scarf)).toBe("sparkle");
  });

  it("Valentine's glasses are a seasonal limited item", () => {
    const glasses = accessoryItem("heartGlasses");
    expect(editionItem("valentinesGlasses")).toBe(glasses);
    expect(editionSource("valentinesGlasses")).toEqual({ kind: "season", id: "valentines" });
    expect(itemTheme(glasses)).toBe("seasonal");
    expect(accessorySlot("heartGlasses")).toBe("face");
    expect(itemEffect(glasses)).toBe("sparkle");
  });

  it("summer shades are a seasonal limited item", () => {
    const shades = accessoryItem("summerShades");
    expect(editionItem("summerShades")).toBe(shades);
    expect(editionSource("summerShades")).toEqual({ kind: "season", id: "summer" });
    expect(itemTheme(shades)).toBe("seasonal");
    expect(accessorySlot("summerShades")).toBe(accessorySlot("coolSunglasses"));
    expect(limitedEditionOf(accessoryItem("coolSunglasses"))).toBeUndefined();
    expect(itemEffect(shades)).toBe("sparkle");
  });

  it("the lion dance hat is a seasonal limited item", () => {
    const hat = accessoryItem("lionDanceHat");
    expect(editionItem("lunarNewYearLion")).toBe(hat);
    expect(editionSource("lunarNewYearLion")).toEqual({ kind: "season", id: "lunar-new-year" });
    expect(itemTheme(hat)).toBe("seasonal");
    expect(accessorySlot("lionDanceHat")).toBe("head");
    expect(itemEffect(hat)).toBe("sparkle");
    expect(itemCost(hat)).toBe(0);
  });

  it("the sakura sprig is a seasonal limited item", () => {
    const sprig = accessoryItem("sakuraSprig");
    expect(editionItem("springSakura")).toBe(sprig);
    expect(editionSource("springSakura")).toEqual({ kind: "season", id: "spring" });
    expect(itemTheme(sprig)).toBe("seasonal");
    expect(accessorySlot("sakuraSprig")).toBe("head");
    expect(limitedEditionOf(accessoryItem("cherryPetals"))).toBeUndefined();
    expect(itemEffect(sprig)).toBe("drift");
    expect(itemCost(sprig)).toBe(0);
  });

  it("the study hoodie is a seasonal limited outfit", () => {
    const hoodie = outfitItem("studyHoodie");
    expect(editionItem("examHoodie")).toBe(hoodie);
    expect(editionSource("examHoodie")).toEqual({ kind: "season", id: "exam-season" });
    expect(itemTheme(hoodie)).toBe("seasonal");
    expect(limitedEditionOf(outfitItem("cozyHoodie")), "the shop's hoodie stays for sale").toBeUndefined();
    expect(itemEffect(hoodie)).toBe("shimmer");
    expect(itemCost(hoodie)).toBe(0);
    expect(themeItems("seasonal"), "limited items are not on a shop shelf").not.toContain(hoodie);
  });

  it("Halloween items are seasonal limited items", () => {
    const hat = accessoryItem("moonlitWitchHat");
    const pumpkin = accessoryItem("pumpkinHat");
    expect(editionItem("halloweenWitchHat")).toBe(hat);
    expect(editionItem("halloweenPumpkin")).toBe(pumpkin);
    for (const item of [hat, pumpkin]) {
      const edition = limitedEditionOf(item);
      expect(edition && editionSource(edition)).toEqual({ kind: "season", id: "halloween" });
      expect(edition && editionMilestone(edition)).toBeUndefined();
      expect(itemTheme(item)).toBe("seasonal");
      expect(item, "the shop's witch hat stays for sale").not.toBe(accessoryItem("witchHat"));
    }
    expect(itemEffect(hat)).toBeUndefined();
    expect(itemEffect(pumpkin)).toBe("flicker");

    const closet = tuxedoCloset(new PetPointsLedger({ earned: 5000 }));
    expect(closet.state(pumpkin)).toEqual({ kind: "unearned" });
    expect(closet.save.ledger.canBuy(pumpkin)).toBe(false);
    expect(closet.tap(pumpkin)).toEqual({ kind: "notEarnedYet" });
  });

  it("seasonal copy names the event and its goal from the events catalog", () => {
    expect(howToEarn("halloweenPumpkin")).toMatch(/^Focus for \d+ (minutes|hours) during .+\.$/);
  });

  it("the Founder's Pin is the Founding Member grant", () => {
    const pin = accessoryItem("foundersPin");
    expect(editionItem("foundingMember")).toBe(pin);
    expect(editionSource("foundingMember")).toEqual({ kind: "event", id: "founding" });
    expect(editionMilestone("foundingMember")).toBeUndefined();
    expect(accessorySlot("foundersPin")).toBe("neck");
    expect(itemEffect(pin)).toBe("sparkle");
    expect(itemCost(pin)).toBe(0);
    expect(itemIsNew(pin)).toBe(false);
    expect(howToEarn("foundingMember")).toBe("For signing in during Tabbi's first 100 days.");

    const closet = tuxedoCloset(new PetPointsLedger({ earned: 5000 }));
    expect(isFoundingMember(closet.save)).toBe(false);
    expect(closet.save.ledger.canBuy(pin), "points never buy it").toBe(false);
    expect(closet.applyGrants(["accessory.foundersPin"])).toEqual([pin]);
    expect(isFoundingMember(closet.save)).toBe(true);
    expect(closet.tap(pin)).toEqual({ kind: "wore" });
    expect(closet.profile.isWearing(pin)).toBe(true);
    expect(isFoundingMember(PetCloset.demo().save), "demo shots show the badge").toBe(true);
  });

  it("server entitlements bring limited items and known badges", () => {
    const entitlements = loadRepoJson<{ entitlements: { id: string; badge: boolean; items: string[] }[] }>(
      "backend/shared/entitlements.json",
    ).entitlements;
    expect(entitlements.map((entry) => entry.id)).toEqual(["founding"]);
    for (const entitlement of entitlements) {
      for (const id of entitlement.items) {
        const item = itemFromID(id);
        expect(item !== undefined && isLimited(item), `${entitlement.id} brings ${id}`).toBe(true);
      }
    }
    expect(entitlements[0]?.items).toEqual([editionItem("foundingMember")]);
    expect(entitlements.filter((entry) => entry.badge).map((entry) => entry.id)).toEqual(["founding"]);
  });
});

describe("limited editions: ledger and closet", () => {
  it("points cannot buy a limited item", () => {
    const ledger = new PetPointsLedger({ earned: 5000 });
    const cap = accessoryItem("backwardsCap");
    expect(ledger.canBuy(cap)).toBe(false);
    expect(purchaseError(() => ledger.buy(cap)).reason).toBe("notForSale");
    expect(ledger.balance).toBe(5000);

    const closet = tuxedoCloset(ledger);
    expect(closet.state(cap)).toEqual({ kind: "unearned" });
    expect(closet.tap(cap)).toEqual({ kind: "notEarnedYet" });
    expect(closet.profile.isWearing(cap)).toBe(false);
    const next = closet.nextUnlock?.item;
    expect(next !== undefined && isLimited(next)).toBe(false);
  });

  it("a granted item is owned, worn and kept through a save", () => {
    const closet = tuxedoCloset();
    const cap = accessoryItem("backwardsCap");
    expect(closet.applyGrants(["accessory.backwardsCap", "accessory.beanie", "accessory.fromTheFuture"])).toEqual([cap]);
    expect(closet.applyGrants(["accessory.backwardsCap"]), "a grant is new only once").toEqual([]);
    expect(closet.save.ledger.owns(accessoryItem("beanie")), "the server never hands out shop items").toBe(false);
    expect(closet.state(cap)).toEqual({ kind: "owned" });
    expect(closet.tap(cap)).toEqual({ kind: "wore" });
    expect(closet.balance).toBe(0);

    const reloaded = PetSave.decode(JSON.parse(closet.save.encoded()));
    expect(reloaded.ledger.owns(cap)).toBe(true);
    expect(reloaded.profile.isWearing(cap)).toBe(true);

    // Withdrawn later: a sync without it keeps the cap.
    closet.applyGrants([]);
    expect(closet.save.ledger.owns(cap)).toBe(true);
  });

  it("a save from before limited items still loads", () => {
    const save = PetSave.decode(
      JSON.parse(
        '{"version":1,"profile":{"name":"Kit","breed":"tuxedo"},"ledger":{"earned":50,"spent":35,"purchased":["accessory.beanie"]}}',
      ),
    );
    expect([...save.ledger.granted]).toEqual([]);
    expect(save.ledger.owns(accessoryItem("beanie"))).toBe(true);
  });

  it("a hand-edited save cannot wear an unearned limited item", () => {
    const save = PetSave.decode(
      JSON.parse(
        '{"version":1,"profile":{"name":"Kit","breed":"tuxedo","accessories":["teamMedal"]},"ledger":{"earned":0,"spent":0,"purchased":["accessory.teamMedal"]}}',
      ),
    );
    expect(save.ledger.owns(accessoryItem("teamMedal"))).toBe(false);
    expect(save.profile.isWearing(accessoryItem("teamMedal"))).toBe(false);
  });
});

describe("limited editions: milestones", () => {
  it("a seven day streak unlocks the flame headband", () => {
    const progress = new PetMilestoneProgress();
    for (let offset = 0; offset < 6; offset++) progress.add(focus(25, day(offset)), calendar);
    expect(progress.isReached("weekStreak")).toBe(false);
    expect(progress.value("weekStreak", day(5), calendar)).toBe(6);

    const closet = tuxedoCloset();
    expect(closet.unlockMilestones(progress)).toEqual([]);

    progress.add(focus(25, day(6)), calendar);
    expect(progress.isReached("weekStreak")).toBe(true);
    expect(closet.unlockMilestones(progress)).toEqual([accessoryItem("flameHeadband")]);
    expect(closet.unlockMilestones(progress), "unlocks once").toEqual([]);
  });

  it("a streak needs consecutive days with real study", () => {
    const progress = new PetMilestoneProgress();
    for (const offset of [0, 1, 2, 4, 5, 6, 7]) progress.add(focus(30, day(offset)), calendar);
    // A 3 minute session does not make day 3 a study day.
    progress.add(focus(3, day(3)), calendar);
    expect(progress.longestStreak()).toBe(4);
    expect(progress.isReached("weekStreak")).toBe(false);

    // Two short sessions on one day add up.
    progress.add(focus(3, day(3, 15)), calendar);
    expect(progress.longestStreak()).toBe(8);
    expect(progress.isReached("weekStreak")).toBe(true);
  });

  it("the current streak holds until a day is missed", () => {
    const progress = new PetMilestoneProgress();
    for (let offset = 0; offset < 3; offset++) progress.add(focus(25, day(offset)), calendar);
    expect(progress.currentStreak(day(2), calendar)).toBe(3);
    expect(progress.currentStreak(day(3), calendar), "still on in the morning").toBe(3);
    expect(progress.currentStreak(day(4), calendar)).toBe(0);
  });

  it("fifty hours counts every focus record once", () => {
    const progress = new PetMilestoneProgress();
    const records = Array.from({ length: 59 }, (_, index) => focus(50, day(Math.trunc(index / 4), 8 + (index % 4))));
    for (const record of records) progress.add(record, calendar);
    // Replaying the log (as on launch) must not count anything twice.
    for (const record of records) progress.add(record, calendar);
    expect(progress.focusMinutes).toBe(2950);
    expect(progress.isReached("fiftyHours")).toBe(false);
    expect(progress.value("fiftyHours", day(15), calendar)).toBe(2950);

    progress.add(focus(50, day(15), "focus", "skipped"), calendar);
    expect(progress.isReached("fiftyHours")).toBe(true);
    expect(progress.value("fiftyHours", day(15), calendar)).toBe(3000);
  });

  it("only a finished party session earns the medal", () => {
    const progress = new PetMilestoneProgress(
      [focus(25, day(0)), focus(15, day(0, 12), "party", "skipped")],
      calendar,
    );
    expect(progress.isReached("firstParty")).toBe(false);

    // The Mac builds this record from a finished PartySessionCompletion; the
    // Party port owns that, so the record it logs is written out here.
    progress.add(focus(25, day(1), "party", "completed"), calendar);
    expect(progress.isReached("firstParty")).toBe(true);

    const closet = tuxedoCloset();
    expect(closet.unlockMilestones(progress)).toEqual([accessoryItem("teamMedal")]);
  });

  it("other activity kinds do not count", () => {
    const cards: StudyActivityRecord = { id: "cards", source: "anki", kind: "cards.reviewed", end: day(0), quantity: 300, unit: "cards" };
    const progress = new PetMilestoneProgress([cards], calendar);
    expect(progress.focusMinutes).toBe(0);
    expect(progress.studyDays).toEqual([]);
  });

  it("the demo progress is part way to every milestone", () => {
    const today = 1_800_000_000;
    const progress = PetMilestoneProgress.demo(today, calendar);
    expect(progress.value("weekStreak", today, calendar)).toBe(4);
    expect(progress.value("fiftyHours", today, calendar)).toBe(40 * 60 + 45);
    expect(progress.value("firstParty", today, calendar)).toBe(0);
    expect(PET_MILESTONES.some((milestone) => progress.isReached(milestone))).toBe(false);
  });
});

describe("limited editions: shelf progress", () => {
  it("shelf progress counts in each milestone's unit", () => {
    const today = 1_800_000_000;
    const progress = PetMilestoneProgress.demo(today, calendar);
    const streak = progress.progress("streakFlame", today, calendar);
    expect(streak?.label).toBe("4/7 days");
    expect(streak ? limitedProgressFraction(streak) : 0).toBeCloseTo(4 / 7, 3);
    expect(progress.progress("focusLaurel", today, calendar)?.label).toBe("40/50 h");
    expect(progress.progress("partyMedal", today, calendar)?.label).toBe("0/1 session");
    expect(progress.progress("launchWeekCap", today, calendar)).toBeUndefined();
  });

  it("shelf progress never shows the goal early or past it", () => {
    expect(milestoneProgress("fiftyHours", 50 * 60 - 1).label).toBe("49/50 h");
    expect(milestoneProgress("fiftyHours", 99_999).label).toBe("50/50 h");
    expect(limitedProgressFraction(milestoneProgress("weekStreak", -3))).toBe(0);
    expect(limitedProgressFraction(milestoneProgress("firstParty", 4))).toBe(1);
  });
});
