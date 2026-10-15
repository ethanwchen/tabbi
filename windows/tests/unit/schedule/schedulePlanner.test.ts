import { beforeAll, describe, expect, it } from "vitest";
import { instantOf } from "../../../src/core/calendar/zonedCalendar";
import type { DateInterval } from "../../../src/core/planner/dateInterval";
import { plannerItem } from "../../../src/core/planner/plannerDay";
import { upcomingEvent, type UpcomingEvent } from "../../../src/core/planner/upcomingEvent";
import {
  clockTime,
  planFocusMinutes,
  planProposal,
  planScheduleDay,
  planScheduleWeek,
  reviewScheduleWork,
  scheduleFreeTime,
  schedulePreferences,
  schedulePreferencesForMethod,
  scheduleWork,
  taskScheduleWork,
  type SchedulePlan,
  type SchedulePreferences,
  type SchedulePriority,
  type ScheduleWork,
} from "../../../src/core/schedule/schedulePlanner";
import { StudyMethod } from "../../../src/core/studyMethods/studyMethod";
import type { Instant } from "../../../src/core/time";
import { switchLanguage } from "../localization/catalogs";

/* Port of SchedulePlannerTests. */

const ZONE = "America/Los_Angeles";
const clock = { timeZone: ZONE, locale: "en-US" };

/** 2026-10-05 (a Monday) plus `day` days, at `hour:minute` Los Angeles time. */
function at(hour: number, minute = 0, day = 0): Instant {
  return instantOf({ year: 2026, month: 10, day: 5 + day, hour, minute }, ZONE);
}

function event(id: string, start: Instant, end: Instant, allDay = false): UpcomingEvent {
  return upcomingEvent({ id, title: id, start, end, isAllDay: allDay });
}

function task(title: string, minutes?: number, priority: SchedulePriority = "normal", due?: Instant): ScheduleWork {
  return scheduleWork({ id: title, title, estimatedMinutes: minutes, priority, due });
}

function plan(
  now: Instant,
  work: ScheduleWork[],
  events: UpcomingEvent[] = [],
  preferences: SchedulePreferences = schedulePreferences(),
): SchedulePlan {
  return planScheduleDay(now, events, work, clock, preferences);
}

function lengths(result: SchedulePlan): number[] {
  return result.blocks.map((entry) => Math.trunc((entry.block.end - entry.block.start) / 60));
}

/** Blocks never overlap each other or a buffered event, never start before `now`, and stay inside working hours. */
function assertSound(
  result: SchedulePlan,
  now: Instant,
  events: UpcomingEvent[],
  preferences: SchedulePreferences = schedulePreferences(),
): void {
  const blocks = result.blocks.map((entry) => entry.block);
  for (let index = 0; index + 1 < blocks.length; index++) {
    expect(blocks[index]?.end ?? 0).toBeLessThanOrEqual(blocks[index + 1]?.start ?? 0);
  }
  const buffer = preferences.eventBufferMinutes * 60;
  for (const block of blocks) {
    expect(block.start).toBeGreaterThanOrEqual(now);
    expect(block.start).toBeGreaterThanOrEqual(clockTime(preferences.workdayStartMinute, result.day, ZONE));
    expect(block.end).toBeLessThanOrEqual(clockTime(preferences.workdayEndMinute, result.day, ZONE));
    expect(block.end - block.start).toBeGreaterThanOrEqual(15 * 60);
    for (const entry of events) {
      if (entry.isAllDay) continue;
      expect(block.start < entry.end + buffer && entry.start - buffer < block.end).toBe(false);
    }
  }
}

function span(start: Instant, end: Instant): DateInterval {
  return { start, end };
}

beforeAll(() => {
  switchLanguage("en");
});

describe("free time", () => {
  it("respects working hours, buffers and all-day events", () => {
    const events = [event("Standup", at(10), at(10, 30)), event("Holiday", at(0), at(23, 59), true)];
    expect(scheduleFreeTime(at(0), at(7), events, ZONE)).toEqual([span(at(9), at(9, 50)), span(at(10, 40), at(18))]);
  });

  it("keeps clock hours on a daylight saving change", () => {
    /* Clocks go back at 2:00 on 2026-11-01 in Los Angeles. */
    expect(scheduleFreeTime(at(0, 0, 27), at(7, 0, 27), [], ZONE)).toEqual([span(at(9, 0, 27), at(18, 0, 27))]);
  });

  it("starts on the next slot after now", () => {
    expect(scheduleFreeTime(at(0), at(14, 2), [], ZONE)[0]?.start).toBe(at(14, 5));
  });

  it("is empty after hours", () => {
    expect(scheduleFreeTime(at(0), at(19), [], ZONE)).toEqual([]);
    const result = plan(at(19), [task("Email")]);
    expect(result.blocks).toEqual([]);
    expect(result.unplaced.map((entry) => entry.reason)).toEqual(["No free time left today"]);
  });

  it("drops slivers too short for a block", () => {
    /* 9:00 to 9:20 minus a 10 min buffer before the meeting leaves 10 min. */
    const events = [event("Sync", at(9, 20), at(17))];
    expect(scheduleFreeTime(at(0), at(8), events, ZONE)).toEqual([span(at(17, 10), at(18))]);
  });
});

describe("overlaps and buffers", () => {
  it("never overlaps events and keeps their buffer", () => {
    const events = [event("Standup", at(9, 30), at(9, 45)), event("Lunch", at(12), at(13)), event("1:1", at(14), at(14, 30))];
    const work = [task("Design review", 90), task("Write spec", 120), task("Inbox", 30), task("Bugs", 60)];
    const result = plan(at(8), work, events);
    assertSound(result, at(8), events);
    expect(result.blocks.length).toBeGreaterThan(0);
    /* The first block waits for the buffer after standup since 9:00-9:20 is too short. */
    expect(result.blocks[0]?.block.start).toBe(at(9, 55));
  });

  it("packs right up to events with no buffer", () => {
    const result = plan(at(9), [task("Report", 60)], [event("Meeting", at(10), at(11))], schedulePreferences({ eventBufferMinutes: 0 }));
    expect(result.blocks.map((entry) => entry.block.start)).toEqual([at(9)]);
    expect(result.blocks[0]?.block.end).toBe(at(10));
  });

  it("waits for an event in progress plus its buffer", () => {
    const result = plan(at(14), [task("Notes", 30)], [event("Workshop", at(13), at(15))]);
    expect(result.blocks[0]?.block.start).toBe(at(15, 10));
  });

  it("plans nothing in the past", () => {
    const result = plan(at(11, 7), [task("A", 30), task("B", 30)]);
    assertSound(result, at(11, 7), []);
    expect(result.blocks[0]?.block.start).toBe(at(11, 10));
  });
});

describe("breaks", () => {
  it("separate consecutive blocks", () => {
    const result = plan(at(9), [task("A", 30), task("B", 30), task("C", 30)]);
    expect(result.blocks.map((entry) => entry.block.start)).toEqual([at(9), at(9, 35), at(10, 10)]);
    expect(result.breaks).toEqual([span(at(9, 30), at(9, 35)), span(at(10, 5), at(10, 10))]);
  });

  it("make every fourth one long", () => {
    const work = [1, 2, 3, 4, 5].map((number) => task(`Task ${number}`, 25));
    expect(plan(at(9), work).breaks.map((rest) => Math.trunc((rest.end - rest.start) / 60))).toEqual([5, 5, 5, 15]);
  });

  it("are not shown across an event", () => {
    const result = plan(
      at(9),
      [task("A", 60), task("B", 60)],
      [event("Meeting", at(10), at(11))],
      schedulePreferences({ eventBufferMinutes: 0 }),
    );
    expect(result.blocks.map((entry) => entry.block.start)).toEqual([at(9), at(11)]);
    expect(result.breaks).toEqual([]);
  });
});

describe("ordering", () => {
  it("puts higher priority first and keeps list order for ties", () => {
    const work = [task("Low", 30, "low"), task("First", 30), task("Urgent", 30, "high"), task("Second", 30)];
    const result = plan(at(9), work);
    expect(result.blocks.map((entry) => entry.block.title)).toEqual(["Urgent", "First", "Second", "Low"]);
    expect(result.blocks.map((entry) => entry.reason)).toEqual([
      "High priority",
      "Next on your list",
      "Next on your list",
      "Low priority, after the rest",
    ]);
  });

  it("puts time-sensitive work first and finishes it before its due time", () => {
    const work = [task("Big project", 90, "high"), task("Submit form", 30, "normal", at(11)), task("Pay invoice", 15, "normal", at(10))];
    const result = plan(at(9), work);
    expect(result.blocks.slice(0, 2).map((entry) => entry.block.title)).toEqual(["Pay invoice", "Submit form"]);
    const form = result.blocks.find((entry) => entry.workID === "Submit form");
    expect(form?.block.end ?? Infinity).toBeLessThanOrEqual(at(11));
    expect(form?.reason).toBe("Due by 11:00");
  });

  it("lists work that cannot meet its due time with the reason", () => {
    const result = plan(at(8), [task("Prep slides", 60, "normal", at(11))], [event("Offsite", at(9), at(12))]);
    expect(result.blocks).toEqual([]);
    expect(result.unplaced[0]?.reason).toBe("No free time before 11:00");
    expect(result.unplaced[0]?.minutes).toBe(60);
  });

  it("puts reviews first by default and last when asked", () => {
    const reviews = reviewScheduleWork({ title: "Anki reviews", minutes: 40 }, "anki");
    const work = [task("Pharm", 50), reviews];
    const early = plan(at(9), work);
    expect(early.blocks[0]?.block.kind).toBe("reviews");
    expect(early.blocks[0]?.reason).toBe("Reviews first, while you are fresh");
    const late = plan(at(9), work, [], schedulePreferences({ reviewsFirst: false }));
    expect(late.blocks.map((entry) => entry.block.title)).toEqual(["Pharm", "Anki reviews"]);
  });

  it("gives tasks without an estimate the default length", () => {
    expect(plan(at(9), [task("Call bank")]).blocks[0]?.block.end).toBe(at(9, 30));
  });

  it("links checklist items to their blocks", () => {
    const item = plannerItem({ title: "  Draft   notes ", createdAt: at(8) });
    const result = plan(at(9), [taskScheduleWork(item)]);
    expect(result.blocks[0]?.block.linkedTaskID).toBe(item.id);
    expect(result.blocks[0]?.block.title).toBe("Draft notes");
  });

  it("ignores blank titles", () => {
    expect(plan(at(9), [task("   ", 30)])).toEqual(plan(at(9), []));
  });
});

describe("splitting and limits", () => {
  it("splits long work into numbered parts", () => {
    const result = plan(at(9), [task("Thesis", 150)]);
    expect(lengths(result)).toEqual([90, 60]);
    expect(result.blocks.map((entry) => entry.part)).toEqual([1, 2]);
    expect(result.blocks.map((entry) => entry.parts)).toEqual([2, 2]);
  });

  it("splits work just over the longest block without a sliver", () => {
    for (const [minutes, expected] of [
      [95, [80, 15]],
      [100, [85, 15]],
    ] as const) {
      const result = plan(at(9), [task("Thesis", minutes)]);
      expect(lengths(result)).toEqual(expected);
      expect(result.unplaced).toEqual([]);
    }
  });

  it("fits work whole in a later gap before splitting it", () => {
    const result = plan(at(9), [task("Refactor", 60)], [event("Standup", at(10), at(10, 30))]);
    expect(result.blocks.map((entry) => entry.block.start)).toEqual([at(10, 40)]);
  });

  it("splits across gaps without leaving a sliver", () => {
    /* Free 9:00-9:50 and 10:40-11:20 only. 60 min of work: 45 and 15, not 50 and 10. */
    const events = [event("Standup", at(10), at(10, 30)), event("Offsite", at(11, 30), at(18))];
    const result = plan(at(9), [task("Refactor", 60)], events);
    expect(result.blocks.map((entry) => entry.block.start)).toEqual([at(9), at(10, 40)]);
    expect(lengths(result)).toEqual([45, 15]);
  });

  it("caps the day at the focus limit and lists the rest", () => {
    const result = plan(at(9), [task("A", 90), task("B", 60)], [], schedulePreferences({ maximumFocusMinutes: 120 }));
    expect(planFocusMinutes(result)).toBe(120);
    expect(result.unplaced.map((entry) => entry.minutes)).toEqual([30]);
    expect(result.unplaced[0]?.reason).toBe("Over your 2h focus limit");
  });

  it("lists what did not fit", () => {
    const preferences = schedulePreferences({ workdayStartMinute: 16 * 60, workdayEndMinute: 17 * 60 });
    const result = plan(at(9), [task("A", 45), task("B", 45)], [], preferences);
    expect(result.blocks.map((entry) => entry.block.title)).toEqual(["A"]);
    expect(result.unplaced.map((entry) => entry.work.title)).toEqual(["B"]);
    expect(result.unplaced[0]?.reason).toBe("No free time left today");
  });

  it("follows custom working hours", () => {
    const preferences = schedulePreferences({ workdayStartMinute: 7 * 60 + 30, workdayEndMinute: 12 * 60 });
    const result = plan(at(6), [task("Run", 30)], [], preferences);
    expect(result.blocks[0]?.block.start).toBe(at(7, 30));
    assertSound(result, at(6), [], preferences);
  });

  it("clamps nonsense preferences", () => {
    const preferences = schedulePreferences({
      workdayStartMinute: -50,
      workdayEndMinute: -10,
      defaultTaskMinutes: 1,
      maximumBlockMinutes: 0,
      breakMinutes: -5,
      maximumFocusMinutes: 0,
    });
    expect(preferences.workdayStartMinute).toBe(0);
    expect(preferences.workdayEndMinute).toBeGreaterThan(preferences.workdayStartMinute);
    expect(preferences.defaultTaskMinutes).toBe(15);
    expect(preferences.maximumBlockMinutes).toBe(15);
    expect(preferences.breakMinutes).toBe(0);
    expect(preferences.maximumFocusMinutes).toBe(15);
  });

  it("takes block and break lengths from the study method", () => {
    const preferences = schedulePreferencesForMethod(StudyMethod.pomodoro);
    expect(preferences.defaultTaskMinutes).toBe(25);
    expect(preferences.breakMinutes).toBe(5);
  });
});

describe("a realistic day", () => {
  it("is sound and deterministic", () => {
    const events = [
      event("Standup", at(9, 30), at(9, 45)),
      event("Lunch", at(12), at(13)),
      event("Design crit", at(15), at(16)),
      event("Exam week", at(0), at(23, 59), true),
    ];
    const work = [
      reviewScheduleWork({ title: "Anki reviews", minutes: 30 }, "anki"),
      task("Write spec", 120, "high"),
      task("Inbox", 20),
      task("Expense report", 30, "normal", at(14)),
      task("Read paper", 60, "low"),
    ];
    const first = plan(at(8, 50), work, events);
    const second = plan(at(8, 50), work, events);
    expect(first.blocks.map((entry) => entry.block.title)).toEqual(second.blocks.map((entry) => entry.block.title));
    expect(first.blocks.map((entry) => entry.block.start)).toEqual(second.blocks.map((entry) => entry.block.start));
    assertSound(first, at(8, 50), events);
    /* Inbox fills the short gap before standup; reviews take the first gap that holds them. */
    expect(first.blocks[0]?.block.title).toBe("Inbox");
    expect(first.blocks.find((entry) => entry.block.kind === "reviews")?.block.start).toBe(at(9, 55));
    expect(first.unplaced).toEqual([]);
    expect(planProposal(first).pending.length).toBe(first.blocks.length);
  });
});

describe("week", () => {
  it("spreads leftovers over the following days", () => {
    const week = planScheduleWeek(at(9), 3, [], [task("A", 120), task("B", 120), task("C", 60)], clock, schedulePreferences({ maximumFocusMinutes: 120 }));
    expect(week.days.length).toBe(3);
    expect(week.days.map(planFocusMinutes)).toEqual([120, 120, 60]);
    expect(week.days[1]?.blocks[0]?.block.start).toBe(at(9, 0, 1));
    expect(week.unplaced).toEqual([]);
    expect(week.days.every((day) => day.unplaced.length === 0)).toBe(true);
  });

  it("respects each day's events and lists what never fit", () => {
    const events = [event("Conference", at(8, 0, 1), at(19, 0, 1))];
    const week = planScheduleWeek(at(9), 2, events, [task("A", 60), task("B", 60), task("C", 60)], clock, schedulePreferences({ maximumFocusMinutes: 60 }));
    expect(week.days.map((day) => day.blocks.map((entry) => entry.block.title))).toEqual([["A"], []]);
    expect(week.unplaced.map((entry) => entry.work.title)).toEqual(["B", "C"]);
    expect(week.unplaced[0]?.reason).toBe("No free time left this week");
  });

  it("keeps due work before its due day", () => {
    const week = planScheduleWeek(at(9), 3, [event("Busy", at(9), at(18))], [task("Tax form", 30, "normal", at(12, 0, 1))], clock);
    expect(week.days[1]?.blocks[0]?.block.start).toBe(at(9, 0, 1));
    expect(week.days[1]?.blocks[0]?.block.end ?? Infinity).toBeLessThanOrEqual(at(12, 0, 1));
  });
});

describe("already on the calendar", () => {
  it("does not plan work already on today's calendar again", () => {
    /* Added from an earlier plan this morning, so it's past but done for today. */
    const events = [event("Write the spec", at(9), at(10)), event("Standup", at(10), at(10, 30)), event("Gym", at(0), at(0), true)];
    const result = plan(at(11), [task("write  the SPEC", 60), task("Email Ana", 30), task("Gym", 30)], events);
    expect(result.blocks.map((entry) => entry.block.title)).toEqual(["Email Ana", "Gym"]);
    expect(result.unplaced).toEqual([]);
  });

  it("keeps today's work when the event is on another day", () => {
    const result = plan(at(9), [task("Write the spec", 60)], [event("Write the spec", at(9, 0, 1), at(10, 0, 1))]);
    expect(result.blocks.map((entry) => entry.block.title)).toEqual(["Write the spec"]);
  });

  it("skips work booked later in the week", () => {
    const events = [event("Write the spec", at(14, 0, 3), at(15, 0, 3))];
    const work = [task("Write the spec", 60), task("Email Ana", 30)];
    const titles = (days: number) =>
      planScheduleWeek(at(9), days, events, work, clock).days.flatMap((day) => day.blocks.map((entry) => entry.block.title));
    expect(titles(7)).toEqual(["Email Ana"]);
    expect(titles(2)).toEqual(["Write the spec", "Email Ana"]);
  });
});
