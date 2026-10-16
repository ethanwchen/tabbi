import { describe, expect, it } from "vitest";
import { makeActivityRecord, type ActivityRecord } from "../../../src/core/activity/activityRecord";
import { instantOf, wallTime } from "../../../src/core/calendar/zonedCalendar";
import { PARTY_FRIENDS_METADATA_KEY } from "../../../src/core/party/partySessionTracker";
import { PetPointsRules } from "../../../src/core/pets/petPointsRules";
import type { StudyPhaseOutcome } from "../../../src/core/studyMethods/studyPhaseRecord";
import {
  addingWeeks,
  latestReadyWeek,
  recapReadyDate,
  recapWeekContaining,
  recapWeekDays,
  recapWeekEnd,
  recapWeekStarting,
} from "../../../src/core/recap/recapWeek";
import {
  RECAP_CHEERS,
  WeeklyRecap,
  decodeWeeklyRecap,
  encodeWeeklyRecap,
  recapCheerLine,
} from "../../../src/core/recap/weeklyRecap";
import { switchLanguage } from "../../support/catalogs";

/* Port of WeeklyRecapTests. */

/** October `day`, 2026 at `hour`:`minute` in `zone`. October 5 is a Monday. */
function date(day: number, hour: number, minute = 0, zone = "UTC"): number {
  return instantOf({ year: 2026, month: 10, day, hour, minute }, zone);
}

let nextID = 0;
function id(): string {
  nextID += 1;
  return `00000000-0000-4000-8000-${String(nextID).padStart(12, "0")}`;
}

function focus(
  end: number,
  minutes: number,
  options: { source?: string; outcome?: StudyPhaseOutcome | null; friends?: number } = {},
): ActivityRecord {
  const metadata: Record<string, string> = {};
  const outcome = options.outcome === undefined ? "completed" : options.outcome;
  if (outcome !== null) metadata.outcome = outcome;
  if (options.friends !== undefined) metadata[PARTY_FRIENDS_METADATA_KEY] = String(options.friends);
  return makeActivityRecord({
    id: id(),
    source: options.source ?? "focus",
    kind: "focus.completed",
    start: end - minutes * 60,
    end,
    quantity: minutes,
    unit: "min",
    metadata,
  });
}

describe("week boundaries", () => {
  it("runs Monday through Sunday", () => {
    expect(recapWeekContaining(date(5, 0), "UTC")).toBe("2026-10-05");
    expect(recapWeekContaining(date(11, 23, 59), "UTC")).toBe("2026-10-05");
    expect(recapWeekContaining(date(12, 0), "UTC")).toBe("2026-10-12");
  });

  it("has seven days, an end and neighbors", () => {
    const week = recapWeekContaining(date(8, 12), "UTC");
    expect(recapWeekEnd(week)).toBe("2026-10-11");
    expect(recapWeekDays(week)).toEqual(["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10", "2026-10-11"]);
    expect(addingWeeks(week, -1)).toBe("2026-09-28");
    expect(addingWeeks(week, 4)).toBe("2026-11-02");
  });

  it("starts only on a Monday", () => {
    expect(recapWeekStarting("2026-10-05")).toBe("2026-10-05");
    expect(recapWeekStarting("2026-10-04")).toBeUndefined();
    expect(recapWeekStarting("2026-10-32")).toBeUndefined();
  });

  it("is ready on Sunday evening", () => {
    const zone = "America/Los_Angeles";
    const thisWeek = recapWeekContaining(date(7, 12, 0, zone), zone);
    const lastWeek = addingWeeks(thisWeek, -1);
    expect(latestReadyWeek(date(7, 12, 0, zone), zone)).toBe(lastWeek);
    expect(latestReadyWeek(date(11, 17, 59, zone), zone)).toBe(lastWeek);
    expect(latestReadyWeek(date(11, 18, 0, zone), zone)).toBe(thisWeek);
    expect(latestReadyWeek(date(12, 9, 0, zone), zone)).toBe(thisWeek);
    expect(recapReadyDate(thisWeek, zone)).toBe(date(11, 18, 0, zone));
  });

  it("keeps the ready hour across a daylight saving change", () => {
    /* Europe moves its clocks back on Sunday, October 25, 2026. */
    const zone = "Europe/Berlin";
    const week = recapWeekContaining(date(21, 12, 0, zone), zone);
    expect(recapWeekEnd(week)).toBe("2026-10-25");
    expect(wallTime(recapReadyDate(week, zone), zone).hour).toBe(18);
  });

  it("counts records toward the local day they ended", () => {
    /* 23:30 Sunday in Los Angeles is Monday morning in UTC. */
    const zone = "America/Los_Angeles";
    const record = focus(date(11, 23, 30, zone), 30);
    const week = recapWeekContaining(date(8, 12, 0, zone), zone);
    expect(WeeklyRecap.fromRecords(week, [record], zone).minutesByDay.at(-1)).toBe(30);
    const utcWeek = recapWeekContaining(date(8, 12), "UTC");
    expect(WeeklyRecap.fromRecords(utcWeek, [record], "UTC").isEmpty).toBe(true);
    expect(WeeklyRecap.fromRecords(addingWeeks(utcWeek, 1), [record], "UTC").minutesByDay[0]).toBe(30);
  });
});

describe("aggregation", () => {
  const week = "2026-10-05";

  it("adds up a week", () => {
    const records = [
      focus(date(5, 10), 25),
      focus(date(5, 11), 25),
      focus(date(6, 10), 50),
      focus(date(6, 12), 12, { outcome: "skipped" }),
      focus(date(9, 10), 3, { outcome: "abandoned" }),
      makeActivityRecord({ id: id(), source: "anki", kind: "cards.reviewed", start: date(7, 9), quantity: 40, unit: "cards" }),
      makeActivityRecord({ id: id(), source: "planner", kind: "task.completed", start: date(8, 9), subject: "a" }),
      makeActivityRecord({ id: id(), source: "planner", kind: "task.completed", start: date(8, 10), subject: "a" }),
      makeActivityRecord({ id: id(), source: "planner", kind: "task.completed", start: date(10, 9), subject: "b" }),
      makeActivityRecord({ id: id(), source: "focus", kind: "break.taken", start: date(5, 10), end: date(5, 10, 5), quantity: 5, unit: "min" }),
    ];
    const recap = WeeklyRecap.fromRecords(week, records, "UTC");
    expect(recap.minutesByDay).toEqual([50, 62, 0, 0, 3, 0, 0]);
    expect(recap.focusMinutes).toBe(115);
    expect(recap.sessions).toBe(3);
    expect(recap.cardsReviewed).toBe(40);
    expect(recap.tasksDone).toBe(2);
    /* 25+10, 25+10, 50+10, 12 skipped, 3 too short. */
    expect(recap.points).toBe(142);
    /* Monday through Thursday: focus, focus, cards, a task. Friday's 3 minutes don't count. */
    expect(recap.longestStreak).toBe(4);
    expect(recap.bestDay()).toEqual({ day: "2026-10-06", minutes: 62 });
    expect(recap.isEmpty).toBe(false);
  });

  it("ignores records outside the week and duplicates", () => {
    const inside = focus(date(5, 10), 25);
    const recap = WeeklyRecap.fromRecords(week, [inside, inside, focus(date(4, 23, 59), 25), focus(date(12, 0, 1), 25)], "UTC");
    expect(recap.focusMinutes).toBe(25);
    expect(recap.sessions).toBe(1);
  });

  it("gives Party stays the team bonus only when finished", () => {
    const records = [
      focus(date(5, 10), 25, { source: "party", friends: 2 }),
      focus(date(6, 10), 20, { source: "party", outcome: "skipped", friends: 2 }),
    ];
    const recap = WeeklyRecap.fromRecords(week, records, "UTC");
    expect(recap.points).toBe(PetPointsRules.sharedPoints(25, 2) + PetPointsRules.sharedPoints(20, 2, false));
    expect(recap.sessions).toBe(1);
  });

  it("reads a friends count only when it is a whole number", () => {
    const record = makeActivityRecord({
      id: id(),
      source: "party",
      kind: "focus.completed",
      start: date(5, 9),
      end: date(5, 10),
      quantity: 30,
      unit: "min",
      metadata: { [PARTY_FRIENDS_METADATA_KEY]: "2.5" },
    });
    expect(WeeklyRecap.fromRecords(week, [record], "UTC").points).toBe(PetPointsRules.sharedPoints(30, 0));
  });

  it("has an empty week", () => {
    const recap = WeeklyRecap.fromRecords(week, [], "UTC");
    expect(recap.isEmpty).toBe(true);
    expect(recap.minutesByDay).toEqual([0, 0, 0, 0, 0, 0, 0]);
    expect(recap.longestStreak).toBe(0);
    expect(recap.bestDay()).toBeUndefined();
    expect(recap.cheer([])).toBe("rest");
  });

  it("lets a streak span the whole week", () => {
    const records = [5, 6, 7, 8, 9, 10, 11].map((day) => focus(date(day, 9), 10));
    expect(WeeklyRecap.fromRecords(week, records, "UTC").longestStreak).toBe(7);
  });

  it("clamps and round-trips saved recaps", () => {
    const recap = new WeeklyRecap({ week, minutesByDay: [10, -5], sessions: 1, cardsReviewed: 2, tasksDone: 3, points: 4, longestStreak: 9 });
    expect(recap.minutesByDay).toEqual([10, 0, 0, 0, 0, 0, 0]);
    expect(recap.longestStreak).toBe(7);
    expect(decodeWeeklyRecap(JSON.parse(JSON.stringify(encodeWeeklyRecap(recap)))).equals(recap)).toBe(true);
    expect(() => decodeWeeklyRecap({ ...encodeWeeklyRecap(recap), week: "monday" })).toThrow();
  });
});

describe("cheer", () => {
  const current = "2026-10-12";
  function recap(weeksAgo: number, minutes: number, cards = 0): WeeklyRecap {
    return new WeeklyRecap({
      week: addingWeeks(current, -weeksAgo),
      minutesByDay: [minutes],
      sessions: 0,
      cardsReviewed: cards,
      tasksDone: 0,
      points: 0,
      longestStreak: 0,
    });
  }

  it("is always kind", () => {
    const lastWeek = recap(1, 300);
    const older = recap(3, 600);
    expect(recap(0, 700).cheer([lastWeek, older])).toBe("bestYet");
    expect(recap(0, 400).cheer([lastWeek, older])).toBe("moreThanLastWeek");
    expect(recap(0, 200).cheer([lastWeek, older])).toBe("steady");
    expect(recap(0, 30).cheer([lastWeek, older])).toBe("light");
    expect(recap(0, 0, 20).cheer([lastWeek])).toBe("light");
    expect(recap(0, 200).cheer([])).toBe("firstWeek");
    expect(recap(0, 0).cheer([lastWeek])).toBe("rest");
  });

  it("ignores later and empty weeks", () => {
    expect(recap(1, 200).cheer([recap(0, 900), recap(2, 0)])).toBe("firstWeek");
  });

  it("needs the week right before for more than last week", () => {
    expect(recap(0, 200).cheer([recap(2, 100), recap(5, 600)])).toBe("steady");
  });

  it("has a warm line for every cheer", () => {
    switchLanguage("en");
    for (const cheer of RECAP_CHEERS) expect(recapCheerLine(cheer)).not.toBe("");
    expect(recapCheerLine("bestYet")).toBe("Your best week yet!");
  });
});
