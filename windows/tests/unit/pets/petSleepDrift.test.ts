import { describe, expect, it } from "vitest";
import { bondLook } from "../../../src/core/pets/petBond";
import type { PetCanvas } from "../../../src/core/pets/petCanvas";
import type { PetClip } from "../../../src/core/pets/petClip";
import { PET_ACCESSORIES, PET_OUTFITS } from "../../../src/core/pets/petCostume";
import { PET_BREEDS } from "../../../src/core/pets/petKinds";
import { clip } from "./support";

// Port of PetSleepDriftTests.swift: the sleep "z" drifts up and right,
// shrinking and fading, always whole.

const ANIMATIONS = ["sleep", "nap"] as const;

interface ZPixel {
  x: number;
  y: number;
  faint: boolean;
}

function zPixels(canvas: PetCanvas): ZPixel[] {
  const pixels: ZPixel[] = [];
  for (let y = 0; y < canvas.height; y++) {
    for (let x = 0; x < canvas.width; x++) {
      const role = canvas.role(x, y);
      if (role === "effect" || role === "effectFaint") pixels.push({ x, y, faint: role === "effectFaint" });
    }
  }
  return pixels;
}

function center(pixels: ZPixel[]): { x: number; y: number } {
  return {
    x: pixels.reduce((sum, p) => sum + p.x, 0) / pixels.length,
    y: pixels.reduce((sum, p) => sum + p.y, 0) / pixels.length,
  };
}

describe("PetSleepDrift", () => {
  it("the z shrinks and fades as it drifts up and right", () => {
    for (const breed of PET_BREEDS) {
      for (const animation of ANIMATIONS) {
        const label = `${breed} ${animation}`;
        const built = clip(animation, breed);
        expect(built.frames.length, label).toBe(4);
        const zs = built.frames.map((frame) => zPixels(frame.canvas));
        expect(zs.map((z) => z.length), `${label}: large, small, faded, then gone`).toEqual([11, 8, 8, 0]);
        expect(zs.map((z) => z.filter((p) => p.faint).length), `${label}: only the last one fades`).toEqual([0, 0, 8, 0]);
        const centers = zs.slice(0, 3).map(center);
        centers.slice(1).forEach((higher, index) => {
          const lower = centers[index];
          if (!lower) return;
          expect(higher.y, `${label} rises`).toBeLessThan(lower.y);
          expect(higher.x, `${label} drifts right`).toBeGreaterThan(lower.x);
          expect(lower.y - higher.y, label).toBeGreaterThanOrEqual(higher.x - lower.x);
        });
      }
    }
  });

  it("costumes never hide the z", () => {
    for (const animation of ANIMATIONS) {
      const cat = "orangeTabby" as const;
      const looks: [string, PetClip][] = [
        ...PET_OUTFITS.map((outfit): [string, PetClip] => [outfit, clip(animation, cat, { outfit })]),
        ...PET_ACCESSORIES.map((accessory): [string, PetClip] => [accessory, clip(animation, cat, { accessories: [accessory] })]),
        ["top bond", clip(animation, cat, { bond: bondLook(10) })],
      ];
      const expected = clip(animation, cat).frames.map((frame) => zPixels(frame.canvas));
      for (const [name, built] of looks) {
        built.frames.forEach((frame, index) => {
          for (const pixel of expected[index] ?? []) {
            expect(frame.canvas.role(pixel.x, pixel.y), `${name} ${animation} at ${pixel.x},${pixel.y}`).toBe(
              pixel.faint ? "effectFaint" : "effect",
            );
          }
        });
      }
    }
  });

  it("the sleep z keeps clear of the frame's top rows", () => {
    for (const breed of PET_BREEDS) {
      for (const frame of clip("sleep", breed).frames) {
        expect(zPixels(frame.canvas).every((p) => p.y >= 5), breed).toBe(true);
      }
    }
  });

  it("a still pet holds a bright z", () => {
    for (const animation of ANIMATIONS) {
      const still = zPixels(clip(animation, "corgi").stillFrame.canvas);
      expect(still.length, animation).toBe(8);
      expect(still.some((p) => p.faint), `${animation}: Reduce Motion freezes a z mid-drift, not a fading one`).toBe(false);
    }
  });
});
