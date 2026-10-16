import { describe, expect, it } from "vitest";
import { StudyCustomRhythm } from "../../../src/core/studyMethods/studyCustomRhythm";
import { StudyMethod, studyLongBreak } from "../../../src/core/studyMethods/studyMethod";
import { StudySession } from "../../../src/core/studyMethods/studySession";
import { decodeStudyMethod, decodeStudySession, encodeStudyMethod, encodeStudySession } from "../../../src/core/studyMethods/studySessionStorage";

/* The saved session, in the shape the Mac's JSONEncoder writes (dates since 2001, enum cases as `{"case": {"_0": value}}`). */

const t0 = 1_790_000_000;
const REFERENCE = 978_307_200;

describe("StudySession storage", () => {
  it("round-trips a session mid-run with its log, lengths and card baseline", () => {
    const session = new StudySession(StudyMethod.ankiSprint(40));
    session.start(t0);
    session.recordReviewedToday(10, t0);
    session.recordReviewedToday(17, t0 + 60);
    session.pause(t0 + 90);
    const json = encodeStudySession(session);
    expect(json.phase).toBe("focus");
    expect(json.resumedAt).toBeUndefined();
    expect(json.phaseStartedAt).toBe(t0 - REFERENCE);
    expect(json.banked).toBe(90);
    expect(json.cardsDone).toBe(7);
    expect(json.cardBaseline).toBe(17);
    expect(json.method).toEqual({ kind: "ankiSprint", focus: { cards: { _0: 40 } }, breakRule: { fixed: { _0: 300 } } });
    const restored = decodeStudySession(JSON.parse(JSON.stringify(json)));
    expect(restored.runState).toBe("paused");
    expect(restored.elapsed(t0 + 180)).toBe(90);
    expect(restored.cardsDone).toBe(7);
    expect(restored.method.cardGoal).toBe(40);
    expect(encodeStudySession(restored)).toEqual(json);
  });

  it("writes every method shape the file defines and reads it back", () => {
    const custom = new StudyCustomRhythm({ focusMinutes: 45, breakMinutes: 10, longBreakMinutes: 25, longBreakEvery: 3, hasLongBreak: true }).method;
    for (const method of [...StudyMethod.presets, custom, StudyMethod.flowtime("fifth")]) {
      const json = JSON.parse(JSON.stringify(encodeStudyMethod(method)));
      expect(encodeStudyMethod(decodeStudyMethod(json)), method.kind).toEqual(encodeStudyMethod(method));
    }
    expect(encodeStudyMethod(StudyMethod.flowtime())).toEqual({ kind: "flowtime", focus: { openEnded: {} }, breakRule: { proportional: { _0: "tiered" } } });
    expect(encodeStudyMethod(StudyMethod.timer(600))).toEqual({ kind: "timer", focus: { duration: { _0: 600 } }, breakRule: { none: {} } });
    expect(encodeStudyMethod(StudyMethod.pomodoro).longBreak).toEqual({ duration: 15 * 60, every: 4 });
    expect(encodeStudyMethod(StudyMethod.questionBlock)).toMatchObject({ review: 60 * 60, questionCount: 40 });
    expect(decodeStudyMethod({ kind: "custom", focus: { duration: { _0: 5 } }, breakRule: { fixed: { _0: 1e9 } }, longBreak: { duration: 3, every: 1 } })).toEqual(
      StudyMethod.custom(5, 1e9, studyLongBreak(3, 1)),
    );
  });

  it("repairs what a hand-edited file could carry and refuses what it can't read", () => {
    const base = encodeStudySession(new StudySession(StudyMethod.pomodoro));
    const repaired = decodeStudySession({ ...base, phaseDuration: 3, banked: -5, completedFocusCount: -2, cardsDone: -1, resumedAt: t0 - REFERENCE });
    expect(repaired.phaseDuration).toBe(60);
    expect(repaired.completedFocusCount).toBe(0);
    expect(repaired.elapsed(t0 + 10)).toBe(10);
    /* A running clock always belongs to a started phase. */
    expect(repaired.runState).toBe("running");
    expect(() => decodeStudySession({ ...base, phase: "nap" })).toThrow();
    expect(() => decodeStudySession({ ...base, method: { kind: "pomodoro" } })).toThrow();
    expect(() => decodeStudySession({ ...base, log: [{ method: "pomodoro" }] })).toThrow();
    expect(() => decodeStudySession("not a session")).toThrow();
  });
});
