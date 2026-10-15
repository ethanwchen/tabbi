// Port of ProviderSnapshotTests.swift.
import { beforeAll, describe, expect, it } from "vitest";
import { FocusTimer } from "../../../src/core/focus/focusTimer";
import { moduleProvision } from "../../../src/core/providers/moduleProvision";
import { ProgressItem } from "../../../src/core/providers/progressItem";
import type { ProvidedEvent } from "../../../src/core/providers/providedEvent";
import { ProvidedFocus, type ProvidedFocusClock } from "../../../src/core/providers/providedFocus";
import { providedTask, type ProvidedTask } from "../../../src/core/providers/providedTask";
import { ProviderSnapshot } from "../../../src/core/providers/providerSnapshot";
import { switchLanguage } from "../../support/catalogs";

// Date(timeIntervalSinceReferenceDate: 800_000_000) in seconds since 1970.
const now = 800_000_000 + 978_307_200;

function event(id: string, startsInMinutes: number): ProvidedEvent {
  const start = now + startsInMinutes * 60;
  return { id, title: id, start, end: start + 1800, isAllDay: false };
}

function task(id: string, done = false): ProvidedTask {
  return providedTask({ id, source: "unset", title: id, isDone: done });
}

function clock(value: ProvidedFocusClock): ProvidedFocus {
  return new ProvidedFocus({ source: "unset", phase: "focus", clock: value, phaseLength: 1500 });
}

beforeAll(() => {
  switchLanguage("en");
});

describe("ProviderSnapshot", () => {
  it("has nothing when empty", () => {
    const snapshot = new ProviderSnapshot([]);
    expect(snapshot).toEqual(new ProviderSnapshot());
    expect(snapshot.tasks).toEqual([]);
    expect(snapshot.focus).toBeUndefined();
  });

  it("keeps tasks in tab order and stamps them with their source", () => {
    const snapshot = new ProviderSnapshot([
      { module: "anki", provision: moduleProvision({ tasks: [task("due")] }) },
      { module: "planner", provision: moduleProvision({ tasks: [task("a"), task("b", true)] }) },
    ]);
    expect(snapshot.tasks.map((t) => t.id)).toEqual(["due", "a", "b"]);
    expect(snapshot.tasks.map((t) => t.source)).toEqual(["anki", "planner", "planner"]);
    expect(snapshot.openTasks.map((t) => t.id)).toEqual(["due", "a"]);
  });

  it("keeps a repeated task id once per module but not across modules", () => {
    const snapshot = new ProviderSnapshot([
      { module: "planner", provision: moduleProvision({ tasks: [task("x"), task("x")] }) },
      { module: "anki", provision: moduleProvision({ tasks: [task("x")] }) },
    ]);
    expect(snapshot.tasks.map((t) => t.source)).toEqual(["planner", "anki"]);
  });

  it("merges events by start time and drops repeated ids", () => {
    const snapshot = new ProviderSnapshot([
      { module: "planner", provision: moduleProvision({ events: [event("standup", 30), event("lunch", 120)] }) },
      { module: "study", provision: moduleProvision({ events: [event("lecture", 60), event("standup", 30)] }) },
    ]);
    expect(snapshot.events.map((e) => e.id)).toEqual(["standup", "lecture", "lunch"]);
  });

  it("keeps tab order for events with equal starts", () => {
    const snapshot = new ProviderSnapshot([
      { module: "study", provision: moduleProvision({ events: [event("b", 10)] }) },
      { module: "planner", provision: moduleProvision({ events: [event("a", 10)] }) },
    ]);
    expect(snapshot.events.map((e) => e.id)).toEqual(["b", "a"]);
  });

  it("lets an active focus timer beat an idle one earlier in tab order", () => {
    const idle = new FocusTimer();
    const running = new FocusTimer();
    running.start(now);
    const snapshot = new ProviderSnapshot([
      { module: "planner", provision: moduleProvision({ focus: idle.provided("planner") }) },
      { module: "study", provision: moduleProvision({ focus: running.provided("planner") }) },
    ]);
    expect(snapshot.focus).toEqual(running.provided("study"));
    expect(snapshot.focus?.equals(running.provided("study"))).toBe(true);
    expect(snapshot.focus?.source).toBe("study");
  });

  it("lets a running focus clock beat a paused one earlier in tab order", () => {
    const snapshot = new ProviderSnapshot([
      { module: "focus", provision: moduleProvision({ focus: clock({ kind: "paused", shown: 600 }) }) },
      { module: "study", provision: moduleProvision({ focus: clock({ kind: "countUp", since: now }) }) },
    ]);
    expect(snapshot.focus?.source).toBe("study");
  });

  it("picks the most recently started running clock", () => {
    const provisions = [
      { module: "focus", provision: moduleProvision({ focus: clock({ kind: "countdown", endsAt: now + 1200 }) }) },
      { module: "study", provision: moduleProvision({ focus: clock({ kind: "countUp", since: now }) }) },
    ];
    const studyLater = new ProviderSnapshot(provisions, new Map([["focus", now], ["study", now + 60]]));
    expect(studyLater.focus?.source).toBe("study");
    const focusLater = new ProviderSnapshot(provisions, new Map([["focus", now + 60], ["study", now]]));
    expect(focusLater.focus?.source).toBe("focus");
  });

  it("orders running clocks with no known start by tab order", () => {
    const provisions = [
      { module: "study", provision: moduleProvision({ focus: clock({ kind: "countUp", since: now }) }) },
      { module: "focus", provision: moduleProvision({ focus: clock({ kind: "countdown", endsAt: now + 1200 }) }) },
    ];
    expect(new ProviderSnapshot(provisions).focus?.source).toBe("study");
    // A known start beats one restored with no start.
    expect(new ProviderSnapshot(provisions, new Map([["focus", now]])).focus?.source).toBe("focus");
  });

  it("ignores the start of a paused clock", () => {
    const snapshot = new ProviderSnapshot(
      [
        { module: "study", provision: moduleProvision({ focus: clock({ kind: "countUp", since: now }) }) },
        { module: "focus", provision: moduleProvision({ focus: clock({ kind: "paused", shown: 600 }) }) },
      ],
      new Map([["focus", now + 60]]),
    );
    expect(snapshot.focus?.source).toBe("study");
  });

  it("keeps an idle focus timer when none is active", () => {
    const snapshot = new ProviderSnapshot([
      { module: "anki", provision: moduleProvision() },
      { module: "planner", provision: moduleProvision({ focus: new FocusTimer().provided("planner") }) },
    ]);
    expect(snapshot.focus).toEqual(new FocusTimer().provided("planner"));
  });

  it("merges progress in tab order", () => {
    const cards = new ProgressItem({ id: "due", source: "unset", title: "Anki reviews", completed: 112, target: 340, unit: "cards" });
    const snapshot = new ProviderSnapshot([{ module: "anki", provision: moduleProvision({ progress: [cards, cards] }) }]);
    expect(snapshot.progress.length).toBe(1);
    expect(snapshot.progress[0]?.source).toBe("anki");
  });

  it("adds study tallies up across modules", () => {
    expect(new ProviderSnapshot([{ module: "anki", provision: moduleProvision() }]).study, "no module keeps a tally").toBeUndefined();
    const snapshot = new ProviderSnapshot([
      { module: "study", provision: moduleProvision({ study: { minutes: 100, sessions: 2, points: 120 } }) },
      { module: "anki", provision: moduleProvision() },
      { module: "focus", provision: moduleProvision({ study: { minutes: 25, sessions: 1, points: 35 } }) },
    ]);
    expect(snapshot.study).toEqual({ minutes: 125, sessions: 3, points: 155 });
  });

  it("does progress math", () => {
    // Swift mutates one item; ProgressItem is immutable here, so each step is a new value.
    const base = { id: "q", source: "study", title: "Questions", unit: "questions" };
    const item = new ProgressItem({ ...base, completed: 30, target: 40 });
    expect(item.remaining).toBe(10);
    expect(item.fraction).toBeCloseTo(0.75, 9);
    expect(item.isComplete).toBe(false);
    const over = new ProgressItem({ ...base, completed: 55, target: 40 });
    expect(over.remaining).toBe(0);
    expect(over.fraction).toBe(1);
    expect(over.isComplete).toBe(true);
    const none = new ProgressItem({ ...base, completed: 55, target: 0 });
    expect(none.fraction).toBe(1);
  });
});
