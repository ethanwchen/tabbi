import { describe, expect, it } from "vitest";
import { colorHex } from "../../src/core/pets/petPalette";
import { BADGE_SIZE, badgeColors, type BadgeState } from "../../src/core/progression/badgeArt";
import type { ProgressTrack } from "../../src/core/progression/progressTrack";
import { loadFixture } from "../support/fixtures";

/*
 * Replays shared/fixtures/pets/badges.json (written by BadgeArtTests on
 * the Mac): every Goals badge at every state, resolved to colors by the
 * plain badge palette lookup, in the rendered.json encoding (the distinct
 * colors in order of first appearance and run-length rows of their
 * indices as letters). Only the inputs are read; colors and rows are
 * compared exactly, so both ports draw the same pixels.
 */

interface BadgeFixture {
  schema: string;
  version: number;
  size: number;
  badges: { track: ProgressTrack; state: BadgeState; twinkle: boolean; colors: string[]; rle: string }[];
}

const fixture = loadFixture<BadgeFixture>("pets/badges.json");
const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

function runLength(rows: readonly string[]): string {
  return rows
    .map((row) => {
      let out = "";
      let index = 0;
      while (index < row.length) {
        const symbol = row[index] ?? "";
        let count = 1;
        while (row[index + count] === symbol) count++;
        out += (count > 1 ? String(count) : "") + symbol;
        index += count;
      }
      return out;
    })
    .join("/");
}

describe("badge golden fixtures", () => {
  it("describe 28 pixel badges", () => {
    expect(fixture.schema).toBe("tabbi.pets.golden");
    expect(fixture.size).toBe(BADGE_SIZE);
    expect(fixture.badges).toHaveLength(12 * 6);
  });

  it("render every track at every state to the same colors, pixel for pixel", () => {
    for (const entry of fixture.badges) {
      const colors: string[] = [];
      const symbols = badgeColors(entry.track, entry.state, entry.twinkle).map((color) => {
        if (!color) return ".";
        const hex = colorHex(color);
        let index = colors.indexOf(hex);
        if (index < 0) index = colors.push(hex) - 1;
        return LETTERS[index] ?? "?";
      });
      const rows: string[] = [];
      for (let y = 0; y < BADGE_SIZE; y++) rows.push(symbols.slice(y * BADGE_SIZE, (y + 1) * BADGE_SIZE).join(""));
      const name = `${entry.track} ${entry.state}${entry.twinkle ? " twinkle" : ""}`;
      expect(colors, name).toEqual(entry.colors);
      expect(runLength(rows), name).toBe(entry.rle);
    }
  });
});
