import { describe, expect, it } from "vitest";
import { PetClipSet, cachedClipSet, type PetLook } from "../../../src/core/pets/petAnimator";
import { composeClip, type PetClip } from "../../../src/core/pets/petClip";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { PET_ANIMATIONS } from "../../../src/core/pets/petKinds";
import { pixelFor } from "../../../src/core/pets/petCanvas";
import { breedBodyShape } from "../../../src/core/pets/petBreed";
import { BODY_SHAPE_BREEDS, opaqueCount } from "./support";

// Port of PetCeilingTests.swift: a clip built with a ceiling (the closed
// island) draws nothing above it and changes nothing that already fits.

function top(clip: PetClip): number {
  const tops = clip.frames
    .flatMap((frame) => [frame.canvas, ...frame.itemFrames])
    .flatMap((canvas) => (canvas.opaqueBounds ? [canvas.opaqueBounds.minY] : []));
  return tops.length === 0 ? Number.MAX_SAFE_INTEGER : Math.min(...tops);
}

function clipKey(clip: PetClip): string {
  return JSON.stringify(
    clip.frames.map((frame) => [
      frame.duration,
      frame.bubbleAnchor ?? null,
      frame.canvas.symbols(),
      frame.itemFrames.map((canvas) => canvas.symbols()),
    ]),
  );
}

function setKey(set: PetClipSet): string {
  return PET_ANIMATIONS.map((animation) => clipKey(set.clip(animation))).join("|");
}

function lookOf(profile: PetProfile): PetLook {
  return { breed: profile.breed, outfit: profile.outfit, accessories: profile.accessories, bond: profile.bondLook };
}

describe("PetCeiling", () => {
  it("a frame that fits is untouched", () => {
    const full = composeClip("idle", "orangeTabby");
    expect(top(full)).toBeGreaterThanOrEqual(2);
    expect(clipKey(composeClip("idle", "orangeTabby", { ceiling: 2 }))).toBe(clipKey(full));
  });

  it("a tall hat hops lower under the ceiling", () => {
    const full = composeClip("celebrate", "corgi", { accessories: ["wizardHat"] });
    const fitted = composeClip("celebrate", "corgi", { accessories: ["wizardHat"], ceiling: 2 });
    expect(top(full), "the hat's tip leaves the top rows mid-hop").toBeLessThan(2);
    expect(top(fitted)).toBeGreaterThanOrEqual(2);
    // The pet still lands on the floor: only the airborne frames move.
    const [fittedFirst, fullFirst] = [fitted.frames[0], full.frames[0]];
    if (!fittedFirst || !fullFirst) expect.fail("frames");
    expect(fittedFirst.canvas.equals(fullFirst.canvas)).toBe(true);
    expect(fitted.frames.map((frame) => frame.duration)).toEqual(full.frames.map((frame) => frame.duration));
  });

  it("petals and sparkles drift in from above the ceiling", () => {
    for (const accessory of ["cherryPetals", "sparkleTrail"] as const) {
      const full = composeClip("idle", "orangeTabby", { accessories: [accessory] });
      const fitted = composeClip("idle", "orangeTabby", { accessories: [accessory], ceiling: 2 });
      expect(top(full), `${accessory} starts at the frame's top`).toBeLessThan(2);
      expect(top(fitted), accessory).toBeGreaterThanOrEqual(2);
      const shown = fitted.frames.flatMap((frame) => [frame.canvas, ...frame.itemFrames]).map(opaqueCount);
      const bareFrame = composeClip("idle", "orangeTabby").frames[0];
      if (!bareFrame) expect.fail("a frame");
      const bare = opaqueCount(bareFrame.canvas);
      expect(shown.some((n) => n > bare), `${accessory} still shows lower down`).toBe(true);
    }
  });

  it("the rain cloud moves down under the ceiling, so the notch shows the cloud itself", () => {
    const coat = pixelFor("coat");
    const cloud = (canvas: { pixels: Uint8Array }) => canvas.pixels.filter((pixel) => pixel === coat).length;
    for (const breed of BODY_SHAPE_BREEDS) {
      for (const animation of ["idle", "walk", "sleep"] as const) {
        /*
         * Where tall ears (the Sphynx, French Bulldog and Corgi sitting, the
         * French Bulldog's breaths asleep) or the dachshund's raised head lying
         * down reach the spot, the lowered cloud would touch the pet, so it is
         * left out there like any particle.
         */
        const shape = breedBodyShape(breed);
        const tallEars =
          (["sphynxCat", "batEaredDog", "pointyEaredDog"].includes(shape) && animation === "idle") ||
          (["longDog", "batEaredDog"].includes(shape) && animation === "sleep");
        const full = composeClip(animation, breed, { accessories: ["rainCloud"] });
        const fitted = composeClip(animation, breed, { accessories: ["rainCloud"], ceiling: 2 });
        expect(top(fitted), `${breed} ${animation}`).toBeGreaterThanOrEqual(2);
        fitted.frames.forEach((frame, index) => {
          const whole = full.frames[index];
          if (!whole) expect.fail("same frame count");
          const ticks = frame.itemFrames.length === 0 ? [frame.canvas] : frame.itemFrames;
          const wholeTicks = whole.itemFrames.length === 0 ? [whole.canvas] : whole.itemFrames;
          ticks.forEach((shown, tick) => {
            const art = wholeTicks[tick];
            if (!art) return;
            expect(cloud(art), `the Closet shows the cloud: ${breed} ${animation}`).toBeGreaterThanOrEqual(10);
            if (!tallEars) expect(cloud(shown), `the notch shows the cloud: ${breed} ${animation}`).toBeGreaterThanOrEqual(10);
          });
        });
      }
    }
  });

  it("the cache hands back the same clips per look and ceiling", () => {
    const profile = PetProfile.starter("dog");
    profile.rename("Biscuit");
    const fitted = cachedClipSet(lookOf(profile), 2);
    expect(setKey(fitted)).toBe(setKey(new PetClipSet(lookOf(profile), 2)));
    expect(cachedClipSet(lookOf(profile), 2)).toBe(fitted);
    expect(setKey(cachedClipSet(lookOf(profile))), "the ceiling is part of the key").toBe(setKey(new PetClipSet(lookOf(profile))));
    // A rename changes nothing drawn, so it reuses the clips.
    profile.rename("Waffles");
    expect(cachedClipSet(lookOf(profile), 2)).toBe(fitted);
  });
});
