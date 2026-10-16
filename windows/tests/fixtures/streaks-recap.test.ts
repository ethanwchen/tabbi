import { describe, expect, it } from "vitest";
import { makeActivityRecord, type ActivityRecord } from "../../src/core/activity/activityRecord";
import { addingDays } from "../../src/core/calendar/zonedCalendar";
import { PetMilestoneProgress } from "../../src/core/closet/petLimited";
import {
  HEATMAP_LABELED_WEEKDAYS,
  HEATMAP_LEVEL_COUNT,
  HEATMAP_LEVEL_THRESHOLDS,
  StudyHeatmap,
  heatmapLevel,
  weekMinutes,
  weekStudiedDays,
  type HeatmapDay,
} from "../../src/core/closet/studyHeatmap";
import { PARTY_FRIENDS_METADATA_KEY } from "../../src/core/party/partySessionTracker";
import { PetPointsRules } from "../../src/core/pets/petPointsRules";
import { recapStats } from "../../src/core/recap/recapStats";
import {
  addingWeeks,
  latestReadyWeek,
  RECAP_READY_HOUR,
  recapReadyDate,
  recapWeekContaining,
  recapWeekEnd,
} from "../../src/core/recap/recapWeek";
import { LIGHT_WEEK_MINUTES, WeeklyRecap } from "../../src/core/recap/weeklyRecap";
import { STREAK_MILESTONE_DAYS, isStreakMilestone, streakMilestoneReached } from "../../src/core/streaks/streakMilestone";
import { StreakFreezeRules, StudyStreak } from "../../src/core/streaks/studyStreak";
import type { DayCalendar } from "../../src/core/streaks/dayCalendar";
import { loadFixture } from "../support/fixtures";
import { goldenDiff } from "../support/goldenCompare";

/*
 * Replays shared/fixtures/streaks-recap (written by StreaksRecapGoldenTests
 * on the Mac): activity logs read on fixed days in named time zones, with
 * the milestone progress, the study streak and its freezes, the Closet's
 * study chart and the weekly recaps they give. Only the inputs are read;
 * every recorded output is compared.
 */

interface FixtureRecord {
  id: string;
  source: string;
  kind: string;
  start: number;
  end?: number;
  quantity?: number;
  unit?: string;
  subject?: string;
  metadata: Record<string, string>;
}

interface FixtureInput {
  timeZone: string;
  firstWeekday: number;
  today: number;
  records: FixtureRecord[];
  freezePurchases: number[];
  recentDays: number;
  heatmapWeeks: number;
  monthLabelMinimumWeeks: number;
  recapWeeks: number;
}

interface FixtureCase {
  name: string;
  input: FixtureInput;
  output: unknown;
}

interface Fixture {
  schema: string;
  version: number;
  constants: Record<string, unknown>;
  milestones: {
    checks: { length: number; isMilestone: boolean }[];
    steps: { from?: number; to: number; reached?: number }[];
  };
  cases: FixtureCase[];
}

const fixture = loadFixture<Fixture>("streaks-recap/streaks-recap.json");

/* The recap stats' locale, `en_US` in the fixture, as a BCP 47 tag. */
const STATS_LOCALE = "en-US";

function record(input: FixtureRecord): ActivityRecord {
  return makeActivityRecord({
    id: input.id,
    source: input.source,
    kind: input.kind,
    start: input.start,
    end: input.end,
    quantity: input.quantity,
    unit: input.unit,
    subject: input.subject,
    metadata: input.metadata,
  });
}

function heatDay(day: HeatmapDay) {
  return { day: day.key, minutes: day.minutes, level: heatmapLevel(day.minutes), isToday: day.isToday };
}

/* StreaksRecapGoldenFixture.evaluate, over the ports. */
function evaluate(input: FixtureInput) {
  const calendar: DayCalendar = { timeZone: input.timeZone, firstWeekday: input.firstWeekday };
  const records = input.records.map(record);
  const progress = new PetMilestoneProgress(records, calendar);
  const streak = new StudyStreak(progress.studyDays, input.freezePurchases, input.today, calendar);
  const yesterday = new StudyStreak(progress.studyDays, input.freezePurchases, addingDays(input.today, -1, input.timeZone), calendar);
  const heatmap = new StudyHeatmap(progress.minutesByDay, input.heatmapWeeks, input.today, calendar);
  const latest = latestReadyWeek(input.today, input.timeZone);
  const weeks = Array.from({ length: input.recapWeeks }, (_, index) => addingWeeks(latest, index - (input.recapWeeks - 1)));
  const recaps = weeks.map((week) => WeeklyRecap.fromRecords(week, records, input.timeZone));
  return {
    progress: {
      minutesByDay: [...progress.minutesByDay.keys()].sort().map((day) => ({ day, minutes: progress.minutesByDay.get(day) ?? 0 })),
      studyDays: progress.studyDays,
      longestStreak: progress.longestStreak(),
      currentStreak: progress.currentStreak(input.today, calendar),
    },
    streak: {
      length: streak.length,
      studiedToday: streak.studiedToday,
      isActive: streak.isActive,
      needsStudyToday: streak.needsStudyToday,
      frozenDays: [...streak.frozenDays].sort(),
      freeFreezeAvailable: streak.freeFreezeAvailable,
      extraFreezes: streak.extraFreezes,
      canBuyFreeze: streak.canBuyFreeze,
      freezesReady: streak.freezesReady,
      recentDays: streak.recentDays(input.recentDays),
      lengthYesterday: yesterday.length,
      milestoneReached: streakMilestoneReached(yesterday.length, streak.length),
    },
    heatmap: {
      today: heatmap.today,
      weekdays: heatmap.weekdays,
      weeks: heatmap.weeks.map((week) => ({
        start: week.start,
        days: week.days.map((day) => (day ? heatDay(day) : null)),
        minutes: weekMinutes(week),
        studiedDays: weekStudiedDays(week),
      })),
      lastThirtyDaysMinutes: heatmap.lastThirtyDaysMinutes,
      bestDay: heatmap.bestDay ? heatDay(heatmap.bestDay) : undefined,
      monthLabels: heatmap.monthLabels(input.monthLabelMinimumWeeks),
    },
    recaps: {
      containingWeek: recapWeekContaining(input.today, input.timeZone),
      latestReadyWeek: latest,
      weeks: recaps.map((recap) => ({
        week: recap.week,
        end: recapWeekEnd(recap.week),
        readyDate: recapReadyDate(recap.week, input.timeZone),
        minutesByDay: recap.minutesByDay,
        sessions: recap.sessions,
        cardsReviewed: recap.cardsReviewed,
        tasksDone: recap.tasksDone,
        points: recap.points,
        longestStreak: recap.longestStreak,
        focusMinutes: recap.focusMinutes,
        isEmpty: recap.isEmpty,
        bestDay: recap.bestDay(),
        cheer: recap.cheer(recaps),
        stats: recapStats(recap, STATS_LOCALE).map((stat) => ({ kind: stat.kind, value: stat.value })),
      })),
    },
  };
}

describe("streaks-recap golden fixture", () => {
  it("is the format this suite reads", () => {
    expect(fixture.schema).toBe("tabbi.streaks-recap.golden");
    expect(fixture.version).toBe(1);
    expect(fixture.cases).toHaveLength(21);
  });

  it("has the same constants", () => {
    const constants = {
      freeFreezesPerWeek: StreakFreezeRules.freePerWeek,
      freezePrice: StreakFreezeRules.price(),
      maxHeldFreezes: StreakFreezeRules.maxHeld,
      minutesForStudyDay: PetMilestoneProgress.minutesForStudyDay,
      milestoneDays: STREAK_MILESTONE_DAYS,
      heatmapLevelCount: HEATMAP_LEVEL_COUNT,
      heatmapLevelThresholds: HEATMAP_LEVEL_THRESHOLDS,
      heatmapLabeledWeekdays: [...HEATMAP_LABELED_WEEKDAYS].sort(),
      recapReadyHour: RECAP_READY_HOUR,
      lightWeekMinutes: LIGHT_WEEK_MINUTES,
      pointsPerMinute: PetPointsRules.pointsPerMinute,
      minimumMinutes: PetPointsRules.minimumMinutes,
      completionBonus: PetPointsRules.completionBonus,
      bonusMinutes: PetPointsRules.bonusMinutes,
      sharedBonusPerFriend: PetPointsRules.sharedBonusPerFriend,
      maxSharedBonus: PetPointsRules.maxSharedBonus,
      partyFriendsKey: PARTY_FRIENDS_METADATA_KEY,
      stockLocale: "en_US",
    };
    expect(goldenDiff(constants, fixture.constants)).toBeUndefined();
  });

  it("checks and reaches the same streak milestones", () => {
    const milestones = {
      checks: fixture.milestones.checks.map(({ length }) => ({ length, isMilestone: isStreakMilestone(length) })),
      steps: fixture.milestones.steps.map(({ from, to }) => ({ from, to, reached: streakMilestoneReached(from, to) })),
    };
    expect(goldenDiff(milestones, fixture.milestones)).toBeUndefined();
  });

  it.each(fixture.cases.map((item) => [item.name, item] as const))("replays %s", (_, item) => {
    expect(goldenDiff(evaluate(item.input), item.output, `$.${item.name}`)).toBeUndefined();
  });
});
