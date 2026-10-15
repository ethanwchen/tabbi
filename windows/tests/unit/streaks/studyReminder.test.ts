import { describe, expect, it } from "vitest";
import { instantOf, wallTime } from "../../../src/core/calendar/zonedCalendar";
import { type DayCalendar } from "../../../src/core/streaks/dayCalendar";
import {
  StudyReminderSettings,
  nextReminderFireDate,
  reminderFireDate,
  reminderMessage,
} from "../../../src/core/streaks/studyReminder";

// Port of StudyReminderTests.
function calendar(zone = "America/New_York"): DayCalendar {
  return { timeZone: zone, firstWeekday: 1 };
}

function date(day: number, hour: number, cal: DayCalendar, minute = 0, month = 10): number {
  return instantOf({ year: 2026, month: month, day: day, hour: hour, minute: minute }, cal.timeZone);
}

const sevenPM = StudyReminderSettings.at(true, 19, 0);

function next(
  cal: DayCalendar,
  now: number,
  options: { settings?: StudyReminderSettings; studied?: boolean; goalMet?: boolean; delivered?: number } = {},
): number | undefined {
  return nextReminderFireDate({
    settings: options.settings ?? sevenPM,
    now,
    studiedToday: options.studied ?? false,
    goalMetToday: options.goalMet ?? false,
    ...(options.delivered === undefined ? {} : { lastDelivered: options.delivered }),
    calendar: cal,
  });
}

describe("StudyReminderSettings", () => {
  it("reminders are off by default", () => {
    expect(StudyReminderSettings.off.isEnabled).toBe(false);
    expect(StudyReminderSettings.off.hour).toBe(19);
    expect(StudyReminderSettings.off.minute).toBe(0);
  });

  it("time is clamped to one day", () => {
    expect(new StudyReminderSettings(true, -5).minuteOfDay).toBe(0);
    expect(new StudyReminderSettings(true, 5000).minuteOfDay).toBe(1439);
    expect(sevenPM.withMinuteOfDay(2000).minuteOfDay).toBe(1439);
  });

  it("settings round-trip and read leniently", () => {
    const settings = StudyReminderSettings.at(true, 8, 30);
    expect(StudyReminderSettings.fromJSON(JSON.parse(JSON.stringify(settings))).equals(settings)).toBe(true);
    const read = StudyReminderSettings.fromJSON({ isEnabled: "yes", minuteOfDay: 99999 });
    expect(read.isEnabled).toBe(false);
    expect(read.minuteOfDay).toBe(1439);
    expect(StudyReminderSettings.fromJSON({}).equals(StudyReminderSettings.off)).toBe(true);
  });
});

describe("StudyReminder: when it fires", () => {
  it("off never fires", () => {
    const cal = calendar();
    expect(next(cal, date(14, 9, cal), { settings: StudyReminderSettings.off })).toBeUndefined();
  });

  it("fires today when not studied yet", () => {
    const cal = calendar();
    expect(next(cal, date(14, 9, cal))).toBe(date(14, 19, cal));
  });

  it("studying today skips to tomorrow", () => {
    const cal = calendar();
    expect(next(cal, date(14, 9, cal), { studied: true })).toBe(date(15, 19, cal));
  });

  it("meeting the goal skips to tomorrow", () => {
    const cal = calendar();
    expect(next(cal, date(14, 9, cal), { goalMet: true })).toBe(date(15, 19, cal));
  });

  it("after the time passed it waits for tomorrow", () => {
    const cal = calendar();
    expect(next(cal, date(14, 19, cal))).toBe(date(15, 19, cal));
    expect(next(cal, date(14, 21, cal))).toBe(date(15, 19, cal));
  });

  it("never twice a day, even when the time moves later", () => {
    const cal = calendar();
    const later = StudyReminderSettings.at(true, 22, 0);
    expect(next(cal, date(14, 20, cal), { settings: later, delivered: date(14, 19, cal) })).toBe(date(15, 22, cal));
  });

  it("yesterday's delivery does not block today", () => {
    const cal = calendar();
    expect(next(cal, date(14, 9, cal), { delivered: date(13, 19, cal) })).toBe(date(14, 19, cal));
  });

  it("a midnight reminder", () => {
    const cal = calendar();
    const midnight = new StudyReminderSettings(true, 0);
    expect(next(cal, date(14, 9, cal), { settings: midnight })).toBe(date(15, 0, cal));
  });

  it("uses the local day of the calendar's time zone", () => {
    // 23:30 in New York on the 14th is already the 15th in Tokyo.
    const newYork = calendar();
    const tokyo = calendar("Asia/Tokyo");
    const now = date(14, 23, newYork, 30);
    expect(next(newYork, now)).toBe(date(15, 19, newYork));
    expect(next(tokyo, now)).toBe(date(15, 19, tokyo));
    // A delivery on the 14th in New York is the 15th in Tokyo too.
    expect(next(tokyo, now, { delivered: now })).toBe(date(16, 19, tokyo));
  });

  it("keeps the wall-clock time across daylight saving", () => {
    // Clocks fall back on November 1, 2026 in New York.
    const cal = calendar();
    const fire = next(cal, date(31, 20, cal)) ?? 0;
    expect(wallTime(fire, cal.timeZone).hour).toBe(19);
    expect(wallTime(fire, cal.timeZone).day).toBe(1);
    expect(fire - date(31, 19, cal)).toBe(25 * 3600);
  });

  it("a time skipped by spring forward moves to the next valid moment", () => {
    // 2:30 doesn't exist on March 8, 2026 in New York; 3:00 does.
    const cal = calendar();
    const fire = reminderFireDate("2026-03-08", StudyReminderSettings.at(true, 2, 30), cal);
    expect(wallTime(fire, cal.timeZone).day).toBe(8);
    expect(wallTime(fire, cal.timeZone).hour).toBe(3);
  });
});

describe("StudyReminder: what it says", () => {
  it("the message uses the pet's name", () => {
    expect(reminderMessage("Mochi", 0)).toEqual({ title: "Mochi misses you", body: "10 minutes?" });
  });

  it("the message mentions a running streak", () => {
    expect(reminderMessage("Mochi", 6).body).toBe("10 minutes? That keeps your 6-day streak going.");
  });

  it("the message without a pet name", () => {
    expect(reminderMessage("  ", 0).title).toBe("Tabbi misses you");
    expect(reminderMessage(undefined, 0).title).toBe("Tabbi misses you");
  });
});
