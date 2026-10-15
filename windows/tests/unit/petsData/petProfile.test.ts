import { describe, expect, it } from "vitest";
import { starterForKit } from "../../../src/core/closet/petKitDefaults";
import { PetClipSet } from "../../../src/core/pets/petAnimator";
import { breedDisplayName, breedFurTint, breedPalette } from "../../../src/core/pets/petBreed";
import type { PetCanvas } from "../../../src/core/pets/petCanvas";
import { sitting } from "../../../src/core/pets/petComposer";
import { PET_ACCESSORIES, PET_OUTFITS } from "../../../src/core/pets/petCostume";
import { accessoryItem, itemFromID, outfitItem } from "../../../src/core/pets/petItem";
import { PET_ANIMATIONS, PET_SPECIES } from "../../../src/core/pets/petKinds";
import { colorFromHex, colorHex, luminance, roleSymbol, type PetColor } from "../../../src/core/pets/petPalette";
import { PetPointsRules } from "../../../src/core/pets/petPointsRules";
import { MAX_PET_NAME_LENGTH, PetProfile } from "../../../src/core/pets/petProfile";
import { PetSave } from "../../../src/core/pets/petSave";
import { ALL_ITEMS, PetPointsLedger, PetPurchaseError, SHOP_ITEMS, isFree, itemCost } from "../../../src/core/pets/petUnlocks";

// Port of PetsProfileTests.swift (PetProfileTests, PetUnlockTests, PetSaveTests).

function hex(value: string): PetColor {
  const color = colorFromHex(value);
  if (!color) throw new Error(`bad color ${value}`);
  return color;
}

const pink = hex("#FF77AA");

function roundTrip(profile: PetProfile): PetProfile {
  return PetProfile.fromJSON(JSON.parse(JSON.stringify(profile.toJSON())));
}

describe("PetProfile", () => {
  it("cleans, caps and never empties names", () => {
    expect(new PetProfile("  Dr.   Whiskers \n", "tuxedo").name).toBe("Dr. Whiskers");
    expect(new PetProfile("Professor Fluffington", "calico").name.length).toBe(MAX_PET_NAME_LENGTH);
    expect(new PetProfile("   ", "corgi").name).toBe("Corgi");
    const profile = PetProfile.starter("cat");
    profile.rename("Nori");
    expect(profile.name).toBe("Nori");
  });

  it("starts new users with the British Shorthair, named by its breed", () => {
    const starter = PetProfile.starter("cat");
    expect(starter.breed).toBe("britishShorthair");
    expect(starter.name).toBe(breedDisplayName("britishShorthair"));
    expect(starter.hasDefaultName).toBe(true);
    expect(starter.palette.equals(breedPalette("britishShorthair").withVisibleRim())).toBe(true);
    expect(starterForKit(undefined).equals(starter)).toBe(true);
    expect(new PetProfile("Earl Grey", "britishShorthair").hasDefaultName).toBe(false);
  });

  it("keeps the starter cat's whole breed name after a save", () => {
    const starter = PetProfile.starter("cat");
    const reloaded = roundTrip(starter);
    expect(reloaded.name).toBe("British Shorthair");
    expect(reloaded.hasDefaultName).toBe(true);
    expect(reloaded.equals(starter)).toBe(true);
  });

  it("keeps an existing saved pet's breed and name", () => {
    const profile = PetProfile.fromJSON({ name: "Mochi", breed: "orangeTabby", outfit: "none", accessories: [] });
    expect(profile.breed).toBe("orangeTabby");
    expect(profile.name).toBe("Mochi");
  });

  it("renders the starter pet in every animation and costume", () => {
    const starter = PetProfile.starter("cat");
    const palette = starter.palette;
    const fur = colorHex(palette.color("furBase"));
    const looks = [
      { outfit: "none" as const, accessories: [] },
      ...PET_OUTFITS.slice(1).map((outfit) => ({ outfit, accessories: [] })),
      ...PET_ACCESSORIES.map((accessory) => ({ outfit: "none" as const, accessories: [accessory] })),
    ];
    for (const look of looks) {
      const clips = new PetClipSet({ breed: starter.breed, ...look });
      for (const animation of PET_ANIMATIONS) {
        // A peek starts or ends hidden, so only some frames show the pet.
        const shown = clips.clip(animation).frames.filter((frame) => frame.canvas.opaqueBounds !== undefined);
        const name = `${animation} ${look.outfit} ${look.accessories.join(",")}`;
        expect(shown.length, name).toBeGreaterThan(0);
        for (const frame of shown) {
          const colors = frame.canvas.colors(palette).flatMap((color) => (color ? [colorHex(color)] : []));
          expect(colors.includes(fur), `the silver fur shows: ${name}`).toBe(true);
        }
      }
    }
  }, 60_000);

  it("rings the British Shorthair's tail sitting and walking", () => {
    const ringCount = (canvas: PetCanvas) => {
      let best = 0;
      for (let x = 0; x < canvas.width; x++) {
        let runs = 0;
        let inRing = false;
        for (let y = 0; y < canvas.height; y++) {
          const isRing = canvas.role(x, y) === "furAccent";
          if (isRing && !inRing) runs += 1;
          inRing = isRing;
        }
        best = Math.max(best, runs);
      }
      return best;
    };
    const clips = new PetClipSet({ breed: "britishShorthair" });
    expect(ringCount(sitting("britishShorthair"))).toBeGreaterThanOrEqual(3);
    for (const frame of clips.clip("walk").frames) expect(ringCount(frame.canvas)).toBeGreaterThanOrEqual(2);
    expect(ringCount(sitting("grayTabby")), "plain cats keep their plain tail").toBeLessThan(3);
  });

  it("gives the British Shorthair the shared cat eyes in blue", () => {
    const palette = breedPalette("britishShorthair");
    expect(palette.color("eye").blue).toBeGreaterThan(palette.color("eye").red + 80);
    expect(luminance(palette.color("eyeLight"))).toBeGreaterThan(0.9);
    const eyePixels = (canvas: PetCanvas) => {
      const out: string[] = [];
      for (let y = 0; y < canvas.height; y++) {
        for (let x = 0; x < canvas.width; x++) {
          const role = canvas.role(x, y);
          if (role === "eye" || role === "pupil" || role === "eyeLight") out.push(`${x},${y},${roleSymbol(role)}`);
        }
      }
      return out;
    };
    const reference = eyePixels(sitting("orangeTabby"));
    expect(reference.length).toBe(12);
    expect(eyePixels(sitting("britishShorthair"))).toEqual(reference);
    const clips = new PetClipSet({ breed: "britishShorthair" });
    const tabby = new PetClipSet({ breed: "orangeTabby" });
    for (const animation of PET_ANIMATIONS) {
      const plain = tabby.clip(animation).frames;
      clips.clip(animation).frames.forEach((frame, index) => {
        const other = plain[index];
        if (other) expect(eyePixels(frame.canvas), animation).toEqual(eyePixels(other.canvas));
      });
    }
  });

  it("gives the British Shorthair a soft white-silver coat", () => {
    const palette = breedPalette("britishShorthair");
    expect(luminance(palette.color("furBase"))).toBeGreaterThan(0.8);
    expect(luminance(palette.color("furShade"))).toBeGreaterThan(0.6);
    expect(luminance(palette.color("furAccent"))).toBeLessThan(luminance(palette.color("furShade")));
    expect(colorHex(palette.color("furBase"))).not.toBe(colorHex(breedPalette("whiteCat").color("furBase")));
  });

  it("sits the British Shorthair plump and centered under its head", () => {
    const belly = (canvas: PetCanvas) => {
      const y = 25;
      let start = 0;
      while (start < canvas.width && canvas.pixel(start, y) === 0) start++;
      let end = start;
      while (end < canvas.width && canvas.pixel(end, y) !== 0) end++;
      return { lower: start, upper: end - 1, count: end - start };
    };
    const plump = belly(sitting("britishShorthair"));
    const plain = belly(sitting("orangeTabby"));
    expect(plump.count).toBeGreaterThanOrEqual(plain.count + 2);
    expect(plump.lower + plump.upper).toBe(plain.lower + plain.upper);
  });

  it("matches the starter to the chosen species", () => {
    for (const species of PET_SPECIES) {
      const starter = PetProfile.starter(species);
      expect(starter.species).toBe(species);
      expect(starter.outfit).toBe("none");
      expect(starter.accessories).toEqual([]);
    }
  });

  it("recolors only user-editable roles", () => {
    const profile = new PetProfile("Pip", "orangeTabby", { paletteOverrides: { eye: pink, furBase: pink } });
    expect(profile.paletteOverrides).toEqual({ furBase: pink });
    profile.setColor(pink, "outline");
    profile.setColor(pink, "costumeBase");
    expect(profile.palette.color("costumeBase")).toEqual(pink);
    expect(profile.palette.color("outline")).toEqual(breedPalette("orangeTabby").color("outline"));
    profile.setColor(undefined, "furBase");
    expect(profile.palette.color("furBase")).toEqual(breedPalette("orangeTabby").color("furBase"));
    profile.resetColors();
    expect(profile.palette.equals(breedPalette("orangeTabby"))).toBe(true);
  });

  it("adds the light rim when fur is recolored dark", () => {
    const profile = new PetProfile("Pip", "whiteCat");
    profile.setColor(hex("#151217"), "furBase");
    expect(profile.palette.color("outline")).toEqual(profile.palette.rim);
  });

  it("keeps the fur tint as the pick and follows the breed", () => {
    const lilac = hex("#B4A2C8");
    const profile = new PetProfile("Pip", "orangeTabby");
    profile.tintFur(lilac);
    expect(profile.furTint).toEqual(lilac);
    expect(profile.palette.color("furBase")).toEqual(lilac);
    profile.breed = "calico";
    expect(profile.palette.color("furBase"), "a calico stays white").toEqual(breedPalette("calico").color("furBase"));
    expect(profile.palette.color("furAccent")).toEqual(breedFurTint("calico", lilac).furAccent);
  });

  it("keeps a legacy tinted save's pick and drops the old shades", () => {
    const profile = PetProfile.fromJSON({
      name: "Pip",
      breed: "calico",
      paletteOverrides: { furBase: "#E58FA8", furShade: "#C46F88", furAccent: "#FFB0C8", costumeBase: "#112233" },
    });
    expect(profile.furTint).toEqual(hex("#E58FA8"));
    expect(profile.paletteOverrides).toEqual({ costumeBase: hex("#112233") });
    expect(roundTrip(profile).equals(profile)).toBe(true);
    const untinted = profile.copy();
    untinted.tintFur(undefined);
    expect(roundTrip(untinted).furTint).toBeUndefined();
  });

  it("clears the fur tint without losing other colors", () => {
    const profile = new PetProfile("Pip", "goldenRetriever");
    profile.setColor(pink, "costumeBase");
    profile.tintFur(hex("#1C1719"));
    expect(profile.palette.color("outline"), "black fur still gets the light rim").toEqual(profile.palette.rim);
    profile.tintFur(undefined);
    expect(profile.paletteOverrides).toEqual({ costumeBase: pink });
    expect(profile.palette.color("furAccent")).toEqual(breedPalette("goldenRetriever").color("furAccent"));
  });

  it("replaces the item in the same slot", () => {
    const profile = new PetProfile("Pip", "beagle", { accessories: ["beanie", "graduationCap"] });
    expect(profile.accessories).toEqual(["graduationCap"]);
    profile.wear("stethoscope");
    profile.wear("surgicalCap");
    expect(profile.accessories).toEqual(["stethoscope", "surgicalCap"]);
    expect(profile.isWearing(accessoryItem("surgicalCap"))).toBe(true);
    profile.takeOff("stethoscope");
    expect(profile.accessories).toEqual(["surgicalCap"]);
    expect(profile.isWearing(outfitItem("none"))).toBe(true);
  });

  it("shows the chosen look in the sitting canvas", () => {
    const profile = new PetProfile("Pip", "corgi", { outfit: "scrubs", accessories: ["stethoscope"] });
    expect(profile.sittingCanvas().equals(sitting("corgi", { outfit: "scrubs", accessories: ["stethoscope"] }))).toBe(true);
  });

  it("round-trips through JSON", () => {
    const profile = new PetProfile("Biscuit", "goldenRetriever", {
      paletteOverrides: { costumeBase: pink },
      outfit: "whiteCoat",
      accessories: ["roundGlasses", "headMirror"],
    });
    expect(roundTrip(profile).equals(profile)).toBe(true);
  });

  it("drops unknown values instead of failing", () => {
    const profile = PetProfile.fromJSON({
      name: "Mochi",
      breed: "calico",
      outfit: "spaceSuit",
      accessories: ["jetpack", "beanie"],
      paletteOverrides: { furBase: "#112233", sparkle: "#FFFFFF", eye: "#12345", nose: "tan" },
    });
    expect(profile.breed).toBe("calico");
    expect(profile.outfit).toBe("none");
    expect(profile.accessories).toEqual(["beanie"]);
    // A legacy fur base is read as the fur tint it was.
    expect(profile.paletteOverrides).toEqual({});
    expect(profile.furTint).toEqual(hex("#112233"));
  });

  it("fails without a breed", () => {
    expect(() => PetProfile.fromJSON({ name: "Mochi" })).toThrow();
  });
});

describe("pet unlocks", () => {
  it("covers every item, cheapest first", () => {
    expect(ALL_ITEMS.length).toBe(PET_OUTFITS.length + PET_ACCESSORIES.length);
    const costs = SHOP_ITEMS.map(itemCost);
    expect(costs).toEqual([...costs].sort((a, b) => a - b));
    expect(new Set(SHOP_ITEMS.filter(isFree))).toEqual(
      new Set([outfitItem("none"), accessoryItem("scarf"), accessoryItem("partyHat"), accessoryItem("bowTie")]),
    );
    const prices = SHOP_ITEMS.filter((item) => !isFree(item)).map(itemCost);
    expect(new Set(prices).size).toBe(prices.length);
    expect(SHOP_ITEMS[SHOP_ITEMS.length - 1]).toBe(accessoryItem("graduationCap"));
  });

  it("has stable ids that round-trip", () => {
    expect(outfitItem("whiteCoat")).toBe("outfit.whiteCoat");
    expect(accessoryItem("headMirror")).toBe("accessory.headMirror");
    for (const item of ALL_ITEMS) expect(itemFromID(item)).toBe(item);
    expect(itemFromID("accessory.jetpack")).toBeUndefined();
    expect(itemFromID("beanie")).toBeUndefined();
    expect(itemFromID("hat.beanie")).toBeUndefined();
  });

  it("turns study minutes into points", () => {
    expect(PetPointsRules.points(4, true)).toBe(0);
    expect(PetPointsRules.points(5, false)).toBe(5);
    expect(PetPointsRules.points(24, true)).toBe(24);
    expect(PetPointsRules.points(25, false)).toBe(25);
    expect(PetPointsRules.points(25, true)).toBe(35);
    expect(PetPointsRules.points(-10, true)).toBe(0);
  });

  it("unlocks the first item with the first focus block", () => {
    const ledger = new PetPointsLedger();
    expect(ledger.nextUnlock).toBe(accessoryItem("beanie"));
    expect(ledger.recordStudy(25, true)).toBe(35);
    expect(ledger.canBuy(accessoryItem("beanie"))).toBe(true);
    ledger.buy(accessoryItem("beanie"));
    expect(ledger.balance).toBe(0);
    expect(ledger.earned).toBe(35);
    expect(ledger.nextUnlock).toBe(accessoryItem("roundGlasses"));
  });

  it("refuses purchases with a reason", () => {
    const ledger = new PetPointsLedger();
    ledger.recordStudy(50, true);
    const reason = (run: () => void) => {
      try {
        run();
      } catch (error) {
        if (error instanceof PetPurchaseError) return { reason: error.reason, missing: error.missing };
      }
      return undefined;
    };
    expect(reason(() => ledger.buy(outfitItem("scrubs")))).toEqual({ reason: "notEnoughPoints", missing: 180 });
    expect(ledger.balance).toBe(60);
    ledger.buy(accessoryItem("roundGlasses"));
    expect(reason(() => ledger.buy(accessoryItem("roundGlasses")))?.reason).toBe("alreadyOwned");
    expect(reason(() => ledger.buy(outfitItem("none")))?.reason).toBe("alreadyOwned");
    expect(ledger.balance).toBe(10);
  });

  it("never spends more than earned", () => {
    const ledger = new PetPointsLedger({ earned: 10, spent: 99, purchased: [outfitItem("none"), accessoryItem("beanie")] });
    expect(ledger.balance).toBe(0);
    expect([...ledger.purchased]).toEqual([accessoryItem("beanie")]);
    expect(new PetPointsLedger({ earned: -5 }).balance).toBe(0);
  });

  it("refunds an old save's scarf once", () => {
    const ledger = PetPointsLedger.fromJSON({ earned: 100, spent: 60, purchased: ["accessory.scarf", "accessory.beanie"] });
    expect(ledger.balance).toBe(70);
    expect([...ledger.purchased]).toEqual([accessoryItem("beanie")]);
    const reloaded = PetPointsLedger.fromJSON(JSON.parse(JSON.stringify(ledger.toJSON())));
    expect(reloaded.balance).toBe(70);
  });

  it("restricts a profile to owned items", () => {
    const ledger = new PetPointsLedger();
    ledger.recordStudy(270, true);
    ledger.buy(accessoryItem("stethoscope"));
    const profile = new PetProfile("Pip", "labrador", { outfit: "whiteCoat", accessories: ["stethoscope", "beanie"] });
    const restricted = profile.restricted(ledger);
    expect(restricted.outfit).toBe("none");
    expect(restricted.accessories).toEqual(["stethoscope"]);
    expect(restricted.name).toBe("Pip");
  });
});

describe("PetSave", () => {
  it("round-trips through its JSON", () => {
    const ledger = new PetPointsLedger();
    ledger.recordStudy(240, true);
    ledger.buy(outfitItem("scrubs"));
    const profile = new PetProfile("Nori", "siamese", { paletteOverrides: { costumeBase: hex("#7A5CFF") }, outfit: "scrubs" });
    const save = new PetSave(profile, ledger);
    const reloaded = PetSave.decode(JSON.parse(save.encoded()));
    expect(reloaded.toJSON()).toEqual(save.toJSON());
    expect(reloaded.profile.equals(save.profile)).toBe(true);
    expect(reloaded.ledger.equals(save.ledger)).toBe(true);
  });

  it("cannot wear unbought items after decoding", () => {
    const save = PetSave.decode({
      version: 1,
      profile: { name: "Rex", breed: "beagle", outfit: "whiteCoat", accessories: ["graduationCap"] },
      ledger: { earned: 40, spent: 30, purchased: ["accessory.beanie", "accessory.fromTheFuture"] },
    });
    expect(save.profile.outfit).toBe("none");
    expect(save.profile.accessories).toEqual([]);
    expect([...save.ledger.purchased]).toEqual([accessoryItem("beanie")]);
    expect(save.ledger.balance).toBe(10);
  });

  it("throws on a corrupt save", () => {
    expect(() => PetSave.decode(JSON.parse('"not json"'))).toThrow();
    expect(() => PetSave.decode(null)).toThrow();
  });
});
