import { describe, expect, it, vi } from "vitest";
import { afterFirstPaint, FIRST_PAINT_TIMEOUT_MS, type FrameClock } from "../../../src/ui/shell/firstPaint";

/* A clock the test steps by hand: frames run only when `frame()` is called. */
function manualClock() {
  let next = 1;
  const frames = new Map<number, () => void>();
  const timers = new Map<number, { callback: () => void; ms: number }>();
  const clock: FrameClock = {
    requestAnimationFrame(callback) {
      frames.set(next, callback);
      return next++;
    },
    cancelAnimationFrame: (handle) => void frames.delete(handle),
    setTimeout(callback, ms) {
      timers.set(next, { callback, ms });
      return next++;
    },
    clearTimeout: (handle) => void timers.delete(handle),
  };
  return {
    clock,
    frame() {
      const due = [...frames.values()];
      frames.clear();
      for (const callback of due) callback();
    },
    timeout() {
      const due = [...timers.values()];
      timers.clear();
      for (const { callback } of due) callback();
    },
    pending: () => ({ frames: frames.size, timers: [...timers.values()].map((t) => t.ms) }),
  };
}

describe("afterFirstPaint", () => {
  it("calls back after the frame that follows the first paint", () => {
    const steps = manualClock();
    const callback = vi.fn();
    afterFirstPaint(callback, steps.clock);
    steps.frame();
    expect(callback).not.toHaveBeenCalled();
    steps.frame();
    expect(callback).toHaveBeenCalledTimes(1);
    expect(steps.pending()).toEqual({ frames: 0, timers: [] });
  });

  it("calls back on the timeout when frames never run, and only once", () => {
    const steps = manualClock();
    const callback = vi.fn();
    afterFirstPaint(callback, steps.clock);
    expect(steps.pending().timers).toEqual([FIRST_PAINT_TIMEOUT_MS]);
    steps.timeout();
    expect(callback).toHaveBeenCalledTimes(1);
    steps.frame();
    steps.frame();
    expect(callback).toHaveBeenCalledTimes(1);
  });

  it("never calls back once cancelled", () => {
    const steps = manualClock();
    const callback = vi.fn();
    const cancel = afterFirstPaint(callback, steps.clock, 50);
    steps.frame();
    cancel();
    steps.frame();
    steps.timeout();
    expect(callback).not.toHaveBeenCalled();
    expect(steps.pending()).toEqual({ frames: 0, timers: [] });
  });
});
