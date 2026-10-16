import { describe, expect, it } from "vitest";
import { PetEconomy } from "../../../src/core/closet/petEconomy";
import { PetMilestoneProgress } from "../../../src/core/closet/petLimited";
import { ACTIVITY_KINDS, ACTIVITY_UNITS, type ActivityRecord } from "../../../src/core/activity/activityRecord";
import { activity } from "../../support/activity";
import { instantOf } from "../../../src/core/calendar/zonedCalendar";
import { type DayCalendar } from "../../../src/core/streaks/dayCalendar";
import { StreakFreezeRules, StudyStreak } from "../../../src/core/streaks/studyStreak";

// Port of StudyStreakTests. New York, weeks starting on Monday. October
// 2026: Monday the 5th, Monday the 12th and Monday the 19th start weeks.
function calendar(zone = "America/New_York", firstWeekday = 2): DayCalendar {
  return { timeZone: zone, firstWeekday };
}

function key(day: number, month = 10): string {
  return `2026-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

function date(day: number, cal: DayCalendar, month = 10, hour = 12): number {
  return instantOf({ year: 2026, month: month, day: day, hour: hour, minute: 0 }, cal.timeZone);
}

function streak(studied: number[], today: number, bought: number[] = [], cal: DayCalendar = calendar()): StudyStreak {
  return new StudyStreak(
    studied.map((day) => key(day)),
    bought.map((day) => date(day, cal)),
    date(today, cal),
    cal,
  );
}

function frozen(result: StudyStreak): string[] {
  return [...result.frozenDays].sort();
}

describe("StudyStreak: plain streaks", () => {
  it("no study has no streak and a free freeze ready", () => {
    const result = streak([], 14);
    expect(result.length).toBe(0);
    expect(result.isActive).toBe(false);
    expect(result.needsStudyToday).toBe(false);
    expect(result.freeFreezeAvailable).toBe(true);
    expect(result.freezesReady).toBe(1);
  });

  it("consecutive days through today count each day", () => {
    const result = streak([12, 13, 14], 14);
    expect(result.length).toBe(3);
    expect(result.studiedToday).toBe(true);
    expect(result.needsStudyToday).toBe(false);
    expect(frozen(result)).toEqual([]);
  });

  it("today without study keeps the streak and asks for study", () => {
    const result = streak([12, 13], 14);
    expect(result.length).toBe(2);
    expect(result.studiedToday).toBe(false);
    expect(result.needsStudyToday).toBe(true);
    expect(frozen(result), "today still has time, so it is never frozen").toEqual([]);
    expect(result.freeFreezeAvailable).toBe(true);
  });

  it("study days after today are ignored", () => {
    const result = streak([13, 15, 16], 14);
    expect(result.length).toBe(1);
    expect(result.studiedToday).toBe(false);
  });
});

describe("StudyStreak: the free weekly freeze", () => {
  it("one missed day is frozen and not counted", () => {
    const result = streak([12, 14, 15], 15);
    expect(result.length).toBe(3);
    expect(frozen(result)).toEqual([key(13)]);
    expect(result.freeFreezeAvailable).toBe(false);
    expect(result.freezesReady).toBe(0);
  });

  it("a missed yesterday is frozen so the streak still shows today", () => {
    const result = streak([12, 13], 15);
    expect(result.length).toBe(2);
    expect(frozen(result)).toEqual([key(14)]);
    expect(result.needsStudyToday).toBe(true);
  });

  it("a second miss in the same week ends the streak", () => {
    const result = streak([12, 14, 16, 17], 17);
    expect(frozen(result)).toEqual([key(13)]);
    expect(result.length).toBe(2);
  });

  it("two missed days in a row end the streak with only the free freeze", () => {
    const result = streak([12, 13], 16);
    expect(frozen(result)).toEqual([key(14)]);
    expect(result.length).toBe(0);
    expect(result.isActive).toBe(false);
    expect(result.needsStudyToday).toBe(false);
  });

  it("misses in different weeks each use that week's freeze", () => {
    // Sunday the 11th ends one week and Monday the 12th starts the next.
    const result = streak([8, 9, 10, 13, 14], 14);
    expect(frozen(result)).toEqual([key(11), key(12)]);
    expect(result.length).toBe(5);
    expect(result.freeFreezeAvailable).toBe(false);
  });

  it("the free freeze resets each week", () => {
    const result = streak([6, 8, 9, 10, 11, 12], 12);
    expect(frozen(result)).toEqual([key(7)]);
    expect(result.freeFreezeAvailable).toBe(true);
  });

  it("the first day of the week follows the calendar", () => {
    // With Sunday-first weeks the 11th and 12th fall in the same week.
    const result = streak([8, 9, 10, 13, 14], 14, [], calendar("America/New_York", 1));
    expect(frozen(result)).toEqual([key(11)]);
    expect(result.length).toBe(2);
  });

  it("no freeze is spent while there is no streak", () => {
    const result = streak([5, 15], 16, [4]);
    expect(frozen(result), "the free freeze, then the extra one").toEqual([key(6), key(7)]);
    expect(result.extraFreezes).toBe(0);
    expect(result.length).toBe(1);
    const idle = streak([15], 16, [4]);
    expect(idle.extraFreezes, "days before the first study day spend nothing").toBe(1);
    expect(idle.freeFreezeAvailable).toBe(true);
  });
});

describe("StudyStreak: extra freezes", () => {
  it("an extra freeze covers a second miss in a week", () => {
    const result = streak([12, 14, 16, 17], 17, [12]);
    expect(frozen(result)).toEqual([key(13), key(15)]);
    expect(result.length).toBe(4);
    expect(result.extraFreezes).toBe(0);
  });

  it("the free freeze is used before an extra one", () => {
    const result = streak([12, 14], 14, [12]);
    expect(frozen(result)).toEqual([key(13)]);
    expect(result.extraFreezes).toBe(1);
    expect(result.freezesReady).toBe(1);
  });

  it("several missed days use every freeze in order", () => {
    const result = streak([12, 16], 16, [10, 11]);
    expect(frozen(result)).toEqual([key(13), key(14), key(15)]);
    expect(result.length).toBe(2);
    expect(result.extraFreezes).toBe(0);
    expect(result.freezesReady).toBe(0);
  });

  it("a freeze bought after a miss cannot repair it", () => {
    const result = streak([12, 13, 15], 16, [14, 15]);
    expect(frozen(result), "the free freeze covered the 14th").toEqual([key(14)]);
    const late = streak([12, 15], 15, [14]);
    expect(frozen(late)).toEqual([key(13)]);
    expect(late.length, "the freeze bought on the 14th did not protect the 14th").toBe(1);
    expect(late.extraFreezes, "it waits for the next miss").toBe(1);
  });

  it("a freeze bought today is held and the holding limit applies", () => {
    const one = streak([14], 14, [14]);
    expect(one.extraFreezes).toBe(1);
    expect(one.canBuyFreeze).toBe(true);
    const two = streak([14], 14, [13, 14]);
    expect(two.extraFreezes).toBe(StreakFreezeRules.maxHeld);
    expect(two.canBuyFreeze).toBe(false);
    expect(two.freezesReady).toBe(3);
  });

  it("an extra freeze costs one typical study day", () => {
    expect(StreakFreezeRules.price()).toBe(PetEconomy.pointsPerTypicalDay());
    expect(StreakFreezeRules.price()).toBe(105);
    expect(StreakFreezeRules.freePerWeek).toBe(1);
  });
});

describe("StudyStreak: time zones", () => {
  it("study days follow the local day of the records", () => {
    const newYork = calendar();
    // 11:30 pm on Monday the 12th and 12:30 am on Wednesday the 14th, New York time.
    const late = instantOf({ year: 2026, month: 10, day: 12, hour: 23, minute: 30 }, newYork.timeZone);
    const early = instantOf({ year: 2026, month: 10, day: 14, hour: 0, minute: 30 }, newYork.timeZone);
    const records: ActivityRecord[] = [late, early].map((end, index) => activity({
      id: `r${index}`,
      source: "focus",
      kind: ACTIVITY_KINDS.focusCompleted,
      end,
      quantity: 20,
      unit: ACTIVITY_UNITS.minutes,
    }));
    const progress = new PetMilestoneProgress(records, newYork);
    const result = new StudyStreak(progress.studyDays, [], early, newYork);
    expect(frozen(result)).toEqual([key(13)]);
    expect(result.length).toBe(2);

    // The same moments in Tokyo fall on the 13th and the 14th: no miss.
    const tokyo = calendar("Asia/Tokyo");
    const tokyoProgress = new PetMilestoneProgress(records, tokyo);
    const tokyoResult = new StudyStreak(tokyoProgress.studyDays, [], early, tokyo);
    expect(frozen(tokyoResult)).toEqual([]);
    expect(tokyoResult.length).toBe(2);
  });

  it("a streak crosses a daylight saving change", () => {
    // US clocks fall back on Sunday, November 1, 2026.
    const newYork = calendar();
    const days = [key(30), key(31), key(1, 11), key(2, 11), key(3, 11)];
    const result = new StudyStreak(days, [], date(3, newYork, 11, 23), newYork);
    expect(result.length).toBe(5);
    expect(frozen(result)).toEqual([]);
  });
});

describe("StudyStreak: day strip", () => {
  it("recent days show study, freezes, misses and an open today", () => {
    const result = streak([5, 6, 7, 9], 10);
    const days = result.recentDays(7);
    expect(days.map((day) => day.day)).toEqual([4, 5, 6, 7, 8, 9, 10].map((day) => key(day)));
    expect(days.map((day) => day.state)).toEqual(["missed", "studied", "studied", "studied", "frozen", "studied", "today"]);
  });

  it("recent days end on today once studied", () => {
    const result = streak([9, 10], 10);
    expect(result.recentDays(2).map((day) => day.state)).toEqual(["studied", "studied"]);
    expect(result.recentDays(0)).toEqual([]);
  });

  it("the demo streak shows a frozen day", () => {
    const cal = calendar();
    for (let day = 5; day <= 11; day++) {
      const today = date(day, cal, 11, 15);
      const result = new StudyStreak(PetMilestoneProgress.demo(today, cal).studyDays, [], today, cal);
      expect(result.length, `day ${day}`).toBe(6);
      expect(result.recentDays(7).map((entry) => entry.state), `day ${day}`).toEqual([
        "studied",
        "studied",
        "frozen",
        "studied",
        "studied",
        "studied",
        "studied",
      ]);
    }
  });
});
