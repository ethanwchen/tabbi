import { beforeAll, describe, expect, it } from "vitest";
import { instantOf } from "../../../src/core/calendar/zonedCalendar";
import {
  DAY_PLANNER_MODEL,
  DayPlanContext,
  DayPlanParseError,
  MAXIMUM_BLOCKS,
  dayEnd,
  dayPlanPrompt,
  dayPlanProposalBlocks,
  dayPlannerArguments,
  freeGaps,
  parseDayPlan,
  planBlock,
  validateDayPlan,
} from "../../../src/core/planner/dayPlan";
import { plannerItem } from "../../../src/core/planner/plannerDay";
import { viewedDayPlanStart } from "../../../src/core/planner/plannerViewedDay";
import { upcomingEvent, type UpcomingEvent } from "../../../src/core/planner/upcomingEvent";
import { switchLanguage } from "../../support/catalogs";

/* Port of DayPlannerTests: day end, free gaps, the prompt and flags, parsing and validation. */

const LA = "America/Los_Angeles";

/* 2026-10-01 at hour:minute Los Angeles time. */
function at(hour: number, minute = 0): number {
  return instantOf({ year: 2026, month: 10, day: 1, hour, minute }, LA);
}

function event(id: string, start: number, end: number, allDay = false): UpcomingEvent {
  return upcomingEvent({ id, title: id, start, end, isAllDay: allDay });
}

const taskA = plannerItem({ title: "Ship planner beta", createdAt: 0 });
const taskB = plannerItem({ title: "Write release notes", createdAt: 0 });
const doneTask = plannerItem({ title: "Done already", isDone: true, createdAt: 0 });

function context(now: number, events: UpcomingEvent[] = []): DayPlanContext {
  return new DayPlanContext({ now, events, tasks: [taskA, doneTask, taskB], timeZone: LA });
}

beforeAll(() => {
  switchLanguage("en");
});

describe("DayPlanner day end", () => {
  it("is 6 pm or two hours out, capped at 10 pm", () => {
    expect(dayEnd(at(9), LA)).toBe(at(18));
    expect(dayEnd(at(17), LA)).toBe(at(19));
    expect(dayEnd(at(21), LA)).toBe(at(22));
    expect(dayEnd(at(23), LA)).toBe(at(22));
  });

  it("follows the kit's end hour", () => {
    expect(dayEnd(at(9), LA, 21)).toBe(at(21));
    expect(dayEnd(at(20), LA, 21)).toBe(at(22));
    expect(dayEnd(at(9), LA, 23)).toBe(at(22));
    const evening = new DayPlanContext({ now: at(17), events: [], tasks: [], timeZone: LA, dayEndHour: 21 });
    expect(evening.gaps).toEqual([{ start: at(17), end: at(21) }]);
  });
});

describe("DayPlanner gaps", () => {
  it("skips events, all-day events and slivers", () => {
    const events = [
      event("standup", at(9, 50), at(10, 15)),
      event("holiday", at(0), at(23, 59), true),
      event("lunch", at(12), at(13)),
      event("overlapping", at(12, 30), at(13, 30)),
      event("sliver-maker", at(13, 40), at(14)),
    ];
    expect(freeGaps(events, at(9, 2), at(18))).toEqual([
      { start: at(9, 5), end: at(9, 50) },
      { start: at(10, 15), end: at(12) },
      { start: at(14), end: at(18) },
    ]);
  });

  it("handles an event in progress and a start past the end", () => {
    const events = [event("now", at(14), at(15)), event("evening", at(17, 30), at(19))];
    expect(freeGaps(events, at(14, 30), at(18))).toEqual([{ start: at(15), end: at(17, 30) }]);
    expect(freeGaps([], at(19), at(18))).toEqual([]);
  });

  it("drops finished tasks from the context and keys the rest", () => {
    const morning = context(at(9));
    expect(morning.taskKeys.map((entry) => entry.key)).toEqual(["t1", "t2"]);
    expect(morning.taskKeys.map((entry) => entry.task.id)).toEqual([taskA.id, taskB.id]);
    expect(morning.hasFreeTime).toBe(true);
    expect(context(at(22, 30)).hasFreeTime).toBe(false);
  });
});

describe("DayPlanner prompt and flags", () => {
  it("lists local times, events, gaps and tasks", () => {
    const prompt = dayPlanPrompt(context(at(13, 2), [event("Design review", at(15), at(15, 30))]));
    expect(prompt).toContain("It is now 13:02");
    expect(prompt).toContain("end by 18:00");
    expect(prompt).toContain("- 15:00-15:30 Design review");
    expect(prompt).toContain("- 13:05-15:00");
    expect(prompt).toContain("- 15:30-18:00");
    expect(prompt).toContain("- t1: Ship planner beta");
    expect(prompt).toContain("- t2: Write release notes");
    expect(prompt).not.toContain("Done already");
  });

  it("keys shared work after the checklist and never links it", () => {
    const shared = new DayPlanContext({
      now: at(9),
      events: [],
      tasks: [taskA, doneTask, taskB],
      sharedWork: ["Anki reviews (320 cards left)", "  "],
      timeZone: LA,
    });
    expect(shared.sharedWorkKeys.map((entry) => entry.key)).toEqual(["t3"]);
    expect(dayPlanPrompt(shared)).toContain("- t2: Write release notes\n- t3: Anki reviews (320 cards left)");
    const blocks = parseDayPlan('{"blocks":[{"start":"10:00","end":"11:00","title":"Anki reviews","task":"t3"}]}', shared);
    expect(blocks.map((block) => block.title)).toEqual(["Anki reviews"]);
    expect(blocks[0]?.linkedTaskID).toBeUndefined();
  });

  it("starts planning tomorrow at the working day and lands on that day", () => {
    /* 9 pm on Oct 1, planning Oct 2. */
    const start = viewedDayPlanStart("tomorrow", at(21), LA);
    const nine = instantOf({ year: 2026, month: 10, day: 2, hour: 9 }, LA);
    expect(start).toBe(nine);
    const meeting = event("Standup", nine + 3600, nine + 5400);
    const ahead = new DayPlanContext({ now: nine, events: [meeting], tasks: [taskA], timeZone: LA, isPlanningAhead: true });
    /* A full day, ending at 6 pm. */
    expect(ahead.dayEnd).toBe(nine + 9 * 3600);
    expect(ahead.gaps[0]).toEqual({ start: nine, end: meeting.start });

    const prompt = dayPlanPrompt(ahead);
    expect(prompt).toContain("day tomorrow, ahead of time. The day starts at 09:00");
    expect(prompt).not.toContain("It is now");
    expect(prompt).toContain("- 10:00-10:30 Standup");

    const blocks = dayPlanProposalBlocks('[{"start":"09:00","end":"09:45","title":"Ship","task":"t1"}]', ahead);
    /* HH:mm resolves on the planned day, not tonight. */
    expect(blocks[0]?.start).toBe(nine);
    expect(blocks[0]?.linkedTaskID).toBe(taskA.id);
  });

  it("says none for empty sections", () => {
    const prompt = dayPlanPrompt(new DayPlanContext({ now: at(23), events: [], tasks: [], timeZone: LA }));
    expect(prompt.split("- none").length - 1).toBe(3);
  });

  it("uses the fast model, no tools and a valid schema", () => {
    const args = dayPlannerArguments();
    expect(args[0]).toBe("--model");
    expect(args[1]).toBe(DAY_PLANNER_MODEL);
    const tools = args.indexOf("--tools");
    expect(tools).toBeGreaterThanOrEqual(0);
    expect(args[tools + 1]).toBe("");
    expect(args).toContain("--strict-mcp-config");
    const schemaIndex = args.indexOf("--json-schema");
    const schema = JSON.parse(args[schemaIndex + 1] ?? "") as { required: string[] };
    expect(schema.required).toEqual(["blocks"]);
  });
});

describe("DayPlanner parsing", () => {
  it("parses fenced JSON with prose and links tasks", () => {
    const text = [
      "Here's your plan:",
      "```json",
      '{"blocks": [',
      '  {"start": "13:30", "end": "14:30", "title": "Ship planner beta", "task": "t1"},',
      '  {"start": "9:05", "end": "9:45", "title": "  Inbox   zero ", "task": "t9"},',
      `  {"start": "15:00", "end": "15:30", "title": "Notes", "task": "${taskB.id}"}`,
      "]}",
      "```",
    ].join("\n");
    const blocks = parseDayPlan(text, context(at(9)));
    expect(blocks.map((block) => block.start)).toEqual([at(13, 30), at(9, 5), at(15)]);
    expect(blocks.map((block) => block.end)).toEqual([at(14, 30), at(9, 45), at(15, 30)]);
    expect(blocks.map((block) => block.title)).toEqual(["Ship planner beta", "Inbox zero", "Notes"]);
    expect(blocks.map((block) => block.linkedTaskID)).toEqual([taskA.id, undefined, taskB.id]);
  });

  it("accepts a bare array and skips malformed entries", () => {
    const text = `[{"start":"10:00","end":"11:00","title":"Good"},
     {"start":"11:00","end":"10:00","title":"Backwards"},
     {"start":"25:00","end":"26:00","title":"Bad hour"},
     {"start":"10:0","end":"11:00","title":"Bad minutes"},
     {"start":"12:00","end":"13:00","title":"   "},
     {"start":"12:00","end":"13:00"},
     "nonsense"]`;
    expect(parseDayPlan(text, context(at(9))).map((block) => block.title)).toEqual(["Good"]);
  });

  it("reads an object without blocks as empty and throws without JSON", () => {
    expect(parseDayPlan('{"plan": []}', context(at(9)))).toEqual([]);
    expect(() => parseDayPlan("Sorry, I can't help with that.", context(at(9)))).toThrow(DayPlanParseError);
    expect(() => parseDayPlan("{not json}", context(at(9)))).toThrow();
  });
});

describe("DayPlanner validation", () => {
  it("trims blocks overlapping events and the past", () => {
    const lunch = context(at(10, 7), [event("lunch", at(12), at(13))]);
    const blocks = [
      planBlock({ start: at(9), end: at(10, 45), title: "Starts in the past" }),
      planBlock({ start: at(11, 30), end: at(12, 30), title: "Runs into lunch" }),
      planBlock({ start: at(12, 10), end: at(12, 50), title: "Inside lunch" }),
      planBlock({ start: at(17, 30), end: at(19), title: "Past day end" }),
    ];
    const valid = validateDayPlan(blocks, lunch);
    expect(valid.map((block) => block.title)).toEqual(["Starts in the past", "Runs into lunch", "Past day end"]);
    expect(valid.map((block) => block.start)).toEqual([at(10, 10), at(11, 30), at(17, 30)]);
    expect(valid.map((block) => block.end)).toEqual([at(10, 45), at(12), at(18)]);
  });

  it("keeps the longest piece of a block spanning an event", () => {
    const call = context(at(9), [event("call", at(10), at(10, 30))]);
    const valid = validateDayPlan([planBlock({ start: at(9, 45), end: at(11, 30), title: "Deep work" })], call);
    expect(valid.map((block) => ({ start: block.start, end: block.end }))).toEqual([{ start: at(10, 30), end: at(11, 30) }]);
  });

  it("resolves overlaps between blocks and drops short ones", () => {
    const blocks = [
      planBlock({ start: at(11), end: at(12), title: "Second" }),
      planBlock({ start: at(10), end: at(11, 30), title: "First" }),
      planBlock({ start: at(11, 50), end: at(12, 10), title: "Squeezed" }),
      planBlock({ start: at(14), end: at(14, 10), title: "Too short" }),
    ];
    const valid = validateDayPlan(blocks, context(at(9)));
    expect(valid.map((block) => block.title)).toEqual(["First", "Second"]);
    expect(valid.map((block) => ({ start: block.start, end: block.end }))).toEqual([
      { start: at(10), end: at(11, 30) },
      { start: at(11, 30), end: at(12) },
    ]);
  });

  it("caps the block count", () => {
    const blocks = Array.from({ length: 10 }, (_, index) =>
      planBlock({
        start: at(9 + Math.trunc(index / 2), (index % 2) * 30),
        end: at(9 + Math.trunc(index / 2), (index % 2) * 30 + 25),
        title: String(index),
      }),
    );
    expect(validateDayPlan(blocks, context(at(9))).length).toBe(MAXIMUM_BLOCKS);
  });

  it("parses then validates a proposal", () => {
    const gym = context(at(16), [event("gym", at(17), at(18))]);
    const text =
      '{"blocks":[{"start":"16:00","end":"17:30","title":"Release notes","task":"t2"},{"start":"17:00","end":"17:45","title":"Gym clash"}]}';
    const proposal = dayPlanProposalBlocks(text, gym);
    expect(proposal.map((block) => block.title)).toEqual(["Release notes"]);
    expect(proposal[0] && { start: proposal[0].start, end: proposal[0].end }).toEqual({ start: at(16), end: at(17) });
    expect(proposal[0]?.linkedTaskID).toBe(taskB.id);
  });
});
