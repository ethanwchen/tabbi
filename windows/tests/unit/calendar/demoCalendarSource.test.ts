import { describe, expect, it } from "vitest";
import { DemoCalendarSource } from "../../../src/core/calendar/demoCalendarSource";

function utc(year: number, month: number, day: number, hour = 0, minute = 0): number {
  return Date.UTC(year, month - 1, day, hour, minute) / 1000;
}

describe("DemoCalendarSource", () => {
  const now = utc(2026, 10, 15, 17, 2);
  const source = new DemoCalendarSource({ now: () => now, timeZone: () => "America/Los_Angeles" });

  it("lists today's samples around now", async () => {
    const today = await source.events(utc(2026, 10, 15, 7), utc(2026, 10, 16, 7));
    expect(today.map((event) => event.id)).toEqual(["demo-study-group", "demo-review", "demo-yoga"]);
    expect(today[0]?.start).toBe(utc(2026, 10, 15, 16, 50));
  });

  it("lists yesterday and tomorrow at fixed local hours", async () => {
    const yesterday = await source.events(utc(2026, 10, 14, 7), utc(2026, 10, 15, 7));
    expect(yesterday.map((event) => event.id)).toEqual(["demo-yesterday-lecture", "demo-yesterday-lunch", "demo-yesterday-review"]);
    expect(yesterday[0]?.start).toBe(utc(2026, 10, 14, 16, 30));
    const tomorrow = await source.events(utc(2026, 10, 16, 7), utc(2026, 10, 17, 7));
    expect(tomorrow.map((event) => event.id)).toEqual(["demo-tomorrow-lecture", "demo-tomorrow-gym"]);
  });

  it("follows the kit's sample day and reports one healthy feed", async () => {
    const medicine = new DemoCalendarSource({ now: () => now, timeZone: () => "America/Los_Angeles", kind: "medicine" });
    expect((await medicine.events(utc(2026, 10, 15, 7), utc(2026, 10, 16, 7))).map((event) => event.id)).toEqual([
      "demo-lecture",
      "demo-lab",
      "demo-skills",
    ]);
    await medicine.reload();
    expect(medicine.status()).toEqual([{ subscriptionID: "demo", name: "Demo", hasData: true }]);
  });
});
