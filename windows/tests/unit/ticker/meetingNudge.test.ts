// Port of MeetingNudgeTests.swift.
import { describe, expect, it } from "vitest";
import type { UpcomingEvent } from "../../../src/core/planner/upcomingEvent";
import { MeetingNudge, MeetingNudgeWatch } from "../../../src/core/ticker/meetingNudge";
import { TickerSources } from "../../../src/core/ticker/tickerSources";

// Date(timeIntervalSinceReferenceDate: 800_000_000) in seconds since 1970.
const now = 800_000_000 + 978_307_200;

function event(id: string, startsInMinutes: number, allDay = false): UpcomingEvent {
  const start = now + startsInMinutes * 60;
  return { id, title: id, start, end: start + 30 * 60, isAllDay: allDay };
}

describe("MeetingNudge", () => {
  it("nudges a meeting once when it comes within five minutes", () => {
    const watch = new MeetingNudgeWatch();
    const sources = new TickerSources({ events: [event("standup", 10)] });
    expect(watch.nudge(sources, now), "ten minutes out is too early").toBeUndefined();
    const fiveBefore = now + 5 * 60;
    const nudge = watch.nudge(sources, fiveBefore);
    expect(nudge?.startedAt).toBe(fiveBefore);
    expect(watch.nudge(sources, fiveBefore + 30), "at most once per meeting").toBeUndefined();
    expect(watch.nudge(sources, fiveBefore + 4 * 60)).toBeUndefined();
  });

  it("is brief and ends on its own", () => {
    const nudge = new MeetingNudge("standup", now);
    expect(nudge.isShowing(now)).toBe(true);
    expect(nudge.isShowing(now + MeetingNudge.duration - 0.1)).toBe(true);
    expect(nudge.isShowing(nudge.endsAt)).toBe(false);
    expect(nudge.isShowing(now - 1), "a clock set back shows nothing").toBe(false);
  });

  it("never nudges meetings under way or all-day events", () => {
    const watch = new MeetingNudgeWatch();
    const sources = new TickerSources({ events: [event("review", -5), event("holiday", 3, true)] });
    expect(watch.nudge(sources, now)).toBeUndefined();
  });

  it("gives back-to-back meetings a nudge each", () => {
    const watch = new MeetingNudgeWatch();
    const sources = new TickerSources({ events: [event("standup", 3), event("review", 33)] });
    const first = watch.nudge(sources, now);
    expect(first).toBeDefined();
    const second = watch.nudge(sources, now + 30 * 60);
    expect(second).toBeDefined();
    expect(first?.key).not.toBe(second?.key);
  });

  it("nudges a moved meeting again", () => {
    const watch = new MeetingNudgeWatch();
    expect(watch.nudge(new TickerSources({ events: [event("standup", 3)] }), now)).toBeDefined();
    const moved = new TickerSources({ events: [event("standup", 13)] });
    expect(watch.nudge(moved, now + 10 * 60)).toBeDefined();
  });
});
