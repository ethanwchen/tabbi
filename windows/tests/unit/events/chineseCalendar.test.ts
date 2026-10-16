import { describe, expect, it } from "vitest";
import { chineseMidnight, newMoon } from "../../../src/core/events/chineseCalendar";

/* Local date of an instant in a fixed offset, as yyyy-MM-dd. */
function localDate(instant: number, offsetHours: number): string {
  return new Date((instant + offsetHours * 3600) * 1000).toISOString().slice(0, 10);
}

describe("chineseCalendar", () => {
  it("places new moons like Meeus' worked example", () => {
    /* Example 49.a: the new moon of k = -283 is JDE 2443192.65118 (February 1977). */
    const deltaT = 62.92 + 0.32217 * -23 + 0.005589 * 23 * 23;
    const jde = (newMoon(-283) + deltaT) / 86400 + 2440587.5;
    expect(Math.abs(jde - 2443192.65118)).toBeLessThan(0.0001);
  });

  it("finds Lunar New Year on the published days, where ICU's approximation is a day off", () => {
    const published: Record<number, string> = {
      2024: "2024-02-10",
      2025: "2025-01-29",
      2026: "2026-02-17",
      2027: "2027-02-06",
      2028: "2028-01-26",
      2030: "2030-02-03",
      2033: "2033-01-31",
      2034: "2034-02-19",
    };
    for (const [year, day] of Object.entries(published)) {
      const tokyo = chineseMidnight(1, 1, Date.UTC(Number(year), 0, 1) / 1000, "Asia/Tokyo");
      const york = chineseMidnight(1, 1, Date.UTC(Number(year), 0, 1) / 1000, "America/New_York");
      expect(tokyo === undefined ? undefined : localDate(tokyo, 9), year).toBe(day);
      expect(york === undefined ? undefined : localDate(york, -5), year).toBe(day);
    }
  });

  it("agrees with every official Lunar New Year from 2020 to 2050", () => {
    /* The Hong Kong Observatory's dates; ICU 76 alone gets 2027 (7 February) and 2030 (2 February) wrong. */
    const official: Record<number, string> = {
      2020: "01-25", 2021: "02-12", 2022: "02-01", 2023: "01-22", 2024: "02-10", 2025: "01-29", 2026: "02-17",
      2027: "02-06", 2028: "01-26", 2029: "02-13", 2030: "02-03", 2031: "01-23", 2032: "02-11", 2033: "01-31",
      2034: "02-19", 2035: "02-08", 2036: "01-28", 2037: "02-15", 2038: "02-04", 2039: "01-24", 2040: "02-12",
      2041: "02-01", 2042: "01-22", 2043: "02-10", 2044: "01-30", 2045: "02-17", 2046: "02-06", 2047: "01-26",
      2048: "02-14", 2049: "02-02", 2050: "01-23",
    };
    for (const [year, day] of Object.entries(official)) {
      const start = chineseMidnight(1, 1, Date.UTC(Number(year), 0, 1) / 1000, "UTC");
      expect(start === undefined ? undefined : localDate(start, 0), year).toBe(`${year}-${day}`);
    }
  });

  it("searches backward for the last match before a moment", () => {
    const before = chineseMidnight(1, 15, Date.UTC(2027, 5, 1) / 1000, "Asia/Tokyo", true);
    expect(before === undefined ? undefined : localDate(before, 9)).toBe("2027-02-20");
  });
});
