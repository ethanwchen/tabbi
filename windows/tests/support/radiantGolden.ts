import { describe, expect, it } from "vitest";
import { composeClip, type PetClip } from "../../src/core/pets/petClip";
import type { PetAccessory, PetOutfit } from "../../src/core/pets/petCostume";
import type { PetItem } from "../../src/core/pets/petItem";
import { PET_ANIMATIONS, type PetAnimation, type PetBreed } from "../../src/core/pets/petKinds";
import type { PetRadiantIntensity } from "../../src/core/pets/radiant/radiantArt";
import { PetRadiantLook, RadiantLayout, radiantEligibleItems } from "../../src/core/pets/radiant/radiantResolver";
import { loadFixture } from "./fixtures";
import { clipsDigest, runLength } from "./petDigest";
import { radiantCombinations, wearing } from "./radiantAudit";

/*
 * Replays shared/fixtures/pets/radiant.json (written by RadiantGoldenTests
 * on the Mac): how every set of Radiant items worn together is laid out,
 * digests of every frame and tick of every animation per dress at full size
 * and under the notch's ceiling, and readable ticks of a few loops. The
 * digests are split over several files so Vitest runs them in parallel.
 */

interface Worn {
  item: PetItem;
  intensity: PetRadiantIntensity;
}

interface Dress {
  breed: PetBreed;
  outfit: PetOutfit;
  accessories: PetAccessory[];
  radiant: Worn[];
}

interface RadiantFile {
  schema: string;
  version: number;
  layouts: { worn: Worn[]; entries: { item: PetItem; intensity: PetRadiantIntensity; placement: number; turn?: number }[]; cycles: number }[];
  digests: { dress: Dress; ceiling?: number; frameCount: number; sha256: string }[];
  frames: { dress: Dress; animation: PetAnimation; ceiling?: number; frame: number; ticks: string[] }[];
}

const FIXTURE = "pets/radiant.json";

function look(worn: readonly Worn[]): PetRadiantLook {
  return new PetRadiantLook(worn.map((entry) => [entry.item, entry.intensity] as const));
}

function clip(dress: Dress, animation: PetAnimation, ceiling: number | undefined): PetClip {
  return composeClip(animation, dress.breed, {
    outfit: dress.outfit,
    accessories: dress.accessories,
    radiant: look(dress.radiant),
    ...(ceiling === undefined ? {} : { ceiling }),
  });
}

/** Every set of Radiant items that can be worn together (one, two or three), with every mix of intensities. */
export function wornSets(): Worn[][] {
  const sets: Worn[][] = [];
  for (const items of [...radiantEligibleItems().map((item) => [item]), ...radiantCombinations()]) {
    for (let mix = 0; mix < 1 << items.length; mix++) {
      sets.push(items.map((item, n) => ({ item, intensity: ((mix >> n) & 1) === 0 ? "bold" : "subtle" })));
    }
  }
  return sets;
}

/** The dresses whose digests the fixture pins, in its order. */
export function radiantDresses(): Dress[] {
  const dress = (breed: PetBreed, items: PetItem[], intensities: PetRadiantIntensity[]): Dress => ({
    breed,
    ...wearing(items),
    radiant: items.map((item, n) => ({ item, intensity: intensities[n] ?? "bold" })),
  });
  const dresses: Dress[] = [];
  for (const item of radiantEligibleItems()) {
    for (const breed of ["britishShorthair", "blackCat", "goldenRetriever", "dachshund", "shihTzu"] as const) {
      for (const intensity of ["bold", "subtle"] as const) dresses.push(dress(breed, [item], [intensity]));
    }
  }
  for (const items of radiantCombinations()) dresses.push(dress("britishShorthair", items, items.map(() => "bold")));
  return dresses;
}

function name(dress: Dress, ceiling: number | undefined): string {
  return `${dress.breed} ${dress.radiant.map((w) => `${w.item}:${w.intensity}`).join(" ")} ceiling ${ceiling ?? "none"}`;
}

/** The layouts, the frames and the share `part` of `parts` of the digests. */
export function describeRadiantGolden(part: number, parts: number): void {
  describe(`Radiant golden fixtures (${part + 1} of ${parts})`, () => {
    const file = loadFixture<RadiantFile>(FIXTURE);

    if (part === 0) {
      it("are the version this port reads", () => {
        expect(file.schema).toBe("tabbi.pets.golden");
        expect(file.version).toBe(1);
      });

      it("lay out every worn set the same way", () => {
        expect(file.layouts.map((entry) => entry.worn)).toEqual(wornSets());
        for (const entry of file.layouts) {
          const { outfit, accessories } = wearing(entry.worn.map((w) => w.item));
          const layout = RadiantLayout.resolve(look(entry.worn), outfit, accessories);
          expect(layout, JSON.stringify(entry.worn)).toBeDefined();
          expect(
            {
              entries: layout?.entries.map((e) => ({
                item: e.item,
                intensity: e.intensity,
                placement: e.placement,
                ...(e.turn === undefined ? {} : { turn: e.turn }),
              })),
              cycles: layout?.cycles,
            },
            JSON.stringify(entry.worn),
          ).toEqual({ entries: entry.entries, cycles: entry.cycles });
        }
      });

      it("match the readable ticks of a few loops", () => {
        for (const entry of file.frames) {
          const frame = clip(entry.dress, entry.animation, entry.ceiling).frames[entry.frame];
          expect(frame).toBeDefined();
          if (!frame) continue;
          const ticks = frame.itemFrames.length === 0 ? [frame.canvas] : frame.itemFrames;
          expect(
            ticks.map((canvas) => runLength(canvas.rows())),
            `${name(entry.dress, entry.ceiling)} ${entry.animation} frame ${entry.frame}`,
          ).toEqual(entry.ticks);
        }
      });

      it("pin every dress full size and under the ceiling", () => {
        const expected = radiantDresses().flatMap((dress) => [
          { dress, ceiling: undefined },
          { dress, ceiling: 2 },
        ]);
        expect(file.digests.map((entry) => ({ dress: entry.dress, ceiling: entry.ceiling }))).toEqual(expected);
      });
    }

    it("match the digest of every frame and tick of every animation", () => {
      const mismatches: string[] = [];
      file.digests.forEach((entry, index) => {
        if (index % parts !== part) return;
        const actual = clipsDigest(PET_ANIMATIONS.map((animation) => clip(entry.dress, animation, entry.ceiling)));
        if (actual.frameCount !== entry.frameCount || actual.sha256 !== entry.sha256) {
          mismatches.push(`${name(entry.dress, entry.ceiling)}: ${actual.frameCount} frames ${actual.sha256}`);
        }
      });
      expect(mismatches).toEqual([]);
    }, 600_000);
  });
}
