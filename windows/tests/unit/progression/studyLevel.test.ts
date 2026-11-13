import { beforeAll, describe, expect, it } from "vitest";
import { ACTIVITY_KINDS, ACTIVITY_METADATA, ACTIVITY_UNITS, makeActivityRecord } from "../../../src/core/activity/activityRecord";
import { profileStanding, readProfile, sharingStanding, withoutStudyLevel } from "../../../src/core/party/partyModels";
import { profileBody } from "../../../src/core/party/partyClient";
import { contrastRatio, luminance, petColor } from "../../../src/core/pets/petPalette";
import { PetProgression, changeUnlocksSomething } from "../../../src/core/progression/petProgression";
import { ProgressTally } from "../../../src/core/progression/progressTally";
import { ProgressionSave } from "../../../src/core/progression/progressionSave";
import { RANK_ART_SIZE, rankBitmap, rankCanvas } from "../../../src/core/progression/rankArt";
import {
  NAMEPLATES,
  RANK_TIERS,
  hoursToReach,
  levelFraction,
  levelFromMinutes,
  makeRank,
  nameplateColor,
  rankForLevel,
  rankID,
  rankName,
  romanNumeral,
  unlockedNameplates,
} from "../../../src/core/progression/studyLevel";
import type { DayCalendar } from "../../../src/core/streaks/dayCalendar";
import { switchLanguage } from "../../support/catalogs";

/* Port of StudyLevelTests: the curve, ranks, nameplates, emblems, the save, the quiet replay and the Party fields. */

const BERLIN: DayCalendar = { timeZone: "Europe/Berlin", firstWeekday: 2 };
const NOW = 1_790_000_000;

function focus(minutes: number, daysAgo: number, metadata: Record<string, string> = {}) {
  const end = NOW - daysAgo * 86_400;
  return makeActivityRecord({
    source: "focus",
    kind: ACTIVITY_KINDS.focusCompleted,
    start: end - minutes * 60,
    end,
    quantity: minutes,
    unit: ACTIVITY_UNITS.minutes,
    metadata,
  });
}

describe("Study Level", () => {
  beforeAll(() => switchLanguage("en"));

  it("follows the design table", () => {
    const expected: Record<number, number> = { 1: 4, 2: 12, 5: 53, 10: 159, 13: 242, 25: 690, 37: 1292, 50: 2091, 64: 3104, 100: 6340, 999: 251_979 };
    for (const [level, hours] of Object.entries(expected)) expect(hoursToReach(Number(level)), level).toBe(hours);
    expect(hoursToReach(0)).toBe(0);
    expect(levelFromMinutes(239)).toBe(0);
    expect(levelFromMinutes(240)).toBe(1);
    expect(levelFromMinutes(242 * 60)).toBe(13);
    expect(levelFromMinutes(300_000 * 60)).toBe(1114);
    expect(levelFraction(0, 120)).toBe(0.5);
  });

  it("names ranks every ten levels and counts on past Galaxy", () => {
    const cases: [number, string][] = [[0, "spark"], [10, "ember"], [20, "comet"], [30, "nova"], [40, "nebula"], [50, "galaxy"], [60, "galaxy-2"], [70, "galaxy-3"], [140, "galaxy-10"]];
    for (const [level, id] of cases) expect(rankID(rankForLevel(level)), String(level)).toBe(id);
    expect(romanNumeral(14)).toBe("XIV");
    expect(rankName(rankForLevel(60))).toBe("Galaxy II");
    expect(rankName(rankForLevel(12))).toBe("Ember");
  });

  it("unlocks a nameplate every five levels, each readable on black", () => {
    expect(unlockedNameplates(4)).toEqual(["plain"]);
    expect(unlockedNameplates(5)).toEqual(["plain", "peach"]);
    expect(unlockedNameplates(60)).toEqual([...NAMEPLATES]);
    const black = luminance(petColor(0, 0, 0));
    for (const nameplate of NAMEPLATES) expect(contrastRatio(luminance(nameplateColor(nameplate)), black), nameplate).toBeGreaterThanOrEqual(7);
  });

  it("draws every named rank its own emblem, and a star per Galaxy numeral", () => {
    const named = RANK_TIERS.map((tier) => rankCanvas(makeRank(tier)).symbols());
    expect(new Set(named).size).toBe(RANK_TIERS.length);
    const gold = (numeral: number) => {
      const canvas = rankCanvas(makeRank("galaxy", numeral));
      let count = 0;
      for (let y = 0; y < canvas.height; y++) for (let x = 0; x < canvas.width; x++) if (canvas.role(x, y) === "gold") count++;
      return count;
    };
    expect(gold(2) - gold(1)).toBe(4);
    expect(gold(9)).toBe(gold(5));
    expect(rankBitmap(rankForLevel(64), 4).width).toBe(RANK_ART_SIZE * 4);
  });

  it("lands a long history at its real level quietly, with a dot, and keeps it when logs go", () => {
    const records = Array.from({ length: 40 }, (_, index) => focus(360, index + 1));
    const progression = new PetProgression(new ProgressionSave(), new ProgressTally(records, BERLIN));
    const change = progression.refresh(NOW, [], BERLIN);
    expect(progression.studyLevel).toBe(12);
    expect(change.levels).toEqual(Array.from({ length: 12 }, (_, index) => index + 1));
    expect(changeUnlocksSomething(change)).toBe(true);
    expect(progression.hasUnseenLevel).toBe(true);
    expect(progression.markSeen()).toBe(true);
    expect(progression.hasUnseenLevel).toBe(false);
    const reread = new PetProgression(ProgressionSave.decode(progression.save.encoded()));
    reread.refresh(NOW, [], BERLIN);
    expect(reread.studyLevel).toBe(12);
    const lost = new PetProgression(new ProgressionSave({ level: 12, levelSeen: 12 }));
    lost.refresh(NOW, [], BERLIN);
    expect(lost.studyLevel).toBe(12);
  });

  it("picks a nameplate only once unlocked", () => {
    const progression = new PetProgression(new ProgressionSave({ best: new Map([["focusHours", 242 * 60]]), level: 13 }));
    expect(progression.pick("honey")).toBe(false);
    expect(progression.pick("ember")).toBe(true);
    expect(progression.standing).toEqual({ level: 13, nameplate: "ember" });
    expect(progression.pick("plain")).toBe(true);
    expect(progression.save.nameplate).toBeUndefined();
  });

  it("migrates a version 1 save to no level yet", () => {
    const save = ProgressionSave.decode('{"schemaVersion":1,"best":{"focusHours":15000}}');
    expect(save.level).toBe(0);
    const progression = new PetProgression(save);
    expect(progression.refresh(NOW, [], BERLIN).levels).toHaveLength(13);
    expect(progression.save.encoded()).toContain('"schemaVersion" : 2');
    const odd = ProgressionSave.decode('{"schemaVersion":2,"level":-4,"levelSeen":"x","nameplate":"neon"}');
    expect([odd.level, odd.levelSeen, odd.nameplate]).toEqual([0, 0, undefined]);
  });

  it("never pays points for a level: the progression has no ledger to touch", () => {
    const history = Array.from({ length: 23 }, (_, index) => focus(10, index + 1));
    const progression = new PetProgression(new ProgressionSave(), new ProgressTally(history, BERLIN));
    progression.refresh(NOW, [], BERLIN);
    const before = progression.save.encoded();
    progression.add(focus(25, 0, { [ACTIVITY_METADATA.outcome]: "skipped" }), BERLIN);
    const change = progression.refresh(NOW, [], BERLIN);
    expect(change.levels).toEqual([1]);
    expect(progression.save.encoded()).not.toBe(before);
    expect(progression.save.encoded()).not.toContain("points");
  });

  it("reads friends' levels leniently and drops them for older servers", () => {
    const base = { code: "K7QW2MZD", name: "Ana", petName: "Mochi", species: "cat", breed: "tabby", colors: [], costume: "none", accessories: [], points: 0, level: 1 };
    expect(profileStanding(readProfile({ ...base, studyLevel: 37, nameplate: "lilac" }))).toEqual({ level: 37, nameplate: "lilac" });
    expect(profileStanding(readProfile(base))).toBeUndefined();
    expect(profileStanding(readProfile({ ...base, studyLevel: "12" }))).toBeUndefined();
    expect(profileStanding(readProfile({ ...base, studyLevel: 5000 }))).toBeUndefined();
    expect(profileStanding(readProfile({ ...base, studyLevel: 12, nameplate: "future" }))?.nameplate).toBe("plain");
    const update = sharingStanding({ petName: "Mochi" }, { level: 1200, nameplate: "gold" });
    expect(profileBody(update)).toEqual({ petName: "Mochi", studyLevel: 999, nameplate: "gold" });
    expect(profileBody(withoutStudyLevel(update))).toEqual({ petName: "Mochi" });
  });
});
