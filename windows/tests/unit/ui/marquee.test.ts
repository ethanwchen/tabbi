import { describe, expect, it } from "vitest";
import { MarqueeMotion } from "../../../src/core/motion/marqueeMotion";
import { marqueeMask } from "../../../src/ui/kit/MarqueeText";

/*
 * The marquee's timing is the core's MarqueeMotion; these pin what the
 * component builds on it: the cycle a line plays, where it rests, and the
 * edge fades it draws in each reading direction.
 */
describe("marquee timing (MarqueeText)", () => {
  const overflow = 90;

  it("rests 2 s, scrolls at 30 px/s, rests 1.6 s, then fades out and in", () => {
    expect(MarqueeMotion.travel(overflow)).toBe(3);
    expect(MarqueeMotion.cycle(overflow)).toBeCloseTo(2 + 3 + 1.6 + 0.6, 9);
    expect(MarqueeMotion.pose(1.9, overflow)).toEqual({ offset: 0, opacity: 1 });
    expect(MarqueeMotion.pose(3.5, overflow).offset).toBeCloseTo(45, 9);
    expect(MarqueeMotion.pose(5.5, overflow)).toEqual({ offset: overflow, opacity: 1 });
    expect(MarqueeMotion.pose(6.75, overflow).opacity).toBeCloseTo(0.5, 9);
    const back = MarqueeMotion.pose(7.05, overflow);
    expect(back.offset).toBe(0);
    expect(back.opacity).toBeCloseTo(0.5, 9);
  });

  it("never scrolls a line that fits, under Reduce Motion, or off screen", () => {
    expect(MarqueeMotion.overflow(200, 220)).toBe(0);
    expect(MarqueeMotion.scrolls(MarqueeMotion.overflow(300, 220), false)).toBe(true);
    expect(MarqueeMotion.scrolls(80, true)).toBe(false);
    expect(MarqueeMotion.scrolls(80, false, false)).toBe(false);
  });

  it("draws a still render part way through the scroll", () => {
    expect(MarqueeMotion.poseScrolled(0.5, overflow)).toEqual({ offset: 45, opacity: 1 });
    expect(MarqueeMotion.poseScrolled(1, overflow)).toEqual({ offset: 90, opacity: 1 });
  });

  it("fades the cut edges toward the reading end", () => {
    expect(marqueeMask(0, 0.1, "ltr")).toBe("linear-gradient(to right, transparent 0%, black 0%, black 90%, transparent 100%)");
    expect(marqueeMask(0.05, 0, "rtl")).toBe("linear-gradient(to left, transparent 0%, black 5%, black 100%, transparent 100%)");
  });
});
