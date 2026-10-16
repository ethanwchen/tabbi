import { describe, expect, it } from "vitest";
import { instantOf } from "../../../src/core/calendar/zonedCalendar";
import { heartbeatBody } from "../../../src/core/party/partyClient";
import { OFFLINE_HEARTBEAT } from "../../../src/core/party/partyModels";
import { PartyPresenceTracker, presenceDayString } from "../../../src/core/party/partyPresenceTracker";
import { FocusTimer, FocusTimerConfig } from "../../../src/core/focus/focusTimer";
import { ProvidedFocus } from "../../../src/core/providers/providedFocus";

const zone = "America/New_York";
/** 2026-10-02 09:00 in New York. */
const morning = instantOf({ year: 2026, month: 10, day: 2, hour: 9 }, zone);

function running(start: number, focus = 25 * 60, rest = 5 * 60): FocusTimer {
  const timer = new FocusTimer(new FocusTimerConfig(focus, rest));
  timer.start(start);
  return timer;
}

const shared = (timer: FocusTimer) => timer.provided("focus");

/** `timer` as its module republishes it at `now`, with every phase end that passed applied. */
function advanced(timer: FocusTimer, now: number): ProvidedFocus {
  const copy = timer.clone();
  copy.advance(now);
  return shared(copy);
}

describe("PartyPresenceTracker", () => {
  it("is idle without a timer", () => {
    const tracker = new PartyPresenceTracker();
    expect(tracker.observe(undefined, morning, zone), "the heartbeat at launch").toBe(true);
    expect(tracker.observe(undefined, morning + 60, zone)).toBe(false);
    const beat = tracker.heartbeat(morning, zone);
    expect(beat.status).toBe("idle");
    expect(beat.method).toBeUndefined();
    expect(beat.phaseEndsAt).toBeUndefined();
    expect(beat.sessionMinutes).toBe(0);
    expect(beat.todayMinutes).toBe(0);
    expect(beat.streakDays).toBe(0);
    expect(beat.day).toBe("2026-10-02");
  });

  it("studies with the method and phase end while focus runs", () => {
    const tracker = new PartyPresenceTracker("52-17");
    expect(tracker.observe(shared(running(morning)), morning, zone)).toBe(true);
    const beat = tracker.heartbeat(morning, zone);
    expect(beat.status).toBe("studying");
    expect(beat.method).toBe("52-17");
    expect(beat.phaseEndsAt).toBe(morning + 25 * 60);
  });

  it("reports breaks and pauses as breaks", () => {
    const tracker = new PartyPresenceTracker();
    const timer = running(morning);
    timer.pause(morning + 60);
    tracker.observe(shared(timer), morning + 60, zone);
    expect(tracker.status).toBe("onBreak");
    expect(tracker.heartbeat(morning + 60, zone).phaseEndsAt).toBeUndefined();

    const breakTime = morning + 26 * 60;
    tracker.observe(advanced(running(morning), breakTime), breakTime, zone);
    const beat = tracker.heartbeat(breakTime, zone);
    expect(beat.status).toBe("onBreak");
    expect(beat.method).toBe("pomodoro");
    expect(beat.phaseEndsAt).toBe(morning + 30 * 60);
  });

  it("asks for an immediate heartbeat only on status, method or phase changes", () => {
    const tracker = new PartyPresenceTracker();
    const timer = running(morning);
    expect(tracker.observe(shared(timer), morning, zone)).toBe(true);
    expect(tracker.observe(shared(timer), morning + 60, zone)).toBe(false);
    expect(tracker.observe(shared(timer), morning + 120, zone)).toBe(false);
    expect(tracker.observe(shared(timer), morning + 25 * 60 + 1, zone)).toBe(true);
    tracker.method = "flowtime";
    expect(tracker.observe(shared(timer), morning + 26 * 60, zone)).toBe(true);
  });

  it("counts only running focus, clipped to the phase end", () => {
    const tracker = new PartyPresenceTracker();
    tracker.observe(shared(running(morning)), morning, zone);
    const later = morning + 3 * 3600;
    tracker.observe(advanced(running(morning), later), later, zone);
    const beat = tracker.heartbeat(later, zone);
    expect(beat.status).toBe("idle");
    expect(beat.todayMinutes).toBe(25);
    expect(beat.sessionMinutes).toBe(0);
    expect(tracker.todayMinutes(later, zone)).toBe(25);
  });

  it("adds session minutes across phases and leaves pauses out", () => {
    const tracker = new PartyPresenceTracker();
    const timer = running(morning, 10 * 60, 2 * 60);
    tracker.observe(shared(timer), morning, zone);
    const pausedAt = morning + 4 * 60;
    timer.pause(pausedAt);
    tracker.observe(shared(timer), pausedAt, zone);
    const resumedAt = pausedAt + 30 * 60;
    timer.start(resumedAt);
    tracker.observe(shared(timer), resumedAt, zone);
    const beat = tracker.heartbeat(resumedAt + 3 * 60, zone);
    expect(beat.status).toBe("studying");
    expect(beat.sessionMinutes).toBe(7);
    expect(beat.todayMinutes).toBe(7);
  });

  it("splits minutes at local midnight and grows the streak", () => {
    const tracker = new PartyPresenceTracker();
    const lateNight = instantOf({ year: 2026, month: 10, day: 2, hour: 23, minute: 50 }, zone);
    tracker.observe(shared(running(lateNight)), lateNight, zone);
    const beat = tracker.heartbeat(lateNight + 25 * 60, zone);
    expect(beat.day).toBe("2026-10-03");
    expect(beat.todayMinutes).toBe(15);
    expect(beat.sessionMinutes).toBe(25);
    expect(beat.streakDays).toBe(2);
  });

  it("keeps the streak through the next day and breaks it after a missed day", () => {
    const tracker = new PartyPresenceTracker();
    tracker.observe(shared(running(morning)), morning, zone);
    tracker.observe(undefined, morning + 3600, zone);
    expect(tracker.streakDays(morning, zone)).toBe(1);

    const nextDay = morning + 86_400;
    const beat = tracker.heartbeat(nextDay, zone);
    expect(beat.streakDays).toBe(1);
    expect(beat.todayMinutes, "yesterday's minutes are not today's").toBe(0);

    tracker.observe(shared(running(nextDay)), nextDay, zone);
    tracker.observe(undefined, nextDay + 3600, zone);
    expect(tracker.streakDays(nextDay, zone)).toBe(2);
    expect(tracker.streakDays(nextDay + 2 * 86_400, zone)).toBe(0);
    const comeback = nextDay + 2 * 86_400;
    tracker.observe(shared(running(comeback)), comeback, zone);
    expect(tracker.heartbeat(comeback + 60, zone).streakDays).toBe(1);
  });

  it("sends offline while invisible and keeps counting locally", () => {
    const tracker = new PartyPresenceTracker();
    tracker.observe(shared(running(morning)), morning, zone);
    expect(tracker.setInvisible(true)).toBe(true);
    expect(tracker.setInvisible(true)).toBe(false);
    expect(tracker.observe(shared(running(morning)), morning + 26 * 60, zone)).toBe(false);
    expect(tracker.heartbeat(morning + 26 * 60, zone)).toEqual(OFFLINE_HEARTBEAT);
    expect(tracker.todayMinutes(morning + 26 * 60, zone)).toBe(25);
    expect(tracker.setInvisible(false)).toBe(true);
    expect(tracker.heartbeat(morning + 27 * 60, zone).status).toBe("onBreak");
  });

  it("round-trips through its stored form", () => {
    const tracker = new PartyPresenceTracker("anki");
    tracker.observe(shared(running(morning)), morning, zone);
    tracker.observe(undefined, morning + 10 * 60, zone);
    const restored = PartyPresenceTracker.decode(tracker.encoded());
    expect(restored.toJSON()).toEqual(tracker.toJSON());
    expect(restored.todayMinutes(morning + 3600, zone)).toBe(10);
    expect(JSON.parse(tracker.encoded()).schemaVersion).toBe(1);
  });

  it("keeps an open-ended focus phase across a restart", () => {
    const tracker = new PartyPresenceTracker("flowtime");
    tracker.observe(new ProvidedFocus({ source: "study", phase: "focus", clock: { kind: "countUp", since: morning }, phaseLength: undefined }), morning, zone);
    const restored = PartyPresenceTracker.decode(tracker.encoded());
    expect(restored.heartbeat(morning + 20 * 60, zone).sessionMinutes).toBe(20);
  });

  it("never mentions what is studied in the heartbeat body", () => {
    const tracker = new PartyPresenceTracker();
    tracker.observe(shared(running(morning)), morning, zone);
    expect(new Set(Object.keys(heartbeatBody(tracker.heartbeat(morning, zone))))).toEqual(
      new Set(["status", "method", "phaseEndsAt", "sessionMinutes", "todayMinutes", "streakDays", "day"]),
    );
  });

  it("uses the local day", () => {
    expect(presenceDayString(1_790_998_200, zone)).toBe("2026-10-02");
  });

  it("stops studying when a countdown ran out before its module moved on", () => {
    const tracker = new PartyPresenceTracker();
    tracker.observe(shared(running(morning)), morning, zone);
    const afterFocus = morning + 26 * 60;
    tracker.observe(shared(running(morning)), afterFocus, zone);
    expect(tracker.status).toBe("onBreak");
    expect(tracker.todayMinutes(afterFocus, zone)).toBe(25);
    tracker.observe(advanced(running(morning), afterFocus), morning + 31 * 60, zone);
    expect(tracker.status).toBe("idle");
  });

  it("studies open-ended focus with no phase end and counts its minutes", () => {
    const tracker = new PartyPresenceTracker("flowtime");
    tracker.observe(new ProvidedFocus({ source: "study", phase: "focus", clock: { kind: "countUp", since: morning }, phaseLength: undefined }), morning, zone);
    const later = morning + 40 * 60;
    const beat = tracker.heartbeat(later, zone);
    expect(beat.status).toBe("studying");
    expect(beat.phaseEndsAt).toBeUndefined();
    expect(beat.sessionMinutes).toBe(40);

    const rest = new ProvidedFocus({ source: "study", phase: "rest", clock: { kind: "countdown", endsAt: later + 8 * 60 }, phaseLength: 8 * 60 });
    tracker.observe(rest, later, zone);
    const breakBeat = tracker.heartbeat(later + 5 * 60, zone);
    expect(breakBeat.status).toBe("onBreak");
    expect(breakBeat.todayMinutes).toBe(40);
  });
});
