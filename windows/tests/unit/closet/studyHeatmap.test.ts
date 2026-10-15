import { describe, expect, it } from "vitest";
import { PetMilestoneProgress } from "../../../src/core/closet/petLimited";
import {
  HEATMAP_LABELED_WEEKDAYS,
  HEATMAP_LEVEL_COUNT,
  StudyHeatmap,
  heatmapDayLabel,
  heatmapLevel,
  weekMinutes,
  weekStudiedDays,
  type HeatmapDay,
} from "../../../src/core/closet/studyHeatmap";
import { zonedInstant, type DayCalendar } from "../../../src/core/streaks/dayCalendar";

// Port of StudyHeatmapTests.
function calendar(firstWeekday = 1): DayCalendar {
  return { timeZone: "America/New_York", firstWeekday };
}

/** Tuesday, October 7, 2025, mid-afternoon in New York. */
function tuesday(cal: DayCalendar): number {
  return zonedInstant(2025, 10, 7, 15, 0, 0, cal.timeZone);
}

function heatmap(minutes: Record<string, number>, weeks: number, cal: DayCalendar = calendar()): StudyHeatmap {
  return new StudyHeatmap(new Map(Object.entries(minutes)), weeks, tuesday(cal), cal);
}

function present(days: readonly (HeatmapDay | undefined)[]): HeatmapDay[] {
  return days.flatMap((day) => (day ? [day] : []));
}

describe("StudyHeatmap: levels", () => {
  it("levels follow study minute thresholds", () => {
    expect([0, 1, 14, 15, 44, 45, 89, 90, 600].map(heatmapLevel)).toEqual([0, 1, 1, 2, 2, 3, 3, 4, 4]);
    expect(heatmapLevel(-5)).toBe(0);
    expect(HEATMAP_LEVEL_COUNT).toBe(5);
  });
});

describe("StudyHeatmap: grid", () => {
  it("weeks are columns from the first weekday ending with today", () => {
    const map = heatmap({}, 3);
    expect(map.weeks.map((week) => week.start)).toEqual(["2025-09-21", "2025-09-28", "2025-10-05"]);
    expect(map.weeks.every((week) => week.days.length === 7)).toBe(true);
    // Sunday, Monday, Tuesday so far; the rest of the week is still to come.
    const current = map.weeks[map.weeks.length - 1]?.days ?? [];
    expect(present(current).map((day) => day.key)).toEqual(["2025-10-05", "2025-10-06", "2025-10-07"]);
    expect(current.slice(-4).filter((day) => day === undefined).length).toBe(4);
    expect(present(current).filter((day) => day.isToday).map((day) => day.key)).toEqual(["2025-10-07"]);
    expect(map.today).toBe("2025-10-07");
  });

  it("weeks follow the locale's first weekday", () => {
    const map = heatmap({}, 1, calendar(2));
    expect(map.weeks.map((week) => week.start)).toEqual(["2025-10-06"]);
    expect(present(map.weeks[0]?.days ?? []).map((day) => day.key)).toEqual(["2025-10-06", "2025-10-07"]);
  });

  it("always shows the current week", () => {
    expect(heatmap({}, 0).weeks.length).toBe(1);
  });

  it("days carry rounded minutes and ignore the future", () => {
    const map = heatmap({ "2025-10-06": 84.6, "2025-10-07": 0.4, "2025-10-08": 300, "2025-10-05": Number.NaN }, 1);
    const week = map.weeks[0];
    if (!week) throw new Error("no week");
    const days = present(week.days);
    expect(days.map((day) => day.minutes)).toEqual([0, 85, 0]);
    expect(days.map((day) => heatmapLevel(day.minutes))).toEqual([0, 3, 0]);
    expect(weekMinutes(week)).toBe(85);
    expect(weekStudiedDays(week)).toBe(1);
    expect(map.bestDay?.key).toBe("2025-10-06");
  });
});

describe("StudyHeatmap: labels", () => {
  it("month labels sit over the first week starting in each month", () => {
    // Weeks from Sunday, August 17 to Sunday, October 5, 2025.
    const labels = heatmap({}, 8).monthLabels(1);
    expect(labels.map((label) => label.week)).toEqual([0, 3, 7]);
    expect(labels.map((label) => label.start)).toEqual(["2025-08-17", "2025-09-07", "2025-10-05"]);
  });

  it("crowded month labels are left out", () => {
    const map = heatmap({}, 8);
    // August has three columns before September's four, and October one at the end.
    expect(map.monthLabels(2).map((label) => label.week)).toEqual([0, 3]);
    expect(map.monthLabels(4).map((label) => label.week)).toEqual([3]);
    expect(map.monthLabels(5).map((label) => label.week)).toEqual([]);
    expect(map.monthLabels(0).length, "every label has at least one column").toBe(3);
  });

  it("rows follow the first weekday", () => {
    expect(heatmap({}, 1).weekdays).toEqual([1, 2, 3, 4, 5, 6, 7]);
    const monday = heatmap({}, 1, calendar(2));
    expect(monday.weekdays).toEqual([2, 3, 4, 5, 6, 7, 1]);
    const rows = monday.weekdays.flatMap((weekday, index) => (HEATMAP_LABELED_WEEKDAYS.has(weekday) ? [index] : []));
    expect(rows, "Monday, Wednesday and Friday are the first, third and fifth rows").toEqual([0, 2, 4]);
  });
});

describe("StudyHeatmap: summary", () => {
  it("counts the last thirty days and the best day ever", () => {
    const map = heatmap(
      {
        "2025-10-07": 30, // today
        "2025-09-08": 20, // 29 days ago, the window's first day
        "2025-09-07": 40, // 30 days ago, outside the window
        "2025-05-01": 130, // months ago, still the best day
        "2025-06-01": 130, // a tie: the later one wins
      },
      2,
    );
    expect(map.lastThirtyDaysMinutes).toBe(50);
    expect(map.bestDay?.key).toBe("2025-06-01");
    expect(map.bestDay?.minutes).toBe(130);
    expect(map.bestDay?.isToday ?? true).toBe(false);
  });

  it("no study has no best day", () => {
    const map = heatmap({ "2025-10-07": 0 }, 4);
    expect(map.bestDay).toBeUndefined();
    expect(map.lastThirtyDaysMinutes).toBe(0);
    expect(map.weeks.every((week) => present(week.days).every((day) => heatmapLevel(day.minutes) === 0))).toBe(true);
  });

  it("the studied label gives the exact time", () => {
    const label = (minutes: number) => heatmapDayLabel({ key: "2025-10-07", minutes, isToday: false });
    expect(label(0)).toBe("No study");
    expect(label(25)).toBe("25 min studied");
    expect(label(85)).toBe("1h 25m studied");
  });
});

describe("StudyHeatmap: demo", () => {
  it("the demo history fills months with every level and a studied today", () => {
    const cal = calendar();
    const today = tuesday(cal);
    const demo = PetMilestoneProgress.demo(today, cal);
    const map = new StudyHeatmap(demo.minutesByDay, 26, today, cal);
    const days = map.weeks.flatMap((week) => present(week.days));
    expect(new Set(days.map((day) => heatmapLevel(day.minutes)))).toEqual(new Set([0, 1, 2, 3, 4]));
    expect(days.filter((day) => day.minutes > 0).length).toBeGreaterThan(50);
    expect(days[days.length - 1]?.minutes ?? 0).toBeGreaterThan(0);
    expect(map.bestDay?.minutes).toBe(120);
  });
});
