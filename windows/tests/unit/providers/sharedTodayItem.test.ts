// Port of SharedTodayItemTests.swift.
import { beforeAll, describe, expect, it } from "vitest";
import { moduleProvision } from "../../../src/core/providers/moduleProvision";
import { ProgressItem, type ProvidedAction } from "../../../src/core/providers/progressItem";
import { providedTask } from "../../../src/core/providers/providedTask";
import { ProviderSnapshot } from "../../../src/core/providers/providerSnapshot";
import { plannableWork, sharedTodayItems } from "../../../src/core/providers/sharedTodayItem";
import { tickerItemAction, tickerItemModule, type TickerItem } from "../../../src/core/ticker/tickerItem";
import { switchLanguage } from "../../support/catalogs";

function progress(id: string, completed: number, target: number): ProgressItem {
  return new ProgressItem({ id, source: "unset", title: id, completed, target, unit: "cards" });
}

beforeAll(() => {
  switchLanguage("en");
});

describe("SharedTodayItem", () => {
  it("leaves out the module's own items and puts goals before tasks", () => {
    const snapshot = new ProviderSnapshot([
      {
        module: "planner",
        provision: moduleProvision({
          tasks: [providedTask({ id: "mine", source: "planner", title: "Mine" })],
          progress: [progress("own", 1, 2)],
        }),
      },
      {
        module: "study",
        provision: moduleProvision({
          tasks: [providedTask({ id: "pomodoro", source: "study", title: "Pomodoro", estimatedMinutes: 25 })],
        }),
      },
      { module: "anki", provision: moduleProvision({ progress: [progress("reviews", 112, 432)] }) },
    ]);
    const items = sharedTodayItems(snapshot, "planner", "en");
    expect(items.map((item) => item.title)).toEqual(["reviews", "Pomodoro"]);
    expect(items.map((item) => item.source)).toEqual(["anki", "study"]);
    expect(items[0]?.detail).toBe("320 cards left");
    expect(items[0]?.fraction ?? 0).toBeCloseTo(112 / 432, 4);
    expect(items[0]?.isDone).toBe(false);
    expect(items[1]?.detail).toBe("25 min");
    expect(items[1]?.fraction).toBeUndefined();
  });

  it("lists only other modules' unfinished work for planning", () => {
    const snapshot = new ProviderSnapshot([
      { module: "planner", provision: moduleProvision({ tasks: [providedTask({ id: "mine", source: "planner", title: "Mine" })] }) },
      {
        module: "study",
        provision: moduleProvision({
          tasks: [
            providedTask({ id: "pomodoro", source: "study", title: "Pomodoro", estimatedMinutes: 25 }),
            providedTask({ id: "done", source: "study", title: "Done", isDone: true }),
          ],
        }),
      },
      {
        module: "anki",
        provision: moduleProvision({ progress: [progress("Anki reviews", 112, 432), progress("met", 5, 5), progress("empty", 0, 0)] }),
      },
    ]);
    expect(plannableWork(snapshot, "planner", "en")).toEqual(["Anki reviews (320 cards left)", "Pomodoro (about 25 min)"]);
    expect(plannableWork(new ProviderSnapshot(), "planner", "en")).toEqual([]);
  });

  it("hides goals with nothing due today and counts met goals as done", () => {
    const snapshot = new ProviderSnapshot([
      { module: "anki", provision: moduleProvision({ progress: [progress("empty", 0, 0), progress("met", 50, 50)] }) },
    ]);
    const items = sharedTodayItems(snapshot, "planner", "en");
    expect(items.map((item) => item.title)).toEqual(["met"]);
    expect(items[0]?.isDone).toBe(true);
    expect(items[0]?.detail).toBe("50 cards");
  });

  it("keeps ids unique across modules and kinds", () => {
    const snapshot = new ProviderSnapshot([
      {
        module: "anki",
        provision: moduleProvision({
          tasks: [providedTask({ id: "x", source: "anki", title: "x" })],
          progress: [progress("x", 0, 1)],
        }),
      },
      { module: "study", provision: moduleProvision({ tasks: [providedTask({ id: "x", source: "study", title: "x" })] }) },
    ]);
    const ids = sharedTodayItems(snapshot, "planner", "en").map((item) => item.id);
    expect(new Set(ids).size).toBe(3);
  });

  it("carries a goal's action to Today and the ticker", () => {
    const action: ProvidedAction = { id: "anki.study", title: "Study Renal" };
    const goal = new ProgressItem({ id: "reviews", source: "anki", title: "Anki reviews", completed: 2, target: 10, unit: "cards", action });
    const snapshot = new ProviderSnapshot([{ module: "anki", provision: moduleProvision({ progress: [goal] }) }]);
    expect(sharedTodayItems(snapshot, "planner", "en")[0]?.action).toEqual(action);
    const first = snapshot.progress[0];
    expect(first).toBeDefined();
    if (first === undefined) return;
    const ticker: TickerItem = { type: "progress", item: first };
    expect(tickerItemAction(ticker)).toEqual(action);
    expect(tickerItemModule(ticker)).toBe("anki");
    expect(tickerItemAction({ type: "tasks", remaining: 3 }), "items without a goal have no action").toBeUndefined();
  });
});
