import { describe, expect, it } from "vitest";
import { FocusMix } from "../../../src/core/focus/focusMix";
import { FocusSettings } from "../../../src/core/focus/focusSettings";
import { kitDefaults } from "../../../src/core/kits/kitManifest";
import type { JSONObject } from "../../../src/core/persistence/json";
import { PetPointsRules } from "../../../src/core/pets/petPointsRules";
import { ProgressItem } from "../../../src/core/providers/progressItem";
import { cardsReviewedToday } from "../../../src/core/studyMethods/studyCardFeed";
import { StudyCustomRhythm, presetMethod } from "../../../src/core/studyMethods/studyCustomRhythm";
import { StudyDailyGoal } from "../../../src/core/studyMethods/studyDailyGoal";
import { sharedStudyFocus } from "../../../src/core/studyMethods/studyFocusShare";
import { StudyLog, studyLogEntry } from "../../../src/core/studyMethods/studyLog";
import { StudyMethod, studyLongBreak } from "../../../src/core/studyMethods/studyMethod";
import { StudyMethodMenu, kitStartingKind } from "../../../src/core/studyMethods/studyMethodMenu";
import { StudySession } from "../../../src/core/studyMethods/studySession";
import { studySoundHelp, studySoundLabel } from "../../../src/core/studyMethods/studySoundLabel";
import { StudyTimerLength } from "../../../src/core/studyMethods/studyTimerLength";

/* The study pieces the golden fixtures do not walk through. */

const t0 = 1_790_000_000;
const studyKit = (study: JSONObject) => kitDefaults({ moduleSettings: { study } });
const points = (minutes: number, completed: boolean) => PetPointsRules.points(minutes, completed);
const goal = (source: string, unit: string, completed: number) =>
  new ProgressItem({ id: `${source}-${unit}`, source, title: "Goal", completed, target: 100, unit });

describe("StudyMethod", () => {
  it("clamps every way a method is made", () => {
    const method = StudyMethod.custom(0, Number.NaN, studyLongBreak(99_999, 1));
    expect(method.duration("focus")).toBe(60);
    expect(method.duration("shortBreak")).toBe(60);
    expect(method.longBreak).toEqual({ duration: 14_400, every: 2 });
    expect(StudyMethod.ankiSprint(0).cardGoal).toBe(1);
    expect(StudyMethod.sprintGoal(-5, 0)).toBe(100);
  });
});

describe("StudyCustomRhythm", () => {
  it("steps on the field's grid and stays in range", () => {
    const rhythm = new StudyCustomRhythm({ focusMinutes: 23, breakMinutes: 5 });
    expect(rhythm.stepped("focus", 1).focusMinutes).toBe(25);
    expect(rhythm.stepped("focus", -1).focusMinutes).toBe(20);
    expect(rhythm.setting("focus", 999).focusMinutes).toBe(180);
    expect(rhythm.canStep("longBreakEvery", -10)).toBe(true);
    expect(rhythm.setting("longBreakEvery", 2).canStep("longBreakEvery", -1)).toBe(false);
  });

  it("makes the Custom method, with the long break only when switched on", () => {
    const rhythm = new StudyCustomRhythm({ focusMinutes: 40, breakMinutes: 10 });
    expect(rhythm.method.longBreak).toBeUndefined();
    expect(rhythm.withLongBreak(true).method.longBreak).toEqual({ duration: 900, every: 4 });
    expect(presetMethod("custom", rhythm).rhythmLabel).toBe("40/10");
    expect(presetMethod("timer", rhythm, new StudyTimerLength(5)).rhythmLabel).toBe("5 min");
    expect(StudyCustomRhythm.fromJSON({ focusMinutes: 1, hasLongBreak: true }).toJSON()).toEqual({
      focusMinutes: 5,
      breakMinutes: 5,
      longBreakMinutes: 15,
      longBreakEvery: 4,
      hasLongBreak: true,
    });
  });
});

describe("StudyMethodMenu", () => {
  it("offers every preset unless a kit names known methods", () => {
    expect(StudyMethodMenu.all.kinds).toHaveLength(8);
    expect(StudyMethodMenu.all.startingKind).toBe("pomodoro");
    const kit = StudyMethodMenu.fromKit(studyKit({ methods: ["ankiSprint", "nope", "questionBlock", "ankiSprint"], method: "questionBlock" }));
    expect(kit.kinds).toEqual(["ankiSprint", "questionBlock"]);
    expect(kit.startingKind).toBe("questionBlock");
    expect(StudyMethodMenu.fromKit(studyKit({ methods: ["nope"] })).kinds).toHaveLength(8);
    expect(kitStartingKind(studyKit({ methods: ["flowtime"] }))).toBe("flowtime");
    expect(kitStartingKind(undefined)).toBeUndefined();
  });

  it("moves only a stopped session, and only when the kit asks or the method is gone", () => {
    const menu = new StudyMethodMenu(["flowtime", "timer"]);
    const idle = new StudySession(StudyMethod.pomodoro);
    expect(menu.replacement(idle, false)).toBe("flowtime");
    const running = new StudySession(StudyMethod.pomodoro);
    running.start(t0);
    expect(menu.replacement(running, true)).toBeUndefined();
    const offered = new StudySession(StudyMethod.flowtime());
    expect(menu.replacement(offered, false)).toBeUndefined();
    expect(new StudyMethodMenu(["timer", "flowtime"]).replacement(offered, true)).toBe("timer");
  });
});

describe("StudyDailyGoal", () => {
  it("snaps to quarter hours inside 15 min to 12 h", () => {
    expect(new StudyDailyGoal(100).minutes).toBe(105);
    expect(new StudyDailyGoal(0).minutes).toBe(15);
    expect(new StudyDailyGoal(10_000).minutes).toBe(720);
    expect(StudyDailyGoal.fromKit(studyKit({ dailyGoalMinutes: 300 })).minutes).toBe(300);
    expect(StudyDailyGoal.fromKit(studyKit({ dailyGoalMinutes: "lots" })).minutes).toBe(120);
    expect(StudyDailyGoal.fromKit(undefined).minutes).toBe(120);
    expect(StudyDailyGoal.standard.stepped(-2).minutes).toBe(90);
  });

  it("shares the day's minutes as a goal that waits for the first ones", () => {
    const goal = StudyDailyGoal.standard;
    const item = goal.progressItem({ minutes: 45, sessions: 2, points: 50 });
    expect([item.id, item.source, item.title, item.completed, item.target, item.unit]).toEqual(["minutes", "study", "Focus time", 45, 120, "min"]);
    expect(item.waitsForStart).toBe(true);
    expect(item.remainingText("en")).toBe("1h 15m left");
    expect(goal.progressItem({ minutes: 0, sessions: 0, points: 0 }).showsBesideNotch).toBe(false);
    expect(new StudyDailyGoal(90).progressItem({ minutes: 95, sessions: 1, points: 95 }).isComplete).toBe(true);
  });
});

describe("StudyLog", () => {
  const record = (minutes: number, outcome: "completed" | "skipped", endedAt = t0) => ({
    method: "pomodoro" as const,
    phase: "focus" as const,
    startedAt: endedAt - minutes * 60,
    endedAt,
    activeDuration: minutes * 60 + 30,
    outcome,
  });

  it("pays points by the pet's rules", () => {
    expect([points(4, true), points(5, false), points(25, true), points(25, false)]).toEqual([
      0, 5, 35, 25,
    ]);
    expect(studyLogEntry({ ...record(25, "completed"), phase: "shortBreak" }, "a")).toBeUndefined();
    expect(studyLogEntry({ ...record(0, "completed") }, "a")).toBeUndefined();
    expect(studyLogEntry(record(25, "completed"), "a")?.points).toBe(35);
  });

  it("totals the stretches that ended on a day in a named time zone", () => {
    let id = 0;
    const makeId = (): string => `id${id++}`;
    /* 1790000000 is 2026-09-21 14:13:20 UTC: still the 21st in New York, the 22nd in Tokyo. */
    const { log, added } = new StudyLog().recording(
      [record(25, "completed"), record(10, "skipped", t0 - 86_400), { ...record(25, "completed"), phase: "longBreak" }],
      makeId,
    );
    expect(added.map((entry) => entry.id)).toEqual(["id0", "id1"]);
    expect(log.summary(t0, "America/New_York")).toEqual({ minutes: 25, sessions: 1, points: 35 });
    expect(log.summary(t0 - 86_400, "UTC")).toEqual({ minutes: 10, sessions: 0, points: 10 });
    expect(log.totalPoints).toBe(45);
  });
});

describe("StudySession extras", () => {
  it("recovers a session the app died in", () => {
    const session = new StudySession(StudyMethod.pomodoro);
    session.start(t0);
    session.recover(t0 + 600, t0 + 99_999);
    expect(session.runState).toBe("idle");
    expect(session.log).toEqual([
      { method: "pomodoro", phase: "focus", startedAt: t0, endedAt: t0 + 600, activeDuration: 600, outcome: "abandoned" },
    ]);
  });

  it("shares a paused open-ended phase as its time worked, and marks deep focus", () => {
    const session = new StudySession(StudyMethod.flowtime());
    session.start(t0);
    session.pause(t0 + 90);
    const shared = sharedStudyFocus(session, "study", true, t0 + 500);
    expect(shared?.clock).toEqual({ kind: "paused", shown: 90 });
    expect(shared?.isDeep).toBe(true);
    expect(shared?.label).toBe("Focus");
  });

  it("counts cards from other modules' shared goals only", () => {
    expect(cardsReviewedToday([], "study")).toBeUndefined();
    expect(
      cardsReviewedToday(
        [
          goal("anki", "cards", 40),
          goal("other", "cards", -3),
          goal("study", "cards", 99),
          goal("anki", "min", 5),
        ],
        "study",
      ),
    ).toBe(40);
  });
});

describe("StudySoundLabel", () => {
  it("names what plays with focus", () => {
    expect(studySoundLabel(FocusSettings.default)).toEqual({ title: "Sound", symbolName: "speaker.slash", isOn: false, addsPlaylist: false });
    expect(studySoundLabel(new FocusSettings({ playlistText: "Chill" })).title).toBe("Playlist");
    const rain = new FocusSettings({ mix: FocusMix.single("rain"), playlistText: "Chill" });
    expect(studySoundLabel(rain)).toEqual({ title: "Rain", symbolName: "cloud.rain", isOn: true, addsPlaylist: true });
    expect(studySoundLabel(new FocusSettings({ mix: new FocusMix([{ sound: "rain" }, { sound: "cafe" }]) })).title).toBe("2 sounds");
    expect(studySoundHelp(FocusSettings.default, undefined)).toBe("Pick a focus sound or a playlist");
    expect(studySoundHelp(rain, undefined)).toBe("Plays Rain and your playlist with focus. Click to change it");
  });
});
