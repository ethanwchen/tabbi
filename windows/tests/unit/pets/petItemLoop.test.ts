import { describe, expect, it } from "vitest";
import { itemEffect } from "../../../src/core/closet/petLimited";
import { PetAnimator, PetClipSet } from "../../../src/core/pets/petAnimator";
import type { PetCanvas } from "../../../src/core/pets/petCanvas";
import { itemFrameDuration } from "../../../src/core/pets/petClip";
import { itemLoopFrameCount } from "../../../src/core/pets/petComposer";
import { PET_ACCESSORIES, accessorySlot, type PetAccessory, type PetOutfit } from "../../../src/core/pets/petCostume";
import { accessoryItem, itemParts, outfitItem, type PetItem } from "../../../src/core/pets/petItem";
import { PET_ANIMATIONS } from "../../../src/core/pets/petKinds";
import { breedBodyShape } from "../../../src/core/pets/petBreed";
import type { PetPaletteRole } from "../../../src/core/pets/petPalette";
import { ALL_ITEMS } from "../../../src/core/pets/petUnlocks";
import { BODY_SHAPE_BREEDS, clip, contains, count, distinct, same } from "./support";

// Port of PetItemLoopTests.swift: animated costume items loop on the item
// clock, in step on every body shape and pose.

const tick = itemFrameDuration();

function look(item: PetItem): { outfit: PetOutfit; accessories: PetAccessory[] } {
  const parts = itemParts(item);
  return parts.kind === "outfit" ? { outfit: parts.outfit, accessories: [] } : { outfit: "none", accessories: [parts.accessory] };
}

function changedPixels(a: PetCanvas, b: PetCanvas): number {
  let n = 0;
  for (let i = 0; i < a.pixels.length; i++) if (a.pixels[i] !== b.pixels[i]) n++;
  return n;
}

describe("PetItemLoop", () => {
  it("items with an effect and animated showpieces are the ones that animate", () => {
    const animatedShopItems = new Set<PetItem>(
      (["angelWings", "kingsCape", "halo", "cherryPetals", "sparkleTrail", "rainCloud"] as const).map(accessoryItem),
    );
    for (const item of ALL_ITEMS) {
      expect(itemLoopFrameCount(item) > 1, item).toBe(itemEffect(item) !== undefined || animatedShopItems.has(item));
    }
    const expected: [PetItem, number][] = [
      [accessoryItem("angelWings"), 4],
      [accessoryItem("kingsCape"), 8],
      [accessoryItem("halo"), 8],
      [accessoryItem("cherryPetals"), 24],
      [accessoryItem("sparkleTrail"), 12],
      [accessoryItem("rainCloud"), 8],
      [accessoryItem("flameHeadband"), 4],
      [accessoryItem("goldenLaurel"), 12],
      [accessoryItem("teamMedal"), 8],
      [accessoryItem("foundersPin"), 8],
      [accessoryItem("backwardsCap"), 8],
      [accessoryItem("pumpkinHat"), 8],
      [accessoryItem("moonlitWitchHat"), 1],
      [accessoryItem("snowScarf"), 8],
      [accessoryItem("reindeerAntlers"), 1],
      [accessoryItem("heartGlasses"), 8],
      [accessoryItem("summerShades"), 8],
      [accessoryItem("lionDanceHat"), 8],
      [accessoryItem("sakuraSprig"), 8],
      [outfitItem("studyHoodie"), 8],
    ];
    for (const [item, frames] of expected) expect(itemLoopFrameCount(item), item).toBe(frames);
  });

  it("effect items move subtly on every body shape", () => {
    for (const item of ALL_ITEMS.filter((candidate) => itemEffect(candidate) !== undefined)) {
      for (const breed of BODY_SHAPE_BREEDS) {
        for (const animation of ["idle", "walk"] as const) {
          const frame = clip(animation, breed, look(item)).frames[0];
          if (!frame) expect.fail("a frame");
          const label = `${item} on ${breed} ${animation}`;
          expect(frame.itemFrames.length, label).toBe(itemLoopFrameCount(item));
          expect(same(frame.itemFrames[0], frame.canvas), `the loop opens on the still: ${label}`).toBe(true);
          const changed = frame.itemFrames.map((canvas) => changedPixels(canvas, frame.canvas));
          expect(changed.some((n) => n > 0), `moves: ${label}`).toBe(true);
          expect(Math.max(...changed), `stays subtle: ${label}`).toBeLessThanOrEqual(6);
        }
      }
    }
  });

  it("back items move behind the pet on every body shape", () => {
    const backItems = new Map<PetAccessory, PetPaletteRole>([
      ["angelWings", "coat"],
      ["kingsCape", "crimson"],
    ]);
    expect([...backItems.keys()].sort()).toEqual(PET_ACCESSORIES.filter((a) => accessorySlot(a) === "back").sort());
    for (const [accessory, color] of backItems) {
      const loop = itemLoopFrameCount(accessoryItem(accessory));
      for (const breed of BODY_SHAPE_BREEDS) {
        for (const animation of PET_ANIMATIONS) {
          const bare = clip(animation, breed);
          const worn = clip(animation, breed, { accessories: [accessory] });
          worn.frames.forEach((frame, index) => {
            const plain = bare.frames[index];
            if (!plain) expect.fail("same frame count");
            const label = `${accessory} on ${breed} ${animation} frame ${index}`;
            const ticks = frame.itemFrames.length === 0 ? [frame.canvas] : frame.itemFrames;
            for (const canvas of ticks) {
              let covered = 0;
              for (let i = 0; i < canvas.pixels.length; i++) {
                if (plain.canvas.pixels[i] !== 0 && plain.canvas.pixels[i] !== canvas.pixels[i]) covered++;
              }
              expect(covered, `nothing in front of the pet: ${label}`).toBe(0);
            }
            // Hanging from the notch, the body (and the item) are out of view.
            if (animation === "peekIn" || animation === "peekOut") return;
            expect(ticks.every((canvas) => contains(canvas, color) && !canvas.equals(plain.canvas)), `shows: ${label}`).toBe(true);
            expect(ticks.length, `loops: ${label}`).toBe(loop);
            expect(distinct(ticks), `moves: ${label}`).toBeGreaterThan(1);
          });
        }
      }
    }
  }, 60_000);

  it("aura items float around the pet on every body shape", () => {
    const auraItems: PetAccessory[] = ["cherryPetals", "sparkleTrail", "rainCloud"];
    expect(auraItems).toEqual(PET_ACCESSORIES.filter((a) => accessorySlot(a) === "aura"));
    for (const accessory of auraItems) {
      const loop = itemLoopFrameCount(accessoryItem(accessory));
      for (const breed of BODY_SHAPE_BREEDS) {
        for (const animation of PET_ANIMATIONS) {
          const bare = clip(animation, breed);
          const worn = clip(animation, breed, { accessories: [accessory] });
          worn.frames.forEach((frame, index) => {
            const plain = bare.frames[index];
            if (!plain) expect.fail("same frame count");
            const label = `${accessory} on ${breed} ${animation} frame ${index}`;
            if (animation === "peekIn" || animation === "peekOut") {
              expect(frame.canvas.equals(plain.canvas), `nothing while hanging: ${label}`).toBe(true);
              return;
            }
            expect(frame.itemFrames.length, label).toBe(loop);
            frame.itemFrames.forEach((canvas, step) => {
              let added = 0;
              for (let y = 0; y < canvas.height; y++) {
                for (let x = 0; x < canvas.width; x++) {
                  if (canvas.role(x, y) === plain.canvas.role(x, y)) continue;
                  if (plain.canvas.role(x, y) !== undefined) expect.fail(`covers the pet at (${x}, ${y}) tick ${step}: ${label}`);
                  const around = [
                    plain.canvas.role(x - 1, y),
                    plain.canvas.role(x + 1, y),
                    plain.canvas.role(x, y - 1),
                    plain.canvas.role(x, y + 1),
                  ];
                  if (!around.every((role) => role === undefined)) expect.fail(`touches the pet at (${x}, ${y}) tick ${step}: ${label}`);
                  added += 1;
                }
              }
              expect(added, `a particle shows on tick ${step}: ${label}`).toBeGreaterThan(0);
            });
            expect(distinct(frame.itemFrames), `moves every tick: ${label}`).toBe(loop);
          });
        }
      }
    }
  }, 60_000);

  it("aura particles over a back item get no outline ring", () => {
    const backs = PET_ACCESSORIES.filter((a) => accessorySlot(a) === "back");
    const auras = PET_ACCESSORIES.filter((a) => accessorySlot(a) === "aura");
    for (const back of backs) {
      for (const aura of auras) {
        for (const breed of BODY_SHAPE_BREEDS) {
          for (const animation of ["idle", "sleep", "walk"] as const) {
            const plain = clip(animation, breed, { accessories: [back] });
            const both = clip(animation, breed, { accessories: [back, aura] });
            both.frames.forEach((frame, index) => {
              const alone = plain.frames[index];
              if (!alone) expect.fail("same frame count");
              const label = `${aura} over ${back} on ${breed} ${animation} frame ${index}`;
              expect(frame.itemFrames.length, label).toBeGreaterThan(0);
              frame.itemFrames.forEach((canvas, step) => {
                // The middle of the same tick on the item clock.
                const under = alone.atItemTime((step + 0.5) * tick).canvas;
                for (let y = 0; y < canvas.height; y++) {
                  for (let x = 0; x < canvas.width; x++) {
                    if (canvas.role(x, y) !== under.role(x, y) && canvas.role(x, y) === "outline") {
                      expect.fail(`ring at (${x}, ${y}) tick ${step}: ${label}`);
                    }
                  }
                }
              });
            });
          }
        }
      }
    }
  });

  it("halo bobs above the head on every body shape", () => {
    const gold = (canvas: PetCanvas) => {
      const found: { x: number; y: number }[] = [];
      for (let y = 0; y < canvas.height; y++) {
        for (let x = 0; x < canvas.width; x++) if (canvas.role(x, y) === "gold") found.push({ x, y });
      }
      return found;
    };
    for (const breed of BODY_SHAPE_BREEDS) {
      for (const animation of ["idle", "walk"] as const) {
        const bare = clip(animation, breed).frames[0]?.canvas;
        const frame = clip(animation, breed, { accessories: ["halo"] }).frames[0];
        if (!bare || !frame) expect.fail("frames");
        const label = `${breed} ${animation}`;
        expect(frame.itemFrames.length, label).toBe(8);
        const tops = frame.itemFrames.map((canvas) => {
          const ys = gold(canvas).map((point) => point.y);
          return ys.length === 0 ? undefined : Math.min(...ys);
        });
        const up = tops[0];
        if (up === undefined) expect.fail(`halo shows: ${label}`);
        expect(tops, label).toEqual([up, up, up, up, up + 1, up + 1, up + 1, up + 1]);
        expect(frame.itemFrames.map((canvas) => count(canvas, "effect")), label).toEqual([0, 1, 1, 1, 0, 0, 0, 0]);
        const shape = breedBodyShape(breed);
        if (shape === "poodleDog" || shape === "shihTzuDog") continue;
        const neighbors: [number, number][] =
          shape === "foldCat" ? [[0, 0]] : [[0, 0], [-1, 0], [1, 0], [0, -1], [0, 1]];
        frame.itemFrames.forEach((canvas, step) => {
          for (const point of gold(canvas)) {
            const around = neighbors.map(([dx, dy]) => bare.role(point.x + dx, point.y + dy));
            expect(
              around.every((role) => role === undefined || role === "outline"),
              `touches the fur at ${point.x},${point.y}, tick ${step}: ${label}`,
            ).toBe(true);
          }
        });
      }
    }
  });

  it("still items have no item frames", () => {
    const clips = new PetClipSet({ breed: "corgi", outfit: "superheroCape", accessories: ["beanie", "bowTie"] });
    for (const animation of PET_ANIMATIONS) {
      expect(clips.clip(animation).frames.every((frame) => frame.itemFrames.length === 0), animation).toBe(true);
    }
  });

  it("the item clock picks the tick and skips ticks that look the same", () => {
    const frame = clip("sit", "orangeTabby", { accessories: ["teamMedal"] }).frames[0];
    if (!frame) expect.fail("a frame");
    const frames = frame.itemFrames;
    expect(frames.length).toBe(8);
    expect(same(frame.atItemTime(5.5 * tick).canvas, frames[5])).toBe(true);
    expect(same(frame.atItemTime(13.5 * tick).canvas, frames[5]), "the loop wraps").toBe(true);
    expect(same(frame.atItemTime(0.5 * tick).canvas, frame.canvas)).toBe(true);
    expect(same(frames[5], frame.canvas)).toBe(false);
    expect(same(frames[6], frames[5])).toBe(false);
    expect(same(frames[7], frame.canvas)).toBe(true);
    expect(frame.nextItemChange(0.5 * tick)).toBeCloseTo(5 * tick, 9);
    expect(frame.nextItemChange(5.5 * tick)).toBeCloseTo(6 * tick, 9);
    expect(frame.nextItemChange(6.5 * tick)).toBeCloseTo(7 * tick, 9);
    expect(frame.nextItemChange(7.5 * tick)).toBeCloseTo(13 * tick, 9);

    const still = clip("sit", "orangeTabby", { accessories: ["beanie"] }).frames[0];
    if (!still) expect.fail("a frame");
    expect(still.nextItemChange(0)).toBeUndefined();
    expect(still.atItemTime(3 * tick)).toBe(still);
  });

  it("the player follows the item clock and Reduce Motion holds the still", () => {
    const clips = new PetClipSet({ breed: "goldenRetriever", accessories: ["flameHeadband"] });
    const animator = new PetAnimator(clips.durations, { at: 0, seed: 7 });
    const next = clips.nextChange(animator, 0.01);
    if (next === undefined) expect.fail("a next change");
    expect(next, "wakes for the next flicker, not the next breath").toBeLessThanOrEqual(tick + 1e-9);
    const idle = clips.clip("idle").frames[0];
    if (!idle) expect.fail("a frame");
    expect(same(clips.frame(animator.playback, 1.5 * tick)?.canvas, idle.itemFrames[1])).toBe(true);
    expect(same(clips.stillFrame(animator)?.canvas, clips.clip("idle").stillFrame.canvas)).toBe(true);
    expect(same(clips.clip("idle").stillFrame.canvas, idle.canvas), "Reduce Motion shows the loop's still").toBe(true);
  });
});
