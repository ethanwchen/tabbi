import { describe, expect, it } from "vitest";
import { PetCloset, radiantGoalFraction, radiantGoalIsReady } from "../../../src/core/closet/petCloset";
import { partyProfile } from "../../../src/core/party/partyModels";
import {
  forCatalogVersion3,
  localRadiance,
  olderCatalogFallback,
  partyPet,
  partyPetUpdate,
  partyRadiant,
} from "../../../src/core/party/partyPetAppearance";
import type { PetItem } from "../../../src/core/pets/petItem";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { PetSave } from "../../../src/core/pets/petSave";
import { PetPointsLedger, PetRadiantPurchaseError } from "../../../src/core/pets/petUnlocks";
import { radiantPrice } from "../../../src/core/pets/radiant/radiantResolver";
import { SyncDocument } from "../../../src/core/sync/syncDocument";

/* Ports of the Mac's Radiant ledger, profile, save, closet, sync and Party tests. */

const hat: PetItem = "accessory.wizardHat";
const coat: PetItem = "outfit.whiteCoat";
const sorcerer: PetItem = "accessory.blindfoldedSorcerer";
const beanie: PetItem = "accessory.beanie";

function refusal(run: () => void): PetRadiantPurchaseError | undefined {
  try {
    run();
  } catch (error) {
    if (error instanceof PetRadiantPurchaseError) return error;
    throw error;
  }
  return undefined;
}

describe("PetPointsLedger Radiant", () => {
  it("upgrades an owned eligible item once for 5x its price", () => {
    const ledger = new PetPointsLedger({ earned: 6000, purchased: [hat] });
    expect(ledger.canUpgrade(hat)).toBe(true);
    ledger.upgradeToRadiant(hat);
    expect(ledger.isRadiant(hat)).toBe(true);
    expect(ledger.spent).toBe(radiantPrice(hat));
    expect(ledger.canUpgrade(hat)).toBe(false);
    expect(refusal(() => ledger.upgradeToRadiant(hat))?.reason).toBe("alreadyRadiant");
  });

  it("refuses an item without an effect, one not owned, and one not affordable", () => {
    const ledger = new PetPointsLedger({ earned: 100, purchased: [hat, beanie] });
    expect(refusal(() => ledger.upgradeToRadiant(beanie))?.reason).toBe("notEligible");
    expect(refusal(() => ledger.upgradeToRadiant(coat))?.reason).toBe("notOwned");
    const poor = refusal(() => ledger.upgradeToRadiant(hat));
    expect(poor?.reason).toBe("notEnoughPoints");
    expect(poor?.missing).toBe(radiantPrice(hat) - 100);
    expect(ledger.spent).toBe(0);
  });

  it("keeps only owned eligible upgrades, also from another copy", () => {
    const ledger = new PetPointsLedger({ purchased: [hat], radiant: [hat, coat, beanie] });
    expect([...ledger.radiant]).toEqual([hat]);
    const synced = new PetPointsLedger({ purchased: [hat, coat] });
    synced.keepRadiant(new PetPointsLedger({ purchased: [hat, coat, sorcerer], radiant: [hat, coat, sorcerer] }));
    expect([...synced.radiant].sort()).toEqual([hat, coat].sort());
  });

  it("encodes upgrades as sorted ids, only when there are any", () => {
    const ledger = new PetPointsLedger({ earned: 10, purchased: [hat, coat], radiant: [hat, coat] });
    expect(ledger.toJSON().radiant).toEqual([hat, coat].sort());
    expect("radiant" in new PetPointsLedger().toJSON()).toBe(false);
    const read = PetPointsLedger.fromJSON({ earned: 10, purchased: [hat, coat], radiant: [hat, "accessory.future", coat] });
    expect(read.equals(ledger)).toBe(true);
    expect([...PetPointsLedger.fromJSON({ purchased: [hat], radiant: "nope" }).radiant]).toEqual([]);
    expect(ledger.copy().equals(ledger)).toBe(true);
  });
});

describe("PetProfile radiance", () => {
  it("keeps exactly the ledger's upgrades, new ones on Bold", () => {
    const profile = new PetProfile("", "blackCat", { accessories: ["wizardHat"], radiance: new Map([[sorcerer, "off"]]) });
    const ledger = new PetPointsLedger({ purchased: [hat, coat], radiant: [hat, coat] });
    const restricted = profile.restricted(ledger);
    expect([...restricted.radiance].sort()).toEqual([
      [hat, "bold"],
      [coat, "bold"],
    ].sort());
    restricted.setRadiance("subtle", hat);
    restricted.setRadiance("subtle", sorcerer);
    expect(restricted.radianceOf(hat)).toBe("subtle");
    expect(restricted.radianceOf(sorcerer)).toBeUndefined();
    /* Only the worn hat shows; the coat is not worn. */
    expect(restricted.radiantLook.key).toBe("accessory.wizardHat:subtle");
    restricted.setRadiance("off", hat);
    expect(restricted.radiantLook.isEmpty).toBe(true);
  });

  it("writes radiance only when there is some and reads it leniently", () => {
    const profile = new PetProfile("Pip", "blackCat", { radiance: new Map([[hat, "subtle"]]) });
    expect(profile.toJSON().radiance).toEqual({ [hat]: "subtle" });
    expect("radiance" in new PetProfile("Pip", "blackCat").toJSON()).toBe(false);
    const read = PetProfile.fromJSON({ ...profile.toJSON(), radiance: { [hat]: "subtle", [coat]: "loud", "accessory.future": "bold" } });
    expect([...read.radiance]).toEqual([[hat, "subtle"]]);
    expect(PetProfile.fromJSON({ ...profile.toJSON(), radiance: { [hat]: 3 } }).radiance.size).toBe(0);
    expect(read.copy().equals(read)).toBe(true);
    expect(read.equals(new PetProfile("Pip", "blackCat"))).toBe(false);
  });
});

describe("PetSave Radiant goal", () => {
  it("round-trips a goal that can still be pinned and drops one that cannot", () => {
    const save = new PetSave(new PetProfile("", "blackCat"), new PetPointsLedger({ purchased: [hat, coat] }));
    expect(save.canPinRadiantGoal(hat)).toBe(true);
    expect(save.canPinRadiantGoal(sorcerer)).toBe(false);
    save.radiantGoal = hat;
    const json = JSON.parse(save.encoded()) as Record<string, unknown>;
    expect(json.radiantGoalID).toBe(hat);
    expect(PetSave.decode(json).radiantGoal).toBe(hat);
    expect(PetSave.decode({ ...json, radiantGoalID: sorcerer }).radiantGoal).toBeUndefined();
    expect(PetSave.decode({ ...json, radiantGoalID: "accessory.future" }).radiantGoal).toBeUndefined();
    expect(save.copy().radiantGoal).toBe(hat);
  });
});

describe("PetCloset Radiant", () => {
  const closet = (earned: number, purchased: PetItem[] = [hat]) =>
    new PetCloset(new PetSave(new PetProfile("", "blackCat"), new PetPointsLedger({ earned, purchased })));

  it("tells where an item stands", () => {
    const c = closet(100);
    expect(c.radiantState(beanie)).toEqual({ kind: "notEligible" });
    expect(c.radiantState(coat)).toEqual({ kind: "needsItem" });
    expect(c.radiantState(hat)).toEqual({ kind: "locked", missing: radiantPrice(hat) - 100 });
    expect(closet(radiantPrice(hat)).radiantState(hat)).toEqual({ kind: "affordable" });
  });

  it("upgrades, wears the item on Bold and finishes a pinned goal", () => {
    const c = closet(radiantPrice(hat) + 5);
    c.pinRadiantGoal(hat);
    expect(c.save.radiantGoal).toBe(hat);
    c.upgradeToRadiant(hat);
    expect(c.profile.isWearing(hat)).toBe(true);
    expect(c.radiantState(hat)).toEqual({ kind: "radiant", intensity: "bold" });
    expect(c.save.radiantGoal).toBeUndefined();
    expect(c.balance).toBe(5);
    c.setRadiance("subtle", hat);
    expect(c.radiantState(hat)).toEqual({ kind: "radiant", intensity: "subtle" });
    expect(() => c.upgradeToRadiant(hat)).toThrow(PetRadiantPurchaseError);
  });

  it("pins only an owned, eligible item not upgraded yet and shows the balance toward it", () => {
    const c = closet(4210, [sorcerer]);
    c.pinRadiantGoal(coat);
    expect(c.radiantGoalProgress).toBeUndefined();
    c.pinRadiantGoal(sorcerer);
    const goal = c.radiantGoalProgress;
    expect(goal).toEqual({ item: sorcerer, have: 4210, price: 9750 });
    expect(goal && radiantGoalFraction(goal)).toBeCloseTo(4210 / 9750);
    expect(goal && radiantGoalIsReady(goal)).toBe(false);
    const rich = closet(20000, [sorcerer]);
    rich.pinRadiantGoal(sorcerer);
    expect(rich.radiantGoalProgress?.have).toBe(9750);
    expect(rich.radiantGoalProgress && radiantGoalIsReady(rich.radiantGoalProgress)).toBe(true);
    c.pinRadiantGoal(undefined);
    expect(c.radiantGoalProgress).toBeUndefined();
  });

  it("previews an upgrade on the pet before it is bought", () => {
    const profile = new PetProfile("", "blackCat", { outfit: "whiteCoat", radiance: new Map([[coat, "subtle"]]) });
    const preview = PetCloset.radiantPreview(hat, "bold", profile);
    expect(preview.isWearing(hat)).toBe(true);
    expect(preview.radiantLook.key).toBe("accessory.wizardHat:bold,outfit.whiteCoat:subtle");
    expect(profile.isWearing(hat)).toBe(false);
  });
});

describe("SyncDocument Radiant", () => {
  it("rides upgrades in unlocks as radiant.<item id> and reads them back", () => {
    const ledger = new PetPointsLedger({ earned: 9000, purchased: [hat] });
    ledger.upgradeToRadiant(hat);
    const save = new PetSave(new PetProfile("", "blackCat", { accessories: ["wizardHat"] }), ledger);
    const document = SyncDocument.empty.recording(save, undefined, "device");
    expect([...document.unlocks].sort()).toEqual([hat, `radiant.${hat}`].sort());
    expect([...document.ledger.radiant]).toEqual([hat]);
  });

  it("keeps local upgrades and a pinnable goal when the account's document is applied", () => {
    const ledger = new PetPointsLedger({ earned: 9000, purchased: [hat, coat] });
    ledger.upgradeToRadiant(hat);
    const save = new PetSave(new PetProfile("", "blackCat"), ledger);
    save.radiantGoal = coat;
    const remote = new SyncDocument({ unlocks: [hat, coat] });
    const applied = remote.applied(save);
    expect(applied.ledger.isRadiant(hat)).toBe(true);
    expect(applied.profile.radianceOf(hat)).toBe("bold");
    expect(applied.radiantGoal).toBe(coat);
  });
});

describe("Party Radiant", () => {
  const upgraded = () => {
    const pet = new PetProfile("Pepper", "blackCat", {
      outfit: "whiteCoat",
      accessories: ["wizardHat"],
      radiance: new Map<PetItem, "bold" | "subtle" | "off">([
        [hat, "bold"],
        [coat, "subtle"],
        [sorcerer, "bold"],
      ]),
    });
    return pet;
  };

  it("sends the worn effects that are on, sorted, with wire ids", () => {
    expect(partyRadiant(upgraded())).toEqual(["white-coat:subtle", "wizard-hat:bold"]);
    expect(partyPetUpdate(upgraded()).radiant).toEqual(["white-coat:subtle", "wizard-hat:bold"]);
  });

  it("sends nothing for a pet without upgrades and an empty list to clear one with none showing", () => {
    expect("radiant" in partyPetUpdate(new PetProfile("Pip", "blackCat", { accessories: ["wizardHat"] }))).toBe(false);
    const off = new PetProfile("Pip", "blackCat", { radiance: new Map([[hat, "bold"]]) });
    expect(partyPetUpdate(off).radiant).toEqual([]);
  });

  it("reads a friend's effects back for the items they wear, dropping what it does not know", () => {
    const friend = partyProfile({
      code: "J0NAH2PF",
      name: "Jonah",
      petName: "Pepper",
      species: "cat",
      breed: "black-cat",
      costume: "white-coat",
      accessories: ["wizard-hat"],
      radiant: ["white-coat:subtle", "wizard-hat:bold", "crown:bold"],
    });
    const pet = partyPet(friend);
    expect(pet.radiantLook.key).toBe("accessory.wizardHat:bold,outfit.whiteCoat:subtle");
    expect([...localRadiance(["wizard-hat:loud", "rain-cloud:bold", "beanie:bold", "nonsense", "wizard-hat:off"], "none", ["wizardHat", "rainCloud"])]).toEqual([
      ["accessory.rainCloud", "bold"],
    ]);
    /* At most three entries are read. */
    expect(localRadiance(["a:bold", "b:bold", "c:bold", "wizard-hat:bold"], "none", ["wizardHat"]).size).toBe(0);
  });

  it("drops radiant first when an older server refuses the update, then the catalog fallbacks", () => {
    const update = { ...partyPetUpdate(upgraded()), accessories: ["wizard-hat", "nightcap"] };
    const first = olderCatalogFallback(update);
    expect(first && "radiant" in first).toBe(false);
    expect(first?.accessories).toEqual(["wizard-hat", "nightcap"]);
    const second = first && olderCatalogFallback(first);
    expect(second?.accessories).toEqual(["wizard-hat"]);
    expect("radiant" in forCatalogVersion3(update)).toBe(false);
  });
});
