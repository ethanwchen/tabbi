import { beforeAll, describe, expect, it } from "vitest";
import { classifyMeetingURL, detectMeetingLink, type MeetingProvider } from "../../../src/core/planner/meetingLink";
import { plannerDayKeyOf } from "../../../src/core/planner/plannerDayKey";
import { sampleEvents, sampleEventsFor } from "../../../src/core/planner/plannerSampleData";
import { viewedDayKey } from "../../../src/core/planner/plannerViewedDay";
import { PLANNER_SAMPLE_DAYS } from "../../../src/core/planner/todayPlanSettings";
import {
  agenda,
  eventBadge,
  eventLength,
  eventStartTime,
  eventTiming,
  eventTitle,
  isInProgress,
  upNext,
  upcomingEvent,
  type UpcomingEvent,
} from "../../../src/core/planner/upcomingEvent";
import { switchLanguage } from "../../support/catalogs";

/* Port of UpcomingEventTests and MeetingLinkTests. */

const NOW = 1_790_000_000;

function event(id: string, start: number, end: number, allDay = false, title?: string): UpcomingEvent {
  return upcomingEvent({ id, title: title ?? id, start: NOW + start * 60, end: NOW + end * 60, isAllDay: allDay });
}

const ids = (events: readonly UpcomingEvent[]) => events.map((entry) => entry.id);

beforeAll(() => {
  switchLanguage("en");
});

describe("UpcomingEvent", () => {
  it("drops ended and all-day events from Up next and sorts by soonest", () => {
    const events = [
      event("later", 90, 120),
      event("ended", -60, -1),
      event("holiday", -600, 800, true),
      event("current", -10, 20),
      event("soon", 12, 40),
      event("tonight", 300, 360),
    ];
    expect(ids(upNext(events, NOW))).toEqual(["current", "soon", "later"]);
    expect(ids(upNext(events, NOW, 1))).toEqual(["current"]);
    expect(upNext(events, NOW, 0)).toEqual([]);
  });

  it("keeps every timed event of the day in the agenda, earliest first", () => {
    const events = [
      event("evening", 300, 360),
      event("ended", -60, -1),
      event("holiday", -600, 800, true),
      event("morning", -200, -150),
      event("soon", 12, 40),
    ];
    expect(ids(agenda(events))).toEqual(["morning", "ended", "soon"]);
    expect(ids(agenda(events, 5))).toEqual(["morning", "ended", "soon", "evening"]);
    expect(agenda(events, 0)).toEqual([]);
  });

  it("writes lengths like other durations", () => {
    expect(eventLength(event("a", 0, 30))).toBe("30 min");
    expect(eventLength(event("b", 0, 90))).toBe("1h 30m");
    expect(eventLength(event("c", 0, 120))).toBe("2h");
  });

  it("puts other days' samples on that day at fixed hours", () => {
    const chicago = "America/Chicago";
    const today = plannerDayKeyOf(NOW, chicago);
    for (const kind of PLANNER_SAMPLE_DAYS) {
      for (const viewed of ["yesterday", "tomorrow"] as const) {
        const samples = sampleEventsFor(viewed, NOW, kind, chicago);
        expect(samples.length).toBeGreaterThanOrEqual(2);
        expect(new Set(ids(samples)).size).toBe(samples.length);
        for (const sample of samples) {
          expect(plannerDayKeyOf(sample.start, chicago)).toBe(viewedDayKey(viewed, today));
          expect(sample.start).toBeLessThan(sample.end);
        }
        /* Same events whatever the time of day, so the demo doesn't shift as the clock moves. */
        const later = sampleEventsFor(viewed, NOW + 3600, kind, chicago);
        if (plannerDayKeyOf(NOW + 3600, chicago) === today) expect(later).toEqual(samples);
      }
      expect(sampleEventsFor("today", NOW, kind, chicago)).toEqual(sampleEvents(NOW, kind));
    }
  });

  it("treats an event ending exactly now as over", () => {
    expect(upNext([event("edge", -30, 0)], NOW)).toEqual([]);
  });

  it("breaks start ties by end, then title", () => {
    const events = [event("b", 10, 40, false, "Beta"), event("a", 10, 40, false, "Alpha"), event("short", 10, 20)];
    expect(ids(upNext(events, NOW))).toEqual(["short", "a", "b"]);
  });

  it("rounds timing up to whole minutes", () => {
    expect(eventTiming(event("x", -5, 5), NOW)).toEqual({ kind: "now" });
    expect(eventTiming(event("x", 0, 5), NOW)).toEqual({ kind: "now" });
    expect(eventTiming(event("x", 0.25, 5), NOW)).toEqual({ kind: "startsIn", minutes: 1 });
    expect(eventTiming(event("x", 11.5, 30), NOW)).toEqual({ kind: "startsIn", minutes: 12 });
    expect(eventTiming(event("x", 12, 30), NOW)).toEqual({ kind: "startsIn", minutes: 12 });
  });

  it("is in progress over a half-open interval", () => {
    const meeting = event("x", 0, 30);
    expect(isInProgress(meeting, NOW)).toBe(true);
    expect(isInProgress(meeting, NOW + 30 * 60)).toBe(false);
    expect(isInProgress(meeting, NOW - 1)).toBe(false);
  });

  it("writes badge text", () => {
    expect(eventBadge({ kind: "now" })).toBe("now");
    expect(eventBadge({ kind: "startsIn", minutes: 1 })).toBe("in 1 min");
    expect(eventBadge({ kind: "startsIn", minutes: 59 })).toBe("in 59 min");
    expect(eventBadge({ kind: "startsIn", minutes: 60 })).toBe("in 1h");
    expect(eventBadge({ kind: "startsIn", minutes: 125 })).toBe("in 2h 5m");
  });

  it("follows the locale's clock without a day period", () => {
    /* 2026-09-20 21:05 UTC. */
    const evening = 1_789_862_400 + 21 * 3600 + 300;
    expect(eventStartTime(evening, "en-US", "UTC")).toBe("9:05");
    expect(eventStartTime(evening, "de-DE", "UTC")).toBe("21:05");
  });

  it("falls back for blank titles", () => {
    expect(eventTitle(event("x", 0, 1, false, "  Sync "))).toBe("Sync");
    expect(eventTitle(event("x", 0, 1, false, " \n"))).toBe("Untitled event");
  });

  it("includes current and joinable events in the samples", () => {
    for (const kind of PLANNER_SAMPLE_DAYS) {
      const samples = sampleEvents(NOW, kind);
      const next = upNext(samples, NOW);
      expect(next.length).toBe(3);
      expect(next[0] && eventTiming(next[0], NOW)).toEqual({ kind: "now" });
      expect(next.some((entry) => entry.meetingLink !== undefined)).toBe(true);
      expect(next.some((entry) => entry.meetingLink === undefined)).toBe(true);
      expect(new Set(ids(samples)).size).toBe(samples.length);
      for (let index = 1; index < samples.length; index++) {
        expect(samples[index - 1]?.start ?? 0).toBeLessThan(samples[index]?.start ?? 0);
      }
    }
  });

  it("makes the medicine samples lectures and labs", () => {
    expect(sampleEvents(NOW, "medicine").map((entry) => entry.title)).toEqual([
      "Cardiology lecture",
      "Anatomy lab: thorax",
      "Clinical skills session",
    ]);
  });

  it("starts samples on five-minute marks at any moment", () => {
    /* Every second across a five-minute window: the first event is live, the next still ahead, all starts clean. */
    for (let offset = 0; offset < 300; offset++) {
      const moment = NOW + offset;
      const next = upNext(sampleEvents(moment, offset < 150 ? "work" : "medicine"), moment);
      expect(next.length).toBe(3);
      expect(next[0] && eventTiming(next[0], moment)).toEqual({ kind: "now" });
      expect(next[1] && eventTiming(next[1], moment)).not.toEqual({ kind: "now" });
      for (const entry of next) expect((entry.start - 978_307_200) % 300).toBe(0);
    }
  });
});

describe("MeetingLink", () => {
  it("recognizes Zoom, Meet and Teams join links", () => {
    const cases: [string, MeetingProvider][] = [
      ["https://zoom.us/j/5551234567?pwd=abc", "zoom"],
      ["https://us02web.zoom.us/j/8765?pwd=x", "zoom"],
      ["https://acme.zoom.us/my/ana", "zoom"],
      ["https://meet.google.com/abc-defg-hij", "googleMeet"],
      ["https://meet.google.com/lookup/team-sync", "googleMeet"],
      ["https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0", "teams"],
      ["https://teams.live.com/meet/9876543210", "teams"],
    ];
    for (const [url, provider] of cases) expect(classifyMeetingURL(url)?.provider, url).toBe(provider);
  });

  it("ignores non-join pages on the same hosts", () => {
    for (const url of [
      "https://zoom.us/pricing",
      "https://meet.google.com/",
      "https://teams.microsoft.com/l/chat/0/0",
      "https://docs.google.com/document/d/abc",
      "mailto:ana@example.com",
      "https://notzoom.us/j/123",
    ]) {
      expect(classifyMeetingURL(url), url).toBeUndefined();
    }
  });

  it("upgrades plain http to https", () => {
    expect(classifyMeetingURL("http://zoom.us/j/123")?.url).toBe("https://zoom.us/j/123");
  });

  it("prefers the URL field, then the location, then the notes", () => {
    const notes = "Agenda: https://docs.google.com/doc\nJoin: https://meet.google.com/abc-defg-hij";
    expect(detectMeetingLink({ url: "https://zoom.us/j/1", location: "https://teams.live.com/meet/2", notes })?.provider).toBe("zoom");
    expect(
      detectMeetingLink({ url: "https://example.com", location: "Room 4 / https://teams.live.com/meet/2", notes })?.provider,
    ).toBe("teams");
    expect(detectMeetingLink({ location: "Room 4", notes })?.provider).toBe("googleMeet");
  });

  it("finds links wrapped in invite formatting", () => {
    const notes = [
      "─".repeat(10),
      "Join Zoom Meeting",
      "<https://us06web.zoom.us/j/81234567890?pwd=AbC123>.",
      "",
      "Meeting ID: 812 3456 7890",
    ].join("\n");
    const link = detectMeetingLink({ notes });
    expect(link?.provider).toBe("zoom");
    expect(link?.url).toBe("https://us06web.zoom.us/j/81234567890?pwd=AbC123");
  });

  it("gives nothing without any meeting link", () => {
    expect(detectMeetingLink({})).toBeUndefined();
    expect(detectMeetingLink({ location: "Cafe on 3rd", notes: "Bring the slides https://example.com/deck" })).toBeUndefined();
  });
});
