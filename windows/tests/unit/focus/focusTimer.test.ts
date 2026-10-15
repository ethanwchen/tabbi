import { describe, expect, it } from "vitest";
import { FocusTimer, FocusTimerConfig } from "../../../src/core/focus/focusTimer";
import { focusSessionsDone, stopActivityRecord } from "../../../src/core/focus/focusTimerActivity";
import { ProvidedFocus } from "../../../src/core/providers/providedFocus";

/* The parts of FocusTimer and ProvidedFocus the golden fixture does not walk through. */

const t0 = 1_790_000_000;

describe("FocusTimer stop and recover", () => {
  it("reports the focus time cut short by a stop or a skip", () => {
    const timer = new FocusTimer();
    expect(timer.stop(t0)).toBeUndefined();
    timer.start(t0);
    expect(timer.stop(t0 + 600)).toEqual({ focused: 600, endedAt: t0 + 600, outcome: "abandoned" });
    expect(timer.runState.kind).toBe("idle");
    timer.start(t0);
    expect(timer.skip(t0 + 120)).toEqual({ focused: 120, endedAt: t0 + 120, outcome: "skipped" });
    expect(timer.skip(t0 + 130)).toBeUndefined();
  });

  it("logs a stop of a minute or more, never as a finished session", () => {
    expect(stopActivityRecord({ focused: 59, endedAt: t0, outcome: "abandoned" }, "focus")).toBeUndefined();
    const record = stopActivityRecord({ focused: 600, endedAt: t0, outcome: "skipped" }, "focus");
    expect(record).toEqual({
      id: expect.any(String),
      source: "focus",
      kind: "focus.completed",
      start: t0 - 600,
      end: t0,
      quantity: 10,
      unit: "min",
      metadata: { method: "pomodoro", outcome: "skipped" },
    });
    const finished = { ...record, metadata: { method: "pomodoro", outcome: "completed" } } as NonNullable<typeof record>;
    expect(record === undefined ? -1 : focusSessionsDone([record, finished, { ...finished, source: "study" }], "focus")).toBe(1);
  });

  it("settles a session the app died in at the last moment it was alive", () => {
    const timer = new FocusTimer();
    timer.start(t0);
    const settled = timer.recover(t0 + 2000, t0 + 9000);
    expect(settled.completions).toEqual([
      { phase: "focus", endedAt: t0 + 1500 },
      { phase: "rest", endedAt: t0 + 1800 },
    ]);
    expect(settled.stop).toBeUndefined();
    expect(timer.runState.kind).toBe("idle");

    const clockSetBack = new FocusTimer();
    clockSetBack.start(t0);
    expect(clockSetBack.recover(t0 + 9000, t0 + 600).stop?.focused).toBe(600);
    expect(new FocusTimer().recover(t0, t0)).toEqual({ completions: [], stop: undefined });
  });

  it("clamps lengths to a second and copies cleanly", () => {
    const config = new FocusTimerConfig(0, -5);
    expect([config.focusDuration, config.restDuration]).toEqual([1, 1]);
    const timer = FocusTimer.withState("rest", { kind: "paused", remaining: 30 }, new FocusTimerConfig(), -3);
    expect(timer.completedFocusCount).toBe(0);
    const copy = timer.clone();
    copy.start(t0);
    expect(timer.isPaused).toBe(true);
    expect(copy.endsAt).toBe(t0 + 30);
  });
});

describe("ProvidedFocus", () => {
  it("labels the phase and sizes focus from the phase by default", () => {
    const focus = new ProvidedFocus({ source: "x", phase: "focus", clock: { kind: "idle" }, phaseLength: 1500 });
    expect(focus.label).toBe("Focus");
    expect(focus.focusLength).toBe(1500);
    const rest = new ProvidedFocus({ source: "x", phase: "rest", clock: { kind: "idle" }, phaseLength: 300, completedFocusCount: -1 });
    expect(rest.label).toBe("Break");
    expect(rest.focusLength).toBeUndefined();
    expect(rest.completedFocusCount).toBe(0);
    expect(rest.equals(rest.withSource("x"))).toBe(true);
    expect(rest.equals(rest.withSource("y"))).toBe(false);
  });

  it("knows when a clock face next changes", () => {
    const countdown = new ProvidedFocus({ source: "x", phase: "focus", clock: { kind: "countdown", endsAt: t0 + 100 }, phaseLength: 1500 });
    expect(countdown.nextShownChange(t0 + 0.5)).toBeCloseTo(t0 + 1.001, 9);
    expect(countdown.nextShownChange(t0 + 100)).toBeUndefined();
    const countUp = new ProvidedFocus({ source: "x", phase: "focus", clock: { kind: "countUp", since: t0 }, phaseLength: undefined });
    expect(countUp.countsUp).toBe(true);
    expect(countUp.nextShownChange(t0 + 2.25)).toBeCloseTo(t0 + 3.001, 9);
    expect(countUp.shownTime(t0 + 42)).toBe(42);
    const paused = new ProvidedFocus({ source: "x", phase: "focus", clock: { kind: "paused", shown: 30 }, phaseLength: undefined });
    expect(paused.nextShownChange(t0)).toBeUndefined();
    expect(paused.elapsed(t0)).toBe(30);
  });
});
