import { describe, expect, it } from "vitest";
import { ACTIVITY_KINDS, ACTIVITY_METADATA, ACTIVITY_UNITS, type ActivityRecord } from "../../../src/core/activity/activityRecord";
import { PetCloset } from "../../../src/core/closet/petCloset";
import { editionMasteryBadge, howToEarn, isLimited, masteryEditions, editionItem } from "../../../src/core/closet/petLimited";
import { itemParts, outfitItem, accessoryItem } from "../../../src/core/pets/petItem";
import { accessorySlot } from "../../../src/core/pets/petCostume";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { PetSave } from "../../../src/core/pets/petSave";
import { PetPointsLedger, isFree, itemCost } from "../../../src/core/pets/petUnlocks";
import { MonthlyQuests, monthAt, nextMonth } from "../../../src/core/progression/monthlyQuests";
import { PetProgression, changeIsEmpty } from "../../../src/core/progression/petProgression";
import { progressionDemo } from "../../../src/core/progression/progressionDemo";
import { ProgressTally, longestGentleStreak } from "../../../src/core/progression/progressTally";
import { ProgressionSave } from "../../../src/core/progression/progressionSave";
import {
  ALL_BADGES,
  PROGRESS_TIERS,
  PROGRESS_TRACKS,
  badgeFromID,
  badgeGoal,
  badgeHowToEarn,
  badgeID,
  progressLabel,
  tierFor,
  trackGoal,
  trackThresholds,
} from "../../../src/core/progression/progressTrack";
import { addDays, dayKey, startOfDay, type DayCalendar } from "../../../src/core/streaks/dayCalendar";
import { StudyStreak } from "../../../src/core/streaks/studyStreak";
import { activity } from "../../support/activity";

// Ports of ProgressTallyTests, GentleStreakTests and PetProgressionTests.

let nextID = 0;

function at(day: string, hour: number, calendar: DayCalendar): number {
  return startOfDay(day, calendar) + hour * 3600;
}

function focus(
  minutes: number,
  end: number,
  options: { source?: string; outcome?: string | undefined; method?: string; friends?: number } = {},
): ActivityRecord {
  nextID += 1;
  const metadata: Record<string, string> = {};
  const outcome = "outcome" in options ? options.outcome : "completed";
  if (outcome !== undefined) metadata[ACTIVITY_METADATA.outcome] = outcome;
  if (options.method !== undefined) metadata[ACTIVITY_METADATA.method] = options.method;
  if (options.friends !== undefined) metadata.friends = String(options.friends);
  return activity({
    id: `focus-${nextID}`,
    source: options.source ?? "focus",
    kind: ACTIVITY_KINDS.focusCompleted,
    end,
    start: end - minutes * 60,
    quantity: minutes,
    unit: ACTIVITY_UNITS.minutes,
    metadata,
  });
}

function other(kind: string, end: number, fields: { quantity?: number; unit?: string; subject?: string; source?: string } = {}): ActivityRecord {
  nextID += 1;
  return activity({ id: `other-${nextID}`, source: fields.source ?? "closet", kind, end, ...fields });
}

describe("ProgressTally", () => {
  const berlin: DayCalendar = { timeZone: "Europe/Berlin", firstWeekday: 2 };
  const on = (day: number, hour = 12) => at(`2026-11-${String(day).padStart(2, "0")}`, hour, berlin);

  it("counts focus minutes, sessions and study days", () => {
    const tally = new ProgressTally();
    tally.add(focus(25, on(2)), berlin);
    tally.add(focus(10, on(2), { outcome: "skipped" }), berlin);
    tally.add(focus(4, on(3)), berlin);
    expect(tally.total("focusHours")).toBe(39);
    expect(tally.total("sessions")).toBe(2);
    expect(tally.total("studyDays")).toBe(1);
    expect(tally.studyDays).toEqual(["2026-11-02"]);
  });

  it("counts the same record once", () => {
    const record = focus(30, on(2));
    const tally = new ProgressTally([record, record], berlin);
    tally.add(record, berlin);
    expect(tally.total("focusHours")).toBe(30);
    expect(tally.total("sessions")).toBe(1);
  });

  it("counts only named methods", () => {
    const tally = new ProgressTally(
      ["pomodoro", "pomodoro", "fiftyTwoSeventeen", "timer", "custom", "lecture"].map((method) => focus(10, on(2), { method })),
      berlin,
    );
    expect(tally.total("methods")).toBe(2);
  });

  it("counts Party sessions that ran to the end with a friend", () => {
    const tally = new ProgressTally(
      [
        focus(25, on(2), { source: "party", friends: 2 }),
        focus(25, on(2, 13), { source: "party", friends: 0 }),
        focus(10, on(2, 14), { source: "party", outcome: "skipped", friends: 3 }),
        focus(25, on(2, 15), { source: "focus", friends: 3 }),
      ],
      berlin,
    );
    expect(tally.total("party")).toBe(1);
  });

  it("counts cards, distinct tasks, moves and water", () => {
    const day = on(2);
    const tally = new ProgressTally(
      [
        other(ACTIVITY_KINDS.cardsReviewed, day, { source: "anki", quantity: 120, unit: "cards" }),
        other(ACTIVITY_KINDS.cardsReviewed, day, { source: "anki", quantity: -5, unit: "cards" }),
        other(ACTIVITY_KINDS.taskCompleted, day, { source: "planner", quantity: 1, subject: "a" }),
        other(ACTIVITY_KINDS.taskCompleted, day + 60, { source: "planner", quantity: 1, subject: "a" }),
        other(ACTIVITY_KINDS.taskCompleted, day, { source: "planner", quantity: 1, subject: "b" }),
        other(ACTIVITY_KINDS.taskCompleted, day, { source: "leetcode" }),
        other("break.move", day, { subject: "stretch" }),
        other("break.move", day, { subject: "breathe" }),
        other("water.logged", day, { quantity: 1, unit: "glass" }),
        other("water.logged", day, { quantity: 1, unit: "glass" }),
        other("water.logged", day, { quantity: 3, unit: "glass" }),
        other(ACTIVITY_KINDS.breakTaken, day, { source: "focus", quantity: 5, unit: "min" }),
      ],
      berlin,
    );
    expect(tally.total("cards")).toBe(120);
    expect(tally.total("tasks")).toBe(3);
    expect(tally.total("breakMoves")).toBe(2);
    expect(tally.total("water")).toBe(5);
    expect(tally.total("focusHours")).toBe(0);
  });

  it("counts steady weeks of three study days, Monday to Sunday", () => {
    const records = [2, 4, 8, 9, 15, 16, 17, 18].map((day) => focus(20, on(day)));
    records.push(focus(3, on(19)));
    expect(new ProgressTally(records, berlin).steadyWeeks()).toBe(2);
  });

  it("knows the first day of each track", () => {
    const tally = new ProgressTally(
      [focus(30, at("2026-10-07", 12, berlin)), other(ACTIVITY_KINDS.cardsReviewed, at("2026-09-03", 12, berlin), { quantity: 5, unit: "cards" })],
      berlin,
    );
    expect(tally.firstDay("cards")).toBe("2026-09-03");
    expect(tally.firstDay("focusHours")).toBe("2026-10-07");
    expect(tally.firstDay("water")).toBeUndefined();
  });
});

describe("longestGentleStreak", () => {
  const newYork: DayCalendar = { timeZone: "America/New_York", firstWeekday: 1 };
  const day = (offset: number) => addDays("2026-11-01", offset);
  const instant = (offset: number) => at(day(offset), 12, newYork);

  it("bridges one missed day a week with the free freeze", () => {
    const days = [...Array(14).keys()].filter((offset) => offset !== 3).map(day);
    expect(longestGentleStreak(days, [], instant(14), newYork)).toBe(13);
  });

  it("keeps the longest run after two misses in a week end it", () => {
    const days = [...[...Array(10).keys()], 12, 13, 14].map(day);
    expect(longestGentleStreak(days, [], instant(20), newYork)).toBe(10);
  });

  it("lets an extra freeze bought before the miss keep the run", () => {
    const days = [...Array(9).keys()].filter((offset) => offset !== 2 && offset !== 3).map(day);
    expect(longestGentleStreak(days, [], instant(9), newYork)).toBe(5);
    expect(longestGentleStreak(days, [instant(1)], instant(9), newYork)).toBe(7);
  });

  it("counts today once studied", () => {
    expect(longestGentleStreak([0, 1, 2].map(day), [], instant(2), newYork)).toBe(3);
    expect(longestGentleStreak([], [], instant(2), newYork)).toBe(0);
  });

  it("matches the Streak section while a run goes on", () => {
    let seed = 7;
    const random = () => {
      seed = (seed * 1103515245 + 12345) % 2147483648;
      return seed / 2147483648;
    };
    const start = "2026-09-01";
    const days = [...Array(60).keys()].filter(() => random() < 0.85).map((offset) => addDays(start, offset));
    const freezes = [at(addDays(start, 20), 12, newYork)];
    let longest = 0;
    for (let offset = 0; offset < 60; offset++) {
      const today = at(addDays(start, offset), 12, newYork);
      longest = Math.max(longest, new StudyStreak(days, freezes, today, newYork).length);
      expect(longestGentleStreak(days, freezes, today, newYork), `day ${offset}`).toBe(longest);
    }
  });
});

describe("PetProgression", () => {
  const tokyo: DayCalendar = { timeZone: "Asia/Tokyo", firstWeekday: 2 };
  const on = (month: number, day: number, hour = 12) => at(`2026-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`, hour, tokyo);

  it("gives every track four rising tiers", () => {
    for (const track of PROGRESS_TRACKS) {
      const thresholds = trackThresholds(track);
      expect(thresholds).toHaveLength(4);
      expect([...thresholds].sort((a, b) => a - b)).toEqual([...thresholds]);
      expect(new Set(thresholds).size).toBe(4);
      expect(tierFor(track, (thresholds[0] ?? 0) - 1)).toBeUndefined();
      expect(tierFor(track, thresholds[0] ?? 0)).toBe("bronze");
      expect(tierFor(track, (thresholds[3] ?? 0) * 2)).toBe("starlight");
    }
    expect(ALL_BADGES).toHaveLength(48);
  });

  it("round-trips badge ids", () => {
    for (const badge of ALL_BADGES) expect(badgeFromID(badgeID(badge))).toEqual(badge);
    expect(badgeFromID("focusHours.5")).toBeUndefined();
    expect(badgeFromID("naps.1")).toBeUndefined();
    expect(badgeID({ track: "focusHours", tier: "gold" })).toBe("focusHours.3");
  });

  it("writes short labels that round down", () => {
    expect(progressLabel("focusHours", 119, 600)).toBe("1/10 h");
    expect(progressLabel("focusHours", 900, 600)).toBe("10/10 h");
    expect(progressLabel("cards", 4210, 10_000)).toBe("4210/10k");
    expect(progressLabel("cards", 12_900, 30_000)).toBe("12k/30k");
    expect(progressLabel("studyDays", -3, 30)).toBe("0/30");
  });

  it("hashes quests with FNV-1a", () => {
    expect(MonthlyQuests.hash("")).toBe(0x811c9dc5);
    expect(MonthlyQuests.hash("a")).toBe(0xe40c292c);
    expect(MonthlyQuests.hash("foobar")).toBe(0xbf9cf968);
  });

  it("gives a new user three focus quests and offers extras only after they did them", () => {
    expect(new Set(MonthlyQuests.quests("2026-11", new ProgressTally()).map((quest) => quest.track))).toEqual(new Set(MonthlyQuests.core));
    const tally = new ProgressTally([other(ACTIVITY_KINDS.cardsReviewed, on(11, 5), { quantity: 50, unit: "cards" })], tokyo);
    expect(MonthlyQuests.quests("2026-11", tally).some((quest) => quest.track === "cards")).toBe(false);
    let offered = false;
    let month = "2026-12";
    for (let index = 0; index < 12; index++) {
      const quests = MonthlyQuests.quests(month, tally);
      expect(quests).toHaveLength(3);
      expect(quests.some((quest) => MonthlyQuests.core.includes(quest.track))).toBe(true);
      offered = offered || quests.some((quest) => quest.track === "cards");
      month = nextMonth(month);
    }
    expect(offered).toBe(true);
  });

  it("completes a month when all three quests are done", () => {
    const records: ActivityRecord[] = [];
    for (let day = 1; day <= 10; day++) {
      records.push(focus(30, on(11, day)));
      records.push(focus(30, on(11, day, 15)));
    }
    const tally = new ProgressTally(records, tokyo);
    expect(MonthlyQuests.isComplete("2026-11", tally)).toBe(true);
    expect(MonthlyQuests.completedMonths(tally, on(11, 30), tokyo)).toEqual(["2026-11"]);
    expect(MonthlyQuests.completedMonths(tally, on(10, 30), tokyo)).toEqual([]);
    expect(monthAt(on(11, 30), tokyo)).toBe("2026-11");
  });

  it("reaches tiers once and reports only new ones", () => {
    const progression = new PetProgression();
    for (let day = 1; day <= 7; day++) progression.add(focus(100, on(11, day)), tokyo);
    const first = progression.refresh(on(11, 7), [], tokyo);
    const ids = first.badges.map(badgeID);
    expect(ids).toEqual(expect.arrayContaining(["focusHours.1", "studyDays.1", "gentleStreak.1"]));
    expect(progression.tier("focusHours")).toBe("bronze");
    expect(progression.nextTier("focusHours")).toBe("silver");
    expect(progression.value("focusHours")).toBe(700);
    expect(progression.progress({ track: "focusHours", tier: "silver" }).label).toBe("11/50 h");
    expect(changeIsEmpty(progression.refresh(on(11, 7), [], tokyo))).toBe(true);
    expect(progression.unseen.map(badgeID).sort()).toEqual([...ids].sort());
    expect(progression.markSeen()).toBe(true);
    expect(progression.markSeen()).toBe(false);
  });

  it("keeps progress in the save when the log is gone", () => {
    const progression = new PetProgression();
    for (let day = 1; day <= 30; day++) progression.add(focus(30, on(10, day)), tokyo);
    progression.refresh(on(10, 30), [], tokyo);
    expect(progression.tier("studyDays")).toBe("silver");
    const relaunched = new PetProgression(ProgressionSave.decode(progression.save.encoded()));
    relaunched.add(focus(30, on(11, 2)), tokyo);
    relaunched.refresh(on(11, 2), [], tokyo);
    expect(relaunched.value("studyDays")).toBe(30);
    expect(relaunched.tier("studyDays")).toBe("silver");
  });

  it("reads saves forgivingly", () => {
    const save = ProgressionSave.decode(
      `{"schemaVersion":3,"best":{"focusHours":90,"naps":4},"reached":{"focusHours.1":"2026-10-30T03:00:00Z","naps.1":"2026-10-30T03:00:00Z","focusHours.9":"2026-10-30T03:00:00Z"},"completedMonths":["2026-10","2026-13","later"],"seen":["focusHours.1","naps.1"],"rooms":{"desk":true}}`,
    );
    expect([...save.best]).toEqual([["focusHours", 90]]);
    expect([...save.reached.keys()]).toEqual(["focusHours.1"]);
    expect([...save.completedMonths]).toEqual(["2026-10"]);
    expect([...save.seen]).toEqual(["focusHours.1"]);
    const broken = ProgressionSave.decode(`{"schemaVersion":1,"best":"lots","reached":[1,2],"completedMonths":{"a":1}}`);
    expect(broken.equals(new ProgressionSave())).toBe(true);
    expect(() => ProgressionSave.decode("[1,2,3]")).toThrow();
  });

  it("makes mastery outfits hard earned and never sold", () => {
    const editions = masteryEditions();
    expect(editions.length).toBeGreaterThanOrEqual(12);
    expect(new Set(editions.map((edition) => badgeID(editionMasteryBadge(edition) ?? { track: "water", tier: "bronze" }))).size).toBe(editions.length);
    for (const edition of editions) {
      const item = editionItem(edition);
      const badge = editionMasteryBadge(edition);
      if (!badge) throw new Error(edition);
      expect(PROGRESS_TIERS.indexOf(badge.tier)).toBeGreaterThanOrEqual(1);
      expect(isLimited(item)).toBe(true);
      expect(isFree(item)).toBe(false);
      expect(itemCost(item)).toBe(0);
      expect(PetCloset.wardrobe).not.toContain(item);
      expect(PetCloset.limitedShelf).not.toContain(item);
      expect(howToEarn(edition)).toBe(badgeHowToEarn(badge));
      const parts = itemParts(item);
      if (parts.kind === "accessory") expect(accessorySlot(parts.accessory)).not.toBe("back");
      expect(badgeGoal(badge)).toBe(trackGoal(badge.track, badge.tier));
    }
  });

  it("unlocks a mastery outfit with its tier, never with points or a server grant", () => {
    const closet = new PetCloset(new PetSave(new PetProfile("Mochi", "tuxedo"), new PetPointsLedger({ earned: 100_000 })));
    const robe = outfitItem("apprenticeRobe");
    expect(closet.state(robe).kind).toBe("unearned");
    expect(closet.tap(robe).kind).toBe("notEarnedYet");
    const progression = new PetProgression();
    for (let index = 0; index < 75; index++) progression.add(focus(25, on(11, 1) + index * 3600), tokyo);
    progression.refresh(on(11, 4), [], tokyo);
    expect(closet.unlockMastery(progression)).toEqual([robe]);
    expect(closet.unlockMastery(progression)).toEqual([]);
    expect(closet.tap(robe).kind).toBe("wore");
    expect(closet.balance).toBe(100_000);
    expect(closet.applyGrants([outfitItem("sagesRobe")])).toEqual([]);
  });

  it("shows the demo shelf part way", () => {
    const progression = progressionDemo(on(11, 20), tokyo);
    expect(progression.unseen).toEqual([]);
    const earned = masteryEditions()
      .filter((edition) => progression.isReached(editionMasteryBadge(edition) ?? { track: "water", tier: "starlight" }))
      .map(editionItem);
    expect(new Set(earned)).toEqual(new Set([accessoryItem("littleSprout"), outfitItem("apprenticeRobe"), accessoryItem("explorersHat")]));
    expect(progression.reachedCount).toBeGreaterThan(8);
    expect(progression.reachedCount).toBeLessThan(24);
    expect(progression.quests(on(11, 20), tokyo)).toHaveLength(3);
    expect(dayKey(on(11, 20), tokyo)).toBe("2026-11-20");
  });
});
