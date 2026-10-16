// Port of GoalCompletionWatchTests.swift: when a goal for today counts as just
// reached, which crowns the pet; only on the change from work left to done,
// never at launch.
import { describe, expect, it } from "vitest";
import type { ModuleID } from "../../../src/core/modules/moduleId";
import { GoalCompletionWatch } from "../../../src/core/motion/goalCompletionWatch";
import { ProgressItem } from "../../../src/core/providers/progressItem";

function reviews(completed: number, target: number, source: ModuleID = "anki"): ProgressItem {
  return new ProgressItem({ id: "reviews", source, title: "Anki reviews", completed, target, unit: "cards" });
}

describe("GoalCompletionWatch", () => {
  it("reaches a goal once when its last work is done", () => {
    const watch = new GoalCompletionWatch();
    expect(watch.reached([reviews(10, 40)])).toEqual([]);
    expect(watch.reached([reviews(39, 40)])).toEqual([]);
    expect(watch.reached([reviews(40, 40)])).toEqual([reviews(40, 40)]);
    expect(watch.reached([reviews(40, 40)]), "still done is no new news").toEqual([]);
    expect(watch.reached([reviews(45, 45)]), "extra work on a done goal").toEqual([]);
  });

  it("does not reach a goal already done at launch or when it appears", () => {
    const watch = new GoalCompletionWatch();
    expect(watch.reached([reviews(40, 40)]), "the first look sets the baseline").toEqual([]);

    const later = new GoalCompletionWatch();
    expect(later.reached([])).toEqual([]);
    expect(later.reached([reviews(40, 40)]), "a module switched on with its goal done").toEqual([]);
  });

  it("never reaches a goal of nothing", () => {
    const watch = new GoalCompletionWatch();
    expect(watch.reached([reviews(0, 0)])).toEqual([]);
    expect(watch.reached([reviews(0, 0)])).toEqual([]);
  });

  it("can reach the next day's goal again", () => {
    const watch = new GoalCompletionWatch();
    watch.reached([reviews(5, 40)]);
    expect(watch.reached([reviews(40, 40)]).length).toBe(1);
    // Anki rolls over: new cards are due.
    expect(watch.reached([reviews(0, 30)])).toEqual([]);
    expect(watch.reached([reviews(30, 30)]).length).toBe(1);
  });

  it("tracks goals per module", () => {
    const watch = new GoalCompletionWatch();
    const init = { id: "reviews", source: "study", title: "Focus time", target: 60, unit: "min", waitsForStart: true };
    const focus = new ProgressItem({ ...init, completed: 50 });
    watch.reached([reviews(40, 40), focus]);
    const done = new ProgressItem({ ...init, completed: 60 });
    expect(watch.reached([reviews(40, 40), done])).toEqual([done]);
  });

  it("does not reach a goal that disappears and comes back done", () => {
    const watch = new GoalCompletionWatch();
    watch.reached([reviews(10, 40)]);
    watch.reached([]);
    expect(watch.reached([reviews(40, 40)]), "its module was off while it was done").toEqual([]);
  });
});
