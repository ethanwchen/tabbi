import { describe, expect, it } from "vitest";
import { PetCloset, type PetRadiantState } from "../../src/core/closet/petCloset";
import { partyProfile } from "../../src/core/party/partyModels";
import { partyPet, partyRadiant, wireItem } from "../../src/core/party/partyPetAppearance";
import type { PetAccessory, PetOutfit } from "../../src/core/pets/petCostume";
import type { PetItem } from "../../src/core/pets/petItem";
import { PetProfile } from "../../src/core/pets/petProfile";
import { PetSave } from "../../src/core/pets/petSave";
import { PetPointsLedger, PetRadiantPurchaseError, itemCost } from "../../src/core/pets/petUnlocks";
import { radiantArt, type PetRadiantIntensity } from "../../src/core/pets/radiant/radiantArt";
import { radiantEffectName, radiantEligibleItems, radiantPrice } from "../../src/core/pets/radiant/radiantResolver";
import { SyncDocument } from "../../src/core/sync/syncDocument";
import { loadFixture } from "../support/fixtures";

/*
 * Replays shared/fixtures/closet/radiant.json (RadiantEconomyFixture on the
 * Mac): the eligible items and their prices and effect names, a Closet
 * scenario step by step down to the saved JSON, the sync unlocks, and the
 * Party `radiant` entries sent and read back.
 */

interface Fixture {
  schema: string;
  version: number;
  multiplier: number;
  items: { item: PetItem; price: number; radiantPrice: number; bold: string; subtle: string; wire: string }[];
  steps: { op: string; item?: PetItem; intensity?: PetRadiantIntensity; points?: number; result: string; balance: number; state?: string; save: string }[];
  unlocks: string[];
  wire: { outfit: PetOutfit; accessories: PetAccessory[]; radiance: Record<string, PetRadiantIntensity>; sent: string[] }[];
  reads: { costume: string; accessories: string[]; radiant: string[]; look: Record<string, string> }[];
}

const fixture = loadFixture<Fixture>("closet/radiant.json");

function stateName(state: PetRadiantState): string {
  switch (state.kind) {
    case "locked":
      return `locked:${state.missing}`;
    case "radiant":
      return `radiant:${state.intensity}`;
    default:
      return state.kind;
  }
}

/** How Swift prints a PetRadiantPurchaseError case. */
function errorName(error: PetRadiantPurchaseError): string {
  return error.reason === "notEnoughPoints" ? `notEnoughPoints(missing: ${error.missing})` : error.reason;
}

describe("closet Radiant golden fixture", () => {
  it("is the version this port reads", () => {
    expect(fixture.schema).toBe("tabbi.closet.radiant");
    expect(fixture.version).toBe(1);
    expect(fixture.multiplier).toBe(radiantArt().upgradeMultiplier);
  });

  it("lists every eligible item with its prices, effect names and wire id", () => {
    expect(
      radiantEligibleItems().map((item) => ({
        item,
        price: itemCost(item),
        radiantPrice: radiantPrice(item),
        bold: radiantEffectName(item, "bold"),
        subtle: radiantEffectName(item, "subtle"),
        wire: wireItem(item),
      })),
    ).toEqual(fixture.items);
  });

  it("replays the Closet scenario step by step, down to the saved JSON", () => {
    const closet = new PetCloset(new PetSave(new PetProfile("Mochi", "britishShorthair"), new PetPointsLedger({ earned: 3000 })));
    const wizard: PetItem = "accessory.wizardHat";
    const sorcerer: PetItem = "accessory.blindfoldedSorcerer";
    const steps: Fixture["steps"] = [];
    const record = (op: string, item: PetItem | undefined, result: string, extra: { intensity?: PetRadiantIntensity; points?: number } = {}) => {
      steps.push({
        op,
        ...(item === undefined ? {} : { item }),
        ...extra,
        result,
        balance: closet.balance,
        ...(item === undefined ? {} : { state: stateName(closet.radiantState(item)) }),
        save: closet.save.encoded(),
      });
    };
    const upgrade = (item: PetItem) => {
      try {
        closet.upgradeToRadiant(item);
        record("upgrade", item, "upgraded");
      } catch (error) {
        if (!(error instanceof PetRadiantPurchaseError)) throw error;
        record("upgrade", item, errorName(error));
      }
    };
    upgrade(wizard);
    closet.tap(wizard);
    record("tap", wizard, "bought");
    upgrade(wizard);
    closet.pinRadiantGoal(wizard);
    record("pin", wizard, "pinned");
    closet.receiveGift(4900);
    record("gift", undefined, "credited", { points: 4900 });
    upgrade(wizard);
    upgrade(wizard);
    closet.setRadiance("subtle", wizard);
    record("set", wizard, "set", { intensity: "subtle" });
    closet.setRadiance("off", wizard);
    record("set", wizard, "set", { intensity: "off" });
    upgrade("accessory.beanie");
    upgrade(sorcerer);

    expect(steps.length).toBe(fixture.steps.length);
    steps.forEach((step, index) => {
      const expected = fixture.steps[index];
      if (!expected) return;
      const { save, ...rest } = step;
      const { save: expectedSave, ...expectedRest } = expected;
      expect(rest, `step ${index}`).toEqual(expectedRest);
      /* The Mac pretty-prints with its own spacing; the value is what must match. */
      expect(JSON.parse(save), `step ${index} save`).toEqual(JSON.parse(expectedSave));
    });
    expect([...SyncDocument.empty.recording(closet.save, undefined, "mac").unlocks].sort()).toEqual(fixture.unlocks);
  });

  it("sends the worn effects that are on", () => {
    for (const entry of fixture.wire) {
      const radiance = new Map(Object.entries(entry.radiance) as [PetItem, PetRadiantIntensity][]);
      const pet = new PetProfile("A", "corgi", { outfit: entry.outfit, accessories: entry.accessories, radiance });
      expect(partyRadiant(pet), JSON.stringify(entry.radiance)).toEqual(entry.sent);
    }
  });

  it("reads a friend's effects back, dropping what it does not know", () => {
    for (const entry of fixture.reads) {
      const profile = partyProfile({
        code: "A",
        name: "A",
        petName: "P",
        species: "cat",
        breed: "tabby",
        costume: entry.costume,
        accessories: entry.accessories,
        radiant: entry.radiant,
      });
      expect(Object.fromEntries(partyPet(profile).radiantLook.intensities), entry.radiant.join(" ")).toEqual(entry.look);
    }
  });
});
