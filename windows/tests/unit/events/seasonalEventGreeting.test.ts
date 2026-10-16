import { describe, expect, it } from "vitest";
import { instantOf } from "../../../src/core/calendar/zonedCalendar";
import { occurrenceID, type SeasonalEventOccurrence } from "../../../src/core/events/seasonalEvent";
import { SeasonalEventGreeting } from "../../../src/core/events/seasonalEventGreeting";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";

// Port of SeasonalEventGreetingTests.
const ZONE = "America/New_York";

function date(year: number, month: number, day: number, hour = 0): number {
  return instantOf({ year, month, day, hour }, ZONE);
}

const ids = (runs: SeasonalEventOccurrence[]) => runs.map((run) => occurrenceID(run, ZONE));

describe("SeasonalEventGreeting", () => {
  it("greets each run once and nothing between events", () => {
    const greeting = new SeasonalEventGreeting();
    expect(greeting.greet(date(2026, 10, 10, 9), ZONE)).toEqual([]);
    expect(ids(greeting.greet(date(2026, 10, 17, 9), ZONE))).toEqual(["halloween-2026"]);
    expect(greeting.greet(date(2026, 10, 17, 10), ZONE)).toEqual([]);
    expect(greeting.greet(date(2026, 10, 31, 22), ZONE)).toEqual([]);
    expect(greeting.due(date(2026, 10, 25), ZONE)).toEqual([]);
  });

  it("greets next year's run again and drops old runs", () => {
    const greeting = new SeasonalEventGreeting();
    greeting.greet(date(2026, 10, 20), ZONE);
    greeting.greet(date(2026, 12, 20), ZONE);
    expect([...greeting.greetedRuns]).toEqual(["winter-holidays-2026"]);
    expect(ids(greeting.greet(date(2027, 10, 17, 8), ZONE))).toEqual(["halloween-2027"]);
  });

  it("greets a winter run over New Year only once", () => {
    const greeting = new SeasonalEventGreeting();
    expect(ids(greeting.greet(date(2026, 12, 31, 23), ZONE))).toEqual(["winter-holidays-2026"]);
    expect(greeting.greet(date(2027, 1, 2), ZONE)).toEqual([]);
  });

  it("lets overlapping events share one moment, and a later one still gets its own", () => {
    const greeting = new SeasonalEventGreeting();
    expect(ids(greeting.greet(date(2027, 2, 6, 9), ZONE))).toEqual(["lunar-new-year-2027"]);
    expect(ids(greeting.greet(date(2027, 2, 8, 9), ZONE))).toEqual(["valentines-2027"]);
    const late = new SeasonalEventGreeting();
    expect(ids(late.greet(date(2027, 2, 10), ZONE))).toEqual(["valentines-2027", "lunar-new-year-2027"]);
  });

  it("checks next at the start of the next run", () => {
    expect(SeasonalEventGreeting.nextCheck(date(2026, 10, 10, 12), ZONE)).toBe(date(2026, 10, 17));
    expect(SeasonalEventGreeting.nextCheck(date(2026, 10, 17, 12), ZONE)).toBe(date(2026, 12, 14));
  });

  it("round-trips its save and reads a damaged list as empty", async () => {
    const store = new InMemoryDocumentStore();
    expect(await SeasonalEventGreeting.load(store)).toBeUndefined();
    const greeting = new SeasonalEventGreeting();
    greeting.greet(date(2026, 10, 20), ZONE);
    await greeting.write(store);
    expect(await SeasonalEventGreeting.load(store)).toEqual(greeting);
    expect(await store.read("Pet/events.json")).toBe('{"greetedRuns":["halloween-2026"],"schemaVersion":1}');
    expect(SeasonalEventGreeting.decode('{"schemaVersion": 1, "greetedRuns": 7}').greetedRuns.size).toBe(0);
    expect(SeasonalEventGreeting.decode('{"greetedRuns": ["a", 2]}').greetedRuns.size).toBe(0);
  });
});
