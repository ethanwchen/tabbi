// Port of the TickerSwipeTests class in TabSwipeTests.swift. TabSwipe and
// CloseSwipe are covered in tests/unit/settings/settingsValues.test.ts.
import { describe, expect, it } from "vitest";
import { TickerSwipe } from "../../../src/core/ticker/tickerSwipe";

/* Feeds one gesture of `count` events, each moving `down`, and returns how many steps it made. */
function gesture(swipe: TickerSwipe, down: number, count: number, momentum = 0): number {
  const steps = [swipe.feed(0, down, "began")];
  for (let index = 1; index < count; index += 1) steps.push(swipe.feed(0, down, "changed"));
  steps.push(swipe.feed(0, 0, "ended"));
  for (let index = 0; index < momentum; index += 1) steps.push(swipe.feed(0, down, "momentum"));
  return steps.filter((step) => step).length;
}

describe("TickerSwipe", () => {
  it("cycles exactly once for a swipe down", () => {
    for (let count = 2; count <= 20; count += 1) {
      expect(gesture(new TickerSwipe(), 30, count, 20), `${count} events`).toBe(1);
    }
  });

  it("does not cycle for short, upward or sideways swipes", () => {
    const swipe = new TickerSwipe();
    expect(gesture(swipe, 15, 2)).toBe(0);
    expect(gesture(swipe, 15, 2), "travel does not carry over").toBe(0);
    expect(gesture(swipe, -50, 10)).toBe(0);
    expect(swipe.feed(0, 0, "began")).toBe(false);
    for (let index = 0; index < 10; index += 1) expect(swipe.feed(-60, 20, "changed")).toBe(false);
  });

  it("does not delay a swipe down after going up first", () => {
    const swipe = new TickerSwipe();
    expect(swipe.feed(0, -100, "began")).toBe(false);
    expect(swipe.feed(0, 45, "changed")).toBe(true);
  });

  it("cycles once per threshold for a mouse wheel", () => {
    const swipe = new TickerSwipe();
    let steps = 0;
    for (let index = 0; index < 10; index += 1) if (swipe.feed(0, 10, "none")) steps += 1;
    expect(steps).toBe(2);
  });
});
