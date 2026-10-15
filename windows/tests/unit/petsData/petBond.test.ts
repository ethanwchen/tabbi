import { describe, expect, it } from "vitest";
import { PetMilestoneProgress } from "../../../src/core/closet/petLimited";
import type { StudyActivityRecord } from "../../../src/core/closet/studyActivity";
import {
  NO_BOND_LOOK,
  PET_COLLARS,
  PetBond,
  bondLook,
  bondUnlock,
  collarUnlockLevel,
} from "../../../src/core/pets/petBond";
import { addDays, startOfDay, type DayCalendar } from "../../../src/core/streaks/dayCalendar";

// Port of PetBondTests.swift.

const calendar: DayCalendar = { timeZone: "America/New_York", firstWeekday: 1 };

/** Ten in the morning, `offset` days after October 1, 2026. */
function day(offset: number): number {
  return startOfDay(addDays("2026-10-01", offset), calendar) + 10 * 3600;
}

let nextID = 0;
function focus(minutes: number, end: number): StudyActivityRecord {
  nextID += 1;
  return { id: `r${nextID}`, source: "focus", kind: "focus.completed", end, quantity: minutes, unit: "min" };
}

function bond(records: StudyActivityRecord[]): PetBond {
  return PetBond.fromProgress(new PetMilestoneProgress(records, calendar));
}

describe("PetBond", () => {
  it("starts at level one and rises gently", () => {
    const thresholds = PetBond.thresholds;
    expect(thresholds.length).toBe(PetBond.maxLevel);
    expect(thresholds[0]).toBe(0);
    const steps = thresholds.slice(1).map((value, index) => value - (thresholds[index] ?? 0));
    expect(steps).toEqual([...steps].sort((a, b) => a - b));
    expect(steps.every((step) => step > 0)).toBe(true);
  });

  it("reaches levels at the thresholds", () => {
    expect(new PetBond(0).level).toBe(1);
    expect(new PetBond(99).level).toBe(1);
    expect(new PetBond(100).level).toBe(2);
    expect(new PetBond(600).level).toBe(4);
    expect(new PetBond(6999).level).toBe(9);
    expect(new PetBond(7000).level).toBe(10);
    expect(new PetBond(1_000_000).level).toBe(10);
    expect(new PetBond(-50).points).toBe(0);
  });

  it("reports progress in the level and points to the next", () => {
    const current = new PetBond(450);
    expect(current.level).toBe(3);
    expect(current.progressInLevel).toBeCloseTo(0.5, 4);
    expect(current.pointsToNextLevel).toBe(150);
    const maxed = new PetBond(9000);
    expect(maxed.isMaxed).toBe(true);
    expect(maxed.pointsToNextLevel).toBeUndefined();
    expect(maxed.progressInLevel).toBe(1);
  });

  it("brings the first levels within the first days of a typical habit", () => {
    const records = [0, 1, 2].flatMap((offset) => [0, 1, 2].map((block) => focus(25, day(offset) + block * 3600)));
    const grown = bond(records);
    expect(grown.points).toBe(3 * 75 + 3 * PetBond.pointsPerStudyDay);
    expect(grown.level).toBe(3);
  });

  it("grows faster with consistency than with one cram", () => {
    const steady = [0, 1, 2, 3, 4].map((offset) => focus(30, day(offset)));
    const cram = [focus(150, day(0))];
    expect(bond(steady).points).toBeGreaterThan(bond(cram).points);
  });

  it("never shrinks after a break", () => {
    const records = Array.from({ length: 10 }, (_, offset) => focus(60, day(offset)));
    const before = bond(records);
    const more = bond([...records, focus(10, day(40))]);
    expect(more.points).toBeGreaterThan(before.points);
  });

  it("counts only focus minutes", () => {
    const cards: StudyActivityRecord = { id: "cards", source: "anki", kind: "cards.reviewed", end: day(0), quantity: 300, unit: "cards" };
    expect(bond([cards]).points).toBe(0);
  });

  it("gives every level a distinct warm name", () => {
    const names = Array.from({ length: PetBond.maxLevel }, (_, index) => PetBond.tierName(index + 1));
    expect(new Set(names).size).toBe(PetBond.maxLevel);
    expect(names[0]).toBe("Just met");
    expect(PetBond.tierName(4)).toBe("Best friends");
    expect(names[names.length - 1]).toBe("Forever friends");
    expect(PetBond.tierName(0)).toBe("Just met");
    expect(PetBond.tierName(99)).toBe("Forever friends");
    expect(new PetBond(600).tierName).toBe("Best friends");
  });

  it("upgrades the collar at its tiers", () => {
    const collars = Array.from({ length: PetBond.maxLevel }, (_, index) => bondLook(index + 1).collar);
    expect(collars).toEqual(["none", "plain", "plain", "bell", "bell", "star", "star", "gold", "gold", "gold"]);
    const levels = PET_COLLARS.map(collarUnlockLevel);
    expect(levels).toEqual([...levels].sort((a, b) => a - b));
  });

  it("adds the happy idle and sparkle at their levels", () => {
    expect(bondLook(2).happyIdle).toBe(false);
    expect(bondLook(3).happyIdle).toBe(true);
    expect(bondLook(8).sparkle).toBe(false);
    expect(bondLook(9).sparkle).toBe(true);
    expect(bondLook(10).sparkle).toBe(true);
    expect(new PetBond(0).look).toEqual(bondLook(1));
    expect(NO_BOND_LOOK).toEqual(bondLook(1));
  });

  it("names what each level adds", () => {
    expect(bondUnlock(2)).toBe("Plain collar");
    expect(bondUnlock(3)).toBe("Happy wiggle");
    expect(bondUnlock(4)).toBe("Bell collar");
    expect(bondUnlock(8)).toBe("Gold tag");
    expect(bondUnlock(9)).toBe("Sparkle");
    expect(bondUnlock(5)).toBeUndefined();
    expect(bondUnlock(11)).toBeUndefined();
  });
});
