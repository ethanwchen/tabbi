import { describe, expect, it } from "vitest";
import { FocusTimer, FocusTimerConfig } from "../../../src/core/focus/focusTimer";
import { InMemoryDefaults } from "../../../src/core/persistence/defaults";
import { focusLogActivityRecords, focusLogSessionID } from "../../../src/core/planner/dayReview";
import {
  FOCUS_LAST_ALIVE_KEY,
  FOCUS_SESSION_LOG_KEY,
  FOCUS_TIMER_KEY,
  FocusTimerStorage,
} from "../../../src/core/planner/focusTimerStorage";

const REFERENCE = 978_307_200;

describe("FocusTimerStorage", () => {
  it("gives a fresh timer when nothing or something unreadable is saved", () => {
    expect(new FocusTimerStorage(new InMemoryDefaults()).loadTimer().runState).toEqual({ kind: "idle" });
    const broken = new InMemoryDefaults({ [FOCUS_TIMER_KEY]: "{not json" });
    expect(new FocusTimerStorage(broken).loadTimer().phase).toBe("focus");
  });

  it("round-trips a running timer in the Mac's Codable shape", () => {
    const defaults = new InMemoryDefaults();
    const storage = new FocusTimerStorage(defaults);
    const timer = new FocusTimer(new FocusTimerConfig(50 * 60, 10 * 60), "00000000-0000-4000-8000-000000000003");
    timer.start(REFERENCE + 1000);
    storage.save(timer);
    const text = defaults.get(FOCUS_TIMER_KEY);
    expect(typeof text).toBe("string");
    const json = JSON.parse(String(text)) as Record<string, unknown>;
    expect(json).toEqual({
      phase: "focus",
      runState: { running: { endsAt: 1000 + 50 * 60 } },
      config: { focusDuration: 3000, restDuration: 600 },
      completedFocusCount: 0,
      linkedItemID: "00000000-0000-4000-8000-000000000003",
      schemaVersion: 1,
    });
    const loaded = storage.loadTimer();
    expect(loaded.runState).toEqual({ kind: "running", endsAt: REFERENCE + 1000 + 3000 });
    expect(loaded.linkedItemID).toBe("00000000-0000-4000-8000-000000000003");
    expect(loaded.config.focusDuration).toBe(3000);
  });

  it("reads a paused timer the Mac wrote before versions existed", () => {
    const defaults = new InMemoryDefaults({
      [FOCUS_TIMER_KEY]: JSON.stringify({
        phase: "rest",
        runState: { paused: { remaining: 90 } },
        config: { focusDuration: 1500, restDuration: 300 },
        completedFocusCount: 3,
      }),
    });
    const timer = new FocusTimerStorage(defaults).loadTimer();
    expect(timer.phase).toBe("rest");
    expect(timer.runState).toEqual({ kind: "paused", remaining: 90 });
    expect(timer.completedFocusCount).toBe(3);
  });

  it("keeps the last moment alive", () => {
    const defaults = new InMemoryDefaults();
    const storage = new FocusTimerStorage(defaults);
    expect(storage.lastAlive).toBeUndefined();
    storage.saveLastAlive(1_791_823_290);
    expect(storage.lastAlive).toBe(1_791_823_290);
    expect(defaults.get(FOCUS_LAST_ALIVE_KEY)).toBe(1_791_823_290);
  });

  it("moves the legacy session log once it is stored elsewhere, and keeps it when that fails", async () => {
    const log = JSON.stringify({ sessions: [{ endedAt: 800_000_000, duration: 1500 }], schemaVersion: 1 });
    const defaults = new InMemoryDefaults({ [FOCUS_SESSION_LOG_KEY]: log });
    const storage = new FocusTimerStorage(defaults);
    await storage.moveSessionLog(() => false);
    expect(defaults.get(FOCUS_SESSION_LOG_KEY)).toBe(log);
    let moved: unknown;
    await storage.moveSessionLog((sessions) => {
      moved = sessions;
      return true;
    });
    expect(moved).toEqual([{ endedAt: 800_000_000 + REFERENCE, duration: 1500 }]);
    expect(defaults.get(FOCUS_SESSION_LOG_KEY)).toBeUndefined();
  });

  it("drops an unreadable session log without calling the move", async () => {
    const defaults = new InMemoryDefaults({ [FOCUS_SESSION_LOG_KEY]: "garbage" });
    let called = false;
    await new FocusTimerStorage(defaults).moveSessionLog(() => {
      called = true;
      return true;
    });
    expect(called).toBe(false);
    expect(defaults.get(FOCUS_SESSION_LOG_KEY)).toBeUndefined();
  });

  it("gives legacy sessions stable ids from their bit patterns", () => {
    const session = { endedAt: REFERENCE + 1, duration: 1 };
    /* 1.0 as a big-endian double is 3FF0000000000000. */
    expect(focusLogSessionID(session)).toBe("3FF00000-0000-0000-3FF0-000000000000");
    const records = focusLogActivityRecords([{ endedAt: REFERENCE + 3600, duration: 1500 }], "focus");
    expect(records[0]).toMatchObject({
      kind: "focus.completed",
      start: REFERENCE + 2100,
      end: REFERENCE + 3600,
      quantity: 25,
      metadata: { method: "pomodoro", outcome: "completed" },
    });
    expect(records[0]?.id).toBe(focusLogActivityRecords([{ endedAt: REFERENCE + 3600, duration: 1500 }], "focus")[0]?.id);
  });
});
