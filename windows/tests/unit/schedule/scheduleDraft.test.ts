import { beforeAll, describe, expect, it } from "vitest";
import { startOfDay, wallTime } from "../../../src/core/calendar/zonedCalendar";
import { planBlock } from "../../../src/core/planner/dayPlan";
import { PLANNED_EVENT_NOTE, type PlanCalendarWriting, type PlannedCalendarEvent } from "../../../src/core/planner/dayPlanProposal";
import { ProgressItem } from "../../../src/core/providers/progressItem";
import type { ProvidedTask } from "../../../src/core/providers/providedTask";
import { scheduleItem, scheduleItemEvent, type ScheduleItem } from "../../../src/core/schedule/scheduleDay";
import { ScheduleDraft } from "../../../src/core/schedule/scheduleDraft";
import {
  SCHEDULE_SAMPLE_TASKS,
  SCHEDULE_SAMPLE_WEEK_TASKS,
  scheduleSampleItems,
  scheduleSampleNow,
  scheduleSampleWeekItems,
} from "../../../src/core/schedule/scheduleSampleData";
import type { Instant } from "../../../src/core/time";
import { switchLanguage } from "../../support/catalogs";

/* Port of ScheduleDraftTests, in UTC like the Swift suite. */

const ZONE = "UTC";
const clock = { timeZone: ZONE, locale: "en-US" };
const DAY = Date.UTC(2026, 9, 5) / 1000;

/** Records what it was asked to write, or fails like a denied calendar. */
class RecordingWriter implements PlanCalendarWriting {
  written: PlannedCalendarEvent[] = [];
  fails = false;

  write(events: readonly PlannedCalendarEvent[]): void {
    if (this.fails) throw new Error("Denied");
    this.written.push(...events);
  }
}

function at(hour: number, minute = 0): Instant {
  return DAY + (hour * 60 + minute) * 60;
}

function on(day: number, hour: number, minute = 0): Instant {
  return at(hour, minute) + day * 86_400;
}

function task(id: string, minutes: number | undefined, done = false): ProvidedTask {
  return { id, source: "planner", title: id, isDone: done, ...(minutes === undefined ? {} : { estimatedMinutes: minutes }) };
}

function draft(tasks: ProvidedTask[], options: { now?: Instant; items?: ScheduleItem[]; progress?: ProgressItem[] } = {}): ScheduleDraft {
  return ScheduleDraft.plan(options.now ?? at(9), options.items ?? [], tasks, options.progress ?? [], clock);
}

function weekDraft(tasks: ProvidedTask[], options: { now?: Instant; items?: ScheduleItem[] } = {}): ScheduleDraft {
  return ScheduleDraft.planWeek(options.now ?? at(9), options.items ?? [], tasks, [], clock);
}

beforeAll(() => {
  switchLanguage("en");
});

describe("schedule draft", () => {
  it("plans around the calendar with reasons", () => {
    const meeting = scheduleItem({ id: "standup", title: "Standup", start: at(9, 30), end: at(10) });
    const result = draft([task("Write spec", 60), task("Inbox", 15)], { items: [meeting] });
    const items = result.items;
    expect(items.map((item) => item.title)).toEqual(["Inbox", "Write spec"]);
    expect(items.every((item) => item.kind === "proposed" && item.reason === "Next on your list")).toBe(true);
    /* 9:00 to 9:20 is free (10 min buffer before the standup), so the short task goes there. */
    expect(items[0]?.start).toBe(at(9));
    expect(items.at(-1)?.start).toBe(at(10, 10));
    expect(result.summary).toBe("2 blocks, 1h 15m");
  });

  it("never lets proposed items block their own replan", () => {
    const first = draft([task("Write spec", 60)]);
    const again = draft([task("Write spec", 60)], { items: first.items });
    expect(again.items.map((item) => item.start)).toEqual(first.items.map((item) => item.start));
  });

  it("puts review goals first", () => {
    const reviews = new ProgressItem({
      id: "deck",
      source: "anki",
      title: "Anki reviews",
      completed: 0,
      target: 120,
      unit: "cards",
      waitsForStart: false,
    });
    const result = draft([task("Write spec", 30)], { progress: [reviews] });
    expect(result.items[0]?.title).toBe("Anki reviews");
    expect(result.items[0]?.reason).toBe("Reviews first, while you are fresh");
  });

  it("numbers split work", () => {
    expect(draft([task("Thesis", 150)]).items.map((item) => item.title)).toEqual(["Thesis (1 of 2)", "Thesis (2 of 2)"]);
  });

  it("leaves out finished tasks", () => {
    const result = draft([task("Done already", 30, true)]);
    expect(result.isEmpty).toBe(true);
    expect(result.summary).toBe("Nothing to plan: no open tasks or reviews");
  });

  it("names what did not fit in the summary", () => {
    const busy = scheduleItem({ id: "offsite", title: "Offsite", start: at(9), end: at(18) });
    const one = draft([task("Write spec", 60)], { items: [busy] });
    expect(one.isEmpty).toBe(true);
    expect(one.summary).toBe("Write spec didn't fit: No free time left today");
    const two = draft([task("Write spec", 60), task("Inbox", 15)], { items: [busy] });
    expect(two.summary).toBe("2 tasks didn't fit: No free time left today");
    expect(two.unplacedDetail).toBe("Write spec, 1h: No free time left today\nInbox, 15 min: No free time left today");
    const partly = draft([task("Write spec", 60), task("Big", 120)], { now: at(16) });
    expect(partly.summary.endsWith(". 1 didn't fit")).toBe(true);
  });

  it("takes a skipped block off the offer", () => {
    const result = draft([task("Write spec", 60), task("Inbox", 15)]);
    const inbox = result.items.find((item) => item.title === "Inbox");
    expect(inbox).toBeDefined();
    result.skip(inbox?.id ?? "");
    expect(result.items.map((item) => item.title)).toEqual(["Write spec"]);
    expect(result.summary).toBe("1 block, 1h");
    result.skip("unknown");
    expect(result.items.length).toBe(1);
  });

  it("writes one or all blocks marked as planned", async () => {
    const result = draft([task("Write spec", 60), task("Inbox", 15)]);
    const writer = new RecordingWriter();
    const spec = result.items.find((item) => item.title === "Write spec");
    expect(spec).toBeDefined();
    await result.add(spec?.id, at(9), [], writer);
    expect(writer.written.map((event) => event.title)).toEqual(["Write spec"]);
    expect(writer.written[0]?.notes).toBe(PLANNED_EVENT_NOTE);
    expect(result.items.map((item) => item.title)).toEqual(["Inbox"]);
    expect(await result.add("unknown", at(9), [], writer)).toEqual([]);
    await result.add(undefined, at(9), [], writer);
    expect(writer.written.map((event) => event.title)).toEqual(["Write spec", "Inbox"]);
    expect(result.isSettled).toBe(true);
    expect(result.addedCount).toBe(2);
  });

  it("keeps the offer when a write fails", async () => {
    const result = draft([task("Write spec", 60)]);
    const writer = new RecordingWriter();
    writer.fails = true;
    await expect(result.add(undefined, at(9), [], writer)).rejects.toThrow("Denied");
    expect(result.items.length).toBe(1);
    expect(result.addedCount).toBe(0);
  });

  it("fills the demo afternoon with the demo tasks and leaves one over", () => {
    const date = at(20);
    const result = ScheduleDraft.plan(scheduleSampleNow(date, ZONE), scheduleSampleItems(date, ZONE), SCHEDULE_SAMPLE_TASKS, [], clock);
    expect(result.items.map((item) => item.title)).toEqual(["Review PR #142", "Reply to Priya", "Prep beta review notes"]);
    expect(result.items.every((item) => item.start >= at(15))).toBe(true);
    expect(result.unplaced.map((entry) => entry.work.title)).toEqual(["Outline the Q4 roadmap"]);
    expect(result.summary).toBe("3 blocks, 1h 30m. 1 didn't fit");
  });
});

describe("refine with Claude", () => {
  it("replaces the offer and explains the AI's blocks", async () => {
    const result = draft([task("Write spec", 60), task("Inbox", 15)]);
    expect(result.canRefine).toBe(true);
    result.refine([planBlock({ start: at(10), end: at(11), title: "Write spec" })]);
    expect(result.refinement).toBe("changed");
    expect(result.canRefine).toBe(false);
    const item = result.items[0];
    expect(result.items.length).toBe(1);
    expect(item?.kind).toBe("proposed");
    expect(item?.start).toBe(at(10));
    expect(item?.reason).toBe("Suggested by Claude");
    expect(result.summary).toBe("1 block, 1h");
    const writer = new RecordingWriter();
    await result.add(item?.id, at(9), [], writer);
    expect(writer.written.map((event) => event.start)).toEqual([at(10)]);
    expect(result.isSettled).toBe(true);
  });

  it("keeps the local reasons after an unchanged refinement", () => {
    const result = draft([task("Write spec", 60)]);
    const before = result.items;
    result.refine(result.proposal.pending);
    expect(result.refinement).toBe("unchanged");
    expect(result.items).toEqual(before);
    expect(result.canRefine).toBe(false);
  });

  it("no longer counts work the AI fits in as left out", () => {
    const result = draft([task("Write spec", 60), task("Big", 120)], { now: at(16) });
    const left = result.unplaced[0]?.work.title;
    expect(left).toBeDefined();
    result.refine([planBlock({ start: at(16), end: at(17), title: left ?? "" })]);
    expect(result.unplaced).toEqual([]);
    expect(result.summary.includes("didn't fit")).toBe(false);
  });

  it("gives the refine context the calendar and all the work", () => {
    const meeting = scheduleItem({ id: "standup", title: "Standup", start: at(9, 30), end: at(10) });
    const result = draft([task("Write spec", 60), task("Big", 120)], { now: at(16), items: [meeting] });
    const context = result.refineContext(at(16), [meeting, ...result.items], ZONE);
    expect(context.events.map((event) => event.id)).toEqual(["standup"]);
    expect(new Set(context.sharedWork)).toEqual(new Set(["Write spec", "Big"]));
    expect(context.tasks).toEqual([]);
  });

  it("does not refine week plans", () => {
    expect(weekDraft([task("Write spec", 60)]).canRefine).toBe(false);
  });
});

describe("week", () => {
  it("moves what today cannot hold to the next day", () => {
    const meeting = scheduleItem({ id: "review", title: "Design review", start: at(16, 30), end: at(18) });
    const result = weekDraft([task("Inbox", 15), task("Write spec", 60)], { now: at(16), items: [meeting] });
    expect(result.isWeek).toBe(true);
    /* 16:00 to 16:20 is all today has left before the meeting's buffer. */
    expect(result.items.map((item) => item.title)).toEqual(["Inbox", "Write spec"]);
    expect(result.items.map((item) => item.start)).toEqual([at(16), on(1, 9)]);
    expect(result.unplaced).toEqual([]);
    expect(result.summary).toBe("2 blocks over 2 days, 1h 15m");
  });

  it("keeps usual hours when planning late", () => {
    /* At 21:00 today's working day is over, so the work starts tomorrow at 9:00. */
    const result = weekDraft([task("Write spec", 60)], { now: at(21) });
    expect(result.items.map((item) => item.start)).toEqual([on(1, 9)]);
    expect(result.summary).toBe("1 block, 1h");
  });

  it("spreads long work across days", () => {
    /* The 6 h daily focus limit leaves 4 of the 10 h for the next day. */
    const busy = [0, 1, 2, 3, 4, 5, 6].map((day) =>
      scheduleItem({ id: `lunch-${day}`, title: "Lunch", start: on(day, 12), end: on(day, 13) }),
    );
    const result = weekDraft(
      [1, 2, 3, 4, 5].map((number) => task(`Project ${number}`, 120)),
      { items: busy },
    );
    const days = new Set(result.items.map((item) => startOfDay(item.start, ZONE)));
    expect(days).toEqual(new Set([DAY, on(1, 0)]));
    const clear = result.items.every((item) => busy.every((lunch) => item.end <= lunch.start - 600 || item.start >= lunch.end + 600));
    expect(clear).toBe(true);
    const workingHours = result.items.every((item) => {
      const start = wallTime(item.start, ZONE);
      const end = wallTime(item.end, ZONE);
      return start.hour >= 9 && (end.hour < 18 || (end.hour === 18 && end.minute === 0));
    });
    expect(workingHours).toBe(true);
    expect(result.unplaced).toEqual([]);
  });

  it("lists what no day could hold", () => {
    const busy = [0, 1, 2, 3, 4, 5, 6].map((day) =>
      scheduleItem({ id: `trip-${day}`, title: "Conference", start: on(day, 8), end: on(day, 19) }),
    );
    const result = weekDraft([task("Write spec", 60)], { items: busy });
    expect(result.isEmpty).toBe(true);
    expect(result.summary).toBe("Write spec didn't fit: No free time left this week");
  });

  it("adds blocks on every day marked as planned", async () => {
    const meeting = scheduleItem({ id: "review", title: "Design review", start: at(16, 30), end: at(18) });
    const result = weekDraft([task("Inbox", 15), task("Write spec", 60)], { now: at(16), items: [meeting] });
    const writer = new RecordingWriter();
    await result.add(undefined, at(16), [scheduleItemEvent(meeting)], writer);
    expect(writer.written.map((event) => event.start)).toEqual([at(16), on(1, 9)]);
    expect(writer.written.every((event) => event.notes === PLANNED_EVENT_NOTE)).toBe(true);
    expect(result.isSettled).toBe(true);
  });

  it("spreads the demo week's tasks over several days", () => {
    const date = at(20);
    const result = ScheduleDraft.planWeek(scheduleSampleNow(date, ZONE), scheduleSampleWeekItems(date, ZONE), SCHEDULE_SAMPLE_WEEK_TASKS, [], clock);
    const days = new Set(result.items.map((item) => startOfDay(item.start, ZONE)));
    expect(days.size).toBeGreaterThanOrEqual(2);
    expect(result.unplaced).toEqual([]);
    const titles = new Set(result.items.map((item) => item.title.split(" (")[0] ?? item.title));
    expect(titles).toEqual(new Set(SCHEDULE_SAMPLE_WEEK_TASKS.map((entry) => entry.title)));
  });
});
