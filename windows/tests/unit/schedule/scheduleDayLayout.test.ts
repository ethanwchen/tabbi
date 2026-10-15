import { beforeAll, describe, expect, it } from "vitest";
import { addingDays } from "../../../src/core/calendar/zonedCalendar";
import { plannerDayKeyOf } from "../../../src/core/planner/plannerDayKey";
import { planBlock } from "../../../src/core/planner/dayPlan";
import { todayPlanSettings } from "../../../src/core/planner/todayPlanSettings";
import { upcomingEvent } from "../../../src/core/planner/upcomingEvent";
import {
  MAXIMUM_LANES,
  ScheduleDayLayout,
  scheduleDaySummary,
  scheduleDuration,
  scheduleItem,
  scheduleItemFromBlock,
  scheduleItemFromEvent,
  scheduleItemMinutes,
  scheduleItemTitle,
  scheduleRange,
  scheduleStatusText,
  type ScheduleItem,
  type ScheduleItemKind,
} from "../../../src/core/schedule/scheduleDay";
import { scheduleSampleItems, scheduleSampleNow, scheduleSampleYesterdayItems } from "../../../src/core/schedule/scheduleSampleData";
import { localSchedulePreferences } from "../../../src/core/schedule/todayLocalPlan";
import type { Instant } from "../../../src/core/time";
import { switchLanguage } from "../localization/catalogs";

/* Port of ScheduleDayLayoutTests, in UTC like the Swift suite. */

const ZONE = "UTC";
const LOCALE = "en-US";
const DAY = Date.UTC(2026, 9, 5) / 1000;

function at(hour: number, minute = 0): Instant {
  return DAY + (hour * 60 + minute) * 60;
}

function item(id: string, start: Instant, end: Instant, kind: ScheduleItemKind = "event", allDay = false): ScheduleItem {
  return scheduleItem({ id, title: id, start, end, kind, isAllDay: allDay });
}

function layout(items: ScheduleItem[], now: Instant = at(8)): ScheduleDayLayout {
  return new ScheduleDayLayout(DAY, now, items, ZONE);
}

beforeAll(() => {
  switchLanguage("en");
});

describe("schedule day layout", () => {
  it("spans the working hours on an empty day", () => {
    const result = layout([]);
    expect(result.range).toEqual({ start: at(9), end: at(18) });
    expect(result.hours.length).toBe(10);
    expect(result.hours[0]).toBe(at(9));
    expect(result.hours.at(-1)).toBe(at(18));
    expect(result.placed).toEqual([]);
    expect(result.freeMinutes).toBe(9 * 60);
  });

  it("stretches the range to whole hours around early and late items", () => {
    const result = layout([item("gym", at(7, 30), at(8, 15)), item("dinner", at(19), at(20, 10))]);
    expect(result.range).toEqual({ start: at(7), end: at(21) });
  });

  it("keeps the range inside the day", () => {
    const result = layout([item("overnight", at(-2), at(1)), item("late", at(23), at(25))]);
    expect(result.range).toEqual({ start: at(0), end: at(24) });
    expect(result.placed[0]?.x).toBe(0);
  });

  it("gives positions as fractions of the range", () => {
    const result = layout([item("standup", at(10, 30), at(11, 15))]);
    const placed = result.placed[0];
    expect(placed).toBeDefined();
    expect(Math.abs((placed?.x ?? 0) - 1.5 / 9)).toBeLessThan(1e-9);
    expect(Math.abs((placed?.width ?? 0) - 0.75 / 9)).toBeLessThan(1e-9);
    expect(result.position(at(13, 30))).toBe(0.5);
    expect(result.position(at(8))).toBeUndefined();
  });

  it("puts overlapping items in separate lanes", () => {
    const result = layout([
      item("a", at(10), at(11)),
      item("b", at(10, 30), at(11, 30)),
      item("c", at(11), at(12)),
      item("d", at(14), at(15)),
    ]);
    const lanes = Object.fromEntries(result.placed.map((placed) => [placed.item.id, [placed.lane, placed.lanes]]));
    expect(lanes.a).toEqual([0, 2]);
    expect(lanes.b).toEqual([1, 2]);
    /* "c" starts as "a" ends, so it reuses the first lane of the same group. */
    expect(lanes.c).toEqual([0, 2]);
    expect(lanes.d).toEqual([0, 1]);
  });

  it("stops lanes at the maximum", () => {
    const result = layout([0, 1, 2, 3, 4].map((index) => item(`e${index}`, at(10), at(11))));
    expect(result.placed.every((placed) => placed.lanes === MAXIMUM_LANES)).toBe(true);
    expect(Math.max(...result.placed.map((placed) => placed.lane))).toBe(MAXIMUM_LANES - 1);
  });

  it("runs labels over the free track until the next item in their row", () => {
    /* Day spans 9-18, so an hour is 1/9 of the width. */
    const result = layout([
      item("a", at(10), at(11)),
      item("b", at(10, 30), at(11, 30)),
      item("c", at(12), at(12, 30)),
      item("d", at(14), at(14, 30)),
      item("e", at(17), at(17, 30)),
    ]);
    const room = Object.fromEntries(result.placed.map((placed) => [placed.item.id, placed.labelWidth * 9]));
    expect(Math.abs((room.a ?? 0) - 2)).toBeLessThan(1e-9);
    expect(Math.abs((room.b ?? 0) - 1.5)).toBeLessThan(1e-9);
    expect(Math.abs((room.c ?? 0) - 2)).toBeLessThan(1e-9);
    expect(Math.abs((room.d ?? 0) - 3)).toBeLessThan(1e-9);
    /* The last item runs to the end of the timeline. */
    expect(Math.abs((room.e ?? 0) - 1)).toBeLessThan(1e-9);
  });

  it("never shrinks labels below their item", () => {
    const result = layout([0, 1, 2, 3].map((index) => item(`e${index}`, at(10), at(11))));
    expect(result.placed.every((placed) => placed.labelWidth >= placed.width)).toBe(true);
    /* Back-to-back items: the first label ends where the next item starts. */
    const row = layout([item("x", at(10), at(10, 30)), item("y", at(10, 30), at(11))]);
    expect(row.placed[0]?.labelWidth).toBe(row.placed[0]?.width);
  });

  it("keeps all-day items off the timeline and never blocks time with them", () => {
    const result = layout([item("holiday", at(0), at(24), "event", true)]);
    expect(result.placed).toEqual([]);
    expect(result.allDay.map((entry) => entry.id)).toEqual(["holiday"]);
    expect(result.freeMinutes).toBe(9 * 60);
  });

  it("keeps buffers and skips the past in free time", () => {
    /* 12:00 to 18:00 is 6 h; the meeting and 10 min either side take 80 min. */
    expect(layout([item("meeting", at(14), at(15))], at(12)).freeMinutes).toBe(6 * 60 - 80);
  });

  it("reports the item under way", () => {
    const result = layout([item("long", at(10), at(12)), item("short", at(10), at(11))]);
    const short = result.placed.find((placed) => placed.item.id === "short")?.item;
    expect(result.status(at(10, 30))).toEqual({ kind: "busy", item: short });
  });

  it("reports free time until the next item", () => {
    const next = item("lunch", at(12, 30), at(13, 30));
    const result = layout([next]);
    expect(result.status(at(11))).toEqual({ kind: "free", until: at(12, 30), next });
    expect(result.status(at(14))).toEqual({ kind: "free" });
    expect(result.status(at(18, 30))).toEqual({ kind: "dayOver" });
  });

  it("keeps the evening open with planning hours", () => {
    /* Plan my day stretches the day to two hours after now, so the layout does too. */
    const now = at(18, 10);
    const preferences = localSchedulePreferences(todayPlanSettings(), now, ZONE);
    const result = new ScheduleDayLayout(DAY, now, [], ZONE, preferences);
    expect(result.freeMinutes).toBe(120);
    expect(result.status(now)).toEqual({ kind: "free" });
  });

  it("makes a planned item from the planned marker in the notes", () => {
    const event = upcomingEvent({ id: "x", title: "Focus", start: at(10), end: at(11) });
    expect(scheduleItemFromEvent(event, "Planned with Tabbi").kind).toBe("planned");
    expect(scheduleItemFromEvent(event, "Agenda").kind).toBe("event");
    expect(scheduleItemFromEvent(event).kind).toBe("event");
  });

  it("keeps the reason of scheduled blocks", () => {
    const block = planBlock({ start: at(10), end: at(11), title: "Write" });
    const result = scheduleItemFromBlock({ block, workID: "w", reason: "Due by 12:00", part: 1, parts: 1 });
    expect(result.kind).toBe("planned");
    expect(result.reason).toBe("Due by 12:00");
    expect(scheduleItemMinutes(result)).toBe(60);
  });

  it("formats durations and status", () => {
    expect(scheduleDuration(45)).toBe("45 min");
    expect(scheduleDuration(120)).toBe("2h");
    expect(scheduleDuration(75)).toBe("1h 15m");
    expect(scheduleRange(at(10, 45), at(12), LOCALE, ZONE)).toBe("10:45-12:00");
    const lunch = item("Lunch", at(12, 30), at(13, 30));
    expect(scheduleStatusText({ kind: "free", until: lunch.start, next: lunch }, at(11, 20), LOCALE, ZONE)).toBe(
      "Free for 1h 10m, then Lunch at 12:30",
    );
    expect(scheduleStatusText({ kind: "busy", item: lunch }, at(13), LOCALE, ZONE)).toBe("Now: Lunch, until 1:30");
    expect(scheduleItemTitle(item("  ", at(9), at(10)))).toBe("Untitled event");
  });

  it("summarizes another day without a now", () => {
    const items = [
      item("Standup", at(10), at(10, 30)),
      item("Review", at(14), at(15)),
      item("Deck", at(9, 15), at(9, 45), "planned"),
      item("Offer", at(16), at(17), "proposed"),
      item("Holiday", DAY, at(24), "event", true),
    ];
    const result = layout(items);
    expect(result.eventCount).toBe(2);
    expect(result.plannedCount).toBe(1);
    /* A day still to come says when it starts; a proposed block isn't on the calendar yet. */
    expect(scheduleDaySummary(result, false, LOCALE, ZONE)).toBe("2 events, 1 planned block, the first at 9:15");
    expect(scheduleDaySummary(result, true, LOCALE, ZONE)).toBe("2 events, 1 planned block");
    expect(scheduleDaySummary(layout([item("Standup", at(10), at(10, 30))]), true, LOCALE, ZONE)).toBe("1 event");
    expect(scheduleDaySummary(layout([]), true, LOCALE, ZONE)).toBe("Nothing was on your calendar");
    expect(scheduleDaySummary(layout([item("Offer", at(16), at(17), "proposed")]), false, LOCALE, ZONE)).toBe(
      "Nothing on your calendar yet",
    );
  });

  it("shows the sample yesterday as a full day that is over", () => {
    const next = addingDays(DAY, 1, ZONE);
    const now = scheduleSampleNow(next, ZONE);
    const items = scheduleSampleYesterdayItems(next, ZONE);
    expect(items.length).toBeGreaterThan(0);
    expect(items.every((entry) => plannerDayKeyOf(entry.start, ZONE) === plannerDayKeyOf(DAY, ZONE) && entry.end <= next)).toBe(
      true,
    );
    expect(new Set(items.map((entry) => entry.id)).size).toBe(items.length);
    const result = new ScheduleDayLayout(DAY, now, items, ZONE);
    expect(result.freeMinutes).toBe(0);
    expect(result.status(now)).toEqual({ kind: "dayOver" });
    expect(result.eventCount > 0 && result.plannedCount > 0).toBe(true);
  });

  it("sees the sample day from late morning", () => {
    const now = scheduleSampleNow(DAY, ZONE);
    const items = scheduleSampleItems(DAY, ZONE);
    const result = new ScheduleDayLayout(DAY, now, items, ZONE);
    expect(now).toBe(at(11, 20));
    expect(items.some((entry) => entry.kind === "planned")).toBe(true);
    expect(result.allDay.length).toBe(1);
    expect(result.placed.some((placed) => placed.lanes === 2)).toBe(true);
    expect(result.status(now).kind).toBe("busy");
  });
});
