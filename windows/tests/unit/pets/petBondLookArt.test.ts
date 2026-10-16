import { describe, expect, it } from "vitest";
import { PetClipSet } from "../../../src/core/pets/petAnimator";
import { NO_BOND_LOOK, PET_COLLARS, PetBond, SPARKLE_LEVEL, bondLook, bondLooksEqual, collarUnlockLevel } from "../../../src/core/pets/petBond";
import type { PetCanvas } from "../../../src/core/pets/petCanvas";
import { sitting } from "../../../src/core/pets/petComposer";
import { PET_ACCESSORIES, accessorySlot } from "../../../src/core/pets/petCostume";
import { PET_ANIMATIONS, PET_BREEDS } from "../../../src/core/pets/petKinds";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { clip, distinct, same, silhouette } from "./support";

// Port of PetBondLookArtTests.swift: the bond's collar and sparkle are
// breed-agnostic overlays that never cover the pet and are never saved.

function setKey(set: PetClipSet): string {
  return PET_ANIMATIONS.map((animation) =>
    set
      .clip(animation)
      .frames.map((frame) => [frame.canvas, ...frame.itemFrames].map((canvas: PetCanvas) => canvas.symbols()).join(";"))
      .join("|"),
  ).join("#");
}

describe("PetBondLookArt", () => {
  it("no bond looks exactly like the bare pet", () => {
    for (const breed of PET_BREEDS) {
      expect(same(sitting(breed, { bond: NO_BOND_LOOK }), sitting(breed)), breed).toBe(true);
      expect(same(sitting(breed, { bond: bondLook(1) }), sitting(breed)), breed).toBe(true);
    }
  });

  it("every collar shows and differs on every breed", () => {
    const levels = PET_COLLARS.map(collarUnlockLevel);
    for (const breed of PET_BREEDS) {
      const frames = levels.map((level) => sitting(breed, { bond: bondLook(level) }));
      expect(distinct(frames), `${breed}: each collar upgrade changes the picture`).toBe(levels.length);
      const bare = silhouette(frames[0] ?? sitting(breed));
      // A collar is drawn on the pet, so the silhouette stays the same.
      for (const frame of frames.slice(1)) expect(silhouette(frame), breed).toBe(bare);
    }
  });

  it("a neck item is worn instead of the collar", () => {
    const gold = bondLook(collarUnlockLevel("gold"));
    for (const accessory of PET_ACCESSORIES.filter((a) => accessorySlot(a) === "neck")) {
      expect(same(sitting("calico", { accessories: [accessory], bond: gold }), sitting("calico", { accessories: [accessory] })), accessory).toBe(
        true,
      );
    }
    // Other slots keep the collar.
    expect(same(sitting("calico", { accessories: ["partyHat"], bond: gold }), sitting("calico", { accessories: ["partyHat"] }))).toBe(false);
  });

  it("the sparkle only fills free air in every clip", () => {
    const collar = bondLook(SPARKLE_LEVEL - 1);
    const sparkle = bondLook(SPARKLE_LEVEL);
    expect(collar.collar, "the sparkle level adds only the sparkle").toBe(sparkle.collar);
    for (const breed of PET_BREEDS) {
      for (const animation of PET_ANIMATIONS) {
        const plain = clip(animation, breed, { bond: collar });
        const sparkling = clip(animation, breed, { bond: sparkle });
        expect(plain.frames.length).toBe(sparkling.frames.length);
        sparkling.frames.forEach((after, index) => {
          const before = plain.frames[index];
          if (!before) expect.fail("same frame count");
          for (const canvas of [after.canvas, ...after.itemFrames]) {
            for (let i = 0; i < before.canvas.pixels.length; i++) {
              const pixel = before.canvas.pixels[i];
              if (pixel !== 0 && canvas.pixels[i] !== pixel) expect.fail(`${breed} ${animation}: the sparkle never covers the pet`);
            }
          }
        });
      }
    }
    // It twinkles: the sitting idle loops through more than one picture.
    const idle = clip("idle", "orangeTabby", { bond: sparkle }).frames[0];
    expect(distinct(idle?.itemFrames ?? [])).toBeGreaterThan(1);
  });

  it("the profile shows its bond but never saves it", () => {
    const profile = new PetProfile("Mochi", "orangeTabby");
    profile.bondLook = bondLook(8);
    expect(same(profile.sittingCanvas(), sitting("orangeTabby", { bond: bondLook(8) }))).toBe(true);
    const fromProfile = new PetClipSet({
      breed: profile.breed,
      outfit: profile.outfit,
      accessories: profile.accessories,
      bond: profile.bondLook,
    });
    expect(setKey(fromProfile)).toBe(setKey(new PetClipSet({ breed: "orangeTabby", bond: bondLook(8) })));

    const text = JSON.stringify(profile);
    expect(text.includes("bond")).toBe(false);
    const decoded = PetProfile.fromJSON(JSON.parse(text));
    expect(bondLooksEqual(decoded.bondLook, NO_BOND_LOOK)).toBe(true);
    expect(PetBond.maxLevel).toBe(10);
  });
});
