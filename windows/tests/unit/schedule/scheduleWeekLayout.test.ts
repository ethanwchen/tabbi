import { describe, expect, it } from "vitest";
import { isWeekend } from "../../../src/core/calendar/zonedCalendar";
import {
  ScheduleDayLayout,
  ScheduleWeekLayout,
  scheduleItem,
  weekDayEventCount,
  weekDayPlannedCount,
  type ScheduleItem,
  type ScheduleItemKind,
} from "../../../src/core/schedule/scheduleDay";
import { scheduleSampleNow, scheduleSampleWeekItems } from "../../../src/core/schedule/scheduleSampleData";
import type { Instant } from "../../../src/core/time";

/* Port of ScheduleWeekLayoutTests, in UTC like the Swift suite. */

const ZONE = "UTC";
/** Monday, October 5, 2026. */
const MONDAY = Date.UTC(2026, 9, 5) / 1000;

function at(day: number, hour: number, minute = 0): Instant {
  return MONDAY + ((day * 24 + hour) * 60 + minute) * 60;
}

function item(id: string, start: Instant, end: Instant, kind: ScheduleItemKind = "event", allDay = false): ScheduleItem {
  return scheduleItem({ id, title: id, start, end, kind, isAllDay: allDay });
}

function layout(items: ScheduleItem[], now: Instant = at(0, 8)): ScheduleWeekLayout {
  return new ScheduleWeekLayout(now, 7, items, ZONE);
}

describe("schedule week layout", () => {
  it("makes an empty week seven free working days from today", () => {
    const result = layout([]);
    expect(result.days.length).toBe(7);
    expect(result.days.map((day) => day.date)).toEqual([0, 1, 2, 3, 4, 5, 6].map((offset) => at(offset, 0)));
    expect(result.days.map((day) => day.isToday)).toEqual([true, false, false, false, false, false, false]);
    expect(result.startMinute).toBe(9 * 60);
    expect(result.endMinute).toBe(18 * 60);
    expect(result.hourMarks.length).toBe(10);
    expect(result.days.every((day) => day.freeMinutes === 9 * 60 && day.placed.length === 0)).toBe(true);
    expect(result.freeMinutes).toBe(7 * 9 * 60);
  });

  it("counts only the free time left today", () => {
    const result = layout([], at(0, 15));
    expect(result.days[0]?.freeMinutes).toBe(3 * 60);
    expect(result.days[1]?.freeMinutes).toBe(9 * 60);
    expect(result.freeMinutes).toBe(3 * 60 + 6 * 9 * 60);
  });

  it("gives every row the hours of the week's earliest and latest items", () => {
    const result = layout([item("gym", at(2, 7, 30), at(2, 8, 15)), item("dinner", at(4, 19), at(4, 20, 30))]);
    expect(result.startMinute).toBe(7 * 60);
    expect(result.endMinute).toBe(21 * 60);
    result.days.forEach((day, offset) => {
      expect(day.range).toEqual({ start: at(offset, 7), end: at(offset, 21) });
    });
    expect(result.positionOfMinute(14 * 60)).toBe(0.5);
  });

  it("puts items on their own day at the same clock position", () => {
    const result = layout([
      item("standup", at(0, 10), at(0, 10, 30)),
      item("standup-tue", at(1, 10), at(1, 10, 30)),
      item("deck", at(1, 13), at(1, 15), "planned"),
    ]);
    expect(result.days[0]?.placed.map((placed) => placed.item.id)).toEqual(["standup"]);
    expect(result.days[1]?.placed.map((placed) => placed.item.id)).toEqual(["standup-tue", "deck"]);
    expect(result.days[2]?.placed).toEqual([]);
    const monday = result.days[0]?.placed[0];
    const tuesday = result.days[1]?.placed[0];
    expect(monday?.x).toBe(tuesday?.x);
    expect(Math.abs((monday?.x ?? 0) - 1 / 9)).toBeLessThan(1e-9);
    const day = result.days[1];
    expect(day === undefined ? -1 : weekDayEventCount(day)).toBe(1);
    expect(day === undefined ? -1 : weekDayPlannedCount(day)).toBe(1);
  });

  it("keeps a buffer around each event in free time", () => {
    /* 9-18 is 540 min; a 60 min event plus a 10 min buffer each side. */
    const result = layout([item("review", at(3, 12), at(3, 13))]);
    expect(result.days[3]?.freeMinutes).toBe(540 - 80);
    expect(result.days[2]?.freeMinutes).toBe(540);
  });

  it("puts overlapping items in lanes", () => {
    const result = layout([item("a", at(1, 14), at(1, 15)), item("b", at(1, 14, 30), at(1, 15, 15))]);
    expect(result.days[1]?.placed.map((placed) => placed.lane)).toEqual([0, 1]);
    expect(result.days[1]?.placed.map((placed) => placed.lanes)).toEqual([2, 2]);
  });

  it("gives all-day items to their days and never blocks time with them", () => {
    const result = layout([item("trip", at(2, 0), at(4, 0), "event", true)]);
    expect(result.days.map((day) => day.allDay.map((entry) => entry.id))).toEqual([[], [], ["trip"], ["trip"], [], [], []]);
    expect(result.days[2]?.freeMinutes).toBe(9 * 60);
    expect(result.days[2]?.placed).toEqual([]);
  });

  it("runs the rows to midnight for late items", () => {
    const result = layout([item("flight", at(5, 22), at(6, 1))]);
    expect(result.endMinute).toBe(24 * 60);
    expect(result.days[5]?.placed.map((placed) => placed.item.id)).toEqual(["flight"]);
    /* The after-midnight part falls before the shared hours. */
    expect(result.days[6]?.placed).toEqual([]);
  });

  it("leaves out items outside the week", () => {
    const result = layout([item("last-week", at(-3, 10), at(-3, 11)), item("next-week", at(8, 10), at(8, 11))]);
    expect(result.days.flatMap((day) => day.placed)).toEqual([]);
    expect(result.startMinute).toBe(9 * 60);
  });

  it("keeps only a day's own all-day items in the day layout", () => {
    const items = [item("payday", at(0, 0), at(0, 24), "event", true), item("trip", at(2, 0), at(3, 0), "event", true)];
    const day = new ScheduleDayLayout(MONDAY, at(0, 8), items, ZONE);
    expect(day.allDay.map((entry) => entry.id)).toEqual(["payday"]);
  });

  it("keeps work off the weekend in the demo week", () => {
    const items = scheduleSampleWeekItems(MONDAY, ZONE);
    const result = new ScheduleWeekLayout(scheduleSampleNow(MONDAY, ZONE), 7, items, ZONE);
    expect(result.days.length).toBe(7);
    expect(result.days.filter((day) => day.placed.length > 0).length).toBe(7);
    const saturday = result.days[5];
    expect(saturday !== undefined && isWeekend(saturday.date, ZONE)).toBe(true);
    expect(saturday?.placed.some((placed) => placed.item.title === "Design standup")).toBe(false);
    expect(result.days[1]?.placed.some((placed) => placed.item.title === "Design standup")).toBe(true);
    const tuesday = result.days[1];
    expect(tuesday === undefined ? -1 : weekDayPlannedCount(tuesday)).toBe(1);
  });
});
