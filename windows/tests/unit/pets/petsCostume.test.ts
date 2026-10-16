import { describe, expect, it } from "vitest";
import { breedPalette } from "../../../src/core/pets/petBreed";
import { FRAME_SIZE, sitting } from "../../../src/core/pets/petComposer";
import { PET_ACCESSORIES, PET_OUTFITS, wearable, type PetAccessory, type PetOutfit } from "../../../src/core/pets/petCostume";
import { PET_BREEDS } from "../../../src/core/pets/petKinds";
import { USER_EDITABLE_ROLES, colorFromHex, colorHex } from "../../../src/core/pets/petPalette";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { bounds, contains, count, same } from "./support";

// Port of PetsCostumeTests.swift: which items can be worn together, and that
// every item shows on every breed.

describe("PetCostume", () => {
  it("wearable keeps one accessory per slot in drawing order", () => {
    expect(wearable(["beanie", "roundGlasses", "stethoscope", "graduationCap", "scarf"]), "last item per slot wins; neck, face, then head").toEqual([
      "scarf",
      "roundGlasses",
      "graduationCap",
    ]);
    expect(wearable([])).toEqual([]);
  });

  it("items that cover the eyes replace glasses and the other way round", () => {
    expect(wearable(["scarf", "coolSunglasses", "pirateHat"])).toEqual(["scarf", "pirateHat"]);
    expect(wearable(["blindfoldedSorcerer", "roundGlasses"])).toEqual(["roundGlasses"]);
    expect(wearable(["roundGlasses", "wizardHat"]), "a plain hat still goes with glasses").toEqual(["roundGlasses", "wizardHat"]);
    const pet = new PetProfile("Pixel", "calico", { accessories: ["coolSunglasses"] });
    pet.wear("blindfoldedSorcerer");
    expect(pet.accessories).toEqual(["blindfoldedSorcerer"]);
  });

  it("every item changes the look of every breed", () => {
    for (const breed of PET_BREEDS) {
      const plain = sitting(breed);
      for (const outfit of PET_OUTFITS.slice(1)) {
        expect(same(sitting(breed, { outfit }), plain), `${outfit} on ${breed}`).toBe(false);
      }
      for (const accessory of PET_ACCESSORIES) {
        expect(same(sitting(breed, { accessories: [accessory] }), plain), `${accessory} on ${breed}`).toBe(false);
      }
    }
  });

  it("full looks stay inside the frame and on the baseline", () => {
    const looks: [PetOutfit, PetAccessory[]][] = [
      ["scrubs", ["stethoscope", "surgicalCap"]],
      ["whiteCoat", ["roundGlasses", "graduationCap"]],
      ["none", ["scarf", "headMirror"]],
      ["none", ["beanie"]],
    ];
    for (const breed of PET_BREEDS) {
      for (const [outfit, accessories] of looks) {
        const found = bounds(sitting(breed, { outfit, accessories }));
        const label = `${breed} in ${outfit} ${accessories.join(",")}`;
        expect(found.minY, `hat clipped at the top: ${label}`).toBeGreaterThan(0);
        expect(found.minX, label).toBeGreaterThan(0);
        expect(found.maxX, label).toBeLessThan(FRAME_SIZE - 1);
        expect(found.maxY, label).toBe(FRAME_SIZE - 1);
      }
    }
  });

  it("costumes never cover the eyes", () => {
    for (const breed of PET_BREEDS) {
      const eyes = count(sitting(breed), "eye", "pupil", "eyeLight");
      const dressed = sitting(breed, { outfit: "whiteCoat", accessories: ["roundGlasses", "beanie"] });
      expect(count(dressed, "eye", "pupil", "eyeLight"), breed).toBe(eyes);
    }
  });

  it("scrubs and cap follow the recolorable costume roles", () => {
    const canvas = sitting("corgi", { outfit: "scrubs", accessories: ["surgicalCap"] });
    expect(contains(canvas, "costumeBase")).toBe(true);
    expect(contains(canvas, "coat"), "the white coat has its own roles").toBe(false);
    const pink = colorFromHex("#F28DB2");
    if (!pink) expect.fail("a color");
    const colors = canvas.colors(breedPalette("corgi").applying({ costumeBase: pink }));
    expect(colors.some((color) => color && colorHex(color) === "#F28DB2")).toBe(true);
    expect(USER_EDITABLE_ROLES.includes("costumeBase")).toBe(true);
    expect(USER_EDITABLE_ROLES.includes("coat")).toBe(false);
  });

  it("costume identifiers are stable for persistence", () => {
    const accessories: PetAccessory[] = ["headMirror", "roundGlasses"];
    expect(JSON.stringify(accessories)).toBe('["headMirror","roundGlasses"]');
    const restored = PetProfile.fromJSON({ breed: "calico", outfit: "whiteCoat" });
    expect(restored.outfit).toBe("whiteCoat");
  });
});
