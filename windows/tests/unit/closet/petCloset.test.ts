import { describe, expect, it } from "vitest";
import { PetCloset, type PetClosetItemState } from "../../../src/core/closet/petCloset";
import { breedDisplayName, breedFurTint, breedPalette, breedsOf } from "../../../src/core/pets/petBreed";
import { PET_ITEM_THEMES, itemIsNew, itemTheme, themeDisplayName } from "../../../src/core/pets/petItemTheme";
import { accessoryItem, outfitItem, type PetItem } from "../../../src/core/pets/petItem";
import { colorFromHex, colorHex, type PetColor } from "../../../src/core/pets/petPalette";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { PetSave } from "../../../src/core/pets/petSave";
import { PetPointsLedger, SHOP_ITEMS, isFree, itemCost } from "../../../src/core/pets/petUnlocks";

// Port of PetClosetTests.
function closet(options: { earned?: number; purchased?: PetItem[]; profile?: PetProfile } = {}): PetCloset {
  return new PetCloset(
    new PetSave(
      options.profile ?? PetProfile.starter("cat"),
      new PetPointsLedger({ earned: options.earned ?? 0, purchased: options.purchased ?? [] }),
    ),
  );
}

function hex(color: PetColor | undefined): string | undefined {
  return color ? colorHex(color) : undefined;
}

function saveJSON(save: PetSave): string {
  return JSON.stringify(save.toJSON());
}

const sorted = (values: readonly number[]) => [...values].sort((a, b) => a - b);

describe("PetCloset", () => {
  it("the wardrobe lists every item cheapest first", () => {
    expect(PetCloset.wardrobe).not.toContain(outfitItem("none"));
    expect(PetCloset.wardrobe.length).toBe(SHOP_ITEMS.length - 1);
    const costs = PetCloset.wardrobe.map(itemCost);
    expect(costs).toEqual(sorted(costs));
  });

  it("item states follow ownership, wearing and balance", () => {
    const c = closet({ earned: 250, purchased: [accessoryItem("beanie")] });
    expect(c.state(accessoryItem("beanie"))).toEqual({ kind: "owned" });
    c.tap(accessoryItem("beanie"));
    expect(c.state(accessoryItem("beanie"))).toEqual({ kind: "wearing" });
    expect(c.state(outfitItem("scrubs"))).toEqual({ kind: "affordable" });
    expect(c.state(accessoryItem("stethoscope"))).toEqual({ kind: "locked", missing: 20 });
  });

  it("tapping toggles, buys and refuses", () => {
    const c = closet({ earned: 100 });
    expect(c.tap(accessoryItem("beanie"))).toEqual({ kind: "boughtAndWore" });
    expect(c.balance).toBe(65);
    expect(c.profile.accessories).toEqual(["beanie"]);

    expect(c.tap(accessoryItem("beanie"))).toEqual({ kind: "tookOff" });
    expect(c.profile.accessories).toEqual([]);
    expect(c.tap(accessoryItem("beanie"))).toEqual({ kind: "wore" });
    expect(c.balance, "wearing an owned item is free").toBe(65);

    const before = saveJSON(c.save);
    expect(c.tap(outfitItem("whiteCoat"))).toEqual({ kind: "needsPoints", missing: 1185 });
    expect(saveJSON(c.save), "a refused tap changes nothing").toBe(before);
  });

  it("outfits take off to none", () => {
    const c = closet({ purchased: [outfitItem("scrubs")] });
    c.tap(outfitItem("scrubs"));
    expect(c.profile.outfit).toBe("scrubs");
    c.tap(outfitItem("scrubs"));
    expect(c.profile.outfit).toBe("none");
  });

  it("a new hat replaces the old one", () => {
    const c = closet({ purchased: [accessoryItem("beanie"), accessoryItem("surgicalCap")] });
    c.tap(accessoryItem("beanie"));
    c.tap(accessoryItem("surgicalCap"));
    expect(c.profile.accessories).toEqual(["surgicalCap"]);
    expect(c.state(accessoryItem("beanie"))).toEqual({ kind: "owned" });
  });

  it("trying on does not need ownership", () => {
    expect(PetCloset.wearing(outfitItem("whiteCoat"), PetProfile.starter("dog")).outfit).toBe("whiteCoat");
  });

  it("switching species picks a breed and keeps chosen names", () => {
    const c = closet();
    c.setSpecies("dog");
    expect(c.profile.species).toBe("dog");
    expect(c.profile.name, "a default name follows the species").toBe(PetProfile.starter("dog").name);

    c.rename("Nori");
    c.setSpecies("cat");
    expect(c.profile.species).toBe("cat");
    expect(c.profile.name).toBe("Nori");
  });

  it("a default name follows the breed and species but a chosen one stays", () => {
    const c = closet();
    expect(c.profile.name, "the starter cat waits for the user to name it").toBe("British Shorthair");
    c.cycleBreed(1);
    expect(c.profile.name).toBe(breedDisplayName(c.profile.breed));
    c.setSpecies("dog");
    c.setSpecies("cat");
    expect(c.profile.name, "back to a cat named by its breed").toBe(breedDisplayName(c.profile.breed));

    const saved = closet({ profile: new PetProfile("Mochi", "orangeTabby") });
    saved.setSpecies("dog");
    expect(saved.profile.name, "the old starter name is still a default").toBe(PetProfile.starter("dog").name);

    const named = closet();
    named.rename("Earl Grey");
    named.cycleBreed(1);
    expect(named.profile.name).toBe("Earl Grey");
  });

  it("switching species keeps the outfit", () => {
    const c = closet({ purchased: [outfitItem("scrubs"), accessoryItem("scarf")] });
    c.tap(outfitItem("scrubs"));
    c.tap(accessoryItem("scarf"));
    c.setSpecies("dog");
    expect(c.profile.outfit).toBe("scrubs");
    expect(c.profile.accessories).toEqual(["scarf"]);
  });

  it("cycling breeds wraps within the species", () => {
    const cats = breedsOf("cat");
    const c = closet({ profile: new PetProfile("Nori", cats[0] ?? "orangeTabby") });
    c.cycleBreed(-1);
    expect(c.profile.breed).toBe(cats[cats.length - 1]);
    c.cycleBreed(1);
    expect(c.profile.breed).toBe(cats[0]);
    c.cycleBreed(cats.length + 2);
    expect(c.profile.breed).toBe(cats[2]);
  });

  it("the fur tint is read back and follows breed changes", () => {
    const c = closet();
    expect(c.furTint).toBeUndefined();
    const pink = PetCloset.furSwatches[PetCloset.furSwatches.length - 1];
    if (!pink) throw new Error("no swatches");
    c.tintFur(pink);
    expect(hex(c.furTint)).toBe(colorHex(pink));

    c.cycleBreed(1);
    expect(hex(c.furTint)).toBe(colorHex(pink));
    expect(hex(c.profile.palette.color("furShade")), "shading follows the new breed's tones").toBe(
      hex(breedFurTint(c.profile.breed, pink).furShade),
    );

    c.tintFur(undefined);
    expect(c.furTint).toBeUndefined();
    expect(hex(c.profile.palette.color("furBase"))).toBe(hex(breedPalette(c.profile.breed).color("furBase")));
  });

  it("retired swatches move to their replacements", () => {
    const swatches = PetCloset.furSwatches.map(colorHex);
    for (const value of ["#F2A65A", "#C98B5B", "#8A5A3C", "#3B3434", "#9AA3AD", "#F4ECE0", "#E58FA8", "#8FB8E8"]) {
      const profile = new PetProfile("Pip", "orangeTabby");
      profile.tintFur(colorFromHex(value));
      const restored = new PetCloset(new PetSave(profile));
      expect(swatches, value).toContain(hex(restored.furTint));
    }
  });

  it("swatches are distinct", () => {
    const swatches = PetCloset.furSwatches.map(colorHex);
    expect(new Set(swatches).size).toBe(swatches.length);
    expect(swatches.length).toBeGreaterThanOrEqual(6);
    const names = PetCloset.furSwatches.flatMap((swatch) => PetCloset.swatchName(swatch) ?? []);
    expect(new Set(names).size, "every swatch has its own name").toBe(swatches.length);
    const other = colorFromHex("#123456");
    if (!other) throw new Error("bad color");
    expect(PetCloset.swatchName(other)).toBeUndefined();
  });

  it("the next unlock reports the gap", () => {
    const c = closet({ earned: 10 });
    expect(c.nextUnlock).toEqual({ item: accessoryItem("beanie"), missing: 25 });
    c.recordStudy(25, true);
    expect(c.nextUnlock?.missing).toBe(0);
  });

  it("edits survive a save round trip", () => {
    const c = PetCloset.demo();
    c.rename("Dr. Mochi");
    c.tintFur(PetCloset.furSwatches[3]);
    c.tap(outfitItem("scrubs"));
    const restored = PetSave.decode(JSON.parse(c.save.encoded()));
    expect(saveJSON(restored)).toBe(saveJSON(c.save));
  });

  it("the demo has every tile state", () => {
    const demo = PetCloset.demo();
    const kinds = new Set(PetCloset.wardrobe.map((item) => demo.state(item).kind));
    for (const kind of ["wearing", "owned", "affordable", "locked"] as PetClosetItemState["kind"][]) {
      expect(kinds.has(kind), kind).toBe(true);
    }
  });

  // The App Store Closet shot: the shelf in view mostly owned, a cozy look worn, and points left.
  it("the demo is a well-stocked wardrobe wearing a cozy look", () => {
    const demo = PetCloset.demo();
    const firstShelf = PetCloset.shelves[0]?.items ?? [];
    const owned = firstShelf.filter((item) => demo.save.ledger.owns(item));
    expect(owned.length).toBeGreaterThanOrEqual(6);
    expect(owned.length, "some items are still to earn").toBeLessThan(firstShelf.length);
    expect(demo.profile.outfit).toBe("cozyHoodie");
    expect(demo.profile.accessories).toEqual(["beanie"]);
    expect(demo.save.ledger.owns(outfitItem("cozyHoodie")) && demo.save.ledger.owns(accessoryItem("beanie"))).toBe(true);
    expect(demo.balance).toBe(240);
    expect(demo.nextUnlock?.missing).toBe(0);
  });

  // Product rule: demo and snapshot art never dress the pet in a cape.
  it("the demo never wears a cape", () => {
    const demo = PetCloset.demo();
    expect(demo.profile.outfit).not.toBe("superheroCape");
    expect(demo.profile.accessories).not.toContain("kingsCape");
    expect(demo.profile.isWearing(outfitItem("superheroCape"))).toBe(false);
    expect(demo.profile.isWearing(accessoryItem("kingsCape"))).toBe(false);
  });

  it("free starters are owned from the start", () => {
    const c = closet();
    for (const item of PetCloset.wardrobe.filter(isFree)) expect(c.state(item), item).toEqual({ kind: "owned" });
    expect(c.tap(accessoryItem("partyHat"))).toEqual({ kind: "wore" });
    expect(c.profile.accessories).toEqual(["partyHat"]);
    expect(c.balance).toBe(0);
  });

  it("shelves group every item once by theme, cheapest first", () => {
    expect(PetCloset.shelves.map((shelf) => shelf.theme)).toEqual([...PET_ITEM_THEMES]);
    const shelved = PetCloset.shelves.flatMap((shelf) => shelf.items);
    expect(new Set(shelved)).toEqual(new Set(PetCloset.wardrobe));
    expect(shelved.length).toBe(PetCloset.wardrobe.length);
    for (const shelf of PetCloset.shelves) {
      expect(shelf.items.every((item) => itemTheme(item) === shelf.theme)).toBe(true);
      const costs = shelf.items.map(itemCost);
      expect(costs, themeDisplayName(shelf.theme)).toEqual(sorted(costs));
      expect(shelf.items.length, `${themeDisplayName(shelf.theme)} is too thin to be a shelf`).toBeGreaterThanOrEqual(3);
    }
    expect(itemTheme(outfitItem("whiteCoat"))).toBe("study");
    expect(itemTheme(accessoryItem("blindfoldedSorcerer"))).toBe("fantasy");
    expect(itemTheme(outfitItem("dinosaurHoodie"))).toBe("silly");
  });

  it("cozy, seasonal and silly shelves start with a free item", () => {
    const starters = PetCloset.shelves.flatMap((shelf) => {
      const first = shelf.items[0];
      return first && isFree(first) ? [shelf.theme] : [];
    });
    expect(starters).toEqual(["cozy", "seasonal", "silly"]);
  });

  it("the new badge shows on fresh items until owned", () => {
    expect(itemIsNew(accessoryItem("scarf")), "the med set shipped first").toBe(false);
    expect(itemIsNew(outfitItem("scrubs"))).toBe(false);
    expect(itemIsNew(accessoryItem("wizardHat")), "the second batch is no longer the latest").toBe(false);
    expect(itemIsNew(accessoryItem("angelWings"))).toBe(true);
    expect(itemIsNew(accessoryItem("goldenLaurel")), "limited items have their own badge").toBe(false);

    const c = closet({ earned: 2000 });
    expect(c.isNew(accessoryItem("angelWings"))).toBe(true);
    expect(c.tap(accessoryItem("angelWings"))).toEqual({ kind: "boughtAndWore" });
    expect(c.isNew(accessoryItem("angelWings")), "the badge goes once the item is unlocked").toBe(false);
  });
});
