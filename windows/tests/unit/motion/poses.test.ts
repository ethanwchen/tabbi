import { describe, expect, it } from "vitest";
import { CheckDrawTiming, checkDraw } from "../../../src/core/motion/checkDraw";
import { MotionTokens } from "../../../src/core/motion/motionTokens";
import { TactileFeedback } from "../../../src/core/motion/tactileFeedback";
import { TransitionPose } from "../../../src/core/motion/transitionPose";

/* Port of TransitionPoseTests. */
describe("TransitionPose", () => {
  const presets = [
    TransitionPose.pop,
    TransitionPose.swap,
    TransitionPose.row("top"),
    TransitionPose.row("bottom"),
    TransitionPose.row("leading"),
    TransitionPose.row("trailing"),
  ];

  it("is neutral once inserted", () => {
    for (const pose of presets) {
      for (const reduce of [false, true]) {
        expect(pose.resolved(true, reduce)).toEqual({ scale: 1, offsetX: 0, offsetY: 0, opacity: 1 });
      }
    }
  });

  it("only fades under Reduce Motion", () => {
    for (const pose of presets) {
      expect(pose.resolved(false, true)).toEqual({ scale: 1, offsetX: 0, offsetY: 0, opacity: 0 });
    }
  });

  it("fades and moves a little while outside", () => {
    for (const pose of presets) {
      const resolved = pose.resolved(false, false);
      expect(resolved.opacity).toBe(0);
      expect(resolved.scale).toBeGreaterThanOrEqual(0.8);
      expect(resolved.scale).toBeLessThanOrEqual(1);
      expect(Math.abs(resolved.offsetX)).toBeLessThanOrEqual(8);
      expect(Math.abs(resolved.offsetY)).toBeLessThanOrEqual(8);
    }
  });

  it("brings rows from their edge", () => {
    expect(TransitionPose.row("top").offsetY).toBeLessThan(0);
    expect(TransitionPose.row("bottom").offsetY).toBeGreaterThan(0);
    expect(TransitionPose.row("leading").offsetX).toBeLessThan(0);
    expect(TransitionPose.row("trailing").offsetX).toBeGreaterThan(0);
    expect(TransitionPose.row("top").scale).toBe(1);
  });

  it("grows a swap from the top", () => {
    expect(TransitionPose.swap.anchorY).toBe(0);
    expect(TransitionPose.swap.scale).toBeLessThan(1);
  });
});

/* Port of CheckDrawTests. */
describe("CheckDraw", () => {
  it("shows only the ring when off", () => {
    expect(checkDraw(0)).toMatchObject({ ringOpacity: 1, fillOpacity: 0, checkTrim: 0, checkOpacity: 0 });
  });

  it("is a full fill with the whole check when on", () => {
    const on = checkDraw(1);
    expect(on.ringOpacity).toBe(0);
    expect(on.fillOpacity).toBe(1);
    expect(on.fillScale).toBeCloseTo(1, 9);
    expect(on.checkTrim).toBeCloseTo(1, 9);
    expect(on.checkOpacity).toBe(1);
  });

  it("draws the check on after the fill starts", () => {
    const { checkStart, fillEnd } = CheckDrawTiming;
    expect(checkDraw(checkStart).checkTrim).toBe(0);
    const overlap = checkDraw((checkStart + fillEnd) / 2);
    expect(overlap.checkTrim).toBeGreaterThan(0);
    expect(overlap.fillScale).toBeLessThan(1);
    expect(checkDraw(fillEnd).fillScale).toBeCloseTo(1, 9);
    expect(checkDraw(fillEnd).checkTrim).toBeLessThan(1);
  });

  it("draws monotonically", () => {
    let previous = checkDraw(0);
    for (let step = 1; step <= 100; step++) {
      const next = checkDraw(step / 100);
      expect(next.fillScale).toBeGreaterThanOrEqual(previous.fillScale);
      expect(next.checkTrim).toBeGreaterThanOrEqual(previous.checkTrim);
      expect(next.fillOpacity).toBeGreaterThanOrEqual(previous.fillOpacity);
      expect(next.ringOpacity).toBeLessThanOrEqual(previous.ringOpacity);
      previous = next;
    }
  });

  it("swells the fill within the cap on overshoot", () => {
    const spring = MotionTokens.check;
    expect(spring.overshoots).toBe(true);
    const atPeak = checkDraw(spring.peak);
    expect(atPeak.fillScale).toBeGreaterThan(1);
    expect(atPeak.fillScale).toBeLessThanOrEqual(CheckDrawTiming.maxSwell);
    expect(atPeak.checkTrim).toBe(1);
    expect(checkDraw(5).fillScale).toBe(CheckDrawTiming.maxSwell);
  });

  it("looks off on undershoot and bad values", () => {
    for (const progress of [-0.2, Number.NaN, -Infinity]) {
      expect(checkDraw(progress)).toEqual(checkDraw(0));
    }
  });

  it("uses a quick check spring", () => {
    expect(MotionTokens.check.settlingTime()).toBeLessThan(0.5);
    expect(MotionTokens.check.peak).toBeLessThan(1.15);
  });

  it("crossfades the finished check under Reduce Motion", () => {
    for (const progress of [0, 0.3, 0.7, 1, 1.1]) {
      const state = checkDraw(progress, true);
      expect(state.fillScale).toBe(1);
      expect(state.checkTrim).toBe(1);
      expect(state.fillOpacity).toBeCloseTo(Math.min(progress, 1), 9);
      expect(state.ringOpacity + state.fillOpacity).toBeCloseTo(1, 9);
    }
  });
});

/* Port of TactileFeedbackTests. */
describe("TactileFeedback", () => {
  it("lets pressing win over hovering", () => {
    const feedback = TactileFeedback.control;
    expect(feedback.scale(true, true, true, false)).toBe(feedback.pressedScale);
    expect(feedback.scale(false, true, true, false)).toBe(feedback.hoverScale);
    expect(feedback.scale(false, false, true, false)).toBe(1);
  });

  it("grows only lifting controls on hover", () => {
    expect(TactileFeedback.pill.scale(false, true, false, false)).toBe(1);
    expect(TactileFeedback.pill.scale(true, true, false, false)).toBeLessThan(1);
  });

  it("dims instead of scaling under Reduce Motion", () => {
    for (const feedback of [TactileFeedback.control, TactileFeedback.pill]) {
      for (const pressed of [false, true]) {
        for (const hovering of [false, true]) {
          expect(feedback.scale(pressed, hovering, true, true)).toBe(1);
        }
      }
      expect(feedback.opacity(true, true)).toBeLessThan(1);
      expect(feedback.opacity(false, true)).toBe(1);
      expect(feedback.opacity(true, false)).toBe(1);
    }
  });

  it("moves edges by a few pixels on press", () => {
    const playButton = 36 * (1 - TactileFeedback.control.pressedScale);
    const pill = 140 * (1 - TactileFeedback.pill.pressedScale);
    expect(playButton > 1 && playButton <= 4).toBe(true);
    expect(pill > 1 && pill <= 4.5).toBe(true);
    expect(TactileFeedback.pill.pressedScale).toBeGreaterThan(TactileFeedback.control.pressedScale);
  });

  it("keeps lifts subtle", () => {
    for (const feedback of [TactileFeedback.control, TactileFeedback.pill]) {
      expect(feedback.hoverScale > 1 && feedback.hoverScale <= 1.06).toBe(true);
    }
  });
});
