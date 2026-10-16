import { describe, expect, it } from "vitest";
import { HangDetector } from "../../../src/core/feedback/hangDetector";

/* Port of HangDetectorTests. */
describe("HangDetector", () => {
  it("never makes a hang from answered pings", () => {
    const detector = new HangDetector(3);
    for (let i = 0; i < 10; i++) expect(detector.tick(true)).toBeUndefined();
    expect(detector.isHanging).toBe(false);
  });

  it("begins once after enough missed ticks and ends on the next answer", () => {
    const detector = new HangDetector(3);
    expect(detector.tick(false)).toBeUndefined();
    expect(detector.tick(false)).toBeUndefined();
    expect(detector.tick(false)).toBe("began");
    expect(detector.tick(false)).toBeUndefined();
    expect(detector.isHanging).toBe(true);
    expect(detector.tick(true)).toBe("ended");
    expect(detector.tick(true)).toBeUndefined();
    expect(detector.isHanging).toBe(false);
  });

  it("resets the count on an answer", () => {
    const detector = new HangDetector(3);
    detector.tick(false);
    detector.tick(false);
    expect(detector.tick(true)).toBeUndefined();
    expect(detector.tick(false)).toBeUndefined();
    expect(detector.tick(false)).toBeUndefined();
    expect(detector.tick(false)).toBe("began");
  });

  it("needs at least one missed tick", () => {
    const detector = new HangDetector(0);
    expect(detector.ticksToHang).toBe(1);
    expect(detector.tick(true)).toBeUndefined();
    expect(detector.tick(false)).toBe("began");
  });
});
