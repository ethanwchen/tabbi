import { describe, expect, it } from "vitest";
import { MotionTokens } from "../../../src/core/motion/motionTokens";
import { SpringSpec } from "../../../src/core/motion/springSpec";
import {
  FAST_SCALE,
  MOTION_PACES,
  adjustedSpring,
  isAnimated,
  motionPaceCaption,
  motionPaceTitle,
  pacedDuration,
} from "../../../src/core/motion/motionPace";

/* Port of MotionTokensTests. */
describe("MotionTokens", () => {
  it("converts a spring with Apple's formula", () => {
    const spring = new SpringSpec(0.5, 0.2);
    expect(spring.stiffness).toBeCloseTo(157.9, 1);
    expect(spring.damping).toBeCloseTo(20.1, 1);
    expect(spring.dampingRatio).toBeCloseTo(0.8, 3);
  });

  it("is critically damped at a bounce of zero and never overshoots", () => {
    const spring = new SpringSpec(0.4, 0);
    expect(spring.overshoots).toBe(false);
    expect(spring.peak).toBe(1);
    for (let step = 0; step <= 400; step++) {
      expect(spring.value(step / 200)).toBeLessThanOrEqual(1 + 1e-9);
    }
  });

  it("still arrives when overdamped", () => {
    const spring = new SpringSpec(0.3, -0.5);
    expect(spring.overshoots).toBe(false);
    expect(Math.abs(spring.value(3) - 1)).toBeLessThanOrEqual(0.001);
  });

  it("closes without overshoot", () => {
    expect(MotionTokens.close.overshoots).toBe(false);
  });

  it("opens with only a small stretch", () => {
    expect(MotionTokens.open.overshoots).toBe(true);
    expect(MotionTokens.open.peak).toBeLessThan(1.06);
  });

  it("looks done opening and closing within about 350 ms", () => {
    expect(MotionTokens.open.settlingTime(0.05)).toBeLessThanOrEqual(0.4);
    expect(MotionTokens.close.settlingTime(0.05)).toBeLessThanOrEqual(0.35);
  });

  it("closes faster than it opens", () => {
    expect(MotionTokens.close.duration).toBeLessThan(MotionTokens.open.duration);
  });

  it("lands hover feedback within its budget", () => {
    const settle = MotionTokens.hover.settlingTime(0.05);
    expect(settle).toBeGreaterThanOrEqual(0.15);
    expect(settle).toBeLessThanOrEqual(0.3);
  });

  it("trails the shape by 60 to 100 ms", () => {
    expect(MotionTokens.contentDelay).toBeGreaterThanOrEqual(0.06);
    expect(MotionTokens.contentDelay).toBeLessThanOrEqual(0.1);
    expect(MotionTokens.contentFadeOut).toBeLessThan(MotionTokens.close.duration);
  });

  it("grows the stagger per item and caps it", () => {
    expect(MotionTokens.stagger(0)).toBe(0);
    expect(MotionTokens.stagger(2)).toBeCloseTo(2 * MotionTokens.staggerStep, 9);
    expect(MotionTokens.stagger(100)).toBe(MotionTokens.staggerCap);
    expect(MotionTokens.stagger(-3)).toBe(0);
  });

  it("clamps its inputs", () => {
    expect(new SpringSpec(0.3, 4).bounce).toBe(1);
    expect(new SpringSpec(0).duration).toBeGreaterThan(0);
  });
});

/* Port of MotionPaceTests (the gentle theme case lives with the themes port). */
describe("MotionPace", () => {
  const all = [
    MotionTokens.open,
    MotionTokens.close,
    MotionTokens.hover,
    MotionTokens.snappy,
    MotionTokens.content,
    MotionTokens.press,
    MotionTokens.check,
  ];

  it("plays the tokens as designed when smooth", () => {
    expect(adjustedSpring("smooth", MotionTokens.open)).toEqual(MotionTokens.open);
    expect(adjustedSpring("smooth", MotionTokens.open)?.overshoots).toBe(true);
    expect(pacedDuration("smooth", MotionTokens.contentFadeIn)).toBe(MotionTokens.contentFadeIn);
  });

  it("is quicker and never overshoots when fast", () => {
    for (const spec of all) {
      const fast = adjustedSpring("fast", spec);
      if (!fast) throw new Error("fast should animate");
      expect(fast.duration).toBeLessThan(spec.duration);
      expect(fast.overshoots).toBe(false);
      expect(fast.settlingTime()).toBeLessThan(spec.settlingTime());
      expect(fast.duration).toBeCloseTo(spec.duration * FAST_SCALE, 9);
    }
    expect(pacedDuration("fast", 0.2)).toBeLessThan(0.2);
  });

  it("does not animate when instant", () => {
    expect(adjustedSpring("instant", MotionTokens.open)).toBeUndefined();
    expect(pacedDuration("instant", MotionTokens.contentDelay)).toBe(0);
    expect(isAnimated("instant", false)).toBe(false);
  });

  it("stops movement under Reduce Motion at every pace", () => {
    for (const pace of MOTION_PACES) expect(isAnimated(pace, true)).toBe(false);
    expect(isAnimated("smooth", false)).toBe(true);
    expect(isAnimated("fast", false)).toBe(true);
  });

  it("names each pace with its catalog key", () => {
    expect(MOTION_PACES.map(motionPaceTitle)).toEqual(["Smooth", "Fast", "Instant"]);
    expect(motionPaceCaption("fast")).toBe("Quick and crisp, with no bounce.");
  });
});
