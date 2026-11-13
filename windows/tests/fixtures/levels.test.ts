import { beforeAll, describe, expect, it } from "vitest";
import { ACTIVITY_KINDS, ACTIVITY_UNITS, makeActivityRecord } from "../../src/core/activity/activityRecord";
import { sharingStanding } from "../../src/core/party/partyModels";
import { colorHex } from "../../src/core/pets/petPalette";
import { PetProgression, changeUnlocksSomething } from "../../src/core/progression/petProgression";
import { ProgressTally } from "../../src/core/progression/progressTally";
import { ProgressionSave } from "../../src/core/progression/progressionSave";
import { RANK_ART_SIZE, RANK_EMBLEM_SIZE, RANK_PIP_ORIGINS, rankColors } from "../../src/core/progression/rankArt";
import {
  CURVE_EXPONENT,
  CURVE_SCALE,
  LEVELS_PER_NAMEPLATE,
  LEVELS_PER_RANK,
  MAX_PIPS,
  MAX_SHARED_LEVEL,
  NAMEPLATES,
  RANK_TIERS,
  hoursToReach,
  isNameplate,
  levelFraction,
  levelFromMinutes,
  makeRank,
  minutesToReach,
  nameplateGlows,
  nameplateHex,
  nameplateUnlockLevel,
  nextNameplate,
  rankFirstLevel,
  rankForLevel,
  rankID,
  rankPips,
  romanNumeral,
  unlockedNameplates,
  type StudyRank,
} from "../../src/core/progression/studyLevel";
import type { DayCalendar } from "../../src/core/streaks/dayCalendar";
import { switchLanguage } from "../support/catalogs";
import { loadFixture } from "../support/fixtures";
import { goldenDiff } from "../support/goldenCompare";

/*
 * Replays shared/fixtures/progression/levels.json (written by
 * StudyLevelGoldenTests on the Mac): the Study Level's curve, the level and
 * rank for a spread of focus totals, Roman numerals, the nameplate colors,
 * every rank emblem's pixels, how the progression save's level fields read
 * and write, and progressions replayed from a save and a focus total. Only
 * inputs are read; every recorded output is compared.
 */

interface LevelsFixture {
  schema: string;
  version: number;
  constants: Record<string, unknown>;
  curve: { level: number; hours: number; minutes: number }[];
  levels: (Record<string, unknown> & { focusMinutes: number })[];
  roman: Record<string, string>;
  nameplates: { id: string; unlockLevel: number; color: string; glows: boolean }[];
  emblems: { rank: string; colors: string[]; rle: string }[];
  saves: { name: string; json: string; output?: unknown }[];
  scenarios: {
    name: string;
    input: { save?: string; focusMinutes?: number; picks: string[]; markSeen: boolean };
    output: unknown;
  }[];
}

const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const UTC: DayCalendar = { timeZone: "UTC", firstWeekday: 1 };

function runLength(rows: readonly string[]): string {
  return rows
    .map((row) => {
      let out = "";
      let index = 0;
      while (index < row.length) {
        const symbol = row[index] ?? "";
        let count = 1;
        while (row[index + count] === symbol) count++;
        out += (count > 1 ? String(count) : "") + symbol;
        index += count;
      }
      return out;
    })
    .join("/");
}

/* What the Mac's encoder writes: nil optionals are left out. */
function plain(value: unknown): unknown {
  return JSON.parse(JSON.stringify(value)) as unknown;
}

function expectGolden(actual: unknown, expected: unknown, label: string): void {
  expect(goldenDiff(plain(actual), expected), label).toBeUndefined();
}

function rankFromID(id: string): StudyRank {
  const [tier, numeral] = id.split("-");
  const found = RANK_TIERS.find((candidate) => candidate === tier);
  if (!found) throw new Error(id);
  return makeRank(found, numeral === undefined ? 1 : Number(numeral));
}

describe("Study Level golden fixture", () => {
  let fixture: LevelsFixture;
  beforeAll(() => {
    switchLanguage("en");
    fixture = loadFixture<LevelsFixture>("progression/levels.json");
  });

  it("is the levels fixture with the same constants", () => {
    expect(fixture.schema).toBe("tabbi.levels.golden");
    expect(fixture.version).toBe(1);
    expectGolden(
      {
        curveScale: CURVE_SCALE,
        curveExponent: CURVE_EXPONENT,
        levelsPerNameplate: LEVELS_PER_NAMEPLATE,
        levelsPerRank: LEVELS_PER_RANK,
        maxShared: MAX_SHARED_LEVEL,
        rankTiers: [...RANK_TIERS],
        emblemSize: RANK_EMBLEM_SIZE,
        canvasSize: RANK_ART_SIZE,
        maxPips: MAX_PIPS,
        saveSchemaVersion: ProgressionSave.schema.current,
      },
      fixture.constants,
      "constants",
    );
    expect(RANK_PIP_ORIGINS).toHaveLength(MAX_PIPS);
  });

  it("follows the same curve to the hour", () => {
    for (const row of fixture.curve) {
      expect(hoursToReach(row.level), `level ${row.level}`).toBe(row.hours);
      expect(minutesToReach(row.level), `level ${row.level}`).toBe(row.minutes);
    }
  });

  it("reaches the same level, rank and nameplates for every focus total", () => {
    for (const row of fixture.levels) {
      const minutes = row.focusMinutes;
      const level = levelFromMinutes(minutes);
      const rank = rankForLevel(level);
      expectGolden(
        {
          focusMinutes: minutes,
          level,
          rank: rankID(rank),
          numeral: rank.numeral,
          pips: rankPips(rank),
          rankFirstLevel: rankFirstLevel(rank),
          fraction: levelFraction(level, minutes),
          nameplates: unlockedNameplates(level),
          nextNameplate: nextNameplate(level),
        },
        row,
        `${minutes} minutes`,
      );
    }
  });

  it("writes the same Roman numerals and nameplates", () => {
    for (const [n, text] of Object.entries(fixture.roman)) expect(romanNumeral(Number(n)), n).toBe(text);
    expectGolden(
      NAMEPLATES.map((id) => ({ id, unlockLevel: nameplateUnlockLevel(id), color: nameplateHex(id), glows: nameplateGlows(id) })),
      fixture.nameplates,
      "nameplates",
    );
  });

  it("draws every emblem to the same colors, pixel for pixel", () => {
    expect(fixture.emblems.length).toBeGreaterThan(6);
    for (const entry of fixture.emblems) {
      const colors: string[] = [];
      const symbols = rankColors(rankFromID(entry.rank)).map((color) => {
        if (!color) return ".";
        const hex = colorHex(color);
        let index = colors.indexOf(hex);
        if (index < 0) index = colors.push(hex) - 1;
        return LETTERS[index] ?? "?";
      });
      const rows: string[] = [];
      for (let y = 0; y < RANK_ART_SIZE; y++) rows.push(symbols.slice(y * RANK_ART_SIZE, (y + 1) * RANK_ART_SIZE).join(""));
      expect(colors, entry.rank).toEqual(entry.colors);
      expect(runLength(rows), entry.rank).toBe(entry.rle);
    }
  });

  it("reads and writes the save's level fields the same", () => {
    for (const row of fixture.saves) {
      let output: unknown;
      try {
        const save = ProgressionSave.decode(row.json);
        output = {
          level: save.level,
          levelSeen: save.levelSeen,
          nameplate: save.nameplate,
          bestFocusMinutes: save.best.get("focusHours"),
          encoded: save.encoded(),
        };
      } catch {
        output = undefined;
      }
      if (row.output === undefined) expect(output, row.name).toBeUndefined();
      else expectGolden(output, row.output, row.name);
    }
  });

  it("replays every scenario the same", () => {
    for (const scenario of fixture.scenarios) {
      const input = scenario.input;
      let save = new ProgressionSave();
      if (input.save !== undefined) {
        try {
          save = ProgressionSave.decode(input.save);
        } catch {
          save = new ProgressionSave();
        }
      }
      const tally = new ProgressTally();
      if (input.focusMinutes !== undefined) {
        tally.add(
          makeActivityRecord({
            id: "6F1C2A4E-0000-4000-8000-000000000001",
            source: "focus",
            kind: ACTIVITY_KINDS.focusCompleted,
            start: 1_790_000_000,
            end: 1_790_000_000 + input.focusMinutes * 60,
            quantity: input.focusMinutes,
            unit: ACTIVITY_UNITS.minutes,
            metadata: {},
          }),
          UTC,
        );
      }
      const progression = new PetProgression(save, tally);
      const change = progression.refresh(1_800_000_000, [], UTC);
      const picked = input.picks.map((id) => (isNameplate(id) ? progression.pick(id) : false));
      if (input.markSeen) progression.markSeen();
      const shared = sharingStanding({}, progression.standing);
      expectGolden(
        {
          level: progression.studyLevel,
          rank: rankID(rankForLevel(progression.studyLevel)),
          levelsGained: change.levels.length,
          firstLevelGained: change.levels[0],
          lastLevelGained: change.levels[change.levels.length - 1],
          unlocksSomething: changeUnlocksSomething(change),
          picked,
          nameplate: progression.nameplate,
          hasUnseenLevel: progression.hasUnseenLevel,
          savedLevel: progression.save.level,
          savedLevelSeen: progression.save.levelSeen,
          sharedLevel: shared.studyLevel ?? -1,
          sharedNameplate: shared.nameplate ?? "",
        },
        scenario.output,
        scenario.name,
      );
    }
  });
});
