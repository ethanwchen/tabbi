import { describe, expect, it } from "vitest";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { BUBBLE_HEIGHT, BUBBLE_WIDTH, petLayout } from "../../../src/ui/kit/PetView";
import { PetPlayer } from "../../../src/ui/kit/petPlayer";

describe("petLayout (PetView)", () => {
  it("draws a 32 px pet at one device pixel per sprite pixel on a 100 percent display", () => {
    const layout = petLayout(1, 1);
    expect(layout).toMatchObject({ scale: 1, boxSize: 32, cssWidth: 32, cssHeight: 32, offsetX: 0, offsetY: 0, deviceWidth: 32 });
  });

  it("keeps whole device pixels on 125, 150 and 200 percent displays, bottom aligned and centered", () => {
    for (const ratio of [1.25, 1.5, 1.75, 2, 2.5]) {
      const layout = petLayout(1, ratio);
      expect(Number.isInteger(layout.scale)).toBe(true);
      expect(layout.scale).toBeGreaterThanOrEqual(1);
      expect(layout.cssWidth).toBeLessThanOrEqual(32 + 1e-9);
      expect(layout.offsetY).toBeCloseTo(32 - layout.cssHeight, 9);
      expect(layout.offsetX).toBeCloseTo((32 - layout.cssWidth) / 2, 9);
    }
    expect(petLayout(1, 2).scale).toBe(2);
    expect(petLayout(2, 1.5).scale).toBe(3);
  });

  it("draws a box too small for one device pixel per sprite pixel scaled down, never nothing", () => {
    const layout = petLayout(0.75, 1);
    expect(layout.scale).toBe(1);
    expect(layout.deviceWidth).toBe(32);
    expect(layout.cssWidth).toBe(24);
    expect(layout.boxSize).toBe(24);
  });

  it("has a 9 x 9 speech bubble", () => {
    expect(BUBBLE_WIDTH).toBe(9);
    expect(BUBBLE_HEIGHT).toBe(9);
  });
});

describe("PetPlayer", () => {
  it("plays the idle clip beside the notch and wakes only when the picture changes", () => {
    const player = new PetPlayer(PetProfile.starter("cat"), { at: 100, seed: 3 });
    const frame = player.frame(100);
    expect(frame?.canvas.width).toBe(32);
    const next = player.nextChange(100);
    expect(next).toBeDefined();
    expect(next ?? 0).toBeGreaterThan(100);
    // A sleeping pet draws the sleep clip; a hidden one draws nothing.
    expect(player.send({ kind: "sleep" }, 101)).toBe(true);
    expect(player.frame(101.5)).toBeDefined();
    expect(player.revision).toBe(1);
    player.send({ kind: "disappear" }, 102);
    expect(player.frame(103)).toBeUndefined();
    expect(player.nextChange(103)).toBeUndefined();
  });

  it("holds still under Reduce Motion until a one-shot clip ends", () => {
    const player = new PetPlayer(PetProfile.starter("dog"), { at: 0, seed: 1 });
    expect(player.nextChange(0, true)).toBeUndefined();
    player.send({ kind: "celebrate" }, 1);
    const end = player.nextChange(1, true);
    expect(end).toBeDefined();
    expect(end ?? 0).toBeGreaterThan(1);
  });

  it("swaps in a new look without moving the pet", () => {
    const player = new PetPlayer(PetProfile.starter("cat"), { at: 0, seed: 1 });
    const dressed = PetProfile.starter("cat");
    dressed.outfit = "cozyHoodie";
    player.update(dressed, 5);
    expect(player.profile.outfit).toBe("cozyHoodie");
    expect(player.revision).toBe(1);
    player.update(dressed, 6);
    expect(player.revision).toBe(1);
  });
});
