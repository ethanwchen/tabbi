// Port of UnlockProgressTests.swift.
import { beforeAll, describe, expect, it } from "vitest";
import { PetEconomy } from "../../../src/core/closet/petEconomy";
import { UnlockProgress } from "../../../src/core/motivation/unlockProgress";
import { accessoryItem, itemDisplayName } from "../../../src/core/pets/petItem";
import { PetPointsLedger, SHOP_ITEMS } from "../../../src/core/pets/petUnlocks";
import { switchLanguage } from "../../support/catalogs";

const beanie = accessoryItem("beanie");

beforeAll(() => {
  switchLanguage("en");
});

describe("UnlockProgress", () => {
  it("fills a first session toward the beanie", () => {
    const progress = UnlockProgress.make(20, new PetPointsLedger(), 20);
    expect(progress).toBeDefined();
    if (progress === undefined) return;
    expect(progress.item).toBe(beanie);
    expect(progress.fractionBefore).toBe(0);
    expect(progress.fraction).toBeCloseTo(20 / 35, 4);
    expect(progress.missing).toBe(15);
    expect(progress.sessionsLeft).toBe(1);
    expect(progress.line).toBe(`1 more session to ${itemDisplayName(beanie)}`);
  });

  it("fills the bar rather than jumping ahead when a session makes an item affordable", () => {
    const progress = UnlockProgress.make(40, new PetPointsLedger(), 35);
    expect(progress).toBeDefined();
    if (progress === undefined) return;
    expect(progress.item).toBe(beanie);
    expect(progress.isReady).toBe(true);
    expect(progress.fraction).toBe(1);
    expect(progress.sessionsLeft).toBe(0);
    expect(progress.line.startsWith("Enough for")).toBe(true);
  });

  it("skips owned and already affordable items", () => {
    const ledger = new PetPointsLedger({ earned: 35, spent: 35, purchased: [beanie] });
    // 60 points before the session: the glasses (50) were already
    // affordable, so the goal is the headband (65).
    const progress = UnlockProgress.make(64, ledger, 4);
    expect(progress).toBeDefined();
    if (progress === undefined) return;
    expect(progress.item).toBe(accessoryItem("ninjaHeadband"));
    expect(progress.missing).toBe(1);
  });

  it("counts sessions left at the pace of the session just done", () => {
    const ledger = new PetPointsLedger();
    const short = UnlockProgress.make(0, ledger, 0, 15);
    expect(short).toBeDefined();
    if (short === undefined) return;
    expect(short.sessionsLeft).toBe(3);
    expect(short.isNear).toBe(false);
    expect(short.line).toBe(`3 more sessions to ${itemDisplayName(beanie)}`);
    const typical = UnlockProgress.make(0, ledger, 0, 0);
    expect(typical).toBeDefined();
    if (typical === undefined) return;
    expect(typical.pointsPerSession).toBe(PetEconomy.pointsPerTypicalBlock());
    expect(typical.sessionsLeft).toBe(1);
    expect(typical.isNear).toBe(true);
  });

  it("gives no progress with nothing left to unlock", () => {
    expect(UnlockProgress.make(0, new PetPointsLedger({ purchased: SHOP_ITEMS }))).toBeUndefined();
  });
});
