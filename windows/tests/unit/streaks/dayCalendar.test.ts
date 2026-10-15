import { describe, expect, it } from "vitest";
import {
  addDays,
  dayKey,
  daysBetween,
  hourOf,
  nextDateMatching,
  parseDayKey,
  startOfDay,
  wallClock,
  weekStart,
  weekday,
  zonedInstant,
  type DayCalendar,
} from "../../../src/core/streaks/dayCalendar";

const newYork: DayCalendar = { timeZone: "America/New_York", firstWeekday: 1 };
const NY = "America/New_York";

describe("zonedInstant", () => {
  it("names the instant of a wall-clock time in a zone", () => {
    // Noon on October 14, 2026 in New York (EDT, UTC-4) is 16:00 UTC.
    expect(zonedInstant(2026, 10, 14, 12, 0, 0, NY)).toBe(Date.UTC(2026, 9, 14, 16) / 1000);
    expect(zonedInstant(2026, 1, 14, 12, 0, 0, NY)).toBe(Date.UTC(2026, 0, 14, 17) / 1000);
    expect(zonedInstant(2026, 10, 14, 12, 0, 0, "Asia/Tokyo")).toBe(Date.UTC(2026, 9, 14, 3) / 1000);
  });

  it("moves a time skipped by spring forward to the end of the gap", () => {
    // 2:30 does not exist on March 8, 2026 in New York; clocks jump from 2:00 to 3:00.
    const instant = zonedInstant(2026, 3, 8, 2, 30, 0, NY);
    expect(instant).toBe(Date.UTC(2026, 2, 8, 7) / 1000);
    const wall = wallClock(instant, NY);
    expect([wall.day, wall.hour, wall.minute]).toEqual([8, 3, 0]);
  });

  it("takes the first of a time that happens twice when clocks fall back", () => {
    // 1:30 happens twice on November 1, 2026 in New York; the first is EDT.
    expect(zonedInstant(2026, 11, 1, 1, 30, 0, NY)).toBe(Date.UTC(2026, 10, 1, 5, 30) / 1000);
    expect(zonedInstant(2026, 11, 2, 19, 0, 0, NY) - zonedInstant(2026, 11, 1, 19, 0, 0, NY)).toBe(86400);
    expect(zonedInstant(2026, 11, 1, 19, 0, 0, NY) - zonedInstant(2026, 10, 31, 19, 0, 0, NY)).toBe(25 * 3600);
  });
});

describe("day keys", () => {
  it("are the local day of an instant", () => {
    const lateInNewYork = zonedInstant(2026, 10, 14, 23, 30, 0, NY);
    expect(dayKey(lateInNewYork, newYork)).toBe("2026-10-14");
    expect(dayKey(lateInNewYork, { timeZone: "Asia/Tokyo", firstWeekday: 1 })).toBe("2026-10-15");
    expect(startOfDay("2026-10-14", newYork)).toBe(zonedInstant(2026, 10, 14, 0, 0, 0, NY));
    expect(hourOf(lateInNewYork, NY)).toBe(23);
  });

  it("accept only real dates", () => {
    expect(parseDayKey("2026-02-28")).toBe("2026-02-28");
    expect(parseDayKey("2026-02-30")).toBeUndefined();
    expect(parseDayKey("2026-2-3")).toBeUndefined();
  });

  it("add days across month and year ends", () => {
    expect(addDays("2026-01-31", 1)).toBe("2026-02-01");
    expect(addDays("2026-03-01", -1)).toBe("2026-02-28");
    expect(addDays("2024-02-28", 1)).toBe("2024-02-29");
    expect(addDays("2026-12-31", 1)).toBe("2027-01-01");
    expect(addDays("2026-10-31", 2)).toBe("2026-11-02");
    expect(daysBetween("2026-10-30", "2026-11-03")).toBe(4);
  });

  it("start their week on the calendar's first weekday", () => {
    // Wednesday, October 14, 2026.
    expect(weekday("2026-10-14")).toBe(4);
    expect(weekStart("2026-10-14", { timeZone: NY, firstWeekday: 1 })).toBe("2026-10-11");
    expect(weekStart("2026-10-14", { timeZone: NY, firstWeekday: 2 })).toBe("2026-10-12");
    expect(weekStart("2026-10-11", { timeZone: NY, firstWeekday: 2 })).toBe("2026-10-05");
    expect(weekStart("2026-10-11", { timeZone: NY, firstWeekday: 1 })).toBe("2026-10-11");
  });
});

describe("nextDateMatching", () => {
  it("is strictly after the given moment", () => {
    const nine = zonedInstant(2026, 10, 14, 9, 0, 0, NY);
    expect(nextDateMatching(nine, 19, 0, newYork)).toBe(zonedInstant(2026, 10, 14, 19, 0, 0, NY));
    const seven = zonedInstant(2026, 10, 14, 19, 0, 0, NY);
    expect(nextDateMatching(seven, 19, 0, newYork)).toBe(zonedInstant(2026, 10, 15, 19, 0, 0, NY));
  });

  it("keeps the wall-clock time across daylight saving and fills a skipped hour", () => {
    const evening = zonedInstant(2026, 10, 31, 20, 0, 0, NY);
    const fire = nextDateMatching(evening, 19, 0, newYork);
    expect(wallClock(fire, NY).hour).toBe(19);
    expect(wallClock(fire, NY).day).toBe(1);
    const gap = nextDateMatching(startOfDay("2026-03-08", newYork), 2, 30, newYork);
    expect([wallClock(gap, NY).day, wallClock(gap, NY).hour]).toEqual([8, 3]);
  });
});
