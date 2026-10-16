import { describe, expect, it } from "vitest";
import { LoaderClock } from "../../../src/core/motion/loaderClock";
import { MarqueeMotion } from "../../../src/core/motion/marqueeMotion";
import { PawTrail } from "../../../src/core/motion/pawTrail";
import { RingProgress } from "../../../src/core/motion/ringProgress";

/* Port of LoaderClockTests. */
describe("LoaderClock", () => {
  it("turns the spinner once per period", () => {
    expect(LoaderClock.spinAngle(0)).toBeCloseTo(0, 9);
    expect(LoaderClock.spinAngle(0.25)).toBeCloseTo(90, 9);
    expect(LoaderClock.spinAngle(1.5)).toBeCloseTo(180, 9);
    expect(LoaderClock.spinAngle(1, 2)).toBeCloseTo(180, 9);
  });

  it("keeps the spin angle in one turn for any time", () => {
    for (let time = -3; time <= 3; time += 0.07) {
      const angle = LoaderClock.spinAngle(time);
      expect(angle).toBeGreaterThanOrEqual(0);
      expect(angle).toBeLessThan(360);
    }
    expect(LoaderClock.spinAngle(5, 0)).toBe(0);
  });

  it("breathes visibly and peaks on whole periods", () => {
    const period = LoaderClock.breathPeriod;
    expect(LoaderClock.breathingOpacity(0)).toBeCloseTo(1, 9);
    expect(LoaderClock.breathingOpacity(period)).toBeCloseTo(1, 9);
    expect(LoaderClock.breathingOpacity(period / 2)).toBeCloseTo(LoaderClock.breathFloor, 9);
    for (let step = 0; step <= 100; step++) {
      const opacity = LoaderClock.breathingOpacity((step * period) / 37);
      expect(opacity).toBeGreaterThanOrEqual(LoaderClock.breathFloor - 1e-9);
      expect(opacity).toBeLessThanOrEqual(1 + 1e-9);
    }
  });

  it("redraws no faster than 30 frames a second", () => {
    expect(LoaderClock.frameRate).toBeLessThanOrEqual(30);
  });

  it("sweeps the shimmer from off the leading edge to off the trailing edge", () => {
    const band = LoaderClock.shimmerBand;
    const period = LoaderClock.shimmerPeriod;
    expect(LoaderClock.shimmerOffset(0)).toBeCloseTo(-band, 9);
    expect(LoaderClock.shimmerOffset(period / 2)).toBeCloseTo((1 - band) / 2, 9);
    expect(Math.abs(LoaderClock.shimmerOffset(period * 0.999999) - 1)).toBeLessThanOrEqual(1e-4);
    expect(LoaderClock.shimmerOffset(6, 2)).toBeCloseTo(-band, 9);
  });

  it("moves the shimmer forward and eases at both ends", () => {
    const period = LoaderClock.shimmerPeriod;
    let previous = -Infinity;
    for (let step = 0; step < 100; step++) {
      const offset = LoaderClock.shimmerOffset((step * period) / 100);
      expect(offset).toBeGreaterThanOrEqual(previous);
      previous = offset;
    }
    const start = LoaderClock.shimmerOffset(period * 0.05) - LoaderClock.shimmerOffset(0);
    const middle = LoaderClock.shimmerOffset(period * 0.525) - LoaderClock.shimmerOffset(period * 0.475);
    expect(start).toBeLessThan(middle);
    expect(LoaderClock.shimmerOffset(1, 0)).toBe(-LoaderClock.shimmerBand);
  });
});

/* Port of MarqueeMotionTests. */
describe("MarqueeMotion", () => {
  it("does not overflow text that fits", () => {
    expect(MarqueeMotion.overflow(120, 148)).toBe(0);
    expect(MarqueeMotion.overflow(148, 148)).toBe(0);
    expect(MarqueeMotion.overflow(148.4, 148)).toBe(0);
  });

  it("overflows wider text by the difference", () => {
    expect(MarqueeMotion.overflow(200, 148)).toBe(52);
  });

  it("never overflows unmeasured widths", () => {
    expect(MarqueeMotion.overflow(200, 0)).toBe(0);
    expect(MarqueeMotion.overflow(Number.NaN, 148)).toBe(0);
    expect(MarqueeMotion.overflow(Infinity, 148)).toBe(0);
  });

  it("scrolls only overflowing visible text when motion is allowed", () => {
    expect(MarqueeMotion.scrolls(10, false, true)).toBe(true);
    expect(MarqueeMotion.scrolls(0, false, true)).toBe(false);
    expect(MarqueeMotion.scrolls(10, true, true)).toBe(false);
    expect(MarqueeMotion.scrolls(10, false, false)).toBe(false);
  });

  it("rests text that fits at its start", () => {
    expect(MarqueeMotion.pose(3, 0)).toEqual(MarqueeMotion.rest);
    expect(MarqueeMotion.pose(-1, 40)).toEqual(MarqueeMotion.rest);
    expect(MarqueeMotion.pose(Number.NaN, 40)).toEqual(MarqueeMotion.rest);
  });

  it("rests, scrolls, rests and fades back each cycle", () => {
    const overflow = 60;
    const travel = MarqueeMotion.travel(overflow);
    expect(travel).toBeCloseTo(2, 4);
    expect(MarqueeMotion.pose(MarqueeMotion.startPause * 0.9, overflow)).toEqual(MarqueeMotion.rest);
    const middle = MarqueeMotion.pose(MarqueeMotion.startPause + travel / 2, overflow);
    expect(middle.offset).toBeCloseTo(overflow / 2, 4);
    expect(middle.opacity).toBe(1);
    const end = MarqueeMotion.pose(MarqueeMotion.startPause + travel + MarqueeMotion.endPause / 2, overflow);
    expect(end).toEqual({ offset: overflow, opacity: 1 });
    const fadeStart = MarqueeMotion.startPause + travel + MarqueeMotion.endPause;
    const fadingOut = MarqueeMotion.pose(fadeStart + MarqueeMotion.fade / 2, overflow);
    expect(fadingOut.offset).toBe(overflow);
    expect(fadingOut.opacity).toBeCloseTo(0.5, 4);
    const fadingIn = MarqueeMotion.pose(fadeStart + MarqueeMotion.fade * 1.5, overflow);
    expect(fadingIn.offset).toBe(0);
    expect(fadingIn.opacity).toBeCloseTo(0.5, 4);
    const cycle = MarqueeMotion.cycle(overflow);
    expect(cycle).toBeCloseTo(fadeStart + 2 * MarqueeMotion.fade, 4);
    expect(MarqueeMotion.pose(cycle + 0.1, overflow)).toEqual(MarqueeMotion.rest);
  });

  it("never leaves its range and moves gently", () => {
    const overflow = 90;
    let previous = 0;
    const frames = Math.trunc(MarqueeMotion.cycle(overflow) * 60);
    for (let frame = 0; frame < frames; frame++) {
      const pose = MarqueeMotion.pose(frame / 60, overflow);
      expect(pose.offset).toBeGreaterThanOrEqual(0);
      expect(pose.offset).toBeLessThanOrEqual(overflow);
      expect(pose.opacity).toBeGreaterThanOrEqual(0);
      expect(pose.opacity).toBeLessThanOrEqual(1);
      if (pose.opacity > 0.01 && pose.offset > 0) {
        expect(Math.abs(pose.offset - previous)).toBeLessThan(2);
      }
      previous = pose.offset;
    }
  });

  it("glides a short overflow", () => {
    expect(MarqueeMotion.travel(3)).toBe(MarqueeMotion.minimumTravel);
  });

  it("draws a still pose as a fraction of the scroll", () => {
    expect(MarqueeMotion.poseScrolled(0.5, 40)).toEqual({ offset: 20, opacity: 1 });
    expect(MarqueeMotion.poseScrolled(2, 40).offset).toBe(40);
    expect(MarqueeMotion.poseScrolled(-1, 40).offset).toBe(0);
    expect(MarqueeMotion.poseScrolled(0.5, 0)).toEqual(MarqueeMotion.rest);
  });
});

/* Port of PawTrailTests. */
describe("PawTrail", () => {
  it("lays prints one after another along the trail", () => {
    const time = 2 * PawTrail.stepInterval + PawTrail.pressDuration;
    expect(PawTrail.opacity(0, time)).toBeGreaterThan(0);
    expect(PawTrail.opacity(1, time)).toBeGreaterThan(0);
    expect(PawTrail.opacity(2, time)).toBeCloseTo(1, 9);
    expect(PawTrail.opacity(3, time)).toBe(0);
    expect(PawTrail.opacity(0, time)).toBeLessThan(PawTrail.opacity(1, time));
  });

  it("fades every print before the next walk starts", () => {
    const end = PawTrail.cycle - 0.001;
    for (let step = 0; step < PawTrail.stepCount; step++) {
      expect(PawTrail.opacity(step, end)).toBeCloseTo(0, 9);
    }
    expect(PawTrail.opacity(1, PawTrail.cycle * 2 + 0.5)).toBeCloseTo(PawTrail.opacity(1, 0.5), 9);
  });

  it("keeps opacity and scale in range at any time", () => {
    for (let time = -2; time <= 4; time += 0.013) {
      for (let step = -1; step <= PawTrail.stepCount; step++) {
        const opacity = PawTrail.opacity(step, time);
        expect(opacity).toBeGreaterThanOrEqual(0);
        expect(opacity).toBeLessThanOrEqual(1);
        const scale = PawTrail.scale(step, time);
        expect(scale).toBeGreaterThanOrEqual(1);
        expect(scale).toBeLessThanOrEqual(1.15 + 1e-9);
      }
    }
    expect(PawTrail.opacity(PawTrail.stepCount, 0.5)).toBe(0);
  });

  it("lands a print large and settles", () => {
    const landing = PawTrail.stepInterval;
    expect(PawTrail.scale(1, landing + 0.01)).toBeGreaterThan(1.1);
    expect(PawTrail.scale(1, landing + PawTrail.pressDuration)).toBeCloseTo(1, 9);
  });

  it("zigzags", () => {
    expect(PawTrail.isLeftFoot(0)).toBe(true);
    expect(PawTrail.isLeftFoot(1)).toBe(false);
    expect(PawTrail.isLeftFoot(2)).toBe(true);
  });

  it("never shows the loader for a fast wait", () => {
    expect(PawTrail.revealOpacity(0)).toBe(0);
    expect(PawTrail.revealOpacity(0.29)).toBe(0);
    expect(PawTrail.revealOpacity(PawTrail.revealDelay + PawTrail.revealDuration / 2)).toBeCloseTo(0.5, 9);
    expect(PawTrail.revealOpacity(2)).toBe(1);
    expect(PawTrail.revealOpacity(0, 0)).toBe(0);
    expect(PawTrail.revealOpacity(1, 0)).toBe(1);
  });
});

/* Port of RingProgressTests. */
describe("RingProgress", () => {
  it("clamps values outside the ring", () => {
    expect(RingProgress.clamped(-0.2)).toBe(0);
    expect(RingProgress.clamped(0.4)).toBe(0.4);
    expect(RingProgress.clamped(1.3)).toBe(1);
  });

  it("draws an empty ring for missing or non-finite values", () => {
    expect(RingProgress.clamped(undefined)).toBe(0);
    expect(RingProgress.clamped(Number.NaN)).toBe(0);
    expect(RingProgress.clamped(Infinity)).toBe(0);
  });

  it("fills as work advances", () => {
    expect(RingProgress.change(0.2, 0.25)).toBe("advance");
    expect(RingProgress.change(undefined, 0.1)).toBe("advance");
  });

  it("unwinds a small drop and restarts on a big one", () => {
    expect(RingProgress.change(0.3, 0)).toBe("unwind");
    expect(RingProgress.change(0.9, 0.6)).toBe("unwind");
    expect(RingProgress.change(1, 0)).toBe("restart");
    expect(RingProgress.change(0.86, 0.02)).toBe("restart");
  });

  it("steps a tick too small to see without a glide", () => {
    for (const tick of [1 / 1500, 1 / 300]) {
      expect(RingProgress.change(0.4, 0.4 + tick)).toBe("step");
      expect(RingProgress.change(0.4, 0.4 - tick)).toBe("step");
    }
    expect(RingProgress.change(0.4, 0.41)).toBe("advance");
  });

  it("does nothing for changes that clamp to the same value", () => {
    expect(RingProgress.change(1, 1.4)).toBe("none");
    expect(RingProgress.change(undefined, 0)).toBe("none");
    expect(RingProgress.change(-1, Number.NaN)).toBe("none");
  });
});
