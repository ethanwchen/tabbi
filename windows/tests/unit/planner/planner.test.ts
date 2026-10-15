import { beforeAll, describe, expect, it } from "vitest";
import { instantOf } from "../../../src/core/calendar/zonedCalendar";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { PlannerDay, type PlannerItem } from "../../../src/core/planner/plannerDay";
import {
  addingDaysToKey,
  dayKeyStart,
  isPlannerDayKey,
  plannerDayKey,
  plannerDayKeyOf,
} from "../../../src/core/planner/plannerDayKey";
import { PlannerRepository } from "../../../src/core/planner/plannerRepository";
import { samplePlannerDay, samplePlannerDayFor } from "../../../src/core/planner/plannerSampleData";
import {
  nextViewedDay,
  previousViewedDay,
  viewedDayCalendarTitle,
  viewedDayHeaderDateStyles,
  viewedDayIsEditable,
  viewedDayKey,
  viewedDayPlanStart,
  viewedDayPlanTitle,
  viewedDayTitle,
  type PlannerViewedDay,
} from "../../../src/core/planner/plannerViewedDay";
import { PLANNER_SAMPLE_DAYS } from "../../../src/core/planner/todayPlanSettings";
import { switchLanguage } from "../localization/catalogs";

/* Port of PlannerTests: PlannerDayKey, PlannerDay, PlannerRepository, sample data, starter tasks and PlannerViewedDay. */

const LA = "America/Los_Angeles";
const NOW = 1_790_000_000;

function snapshot(day: PlannerDay): { date: string; items: PlannerItem[]; isPlannedAhead: boolean } {
  return { date: day.date, items: [...day.items], isPlannedAhead: day.isPlannedAhead };
}

function newDay(raw: string, items: readonly PlannerItem[] = [], plannedAhead = false): PlannerDay {
  return new PlannerDay(raw, items, plannedAhead);
}

function added(day: PlannerDay, title: string, now = NOW): PlannerItem {
  const item = day.add(title, now);
  if (item === undefined) throw new Error(`Could not add ${title}`);
  return item;
}

beforeAll(() => {
  switchLanguage("en");
});

describe("PlannerDayKey", () => {
  it("formats the local day in the zone", () => {
    /* 2026-10-02 03:00 UTC is still Oct 1 in Los Angeles. */
    expect(plannerDayKeyOf(1_790_910_000, LA)).toBe("2026-10-01");
  });

  it("rejects malformed and impossible dates", () => {
    expect(plannerDayKey("2028-02-29")).toBe("2028-02-29");
    expect(isPlannerDayKey("2026-02-30")).toBe(false);
    expect(isPlannerDayKey("2026-1-01")).toBe(false);
    expect(isPlannerDayKey("notes")).toBe(false);
  });

  it("round-trips its start date and sorts chronologically", () => {
    expect(plannerDayKeyOf(dayKeyStart("2026-10-01", LA), LA)).toBe("2026-10-01");
    expect("2026-09-30" < "2026-10-01").toBe(true);
  });

  it("steps across month ends and daylight saving", () => {
    /* Clocks go back on Nov 1, 2026 in Los Angeles, a 25-hour day. */
    expect(addingDaysToKey("2026-10-31", 1)).toBe("2026-11-01");
    expect(addingDaysToKey("2026-10-31", 2)).toBe("2026-11-02");
    expect(addingDaysToKey(addingDaysToKey("2026-10-31", 2), -2)).toBe("2026-10-31");
    expect(addingDaysToKey("2026-03-01", -1)).toBe("2026-02-28");
  });
});

describe("PlannerDay", () => {
  it("trims titles on add and rejects blank ones", () => {
    const day = newDay("2026-10-01");
    expect(day.add("   \n", NOW)).toBeUndefined();
    const item = day.add("  Ship   the\nrelease ", NOW);
    expect(item?.title).toBe("Ship the release");
    expect(item?.createdAt).toBe(NOW);
    expect(day.items.map((entry) => entry.title)).toEqual(["Ship the release"]);
  });

  it("stamps and clears completion on toggle", () => {
    const day = newDay("2026-10-01");
    const id = added(day, "Run").id;
    day.toggle(id, NOW);
    expect(day.items[0]?.isDone).toBe(true);
    expect(day.items[0]?.completedAt).toBe(NOW);
    expect(day.progress).toBe(1);
    day.toggle(id, NOW);
    expect(day.items[0]?.isDone).toBe(false);
    expect(day.items[0]?.completedAt).toBeUndefined();
    expect(day.doneCount).toBe(0);
  });

  it("ignores blank and unchanged titles on rename", () => {
    const day = newDay("2026-10-01");
    const id = added(day, "Draft").id;
    expect(day.rename(id, "  ")).toBe(false);
    expect(day.rename(id, "Draft")).toBe(false);
    expect(day.rename(id, " Final draft ")).toBe(true);
    expect(day.items[0]?.title).toBe("Final draft");
  });

  it("deletes and clears completed items", () => {
    const day = newDay("2026-10-01");
    const a = added(day, "A").id;
    const b = added(day, "B").id;
    day.add("C", NOW);
    day.delete(a);
    day.toggle(b, NOW);
    day.clearCompleted();
    expect(day.items.map((item) => item.title)).toEqual(["C"]);
  });

  it("moves offsets with Array.move semantics", () => {
    const day = newDay("2026-10-01");
    for (const title of ["A", "B", "C", "D"]) day.add(title, NOW);
    day.moveOffsets([0], 3);
    expect(day.items.map((item) => item.title)).toEqual(["B", "C", "A", "D"]);
    day.moveOffsets([1, 3], 0);
    expect(day.items.map((item) => item.title)).toEqual(["C", "D", "B", "A"]);
    day.moveOffsets([0], 99);
    expect(day.items.map((item) => item.title)).toEqual(["D", "B", "A", "C"]);
  });

  it("moves an item by id to the target index", () => {
    const day = newDay("2026-10-01");
    for (const title of ["A", "B", "C"]) day.add(title, NOW);
    day.move(day.items[2]?.id ?? "", 0);
    expect(day.items.map((item) => item.title)).toEqual(["C", "A", "B"]);
    day.move(day.items[0]?.id ?? "", 2);
    expect(day.items.map((item) => item.title)).toEqual(["A", "B", "C"]);
  });

  it("lists only open items the other day lacks", () => {
    const yesterday = newDay("2026-09-30");
    const carried = added(yesterday, "Carried");
    const left = added(yesterday, "Left behind");
    const done = added(yesterday, "Done");
    yesterday.toggle(done.id, NOW);
    const today = newDay("2026-10-01", [carried]);
    expect(yesterday.unfinished(today)).toEqual([left]);
  });

  it("skips titles the other day already has", () => {
    const yesterday = newDay("2026-09-30");
    yesterday.add("Call the dentist", NOW);
    const today = newDay("2026-10-01");
    today.add("call the DENTIST", NOW);
    /* Exactly what `adopt` would add, so a leftover is never offered and then skipped. */
    expect(yesterday.unfinished(today)).toEqual([]);
    expect(today.adopt(yesterday.items)).toEqual([]);
  });

  it("keeps identity on adopt and skips duplicates", () => {
    const yesterday = newDay("2026-09-30");
    const left = added(yesterday, "Left behind");
    const twin = added(yesterday, "Already there");
    const today = newDay("2026-10-01");
    today.add("already THERE", NOW);
    expect(today.adopt([left, twin, left])).toEqual([left]);
    expect(today.items.map((item) => item.title)).toEqual(["already THERE", "Left behind"]);
    expect(today.items.at(-1)?.id).toBe(left.id);
    expect(today.items.at(-1)?.createdAt).toBe(NOW);
    expect(today.adopt([left])).toEqual([]);
  });

  it("has zero progress when empty", () => {
    expect(newDay("2026-10-01").progress).toBe(0);
  });
});

describe("PlannerRepository", () => {
  const oct1 = "2026-10-01";

  function setUp(): { store: InMemoryDocumentStore; repository: PlannerRepository } {
    const store = new InMemoryDocumentStore();
    return { store, repository: new PlannerRepository(store) };
  }

  it("round-trips every field", async () => {
    const { store, repository } = setUp();
    const day = newDay(oct1);
    day.add("Write tests", NOW);
    const id = added(day, "Ship").id;
    day.toggle(id, NOW + 60);
    await repository.save(day);
    expect(Object.keys(store.snapshot())).toEqual(["Planner/2026-10-01.json"]);
    const loaded = await new PlannerRepository(store).load(oct1);
    expect(loaded && snapshot(loaded)).toEqual(snapshot(day));
  });

  it("writes the Mac's file format", async () => {
    const { store, repository } = setUp();
    const day = newDay(oct1);
    day.add("Ship", NOW);
    await repository.save(day);
    const text = store.snapshot()["Planner/2026-10-01.json"] ?? "";
    const json = JSON.parse(text) as Record<string, unknown>;
    expect(json.schemaVersion).toBe(2);
    expect(json.isPlannedAhead).toBe(false);
    expect(text).toContain('"createdAt" : "2026-09-21T14:13:20Z"');
  });

  it("migrates an older file without isPlannedAhead", async () => {
    const { repository } = setUp();
    const store = new InMemoryDocumentStore({
      "Planner/2026-10-01.json": JSON.stringify({
        date: oct1,
        items: [{ id: "00000000-0000-4000-8000-000000000001", title: "Old", isDone: false, createdAt: "2026-10-01T08:00:00Z" }],
      }),
    });
    const day = await new PlannerRepository(store).load(oct1);
    expect(day?.isPlannedAhead).toBe(false);
    expect(day?.items.map((item) => item.title)).toEqual(["Old"]);
    expect(await repository.load(oct1)).toBeUndefined();
  });

  it("gives undefined for a missing day", async () => {
    expect(await setUp().repository.load(oct1)).toBeUndefined();
  });

  it("carries over unfinished items from the most recent day on a new day", async () => {
    const { repository } = setUp();
    const older = newDay("2026-09-20");
    older.add("Stale", NOW);
    await repository.save(older);
    const latest = newDay("2026-09-29");
    const keep = added(latest, "Unfinished");
    const done = added(latest, "Finished");
    latest.add("Also open", NOW);
    latest.toggle(done.id, NOW);
    await repository.save(latest);

    const today = await repository.open(oct1);
    expect(today.items.map((item) => item.title)).toEqual(["Unfinished", "Also open"]);
    expect(today.items[0]?.id).toBe(keep.id);
    expect(today.items[0]?.createdAt).toBe(NOW);
    /* The previous day stays as a historical record. */
    const reloaded = await repository.load(latest.date);
    expect(reloaded && snapshot(reloaded)).toEqual(snapshot(latest));
  });

  it("carries over only once", async () => {
    const { repository } = setUp();
    const yesterday = newDay("2026-09-30");
    yesterday.add("Carry me", NOW);
    await repository.save(yesterday);
    const today = await repository.open(oct1);
    today.delete(today.items[0]?.id ?? "");
    await repository.save(today);
    expect((await repository.open(oct1)).items).toEqual([]);
  });

  it("previews the carried-over day without creating its file", async () => {
    const { repository } = setUp();
    const yesterday = newDay("2026-09-30");
    yesterday.add("Carry me", NOW);
    await repository.save(yesterday);
    expect((await repository.preview(oct1)).items.map((item) => item.title)).toEqual(["Carry me"]);
    expect(await repository.load(oct1)).toBeUndefined();
    expect(await repository.savedDays()).toEqual([yesterday.date]);

    /* Once the day exists, preview reads it as saved. */
    const today = await repository.open(oct1);
    today.delete(today.items[0]?.id ?? "");
    await repository.save(today);
    expect((await repository.preview(oct1)).items).toEqual([]);
  });

  it("ignores future days and unrelated files", async () => {
    const { store, repository } = setUp();
    const future = newDay("2026-10-05");
    future.add("From the future", NOW);
    await repository.save(future);
    await store.write("Planner/notes.json", "hi");
    expect((await repository.open(oct1)).items).toEqual([]);
    expect(await repository.savedDays()).toEqual(["2026-10-01", "2026-10-05"]);
  });

  it("skips a corrupt previous day", async () => {
    const { store, repository } = setUp();
    const older = newDay("2026-09-28");
    older.add("Recovered", NOW);
    await repository.save(older);
    await store.write("Planner/2026-09-30.json", "{");
    expect((await repository.open(oct1)).items.map((item) => item.title)).toEqual(["Recovered"]);
  });

  it("rejects a corrupt today instead of overwriting it", async () => {
    const { store, repository } = setUp();
    await store.write(repository.documentName(oct1), "garbage");
    await expect(repository.open(oct1)).rejects.toThrow();
    expect(await store.read(repository.documentName(oct1))).toBe("garbage");
  });

  it("creates an empty day file on the first open with no history", async () => {
    const { repository } = setUp();
    expect(snapshot(await repository.open(oct1))).toEqual(snapshot(newDay(oct1)));
    expect(await repository.load(oct1)).toBeDefined();
  });

  it("never creates a file on peek", async () => {
    const { repository } = setUp();
    const tomorrow = addingDaysToKey(oct1, 1);
    const yesterday = addingDaysToKey(oct1, -1);
    expect(snapshot(await repository.peek(tomorrow, oct1))).toEqual(snapshot(newDay(tomorrow, [], true)));
    expect(snapshot(await repository.peek(yesterday, oct1))).toEqual(snapshot(newDay(yesterday)));
    expect(await repository.savedDays()).toEqual([]);
  });

  it("takes in leftovers when a planned-ahead day comes", async () => {
    const { repository } = setUp();
    const tomorrow = addingDaysToKey(oct1, 1);
    const today = await repository.open(oct1);
    const open = added(today, "Write report");
    const done = added(today, "Inbox zero");
    today.toggle(done.id, NOW);
    await repository.save(today);

    /* In the evening, plan tomorrow; that saves tomorrow's file early. */
    const plan = await repository.peek(tomorrow, oct1);
    plan.add("Call the dentist", NOW);
    plan.add("write REPORT", NOW);
    await repository.save(plan);

    /* The planned "write REPORT" stands in for the leftover of that name. */
    const opened = await repository.open(tomorrow);
    expect(opened.items.map((item) => item.title)).toEqual(["Call the dentist", "write REPORT"]);
    expect(opened.items.some((item) => item.id === open.id)).toBe(false);
    expect(opened.isPlannedAhead).toBe(false);
    const reloaded = await repository.load(tomorrow);
    expect(reloaded && snapshot(reloaded)).toEqual(snapshot(opened));
  });

  it("keeps planned tasks' state when the day comes", async () => {
    const { repository } = setUp();
    const tomorrow = addingDaysToKey(oct1, 1);
    const today = await repository.open(oct1);
    const leftover = added(today, "Write report");
    await repository.save(today);

    const plan = await repository.peek(tomorrow, oct1);
    const done = added(plan, "Book flights");
    plan.toggle(done.id, NOW);
    const first = added(plan, "Stretch");
    const second = added(plan, "Stretch");
    await repository.save(plan);

    const opened = await repository.open(tomorrow);
    expect(opened.items.map((item) => item.id)).toEqual([leftover.id, done.id, first.id, second.id]);
    expect(opened.items.map((item) => item.isDone)).toEqual([false, true, false, false]);
    expect(opened.items[1]?.completedAt).toBeDefined();
  });

  it("takes in leftovers only once on a planned-ahead day", async () => {
    const { repository } = setUp();
    const today = await repository.open(oct1);
    today.add("Carry me", NOW);
    await repository.save(today);
    await repository.save(newDay(addingDaysToKey(oct1, 1), [], true));

    const opened = await repository.open(addingDaysToKey(oct1, 1));
    opened.delete(opened.items[0]?.id ?? "");
    await repository.save(opened);
    expect((await repository.open(addingDaysToKey(oct1, 1))).items).toEqual([]);
  });

  it("passes on older leftovers past a skipped planned-ahead day", async () => {
    const { repository } = setUp();
    const today = await repository.open(oct1);
    today.add("Old leftover", NOW);
    await repository.save(today);
    const planned = newDay(addingDaysToKey(oct1, 1), [], true);
    planned.add("Planned", NOW);
    await repository.save(planned);

    /* The planned day is never opened; the day after it is. */
    const later = await repository.open(addingDaysToKey(oct1, 2));
    expect(later.items.map((item) => item.title)).toEqual(["Old leftover", "Planned"]);
  });
});

describe("PlannerSampleData", () => {
  const oct1 = "2026-10-01";

  function expectPartlyFinished(day: PlannerDay): void {
    expect(day.date).toBe(oct1);
    expect(day.items.length).toBeGreaterThanOrEqual(3);
    expect(day.doneCount).toBeGreaterThanOrEqual(2);
    expect(day.doneCount).toBeLessThan(day.items.length);
    expect(new Set(day.items.map((item) => item.id)).size).toBe(day.items.length);
    for (const item of day.items) {
      expect(plannerDayKeyOf(item.createdAt, LA)).toBe(oct1);
      expect(item.isDone).toBe(item.completedAt !== undefined);
      if (item.completedAt !== undefined) expect(item.completedAt).toBeGreaterThan(item.createdAt);
    }
  }

  it("makes every sample a partly finished day within the date", () => {
    for (const kind of PLANNER_SAMPLE_DAYS) expectPartlyFinished(samplePlannerDay(oct1, kind, LA));
  });

  it("shares the first open item across sample days", () => {
    /* The demo focus timer links the work day's first open item; every other sample day has it too. */
    const firstOpen = samplePlannerDay(oct1, "work", LA).items.find((item) => !item.isDone)?.id;
    expect(firstOpen).toBeDefined();
    for (const kind of PLANNER_SAMPLE_DAYS) {
      expect(samplePlannerDay(oct1, kind, LA).items.find((item) => !item.isDone)?.id).toBe(firstOpen);
    }
  });

  it("uses the store screenshots' day for work", () => {
    const day = samplePlannerDay(oct1, "work", LA);
    expect(day.items.map((item) => item.title)).toEqual(["Outline the history essay", "Reply to Sam about Saturday", "Read chapter 4"]);
    expect(day.doneCount).toBe(2);
  });

  it("makes the medicine sample a study day", () => {
    const titles = samplePlannerDay(oct1, "medicine", LA).items.map((item) => item.title);
    expect(titles).toContain("Cardio practice questions");
    expect(titles).not.toContain("Read chapter 4");
  });

  it("leaves one task carried and two to move yesterday", () => {
    for (const kind of PLANNER_SAMPLE_DAYS) {
      const today = samplePlannerDayFor("today", oct1, kind, LA);
      const yesterday = samplePlannerDayFor("yesterday", oct1, kind, LA);
      expect(yesterday.date).toBe("2026-09-30");
      expect(yesterday.unfinished(today).length).toBe(2);
      expect(yesterday.items.filter((item) => !item.isDone).length).toBe(3);
      expect(snapshot(today)).toEqual(snapshot(samplePlannerDay(oct1, kind, LA)));
    }
  });

  it("plans tomorrow's sample ahead the day before", () => {
    for (const kind of PLANNER_SAMPLE_DAYS) {
      const tomorrow = samplePlannerDayFor("tomorrow", oct1, kind, LA);
      expect(tomorrow.date).toBe("2026-10-02");
      expect(tomorrow.isPlannedAhead).toBe(true);
      expect(tomorrow.items.length).toBeGreaterThan(0);
      expect(tomorrow.doneCount).toBe(0);
      for (const item of tomorrow.items) expect(plannerDayKeyOf(item.createdAt, LA)).toBe(oct1);
    }
  });

  it("is stable", () => {
    expect(snapshot(samplePlannerDay(oct1, "work", LA))).toEqual(snapshot(samplePlannerDay(oct1, "work", LA)));
  });
});

describe("PlannerDay starter tasks", () => {
  it("adds starter tasks once, skipping blanks and existing titles", () => {
    const day = newDay("2026-10-01");
    day.add("Review lecture notes", NOW);
    const result = day.addStarterTasks(["review  LECTURE notes", "  ", "Plan the week", "Plan the week"], NOW);
    expect(result.map((item) => item.title)).toEqual(["Plan the week"]);
    expect(day.items.map((item) => item.title)).toEqual(["Review lecture notes", "Plan the week"]);
    /* Applying a kit again adds nothing. */
    expect(day.addStarterTasks(["Plan the week"], NOW)).toEqual([]);
    expect(day.items.length).toBe(2);
  });

  it("takes back on undo only starter tasks the user has not touched", () => {
    const day = newDay("2026-10-01");
    day.add("Mine", NOW);
    const result = day.addStarterTasks(["Read", "Write", "Plan"], NOW);
    day.toggle(result[0]?.id ?? "", NOW);
    expect(day.rename(result[1]?.id ?? "", "Write the essay")).toBe(true);
    expect(day.removeUntouched(result)).toBe(true);
    expect(day.items.map((item) => item.title)).toEqual(["Mine", "Read", "Write the essay"]);
    /* Nothing left to take back. */
    expect(day.removeUntouched(result)).toBe(false);
  });
});

describe("PlannerViewedDay", () => {
  const oct1 = "2026-10-01";

  it("steps one day either side of today", () => {
    expect(viewedDayKey("yesterday", oct1)).toBe("2026-09-30");
    expect(viewedDayKey("today", oct1)).toBe(oct1);
    expect(viewedDayKey("tomorrow", oct1)).toBe("2026-10-02");
    expect(previousViewedDay("today")).toBe("yesterday");
    expect(nextViewedDay("today")).toBe("tomorrow");
    expect(nextViewedDay("yesterday")).toBe("today");
    expect(previousViewedDay("yesterday")).toBeUndefined();
    expect(nextViewedDay("tomorrow")).toBeUndefined();
  });

  it("makes only yesterday read-only and only today untitled", () => {
    expect(viewedDayIsEditable("yesterday")).toBe(false);
    expect(viewedDayIsEditable("today")).toBe(true);
    expect(viewedDayIsEditable("tomorrow")).toBe(true);
    expect(viewedDayTitle("today")).toBeUndefined();
    expect(viewedDayTitle("yesterday")).toBe("Yesterday");
    expect(viewedDayTitle("tomorrow")).toBe("Tomorrow");
  });

  it("plans from now today, the working day tomorrow, and never yesterday", () => {
    const berlin = "Europe/Berlin";
    /* The night before the October clock change, at 11 pm. */
    const now = instantOf({ year: 2026, month: 10, day: 24, hour: 23 }, berlin);
    expect(viewedDayPlanStart("today", now, berlin)).toBe(now);
    expect(viewedDayPlanStart("yesterday", now, berlin)).toBeUndefined();
    expect(viewedDayPlanStart("tomorrow", now, berlin)).toBe(instantOf({ year: 2026, month: 10, day: 25, hour: 9 }, berlin));
    expect(viewedDayPlanStart("tomorrow", now, berlin, 7)).toBe(instantOf({ year: 2026, month: 10, day: 25, hour: 7 }, berlin));
    expect(viewedDayPlanTitle("today")).toBe("Plan my day");
    expect(viewedDayPlanTitle("tomorrow")).toBe("Plan tomorrow");
  });

  it("shows the date in the header unless dates are hidden, then only the weekday", () => {
    const saturday = Date.UTC(2026, 9, 10, 12);
    const texts = (day: PlannerViewedDay, showsDates: boolean) =>
      viewedDayHeaderDateStyles(day, showsDates).map((style) =>
        style === undefined ? undefined : new Intl.DateTimeFormat("en-US", { ...style, timeZone: "UTC" }).format(saturday),
      );
    /*
     * The Mac writes the short form "Sat 10"; Intl orders en-US weekday and
     * day as "10 Sat", which the header view arranges itself.
     */
    expect(texts("today", true)).toEqual(["Sat, Oct 10", "10 Sat"]);
    expect(texts("yesterday", true)).toEqual(["Oct 10", undefined]);
    expect(texts("today", false)).toEqual(["Saturday", "Sat"]);
    for (const day of ["yesterday", "tomorrow"] as const) expect(texts(day, false)).toEqual([undefined]);
  });

  it("captions the calendar card for the day it lists", () => {
    expect(viewedDayCalendarTitle("today")).toBe("Up next");
    expect(viewedDayCalendarTitle("yesterday")).toBe("Yesterday's calendar");
    expect(viewedDayCalendarTitle("tomorrow")).toBe("Tomorrow's calendar");
  });
});
