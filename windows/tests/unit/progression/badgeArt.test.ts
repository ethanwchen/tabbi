import { describe, expect, it } from "vitest";
import { petArt } from "../../../src/core/pets/petArt";
import { contrastRatio, luminance, type PetPaletteRole } from "../../../src/core/pets/petPalette";
import {
  BADGE_SIZE,
  BADGE_STATES,
  badgeBitmap,
  badgeCanvas,
  badgeColors,
  badgeGlyphOrigin,
  badgeScale,
  badgeState,
  badgeStateColors,
  type BadgeState,
} from "../../../src/core/progression/badgeArt";
import { PROGRESS_TRACKS } from "../../../src/core/progression/progressTrack";

/* Port of BadgeArtTests: the Goals badges are sprites composed from the Mac's badge.json. */

function count(state: BadgeState, role: PetPaletteRole): number {
  const canvas = badgeCanvas("water", state);
  let total = 0;
  for (let y = 0; y < canvas.height; y++) for (let x = 0; x < canvas.width; x++) if (canvas.role(x, y) === role) total++;
  return total;
}

describe("BadgeArt", () => {
  it("loads the badge art file", () => {
    expect(petArt("badge").grid("frameBronze").width).toBe(BADGE_SIZE);
    expect(petArt("badge").grid("glyphWater").width).toBe(9);
  });

  it("composes every badge as a whole sprite with its glyph inside", () => {
    for (const track of PROGRESS_TRACKS) {
      for (const state of BADGE_STATES) {
        const canvas = badgeCanvas(track, state);
        const label = `${track} ${state}`;
        expect(canvas.width, label).toBe(BADGE_SIZE);
        expect(canvas.height, label).toBe(BADGE_SIZE);
        let glyph = 0;
        const origin = badgeGlyphOrigin(state);
        for (let y = origin.y; y < origin.y + 9; y++) {
          for (let x = origin.x; x < origin.x + 9; x++) {
            if (canvas.role(x, y) !== "belly") continue;
            glyph++;
            const neighbors: [number, number][] = [
              [1, 0],
              [-1, 0],
              [0, 1],
              [0, -1],
            ];
            for (const [dx, dy] of neighbors) {
              expect(canvas.role(x + dx, y + dy), `glyph touches air: ${label} at ${x},${y}`).toBeDefined();
            }
          }
        }
        expect(glyph, `the glyph shows: ${label}`).toBeGreaterThan(8);
        const colors = badgeColors(track, state);
        expect(colors, label).toHaveLength(BADGE_SIZE * BADGE_SIZE);
        const glyphColor = badgeStateColors(state).glyph;
        expect(colors.some((color) => color !== undefined && color.red === glyphColor.red && color.green === glyphColor.green && color.blue === glyphColor.blue), label).toBe(true);
      }
    }
  });

  it("adds each tier's own shapes", () => {
    /* The reference draws the two pixel highlight on every medal, dim on the quiet coin. */
    expect(count("notYet", "eyeLight"), "the coin's dim highlight").toBe(2);
    expect(count("bronze", "eyeLight"), "the medal's two pixel highlight").toBe(2);
    expect(count("silver", "costumeShade"), "the rosette and a ribbon tail").toBeGreaterThan(count("bronze", "costumeShade"));
    expect(count("gold", "leaf") + count("gold", "furShade"), "the laurel").toBeGreaterThan(20);
    expect(count("bronze", "leaf")).toBe(0);
    expect(count("starlight", "effect"), "a sparkle and a dot").toBeGreaterThan(4);
    expect(badgeCanvas("water", "starlight").symbols()).not.toBe(badgeCanvas("water", "starlight", true).symbols());
    expect(badgeCanvas("water", "gold", true).symbols()).toBe(badgeCanvas("water", "gold").symbols());
    expect(badgeState(undefined)).toBe("notYet");
    expect(badgeState("gold")).toBe("gold");
  });

  it("keeps the glyph readable on every disc", () => {
    for (const state of BADGE_STATES) {
      const colors = badgeStateColors(state);
      const contrast = contrastRatio(luminance(colors.glyph), luminance(colors.inner));
      expect(contrast, `${state} glyph on its disc`).toBeGreaterThanOrEqual(state === "notYet" ? 1.8 : 3.9);
    }
  });

  it("scales to whole pixels and renders exact blocks", () => {
    expect(badgeScale(1.5, 2)).toBe(3);
    expect(badgeScale(2, 2)).toBe(4);
    expect(badgeScale(1.5, 1), "no fractional scale on a 1x display").toBe(1);
    expect(badgeScale(2, 1)).toBe(2);
    expect(badgeScale(1.5, 1.5)).toBe(2);
    const bitmap = badgeBitmap("focusHours", "gold", false, 3);
    expect(bitmap.width).toBe(84);
    expect(bitmap.data).toHaveLength(84 * 84 * 4);
    expect(badgeBitmap("focusHours", "gold", false, 3)).toBe(bitmap);
  });
});
