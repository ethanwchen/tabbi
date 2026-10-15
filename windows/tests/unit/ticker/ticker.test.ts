// Port of TickerTests.swift (TickerSourcesTests, TickerRotationTests and TickerFormatTests).
import { beforeAll, describe, expect, it } from "vitest";
import { usageHighlight, usageHighlights } from "../../../src/core/claudeUsage/claudeUsageHighlights";
import type { ClaudeRateLimitSnapshot } from "../../../src/core/claude/claudeStreamEvent";
import { FocusTimer, FocusTimerConfig } from "../../../src/core/focus/focusTimer";
import type { ModuleID } from "../../../src/core/modules/moduleId";
import { ProgressItem } from "../../../src/core/providers/progressItem";
import type { EventTiming, ProvidedEvent, ProvidedMeetingLink } from "../../../src/core/providers/providedEvent";
import { TickerHighlight } from "../../../src/core/providers/tickerHighlight";
import { tickerFocusClock, tickerMeetingCountdown, tickerMeetingSummary, tickerProgressLeft, tickerTasksLeft } from "../../../src/core/ticker/tickerFormat";
import {
  meetingOffersJoin,
  tickerFocus,
  tickerFocusProgress,
  tickerItemIsPinned,
  tickerItemKind,
  tickerItemModule,
  tickerMeeting,
  type TickerItem,
} from "../../../src/core/ticker/tickerItem";
import { highlightsKind, TICKER_KINDS, tickerKindModule } from "../../../src/core/ticker/tickerKind";
import { TickerRotation } from "../../../src/core/ticker/tickerRotation";
import { StudyDailyGoal } from "../../../src/core/studyMethods/studyDailyGoal";
import { TickerSources } from "../../../src/core/ticker/tickerSources";
import { switchLanguage } from "../../support/catalogs";

// Date(timeIntervalSinceReferenceDate: 800_000_000) in seconds since 1970.
const now = 800_000_000 + 978_307_200;

const zoom: ProvidedMeetingLink = { provider: "zoom", url: "https://zoom.us/j/1" };

function event(title: string, startsInMinutes: number, options: { length?: number; link?: boolean; allDay?: boolean } = {}): ProvidedEvent {
  const start = now + startsInMinutes * 60;
  return {
    id: title,
    title,
    start,
    end: start + (options.length ?? 30) * 60,
    isAllDay: options.allDay ?? false,
    ...(options.link === true ? { meetingLink: zoom } : {}),
  };
}

function runningFocus(remaining: number): FocusTimer {
  const timer = new FocusTimer(new FocusTimerConfig(25 * 60));
  timer.start(now + remaining - 25 * 60);
  return timer;
}

/* The Swift fixture's FocusTimer.shared: the timer as Today (the planner) shares it. */
const shared = (timer: FocusTimer) => timer.provided("planner");

function cards(completed: number, target: number, source: ModuleID = "anki"): ProgressItem {
  return new ProgressItem({ id: "reviews", source, title: "Anki reviews", completed, target, unit: "cards" });
}

function usage(snapshot: ClaudeRateLimitSnapshot): TickerHighlight[] {
  return usageHighlights(snapshot, now).map((h) => new TickerHighlight(h));
}

const highlightItem = (...args: Parameters<typeof usageHighlight>): TickerItem => ({
  type: "highlight",
  highlight: new TickerHighlight(usageHighlight(...args)),
});

const meetingItem = (init: Parameters<typeof tickerMeeting>[0]): TickerItem => ({ type: "meeting", meeting: tickerMeeting(init) });

beforeAll(() => {
  switchLanguage("en");
});

describe("TickerSources", () => {
  it("has no items without data", () => {
    expect(new TickerSources().items(now)).toEqual([]);
  });

  it("an untouched focus goal waits for the day's first minutes", () => {
    const goal = new StudyDailyGoal(120);
    const fresh = goal.progressItem({ minutes: 0, sessions: 0, points: 0 });
    // A fresh day doesn't open on "2h left" for a goal the user never set.
    expect(new TickerSources({ progress: [fresh] }).items(now)).toEqual([]);
    const started = goal.progressItem({ minutes: 25, sessions: 0, points: 0 });
    expect(new TickerSources({ progress: [started] }).items(now)).toEqual([{ type: "progress", item: started }]);
    // Work that is due shows from the start.
    const dueCards = cards(0, 50);
    expect(new TickerSources({ progress: [fresh, dueCards] }).items(now)).toEqual([{ type: "progress", item: dueCards }]);
  });

  it("lists items in rotation order", () => {
    const sources = new TickerSources({
      events: [event("Standup", 30)],
      isMusicPlaying: true,
      focus: shared(runningFocus(600)),
      tasksRemaining: 3,
      progress: [cards(10, 50)],
      highlights: usage({ fiveHour: { utilization: 0.85 } }),
    });
    expect(sources.items(now).map(tickerItemKind)).toEqual(["meeting", "nowPlaying", "focus", "tasks", "progress", "claudeUsage"]);
  });

  it("skips disabled kinds", () => {
    const sources = new TickerSources({ isMusicPlaying: true, tasksRemaining: 2 });
    expect(sources.items(now, new Set([TICKER_KINDS.tasks]))).toEqual([{ type: "tasks", remaining: 2 }]);
    expect(sources.items(now, new Set())).toEqual([]);
  });

  it("counts a meeting down and reports its join link", () => {
    const sources = new TickerSources({ events: [event("Standup", 3.5, { link: true })] });
    expect(sources.items(now)).toEqual([meetingItem({ title: "Standup", timing: { kind: "startsIn", minutes: 4 }, canJoin: true, link: zoom })]);
  });

  it("shows Join only once a call is close", () => {
    expect(meetingOffersJoin(tickerMeeting({ title: "Standup", timing: { kind: "startsIn", minutes: 5 }, canJoin: true, link: zoom }))).toBe(true);
    expect(meetingOffersJoin(tickerMeeting({ title: "Standup", timing: { kind: "now" }, canJoin: true, link: zoom }))).toBe(true);
    expect(meetingOffersJoin(tickerMeeting({ title: "Standup", timing: { kind: "startsIn", minutes: 6 }, canJoin: true, link: zoom }))).toBe(false);
    expect(meetingOffersJoin(tickerMeeting({ title: "Standup", timing: { kind: "now" }, canJoin: true })), "no link, nothing to join").toBe(false);
  });

  it("reads now for a meeting in progress", () => {
    const sources = new TickerSources({ events: [event("Design review", -10)] });
    expect(sources.items(now)).toEqual([meetingItem({ title: "Design review", timing: { kind: "now" }, canJoin: false })]);
  });

  it("lets an imminent meeting beat one already under way", () => {
    const focusBlock = event("Focus block", -57, { length: 120 });
    const standup = event("Standup", 3);
    expect(new TickerSources({ events: [focusBlock, standup] }).items(now)).toEqual([
      meetingItem({ title: "Standup", timing: { kind: "startsIn", minutes: 3 }, canJoin: false }),
    ]);
    const later = event("Standup", 20);
    expect(new TickerSources({ events: [focusBlock, later] }).items(now)).toEqual([
      meetingItem({ title: "Focus block", timing: { kind: "now" }, canJoin: false }),
    ]);
  });

  it("has no wake when nothing is timed", () => {
    expect(new TickerSources({ isMusicPlaying: true, tasksRemaining: 3 }).nextChange(now)).toBeUndefined();
  });

  it("follows the meeting countdown for the next change", () => {
    const soon = new TickerSources({ events: [event("Standup", 3.5)] });
    const wake = soon.nextChange(now);
    expect(wake).toBe(now + 30);
    if (wake === undefined) return;
    expect(soon.items(now)).not.toEqual(soon.items(wake));
    expect(soon.items(now)).toEqual(soon.items(wake - 1));

    const started = new TickerSources({ events: [event("Review", -10, { length: 30 })] });
    expect(started.nextChange(now)).toBe(now + 20 * 60);

    const distant = new TickerSources({ events: [event("Later", 90)] });
    const entry = distant.nextChange(now);
    expect(entry).toBe(now + 30 * 60);
    if (entry === undefined) return;
    expect(distant.items(entry).map(tickerItemKind)).toEqual(["meeting"]);
    expect(distant.nextChange(now, new Set([TICKER_KINDS.tasks]))).toBeUndefined();
  });

  it("covers the focus end and a usage reset in the next change", () => {
    const focus = new TickerSources({ focus: shared(runningFocus(600)) });
    expect(focus.nextChange(now)).toBe(now + 600);

    const reset = now + 900;
    const usageSources = new TickerSources({ highlights: usage({ fiveHour: { utilization: 0.9, resetsAt: reset } }) });
    expect(usageSources.nextChange(now)).toBe(reset);
    expect(usageSources.items(reset)).toEqual([]);
  });

  it("hides meetings beyond the horizon and all-day events", () => {
    const allDay = event("Offsite", 0, { length: 24 * 60, allDay: true });
    expect(new TickerSources({ events: [event("Later", 61), allDay] }).items(now)).toEqual([]);
    expect(new TickerSources({ events: [event("Soon", 60)] }).items(now).length).toBe(1);
  });

  it("shows only an active focus session", () => {
    expect(new TickerSources({ focus: shared(new FocusTimer()) }).items(now)).toEqual([]);

    expect(new TickerSources({ focus: shared(runningFocus(600)) }).items(now)).toEqual([
      { type: "focus", focus: tickerFocus({ phase: "focus", time: 600, isRunning: true, length: 25 * 60 }) },
    ]);

    const paused = runningFocus(600);
    paused.pause(now);
    expect(new TickerSources({ focus: shared(paused) }).items(now)).toEqual([
      { type: "focus", focus: tickerFocus({ phase: "focus", time: 600, isRunning: false, length: 25 * 60 }) },
    ]);
  });

  it("fills the focus ring as the phase passes", () => {
    const item = new TickerSources({ focus: shared(runningFocus(15 * 60)) }).items(now)[0];
    expect(item?.type).toBe("focus");
    if (item?.type !== "focus") return;
    expect(tickerFocusProgress(item.focus)).toBeCloseTo(0.4, 4);

    expect(tickerFocusProgress(tickerFocus({ phase: "focus", time: 25 * 60, isRunning: true, length: 25 * 60 }))).toBe(0);
    expect(tickerFocusProgress(tickerFocus({ phase: "rest", time: 0, isRunning: true, length: 5 * 60 }))).toBe(1);
    // A clock running past its length (a late tick) stays full.
    expect(tickerFocusProgress(tickerFocus({ phase: "focus", time: -5, isRunning: true, length: 60 }))).toBe(1);
  });

  it("gives no ring to open-ended or unsized clocks", () => {
    expect(tickerFocusProgress(tickerFocus({ phase: "focus", time: 600, countsUp: true, isRunning: true, length: 900 }))).toBeUndefined();
    expect(tickerFocusProgress(tickerFocus({ phase: "focus", time: 600, isRunning: true }))).toBeUndefined();
    expect(tickerFocusProgress(tickerFocus({ phase: "focus", time: 600, isRunning: true, length: 0 }))).toBeUndefined();
  });

  it("shows nothing for a finished task list", () => {
    expect(new TickerSources({ tasksRemaining: 0 }).items(now)).toEqual([]);
  });

  it("shows the first unfinished goal", () => {
    const done = cards(40, 40);
    const left = new ProgressItem({ id: "qbank", source: "study", title: "Questions", completed: 5, target: 40, unit: "questions" });
    expect(new TickerSources({ progress: [done] }).items(now)).toEqual([]);
    expect(new TickerSources({ progress: [cards(0, 0)] }).items(now)).toEqual([]);
    expect(new TickerSources({ progress: [done, left] }).items(now)).toEqual([{ type: "progress", item: left }]);
  });

  it("shows usage only above eighty percent and picks the fuller window", () => {
    const items = (fiveHour: number | undefined, weekly: number | undefined) =>
      new TickerSources({
        highlights: usage({
          ...(fiveHour === undefined ? {} : { fiveHour: { utilization: fiveHour } }),
          ...(weekly === undefined ? {} : { sevenDay: { utilization: weekly } }),
        }),
      }).items(now);
    expect(items(0.8, 0.5)).toEqual([]);
    expect(items(undefined, undefined)).toEqual([]);
    expect(items(0.81, 0.5)).toEqual([highlightItem("fiveHour", 0.81)]);
    expect(items(0.4, 0.93)).toEqual([highlightItem("weekly", 0.93)]);
    expect(items(0.9, 0.9)).toEqual([highlightItem("fiveHour", 0.9)]);
  });

  it("ignores usage from a window that has reset", () => {
    const sources = new TickerSources({
      highlights: usage({
        fiveHour: { utilization: 0.95, resetsAt: now - 60 },
        sevenDay: { utilization: 0.85, resetsAt: now + 3600 },
      }),
    });
    expect(sources.items(now)).toEqual([highlightItem("weekly", 0.85, now + 3600)]);
    expect(sources.items(now + 7200)).toEqual([]);
  });

  it("pins only imminent or current meetings", () => {
    const pinned = (startsIn: number) => {
      const first = new TickerSources({ events: [event("M", startsIn)] }).items(now)[0];
      return first === undefined ? false : tickerItemIsPinned(first);
    };
    expect(pinned(-5)).toBe(true);
    expect(pinned(0)).toBe(true);
    expect(pinned(5)).toBe(true);
    expect(pinned(5.5)).toBe(false);
    expect(tickerItemIsPinned({ type: "tasks", remaining: 1 })).toBe(false);
  });

  it("opens each kind's module", () => {
    expect(tickerKindModule(TICKER_KINDS.meeting)).toBe("planner");
    expect(tickerKindModule(TICKER_KINDS.focus), "Any module can run the focus clock").toBeUndefined();
    expect(tickerKindModule(TICKER_KINDS.tasks)).toBe("planner");
    expect(tickerKindModule(TICKER_KINDS.nowPlaying)).toBe("spotify");
    expect(tickerKindModule(highlightsKind("claudeUsage"))).toBe("claudeUsage");
    expect(tickerKindModule(TICKER_KINDS.progress)).toBeUndefined();
  });

  it("opens the module that provided a goal", () => {
    expect(tickerItemModule({ type: "progress", item: cards(1, 5) })).toBe("anki");
    expect(tickerItemModule({ type: "progress", item: cards(1, 5, "study") })).toBe("study");
    expect(tickerItemModule({ type: "tasks", remaining: 1 })).toBe("planner");
  });
});

describe("TickerRotation", () => {
  const start = now;
  const music: TickerItem = { type: "nowPlaying" };
  const tasks: TickerItem = { type: "tasks", remaining: 3 };
  const focus: TickerItem = { type: "focus", focus: tickerFocus({ phase: "focus", time: 600, isRunning: true }) };
  const at = (seconds: number) => start + seconds;
  const meeting = (timing: EventTiming): TickerItem => meetingItem({ title: "Standup", timing, canJoin: false });

  it("shows nothing when nothing is available", () => {
    const rotation = new TickerRotation(8);
    expect(rotation.update([], start)).toBeUndefined();
    expect(rotation.currentKind).toBeUndefined();
  });

  it("holds each item for the interval then wraps around", () => {
    const rotation = new TickerRotation(8);
    const items = [music, focus, tasks];
    expect(rotation.update(items, at(0))).toEqual(music);
    expect(rotation.update(items, at(7.9))).toEqual(music);
    expect(rotation.update(items, at(8))).toEqual(focus);
    expect(rotation.update(items, at(15))).toEqual(focus);
    expect(rotation.update(items, at(16))).toEqual(tasks);
    expect(rotation.update(items, at(24))).toEqual(music);
  });

  it("returns fresh data for the item on screen", () => {
    const rotation = new TickerRotation(8);
    rotation.update([focus], at(0));
    const later: TickerItem = { type: "focus", focus: tickerFocus({ phase: "focus", time: 597, isRunning: true }) };
    expect(rotation.update([later], at(3))).toEqual(later);
  });

  it("keeps a single item and restarts its hold", () => {
    const rotation = new TickerRotation(5);
    expect(rotation.update([tasks], at(0))).toEqual(tasks);
    expect(rotation.update([tasks], at(5))).toEqual(tasks);
    expect(rotation.shownSince).toBe(at(5));
  });

  it("hands a vanished item over to its successor immediately", () => {
    const rotation = new TickerRotation(8);
    expect(rotation.update([music, focus, tasks], at(0))).toEqual(music);
    expect(rotation.update([focus, tasks], at(2))).toEqual(focus);
    expect(rotation.shownSince).toBe(at(2));
  });

  it("lets a new item join the rotation in order", () => {
    const rotation = new TickerRotation(8);
    rotation.update([music, tasks], at(0));
    expect(rotation.update([music, focus, tasks], at(8))).toEqual(focus);
  });

  it("pins an imminent meeting and resumes the rotation after it", () => {
    const rotation = new TickerRotation(8);
    rotation.update([music, tasks], at(0));

    const soon = meeting({ kind: "startsIn", minutes: 4 });
    expect(rotation.update([soon, music, tasks], at(2))).toEqual(soon);
    expect(rotation.update([soon, music, tasks], at(60))).toEqual(soon);
    const live = meeting({ kind: "now" });
    expect(rotation.update([live, music, tasks], at(300))).toEqual(live);
    expect(rotation.shownSince, "the pin keeps its original start").toBe(at(2));

    // The meeting ends; rotation picks up with the item after it.
    expect(rotation.update([music, tasks], at(2000))).toEqual(music);
    expect(rotation.update([music, tasks], at(2008))).toEqual(tasks);
  });

  it("rotates a distant meeting like any other item", () => {
    const rotation = new TickerRotation(8);
    const later = meeting({ kind: "startsIn", minutes: 30 });
    expect(rotation.update([later, music], at(0))).toEqual(later);
    expect(rotation.update([later, music], at(8))).toEqual(music);
  });

  it("applies a changed interval to the item on screen", () => {
    const rotation = new TickerRotation(12);
    rotation.update([music, tasks], at(0));
    rotation.interval = 5;
    expect(rotation.update([music, tasks], at(5))).toEqual(tasks);
  });

  it("shows the next item on advance and holds it for a full turn", () => {
    const rotation = new TickerRotation(8);
    const items = [music, focus, tasks];
    rotation.update(items, at(0));
    expect(rotation.advance(items, at(5))).toEqual(focus);
    expect(rotation.update(items, at(12.9)), "a fresh turn from the swipe").toEqual(focus);
    expect(rotation.update(items, at(13))).toEqual(tasks);
    expect(rotation.advance(items, at(14)), "wraps around").toEqual(music);
  });

  it("keeps the island as it is when advancing with one item or none", () => {
    const rotation = new TickerRotation(8);
    expect(rotation.advance([], at(0))).toBeUndefined();
    expect(rotation.advance([tasks], at(1))).toEqual(tasks);
    expect(rotation.update([tasks, music], at(2))).toEqual(tasks);
  });

  it("peeks past a pin on advance, then the pin returns", () => {
    const rotation = new TickerRotation(8);
    const soon = meeting({ kind: "startsIn", minutes: 4 });
    const items = [soon, music, tasks];
    expect(rotation.update(items, at(0))).toEqual(soon);
    expect(rotation.advance(items, at(10))).toEqual(music);
    expect(rotation.update(items, at(17))).toEqual(music);
    expect(rotation.update(items, at(18)), "the meeting takes the island back").toEqual(soon);
    expect(rotation.update(items, at(60))).toEqual(soon);
  });

  it("hands back to the pin when a peeked item vanishes", () => {
    const rotation = new TickerRotation(8);
    const soon = meeting({ kind: "startsIn", minutes: 4 });
    rotation.update([soon, music], at(0));
    expect(rotation.advance([soon, music], at(1))).toEqual(music);
    expect(rotation.update([soon], at(2))).toEqual(soon);
  });

  it("clears the rotation when everything disappears", () => {
    const rotation = new TickerRotation(8);
    rotation.update([music], at(0));
    expect(rotation.update([], at(1))).toBeUndefined();
    expect(rotation.currentKind).toBeUndefined();
    expect(rotation.update([tasks], at(2))).toEqual(tasks);
  });
});

describe("TickerFormat", () => {
  it("writes meeting lines", () => {
    const soon = tickerMeeting({ title: "Standup", timing: { kind: "startsIn", minutes: 4 }, canJoin: true });
    const live = tickerMeeting({ title: "Design review", timing: { kind: "now" }, canJoin: false });
    expect(tickerMeetingSummary(soon)).toBe("Standup in 4 min");
    expect(tickerMeetingSummary(live)).toBe("Design review now");
    expect(tickerMeetingCountdown({ kind: "startsIn", minutes: 4 })).toBe("in 4 min");
  });

  it("pluralizes tasks left", () => {
    expect(tickerTasksLeft(1)).toBe("1 task left");
    expect(tickerTasksLeft(3)).toBe("3 tasks left");
  });

  it("uses the goal's unit for progress left", () => {
    const item = new ProgressItem({ id: "reviews", source: "anki", title: "Anki reviews", completed: 16, target: 100, unit: "cards" });
    expect(tickerProgressLeft(item, "en")).toBe("84 cards left");
  });

  it("writes focus and usage", () => {
    expect(tickerFocusClock(18 * 60 + 42)).toBe("18:42");
    expect(usageHighlight("fiveHour", 0.842).text).toBe("5h 84%");
    expect(usageHighlight("weekly", 0.91).text).toBe("Week 91%");
  });
});
