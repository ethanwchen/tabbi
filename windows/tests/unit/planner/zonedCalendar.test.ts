import { describe, expect, it } from "vitest";
import {
  addingDays,
  clockText,
  daysInMonth,
  instantOf,
  isKnownTimeZone,
  isWeekend,
  minuteOfDay,
  settingTime,
  startOfDay,
  startOfHour,
  utcOffset,
  wallTime,
} from "../../../src/core/calendar/zonedCalendar";
import {
  addingDaysToKey,
  dayKeyStart,
  isPlannerDayKey,
  plannerDayKey,
  plannerDayKeyOf,
} from "../../../src/core/planner/plannerDayKey";

/* Seconds since 1970 of a UTC wall time. */
function utc(year: number, month: number, day: number, hour = 0, minute = 0): number {
  return Date.UTC(year, month - 1, day, hour, minute) / 1000;
}

const NEW_YORK = "America/New_York";

describe("zoned calendar", () => {
  it("reads wall-clock fields in the named zone, not the machine's", () => {
    const instant = utc(2026, 10, 15, 14, 30);
    expect(wallTime(instant, "UTC")).toMatchObject({ year: 2026, month: 10, day: 15, hour: 14, minute: 30, weekday: 5 });
    expect(wallTime(instant, NEW_YORK)).toMatchObject({ day: 15, hour: 10, minute: 30 });
    expect(wallTime(instant, "Asia/Tokyo")).toMatchObject({ day: 15, hour: 23 });
    expect(utcOffset(instant, "Asia/Kolkata")).toBe(5.5 * 3600);
  });

  it("finds midnight and wall times on ordinary days", () => {
    const instant = utc(2026, 10, 15, 14, 30);
    expect(startOfDay(instant, NEW_YORK)).toBe(utc(2026, 10, 15, 4));
    expect(settingTime(instant, 18, 0, 0, NEW_YORK)).toBe(utc(2026, 10, 15, 22));
    expect(clockText(instant, NEW_YORK)).toBe("10:30");
    expect(minuteOfDay(instant, NEW_YORK)).toBe(630);
  });

  it("resolves a time skipped by spring forward to the first moment after the jump", () => {
    /* 2026-03-08: New York jumps from 2:00 to 3:00. */
    const day = utc(2026, 3, 8, 12);
    expect(settingTime(day, 2, 30, 0, NEW_YORK)).toBe(utc(2026, 3, 8, 7));
    expect(settingTime(day, 3, 0, 0, NEW_YORK)).toBe(utc(2026, 3, 8, 7));
    expect(settingTime(day, 1, 59, 0, NEW_YORK)).toBe(utc(2026, 3, 8, 6, 59));
  });

  it("resolves a repeated fall-back time to its first occurrence", () => {
    /* 2026-11-01: New York repeats 1:00 to 2:00. */
    expect(settingTime(utc(2026, 11, 1, 12), 1, 30, 0, NEW_YORK)).toBe(utc(2026, 11, 1, 5, 30));
  });

  it("adds calendar days keeping the wall-clock time across a change", () => {
    const before = utc(2026, 3, 7, 14);
    expect(wallTime(addingDays(before, 1, NEW_YORK), NEW_YORK)).toMatchObject({ day: 8, hour: 9 });
    expect(addingDays(before, 1, NEW_YORK) - before).toBe(23 * 3600);
    expect(addingDays(utc(2026, 1, 31, 17), 1, NEW_YORK)).toBe(utc(2026, 2, 1, 17));
    expect(addingDays(utc(2026, 3, 1, 17), -1, NEW_YORK)).toBe(utc(2026, 2, 28, 17));
  });

  it("finds the start of the hour in half-hour zones", () => {
    expect(startOfHour(utc(2026, 10, 15, 10, 45), "Asia/Kolkata")).toBe(utc(2026, 10, 15, 10, 30));
    expect(startOfHour(utc(2026, 10, 15, 10, 45), "UTC")).toBe(utc(2026, 10, 15, 10));
  });

  it("rolls over out-of-range fields and counts month lengths", () => {
    expect(instantOf({ year: 2026, month: 13, day: 1 }, "UTC")).toBe(utc(2027, 1, 1));
    expect(daysInMonth(2028, 2)).toBe(29);
    expect(daysInMonth(2026, 2)).toBe(28);
  });

  it("knows weekends and zone names", () => {
    expect(isWeekend(utc(2026, 10, 17, 12), "UTC")).toBe(true);
    expect(isWeekend(utc(2026, 10, 16, 12), "UTC")).toBe(false);
    /* Friday 23:00 in Los Angeles is Saturday in Tokyo. */
    expect(isWeekend(utc(2026, 10, 17, 6), "Asia/Tokyo")).toBe(true);
    expect(isKnownTimeZone("Europe/Berlin")).toBe(true);
    expect(isKnownTimeZone("Pacific Standard Time")).toBe(false);
    expect(isKnownTimeZone("")).toBe(false);
  });
});

describe("PlannerDayKey", () => {
  it("accepts only real dates", () => {
    expect(isPlannerDayKey("2028-02-29")).toBe(true);
    expect(isPlannerDayKey("2026-02-29")).toBe(false);
    expect(isPlannerDayKey("2026-2-01")).toBe(false);
    expect(plannerDayKey("readme")).toBeUndefined();
  });

  it("names the day in the given zone and finds its midnight", () => {
    const instant = utc(2026, 10, 15, 3);
    expect(plannerDayKeyOf(instant, "UTC")).toBe("2026-10-15");
    expect(plannerDayKeyOf(instant, "America/Los_Angeles")).toBe("2026-10-14");
    expect(dayKeyStart("2026-10-15", "America/Los_Angeles")).toBe(utc(2026, 10, 15, 7));
  });

  it("steps across month and year ends", () => {
    expect(addingDaysToKey("2026-12-31", 1)).toBe("2027-01-01");
    expect(addingDaysToKey("2026-03-01", -1)).toBe("2026-02-28");
    expect(addingDaysToKey("2026-03-08", 1)).toBe("2026-03-09");
    expect(() => addingDaysToKey("nope", 1)).toThrow();
  });

  it("sorts chronologically as text", () => {
    expect(["2026-10-02", "2025-12-31", "2026-09-30"].sort()).toEqual(["2025-12-31", "2026-09-30", "2026-10-02"]);
  });
});
