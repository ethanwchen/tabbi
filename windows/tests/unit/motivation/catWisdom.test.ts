import { describe, expect, it } from "vitest";
import { makeActivityRecord, ACTIVITY_KINDS, ACTIVITY_UNITS, type ActivityRecord } from "../../../src/core/activity/activityRecord";
import type { PetStudyAward } from "../../../src/core/closet/petStudyCredit";
import { PetMilestoneProgress } from "../../../src/core/closet/petLimited";
import {
  CAT_WISDOM_COMEBACK,
  CAT_WISDOM_DAILY,
  CAT_WISDOM_EARLY_STOP,
  CAT_WISDOM_LATE_NIGHT,
  catWisdomRecapLine,
  catWisdomSessionFromAward,
  CatWisdomSchedule,
  wisdomDisplayText,
  type CatWisdomKind,
  type CatWisdomSession,
} from "../../../src/core/motivation/catWisdom";
import { MODULE_IDS } from "../../../src/core/modules/moduleId";
import { dayKeyStart } from "../../../src/core/planner/plannerDayKey";
import { StudyStreak } from "../../../src/core/streaks/studyStreak";
import { resetLanguage } from "../../../src/core/localization/lookup";
import { switchLanguage } from "../../support/catalogs";
import { fixed, seeded, utcTime as time } from "../coach/support";

const UTC = "UTC";
const calendar = { timeZone: UTC, firstWeekday: 1 };

function session(day: number, options: { hour?: number; previous?: number; streak?: number; minutes?: number; outcome?: CatWisdomSession["outcome"] } = {}): CatWisdomSession {
  return {
    outcome: options.outcome ?? "completed",
    end: time(day, options.hour ?? 14),
    ...(options.previous === undefined ? {} : { previousCompletion: options.previous }),
    streakDays: options.streak ?? 1,
    totalFocusMinutes: options.minutes ?? 60,
  };
}

const yes = fixed(0);
const no = fixed(0.9);
const kindOf = (kind: CatWisdomKind | undefined) => (kind?.type === "milestone" ? kind.milestone : kind?.type);

describe("CatWisdomSchedule", () => {
  it("shows a daily line on the first session of the day half the time", () => {
    const line = new CatWisdomSchedule().line(session(1, { previous: time(0) }), UTC, yes);
    expect(line?.kind.type).toBe("firstOfDay");
    expect(CAT_WISDOM_DAILY).toContain(line?.text);
    expect(new CatWisdomSchedule().line(session(1, { previous: time(0) }), UTC, no)).toBeUndefined();
  });

  it("shows at most one line a day and none for later sessions", () => {
    const schedule = new CatWisdomSchedule();
    expect(schedule.line(session(1, { previous: time(0) }), UTC, yes)).toBeDefined();
    const later = session(1, { hour: 16, previous: time(1) });
    expect(schedule.line(later, UTC, yes)).toBeUndefined();
    const quiet = new CatWisdomSchedule();
    expect(quiet.line(session(1, { previous: time(0) }), UTC, no)).toBeUndefined();
    expect(quiet.line(later, UTC, yes)).toBeUndefined();
  });

  it("lands roughly three to four lines a week", () => {
    const schedule = new CatWisdomSchedule();
    const random = seeded(5);
    let shown = 0;
    const days = 700;
    for (let day = 1; day <= days; day++) {
      for (const hour of [10, 14, 17]) {
        const previous = hour === 10 ? time(day - 1, 17) : time(day, hour - 3);
        if (schedule.line(session(day, { hour, previous }), UTC, random)) shown += 1;
      }
    }
    const perWeek = (shown / days) * 7;
    expect(perWeek).toBeGreaterThan(3);
    expect(perWeek).toBeLessThan(4);
  });

  it("puts a milestone before a comeback before the first of the day", () => {
    const schedule = new CatWisdomSchedule();
    schedule.line(session(0, { streak: 6, minutes: 100 }), UTC, no);
    expect(kindOf(schedule.line(session(4, { previous: time(0), minutes: 600 }), UTC, no)?.kind)).toBe("tenHours");
    const line = schedule.line(session(8, { previous: time(4), minutes: 660 }), UTC, no);
    expect(line?.kind.type).toBe("comeback");
    expect(CAT_WISDOM_COMEBACK).toContain(line?.text);
  });

  it("needs two full days away for a comeback", () => {
    const schedule = new CatWisdomSchedule();
    expect(schedule.line(session(2, { previous: time(0) }), UTC, no)).toBeUndefined();
    expect(schedule.line(session(3, { previous: time(0) }), UTC, no)?.kind.type).toBe("comeback");
  });

  it("shows each milestone once", () => {
    const schedule = new CatWisdomSchedule();
    schedule.line(session(0, { minutes: 30 }), UTC, no);
    const seen: (string | undefined)[] = [];
    for (let day = 1; day <= 200; day++) {
      const line = schedule.line(session(day, { previous: time(day - 1), streak: day + 1, minutes: 30 + day * 60 }), UTC, no);
      if (line) seen.push(kindOf(line.kind));
    }
    expect(seen).toEqual(["sevenDayStreak", "tenHours", "thirtyDayStreak", "fiftyHours", "lastSquare"]);
  });

  it("keeps milestones reached before the first look quiet", () => {
    const schedule = new CatWisdomSchedule();
    expect(schedule.line(session(1, { previous: time(0), streak: 40, minutes: 70 * 60 }), UTC, no)).toBeUndefined();
    expect(schedule.line(session(2, { previous: time(1), streak: 41, minutes: 71 * 60 }), UTC, no)).toBeUndefined();
    expect(kindOf(schedule.line(session(3, { previous: time(2), streak: 42, minutes: 100 * 60 }), UTC, no)?.kind)).toBe("lastSquare");
  });

  it("repeats no daily line until the pool is used up", () => {
    const schedule = new CatWisdomSchedule();
    const random = seeded(9);
    const lines: string[] = [];
    for (let day = 1; lines.length < CAT_WISDOM_DAILY.length * 2; day++) {
      const line = schedule.line(session(day, { previous: time(day - 1) }), UTC, random);
      if (line) lines.push(line.text);
    }
    const first = lines.slice(0, CAT_WISDOM_DAILY.length);
    const second = lines.slice(CAT_WISDOM_DAILY.length);
    expect(new Set(first)).toEqual(new Set(CAT_WISDOM_DAILY));
    expect(new Set(second)).toEqual(new Set(CAT_WISDOM_DAILY));
    expect(first[first.length - 1]).not.toBe(second[0]);
  });

  it("keeps the rotation across a restart", () => {
    let schedule = new CatWisdomSchedule();
    const random = seeded(1);
    const lines: string[] = [];
    for (let day = 1; lines.length < CAT_WISDOM_DAILY.length; day++) {
      if (lines.length === 5) schedule = CatWisdomSchedule.decode(schedule.encoded());
      const line = schedule.line(session(day, { previous: time(day - 1) }), UTC, random);
      if (line) lines.push(line.text);
    }
    expect(new Set(lines).size).toBe(CAT_WISDOM_DAILY.length);
  });

  it("says the late-night line at most once a week", () => {
    const schedule = new CatWisdomSchedule();
    const first = schedule.line(session(1, { hour: 23, previous: time(0) }), UTC, no);
    expect(first).toEqual({ kind: { type: "lateNight" }, text: CAT_WISDOM_LATE_NIGHT });
    for (let day = 2; day <= 7; day++) {
      expect(schedule.line(session(day, { hour: 23, previous: time(day - 1) }), UTC, no)).toBeUndefined();
    }
    expect(schedule.line(session(8, { hour: 23, previous: time(7) }), UTC, no)?.kind.type).toBe("lateNight");
  });

  it("is gentle on an early stop, which counts toward the daily cap", () => {
    const schedule = new CatWisdomSchedule();
    expect(schedule.line(session(1, { previous: time(0), outcome: "stoppedWithPoints" }), UTC, yes)).toEqual({
      kind: { type: "earlyStop" },
      text: CAT_WISDOM_EARLY_STOP,
    });
    expect(schedule.line(session(1, { hour: 16, previous: time(0) }), UTC, yes)).toBeUndefined();
  });

  it("shows nothing while off and brings no backlog when turned on", () => {
    const schedule = new CatWisdomSchedule();
    for (let day = 1; day <= 10; day++) {
      expect(schedule.line(session(day, { previous: time(day - 1), streak: day, minutes: day * 60 }), UTC, yes, false)).toBeUndefined();
    }
    expect(schedule.line(session(11, { previous: time(10), streak: 11, minutes: 11 * 60 }), UTC, yes)?.kind.type).toBe("firstOfDay");
  });

  it("counts days in the zone it is given", () => {
    /* 01:00 UTC is still the evening before in New York: a late session there, not a new day. */
    const schedule = new CatWisdomSchedule();
    schedule.line(session(0, { hour: 14 }), "America/New_York", yes);
    expect(schedule.lastShownDay).toBe("2026-10-05");
    expect(schedule.line({ ...session(1, { hour: 1 }), previousCompletion: time(0) }, "America/New_York", yes)).toBeUndefined();
  });

  it("reads saves with missing fields as the Mac does", () => {
    const schedule = CatWisdomSchedule.fromJSON({});
    expect(schedule.equals(new CatWisdomSchedule())).toBe(true);
    expect(() => CatWisdomSchedule.fromJSON({ lastShownDay: "2026-02-30" })).toThrow();
  });
});

describe("CatWisdom lines", () => {
  it("picks a recap line from the daily pool, stable for a week", () => {
    const line = catWisdomRecapLine(time(0), UTC);
    expect(CAT_WISDOM_DAILY).toContain(line);
    expect(catWisdomRecapLine(time(0, 20), UTC)).toBe(line);
    expect(catWisdomRecapLine(time(7), UTC)).not.toBe(line);
  });

  it("matches the Mac's week count from 2001", () => {
    /* 2026-10-05 is 1344 whole weeks after 2001-01-01 (the Mac's reference date), and 1344 mod 12 is 0. */
    expect(catWisdomRecapLine(time(0), UTC)).toBe(CAT_WISDOM_DAILY[0]);
    expect(catWisdomRecapLine(time(7), UTC)).toBe(CAT_WISDOM_DAILY[1]);
  });

  it("looks lines up in the catalog by their English", () => {
    const line = { kind: { type: "firstOfDay" } as const, text: "Water carves canyons by never skipping a day." };
    expect(wisdomDisplayText(line)).toBe(line.text);
    switchLanguage("de");
    try {
      expect(wisdomDisplayText(line)).not.toBe(line.text);
    } finally {
      resetLanguage();
    }
  });
});

describe("CatWisdomSession from an award", () => {
  function focus(minutes: number, day: number, hour = 10): ActivityRecord {
    const end = time(day, hour);
    return makeActivityRecord({
      source: MODULE_IDS.focus,
      kind: ACTIVITY_KINDS.focusCompleted,
      start: end - minutes * 60,
      end,
      quantity: minutes,
      unit: ACTIVITY_UNITS.minutes,
    });
  }

  function make(award: PetStudyAward, records: ActivityRecord[], lastCompletion?: number): CatWisdomSession | undefined {
    const progress = new PetMilestoneProgress(records, calendar);
    const now = time(3);
    const streak = new StudyStreak(progress.studyDays, [], now, calendar);
    return catWisdomSessionFromAward(award, now, lastCompletion, streak, progress, UTC);
  }

  const award = (completedSessions: number, minutes: number, points: number): PetStudyAward => ({ completedSessions, minutes, points, unlocked: [] });

  it("counts a completed session not yet logged toward the streak and total", () => {
    const made = make(award(1, 25, 35), [focus(60, 1), focus(60, 2)]);
    expect(made?.outcome).toBe("completed");
    expect(made?.streakDays).toBe(3);
    expect(made?.totalFocusMinutes).toBe(145);
    expect(made?.previousCompletion).toBe(dayKeyStart("2026-10-07", UTC));
  });

  it("does not count a logged session twice", () => {
    const made = make(award(1, 25, 35), [focus(60, 2), focus(25, 3, 13)]);
    expect(made?.streakDays).toBe(2);
    expect(made?.totalFocusMinutes).toBe(85);
    expect(made?.previousCompletion).toBe(dayKeyStart("2026-10-07", UTC));
  });

  it("reads an early stop and keeps a saved last completion", () => {
    const made = make(award(0, 12, 12), [], time(0));
    expect(made?.outcome).toBe("stoppedWithPoints");
    expect(made?.streakDays).toBe(0);
    expect(made?.previousCompletion).toBe(time(0));
  });

  it("makes no session without points", () => {
    expect(make(award(0, 2, 0), [])).toBeUndefined();
  });
});
