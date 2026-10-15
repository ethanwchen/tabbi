import { beforeAll, describe, expect, it } from "vitest";
import { PlannerDay } from "../../../src/core/planner/plannerDay";
import { mergedProgress, progressIsComplete, type SharedTodayItemState } from "../../../src/core/planner/providedWork";
import { TodayTally } from "../../../src/core/planner/todayTally";
import { switchLanguage } from "../../support/catalogs";

/* Port of TodayTallyTests. */

const OCT1 = "2026-10-01";
const NOW = 1_790_000_000;

/* Anki's reviews goal as Today lists it (`sharedTodayItems(excluding: .planner)`): goals with something due, done at zero left. */
function reviews(completed: number, target: number): SharedTodayItemState[] {
  return mergedProgress([
    ["anki", [{ id: "reviews", source: "anki", title: "Anki reviews", completed, target, unit: "cards", waitsForStart: false }]],
  ])
    .filter((item) => item.source !== "planner" && item.target > 0)
    .map((item) => ({ isDone: progressIsComplete(item) }));
}

function add(day: PlannerDay, title: string): string {
  return day.add(title, NOW)?.id ?? "";
}

beforeAll(() => {
  switchLanguage("en");
});

describe("TodayTally", () => {
  it("matches the day for the own checklist alone", () => {
    const day = new PlannerDay(OCT1);
    expect(new TodayTally(day, []).summary).toBe("Nothing planned");
    expect(new TodayTally(day, []).progress).toBe(0);
    const first = add(day, "One");
    const second = add(day, "Two");
    expect(new TodayTally(day, []).summary).toBe("0 of 2 done");
    day.toggle(first, NOW);
    expect(new TodayTally(day, []).summary).toBe("1 of 2 done");
    day.toggle(second, NOW);
    expect(new TodayTally(day, []).summary).toBe("All 2 done");
  });

  it("counts what a day ahead holds in the planned summary", () => {
    const day = new PlannerDay(OCT1, [], true);
    expect(new TodayTally(day, []).plannedSummary).toBe("Nothing planned");
    add(day, "One");
    add(day, "Two");
    expect(new TodayTally(day, []).plannedSummary).toBe("2 planned");
  });

  it("counts done of total in the short summary", () => {
    const day = new PlannerDay(OCT1);
    expect(new TodayTally(day, []).shortSummary).toBe("Nothing planned");
    const first = add(day, "One");
    const second = add(day, "Two");
    expect(new TodayTally(day, []).shortSummary).toBe("0/2");
    day.toggle(first, NOW);
    expect(new TodayTally(day, reviews(0, 80)).shortSummary).toBe("1/3");
    day.toggle(second, NOW);
    expect(new TodayTally(day, []).shortSummary).toBe("2/2");
  });

  it("counts pending reviews as one open item", () => {
    const day = new PlannerDay(OCT1);
    day.toggle(add(day, "Pathology lecture notes"), NOW);
    const tally = new TodayTally(day, reviews(112, 432));
    expect(tally.doneCount).toBe(1);
    expect(tally.totalCount).toBe(2);
    expect(tally.summary).toBe("1 of 2 done");
    expect(tally.progress).toBe(0.5);
  });

  it("checks reviews off at zero due", () => {
    const day = new PlannerDay(OCT1);
    day.toggle(add(day, "Pathology lecture notes"), NOW);
    const shared = reviews(432, 432);
    expect(shared[0]?.isDone).toBe(true);
    expect(new TodayTally(day, shared).summary).toBe("All 2 done");
    expect(new TodayTally(new PlannerDay(OCT1), shared).progress).toBe(1);
  });

  it("makes reviews alone a day with something planned", () => {
    expect(new TodayTally(new PlannerDay(OCT1), reviews(0, 80)).summary).toBe("0 of 1 done");
  });
});
