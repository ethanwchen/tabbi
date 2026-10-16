import { describe, expect, it } from "vitest";
import type { PetCanvas } from "../../../src/core/pets/petCanvas";
import { FRAME_SIZE, sitting } from "../../../src/core/pets/petComposer";
import {
  PET_ACCESSORIES,
  PET_OUTFITS,
  accessorySlot,
  coversEyes,
  type PetAccessory,
  type PetOutfit,
} from "../../../src/core/pets/petCostume";
import { PET_ANIMATIONS, PET_BREEDS, type PetAnimation } from "../../../src/core/pets/petKinds";
import type { PetPoint } from "../../../src/core/pets/petPose";
import { clip, points } from "./support";

// Port of PetsCostumeFitTests.swift: every costume item on every breed
// through every frame of every animation, each dressed frame compared with
// the same frame undressed.

const LOOKS: { name: string; outfit: PetOutfit; accessories: PetAccessory[] }[] = [
  ...PET_OUTFITS.filter((outfit) => outfit !== "none").map((outfit) => ({ name: outfit, outfit, accessories: [] })),
  ...PET_ACCESSORIES.map((accessory) => ({ name: accessory, outfit: "none" as PetOutfit, accessories: [accessory] })),
];

// Where a dressed frame differs from the plain one, minus outline pixels.
function costumePixels(dressed: PetCanvas, plain: PetCanvas): PetPoint[] {
  const found: PetPoint[] = [];
  for (let y = 0; y < dressed.height; y++) {
    for (let x = 0; x < dressed.width; x++) {
      const role = dressed.role(x, y);
      if (role !== undefined && role !== "outline" && role !== plain.role(x, y)) found.push({ x, y });
    }
  }
  return found;
}

function boundsOf(found: PetPoint[]): { minX: number; minY: number; maxX: number; maxY: number } | undefined {
  if (found.length === 0) return undefined;
  const xs = found.map((p) => p.x);
  const ys = found.map((p) => p.y);
  return { minX: Math.min(...xs), minY: Math.min(...ys), maxX: Math.max(...xs), maxY: Math.max(...ys) };
}

function isSliding(animation: PetAnimation): boolean {
  return animation === "peekIn" || animation === "peekOut";
}

function hidesTheNeck(animation: PetAnimation, accessories: readonly PetAccessory[]): boolean {
  return (
    ((animation === "coffee" || animation === "nap") && accessories.some((a) => accessorySlot(a) === "neck")) ||
    (animation === "typing" && accessories.includes("foundersPin"))
  );
}

function liesOnTheFloor(animation: PetAnimation, outfit: PetOutfit, accessories: readonly PetAccessory[]): boolean {
  return animation === "nap" && (outfit !== "none" || accessories.some((a) => accessorySlot(a) === "neck"));
}

function isCovered(animation: PetAnimation, item: number, nose: number, sat: { item: number; nose: number }): boolean {
  return (animation === "coffee" || animation === "wave") && (item < sat.item || nose < sat.nose);
}

function eyesOf(canvas: PetCanvas): PetPoint[] {
  return [...points("eye", canvas), ...points("eyeLight", canvas)];
}

describe("PetCostumeFit", () => {
  it("every item shows and stays inside the frame in every animation", () => {
    const edge = FRAME_SIZE - 1;
    for (const breed of PET_BREEDS) {
      for (const animation of PET_ANIMATIONS) {
        if (isSliding(animation)) continue;
        const plain = clip(animation, breed).frames;
        for (const look of LOOKS) {
          const dressed = clip(animation, breed, look).frames;
          expect(dressed.length).toBe(plain.length);
          dressed.forEach((frame, index) => {
            const label = `${look.name} on ${breed}, ${animation} ${index + 1}`;
            const under = plain[index];
            if (!under) expect.fail(label);
            const found = costumePixels(frame.canvas, under.canvas);
            if (!hidesTheNeck(animation, look.accessories) && found.length === 0) expect.fail(`not visible: ${label}`);
            if (look.accessories.some((a) => accessorySlot(a) === "aura")) return;
            const floor = liesOnTheFloor(animation, look.outfit, look.accessories) ? edge + 1 : edge;
            if (found.some((p) => p.x === 0 || p.y === 0 || p.x === edge || p.y === floor)) {
              expect.fail(`clipped at the frame edge: ${label}`);
            }
          });
        }
      }
    }
  }, 60_000);

  it("head and face items move with the head in every frame", () => {
    const items = PET_ACCESSORIES.filter((a) => accessorySlot(a) === "head" || accessorySlot(a) === "face");
    for (const breed of PET_BREEDS) {
      const plainSitting = sitting(breed);
      for (const accessory of items) {
        const sat = {
          item: costumePixels(sitting(breed, { accessories: [accessory] }), plainSitting).length,
          nose: points("nose", plainSitting).length,
        };
        let offset: PetPoint | undefined;
        for (const animation of PET_ANIMATIONS) {
          const plain = clip(animation, breed).frames;
          const dressed = clip(animation, breed, { accessories: [accessory] }).frames;
          dressed.forEach((frame, index) => {
            const label = `${accessory} on ${breed}, ${animation} ${index + 1}`;
            const under = plain[index];
            if (!under) expect.fail(label);
            const itemPixels = costumePixels(frame.canvas, under.canvas);
            const nosePixels = points("nose", frame.canvas);
            const item = boundsOf(itemPixels);
            const nose = boundsOf(nosePixels);
            if (!item || !nose || isCovered(animation, itemPixels.length, nosePixels.length, sat)) return;
            if (isSliding(animation) && item.minY === 0) return;
            const here = { x: item.minX - nose.minX, y: item.minY - nose.minY };
            if (offset) {
              if (here.x !== offset.x || here.y !== offset.y) expect.fail(`drifted off the head: ${label}`);
            } else {
              offset = here;
            }
          });
        }
        expect(offset, `${accessory} on ${breed} never seen`).toBeDefined();
      }
    }
  }, 60_000);

  it("head items sit above the eyes on every breed", () => {
    for (const breed of PET_BREEDS) {
      const plain = sitting(breed);
      const eyes = eyesOf(plain);
      const eyeTop = Math.min(...eyes.map((p) => p.y));
      for (const accessory of PET_ACCESSORIES.filter((a) => accessorySlot(a) === "head")) {
        const dressed = sitting(breed, { accessories: [accessory] });
        const label = `${accessory} on ${breed}`;
        const shownEyes = eyesOf(dressed);
        if (coversEyes(accessory)) {
          expect(shownEyes.length * 2, `leaves both eyes showing: ${label}`).toBeLessThan(eyes.length + 1);
        } else {
          expect(shownEyes, `covers an eye: ${label}`).toEqual(eyes);
        }
        const found = costumePixels(dressed, plain);
        const item = boundsOf(found);
        if (!item) expect.fail(label);
        const hatLine = breed === "shihTzu" ? eyeTop - 1 : eyeTop - 2;
        expect(item.minY, `sits too low to read as a hat: ${label}`).toBeLessThan(hatLine);
        if (accessory === "halo") continue;
        expect(
          found.some((p) => plain.role(p.x, p.y) !== undefined || plain.role(p.x, p.y + 1) !== undefined),
          `floats above the head: ${label}`,
        ).toBe(true);
      }
    }
  });

  it("outfits never cover an eye", () => {
    for (const breed of PET_BREEDS) {
      for (const animation of PET_ANIMATIONS) {
        const plain = clip(animation, breed).frames;
        for (const outfit of PET_OUTFITS.filter((o) => o !== "none")) {
          clip(animation, breed, { outfit }).frames.forEach((frame, index) => {
            const under = plain[index];
            if (!under) expect.fail("same frame count");
            const eyes = eyesOf(under.canvas);
            const shown = eyesOf(frame.canvas);
            if (JSON.stringify(shown) !== JSON.stringify(eyes)) {
              expect.fail(`${outfit} covers an eye on ${breed}, ${animation} ${index + 1}`);
            }
          });
        }
      }
    }
  });

  it("face items sit on the eyes of every breed", () => {
    for (const breed of PET_BREEDS) {
      const plain = sitting(breed);
      const ys = eyesOf(plain).map((p) => p.y);
      const lower = Math.min(...ys);
      const upper = Math.max(...ys);
      for (const accessory of PET_ACCESSORIES.filter((a) => accessorySlot(a) === "face")) {
        const item = boundsOf(costumePixels(sitting(breed, { accessories: [accessory] }), plain));
        if (!item) expect.fail(`${accessory} on ${breed}`);
        expect(item.minY <= lower && item.maxY >= upper - 1, `${accessory} misses the eyes on ${breed}`).toBe(true);
      }
    }
  });
});
