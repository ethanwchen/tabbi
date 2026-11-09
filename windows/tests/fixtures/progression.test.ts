import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { makeActivityRecord } from "../../src/core/activity/activityRecord";
import { PetCloset } from "../../src/core/closet/petCloset";
import { editionItem, editionMasteryBadge, masteryEditions } from "../../src/core/closet/petLimited";
import { PetProfile } from "../../src/core/pets/petProfile";
import { PetSave } from "../../src/core/pets/petSave";
import { MonthlyQuests, questIsDone, questLabel } from "../../src/core/progression/monthlyQuests";
import { PetProgression } from "../../src/core/progression/petProgression";
import { MINUTES_FOR_STUDY_DAY, NAMED_METHODS, longestGentleStreak } from "../../src/core/progression/progressTally";
import { ProgressionSave } from "../../src/core/progression/progressionSave";
import {
  ALL_BADGES,
  PROGRESS_TIERS,
  PROGRESS_TRACKS,
  STEADY_WEEK_DAYS,
  badgeGoal,
  badgeID,
  compareBadges,
  progressLabel,
  trackThresholds,
  type ProgressTrack,
} from "../../src/core/progression/progressTrack";
import type { DayCalendar } from "../../src/core/streaks/dayCalendar";
import { switchLanguage } from "../support/catalogs";
import { loadFixture } from "../support/fixtures";
import { goldenDiff } from "../support/goldenCompare";

/*
 * Replays shared/fixtures/progression (written by ProgressionGoldenTests on
 * the Mac): every badge's tiers, the mastery outfits, the quest hash, short
 * labels, the gentle streak, whole progressions fed sample activity logs,
 * and how the progression save reads and writes. Only inputs are read;
 * every recorded output is compared.
 */

interface RecordJson {
  id: string;
  source: string;
  kind: string;
  unit?: string;
  start: number;
  end: number;
  quantity?: number;
  subject?: string;
  metadata: Record<string, string>;
}

interface ProgressionFixture {
  schema: string;
  version: number;
  constants: Record<string, unknown>;
  tracks: { id: string; thresholds: number[] }[];
  mastery: { item: string; edition: string; badge: string; goal: number }[];
  hashes: { text: string; hash: number }[];
  labels: { track: string; value: number; goal: number; label: string }[];
  streaks: {
    name: string;
    input: { timeZone: string; firstWeekday: number; studyDays: string[]; freezePurchases: number[]; today: number };
    longest: number;
  }[];
  scenarios: {
    name: string;
    input: { timeZone: string; firstWeekday: number; today: number; freezePurchases: number[]; save?: string; records: RecordJson[] };
    output: unknown;
  }[];
  saves: { name: string; json: string; output?: unknown }[];
}

const PATH = "progression/progression.json";
const recorded = existsSync(fileURLToPath(new URL(`../../../shared/fixtures/${PATH}`, import.meta.url)));

function expectGolden(actual: unknown, expected: unknown, label: string): void {
  expect(goldenDiff(actual, expected), label).toBeUndefined();
}

function record(json: RecordJson) {
  return makeActivityRecord({
    id: json.id,
    source: json.source,
    kind: json.kind,
    start: json.start,
    end: json.end,
    ...(json.quantity === undefined ? {} : { quantity: json.quantity }),
    ...(json.unit === undefined ? {} : { unit: json.unit }),
    ...(json.subject === undefined ? {} : { subject: json.subject }),
    metadata: json.metadata,
  });
}

describe.skipIf(!recorded)("progression golden fixture", () => {
  let fixture: ProgressionFixture;
  beforeAll(() => {
    switchLanguage("en");
    fixture = loadFixture<ProgressionFixture>(PATH);
  });

  it("is the progression fixture", () => {
    expect(fixture.schema).toBe("tabbi.progression.golden");
    expect(fixture.version).toBe(1);
  });

  it("has the same constants, tracks and mastery outfits", () => {
    expectGolden(
      {
        tiers: [...PROGRESS_TIERS],
        namedMethods: [...NAMED_METHODS],
        steadyWeekDays: STEADY_WEEK_DAYS,
        minutesForStudyDay: MINUTES_FOR_STUDY_DAY,
        questCount: MonthlyQuests.count,
        questCore: [...MonthlyQuests.core],
        questExtras: [...MonthlyQuests.extras],
        questTargets: { ...MonthlyQuests.targets },
        saveSchemaVersion: ProgressionSave.schema.current,
      },
      fixture.constants,
      "constants",
    );
    expectGolden(PROGRESS_TRACKS.map((id) => ({ id, thresholds: [...trackThresholds(id)] })), fixture.tracks, "tracks");
    expectGolden(
      masteryEditions().map((edition) => {
        const badge = editionMasteryBadge(edition);
        if (!badge) throw new Error(edition);
        return { item: editionItem(edition), edition, badge: badgeID(badge), goal: badgeGoal(badge) };
      }),
      fixture.mastery,
      "mastery",
    );
  });

  it("hashes and labels the same", () => {
    for (const row of fixture.hashes) expect(MonthlyQuests.hash(row.text), row.text).toBe(row.hash);
    for (const row of fixture.labels) {
      expect(progressLabel(row.track as ProgressTrack, row.value, row.goal), JSON.stringify(row)).toBe(row.label);
    }
  });

  it("finds the same longest gentle streak", () => {
    for (const row of fixture.streaks) {
      const calendar: DayCalendar = { timeZone: row.input.timeZone, firstWeekday: row.input.firstWeekday };
      expect(longestGentleStreak(row.input.studyDays, row.input.freezePurchases, row.input.today, calendar), row.name).toBe(row.longest);
    }
  });

  it("counts, picks quests and unlocks the same for every scenario", () => {
    for (const scenario of fixture.scenarios) {
      const input = scenario.input;
      const calendar: DayCalendar = { timeZone: input.timeZone, firstWeekday: input.firstWeekday };
      const save = input.save === undefined ? new ProgressionSave() : ProgressionSave.decode(input.save);
      const progression = new PetProgression(save);
      for (const json of input.records) progression.add(record(json), calendar);
      const change = progression.refresh(input.today, input.freezePurchases, calendar);
      const closet = new PetCloset(new PetSave(new PetProfile("Mochi", "tuxedo")));
      const unlocked = closet.unlockMastery(progression);
      const tiers: Record<string, string> = {};
      for (const track of PROGRESS_TRACKS) {
        const tier = progression.tier(track);
        if (tier !== undefined) tiers[track] = tier;
      }
      expectGolden(
        {
          values: Object.fromEntries(PROGRESS_TRACKS.map((track) => [track, progression.value(track)])),
          tiers,
          reachedBadges: [...change.badges].sort(compareBadges).map(badgeID),
          completedMonths: [...progression.save.completedMonths].sort(),
          quests: progression.quests(input.today, calendar).map((quest) => ({
            track: quest.quest.track,
            target: quest.quest.target,
            value: quest.value,
            isDone: questIsDone(quest),
            label: questLabel(quest),
          })),
          unlocked,
          progress: Object.fromEntries(ALL_BADGES.map((badge) => [badgeID(badge), progression.progress(badge).label])),
        },
        scenario.output,
        scenario.name,
      );
    }
  });

  it("reads and writes saves the same", () => {
    for (const row of fixture.saves) {
      let output: unknown;
      try {
        const save = ProgressionSave.decode(row.json);
        output = {
          best: Object.fromEntries(save.best),
          reached: Object.fromEntries(save.reached),
          completedMonths: [...save.completedMonths].sort(),
          seen: [...save.seen].sort(),
          encoded: save.encoded(),
        };
      } catch {
        output = undefined;
      }
      if (row.output === undefined) expect(output, row.name).toBeUndefined();
      else expectGolden(output, row.output, row.name);
    }
  });
});
