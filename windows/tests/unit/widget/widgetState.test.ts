import { describe, expect, it } from "vitest";
import { makeActivityRecord, type ActivityRecord } from "../../../src/core/activity/activityRecord";
import { instantOf } from "../../../src/core/calendar/zonedCalendar";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";
import { PET_OUTFITS } from "../../../src/core/pets/petCostume";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { ProvidedFocus } from "../../../src/core/providers/providedFocus";
import {
  WidgetState,
  WidgetStateFile,
  widgetFocusDays,
  widgetFocusMinutes,
  widgetStreak,
  widgetTimer,
  widgetTimerFrom,
  type WidgetTimer,
} from "../../../src/core/widget/widgetState";

/* Port of WidgetStateTests and WidgetStateActivityTests. */

/** 2026-10-`day` at `hour`:`minute` UTC. */
function date(hour: number, minute = 0, day = 9): number {
  return instantOf({ year: 2026, month: 10, day, hour, minute }, "UTC");
}

function key(day: number): string {
  return `2026-10-${String(day).padStart(2, "0")}`;
}

function state(timer?: WidgetTimer, pet = PetProfile.starter("cat")): WidgetState {
  return new WidgetState({ pet, day: "2026-10-09", focusMinutes: 50, streakDays: 3, lastFocusDay: "2026-10-09", timer });
}

let nextID = 0;
function focus(minutes: number, end: number, outcome = "completed", kind = "focus.completed"): ActivityRecord {
  nextID += 1;
  return makeActivityRecord({
    id: `00000000-0000-4000-8000-${String(nextID).padStart(12, "0")}`,
    source: "focus",
    kind,
    start: end - minutes * 60,
    end,
    quantity: minutes,
    unit: "min",
    metadata: { outcome },
  });
}

describe("shown at a date", () => {
  it("resets the minutes at midnight", () => {
    expect(state().minutesAt(date(23, 59), "UTC")).toBe(50);
    expect(state().minutesAt(date(0, 1, 10), "UTC")).toBe(0);
  });

  it("holds the streak through the next day, then breaks it", () => {
    expect(state().streakAt(date(12), "UTC")).toBe(3);
    expect(state().streakAt(date(12, 0, 10), "UTC")).toBe(3);
    expect(state().streakAt(date(0, 1, 11), "UTC")).toBe(0);
    const fresh = new WidgetState({ pet: PetProfile.starter("cat"), day: "2026-10-09", streakDays: 3 });
    expect(fresh.streakAt(date(12), "UTC")).toBe(0);
  });

  it("drops a countdown once it runs out", () => {
    const running = state(widgetTimer("focus", "Focus", { kind: "countdown", endsAt: date(10, 25) }));
    expect(running.timerAt(date(10, 24))).toBeDefined();
    expect(running.timerAt(date(10, 25))).toBeUndefined();
    const paused = state(widgetTimer("rest", "Break", { kind: "paused", shown: 120 }));
    expect(paused.timerAt(date(23))?.label).toBe("Break");
  });

  it("changes at the countdown's end and at midnight", () => {
    const running = state(widgetTimer("focus", "Focus", { kind: "countdown", endsAt: date(10, 25) }));
    expect(running.changeDates(date(10), "UTC")).toEqual([date(10, 25), date(0, 0, 10)]);
    expect(running.changeDates(date(11), "UTC")).toEqual([date(0, 0, 10)]);
    const counting = state(widgetTimer("focus", "Focus", { kind: "countUp", since: date(9) }));
    expect(counting.changeDates(date(10), "UTC")).toEqual([date(0, 0, 10)]);
  });
});

describe("timer from the shared clock", () => {
  it("follows the provided focus clock", () => {
    expect(widgetTimerFrom(new ProvidedFocus({ source: "focus", phase: "focus", clock: { kind: "idle" }, phaseLength: 1500 }))).toBeUndefined();
    const running = new ProvidedFocus({
      source: "focus",
      phase: "rest",
      label: "Long break",
      clock: { kind: "countdown", endsAt: date(10, 15) },
      phaseLength: 900,
    });
    expect(widgetTimerFrom(running)).toEqual({ phase: "rest", label: "Long break", clock: { kind: "countdown", endsAt: date(10, 15) } });
  });
});

describe("streak", () => {
  it("counts consecutive days ending on the latest focus day", () => {
    const days = new Set(["2026-10-05", "2026-10-07", "2026-10-08", "2026-10-09"]);
    expect(widgetStreak(days, "2026-10-09")).toEqual({ days: 3, last: "2026-10-09" });
    expect(widgetStreak(days, "2026-10-07").days).toBe(1);
    expect(widgetStreak(new Set(["2026-09-30", "2026-10-01"]), "2026-10-01").days).toBe(2);
    expect(widgetStreak(new Set(), "2026-10-09")).toEqual({ days: 0, last: undefined });
  });
});

describe("file", () => {
  it("round-trips and skips unchanged writes", async () => {
    const store = new InMemoryDocumentStore();
    const file = new WidgetStateFile(store);
    expect(await file.read()).toBeUndefined();
    /* A fractional end second must not make every write look like a change. */
    const pet = PetProfile.starter("cat");
    pet.outfit = PET_OUTFITS[PET_OUTFITS.length - 1] ?? "none";
    const timed = state(widgetTimer("focus", "Focus", { kind: "countdown", endsAt: date(10, 25) + 0.4 }), pet);
    expect(await file.write(timed)).toBe(true);
    expect((await file.read())?.equals(timed)).toBe(true);
    expect(await file.write(timed)).toBe(false);
    expect(await file.write(state(undefined, pet))).toBe(true);
    expect((await file.read())?.timer).toBeUndefined();
  });

  it("writes the Mac's shape with its schema version", () => {
    const text = state(widgetTimer("focus", "Focus", { kind: "countdown", endsAt: date(10, 25) })).encode();
    expect(VersionedJSON.version(text)).toBe(WidgetState.schema.current);
    const json = JSON.parse(text) as Record<string, unknown>;
    expect(json.timer).toEqual({ clock: { countdown: { endsAt: "2026-10-09T10:25:00Z" } }, label: "Focus", phase: "focus" });
    expect(Object.keys(json)).toEqual(["day", "focusMinutes", "lastFocusDay", "pet", "schemaVersion", "streakDays", "timer"]);
  });

  it("reads an unreadable file as nothing", async () => {
    const store = new InMemoryDocumentStore({ [WidgetState.fileName]: "not json" });
    expect(await new WidgetStateFile(store).read()).toBeUndefined();
  });
});

describe("state from the activity log", () => {
  it("counts stopped stretches but not breaks or cards", () => {
    const records = [
      focus(25, date(9)),
      focus(12.6, date(10), "abandoned"),
      focus(5, date(10), "completed", "break.taken"),
      makeActivityRecord({ source: "anki", kind: "cards.reviewed", start: date(11), quantity: 40, unit: "cards" }),
    ];
    expect(widgetFocusMinutes(records)).toBe(37);
  });

  it("walks back until the first gap", async () => {
    const reads: string[] = [];
    const byDay = new Map<string, ActivityRecord[]>([
      [key(9), [focus(25, date(9, 0, 9))]],
      [key(8), [focus(5, date(9, 0, 8), "completed", "break.taken"), focus(30, date(10, 0, 8))]],
      [key(7), [focus(25, date(9, 0, 7))]],
      [key(5), [focus(25, date(9, 0, 5))]],
    ]);
    const days = await widgetFocusDays(key(9), (day) => {
      reads.push(day);
      return byDay.get(day) ?? [];
    });
    expect([...days].sort()).toEqual([key(7), key(8), key(9)]);
    expect(reads).toEqual([key(9), key(8), key(7), key(6)]);
  });

  it("keeps yesterday's streak before today's first session", async () => {
    const byDay = new Map([
      [key(8), [focus(25, date(9, 0, 8))]],
      [key(7), [focus(25, date(9, 0, 7))]],
    ]);
    const days = await widgetFocusDays(key(9), (day) => byDay.get(day) ?? []);
    expect([...days].sort()).toEqual([key(7), key(8)]);
    const widget = WidgetState.fromActivity({ pet: PetProfile.starter("cat"), timer: undefined, todayRecords: [], focusDays: days, now: date(8), timeZone: "UTC" });
    expect(widget.streakAt(date(8), "UTC")).toBe(2);
    expect(widget.minutesAt(date(8), "UTC")).toBe(0);
  });

  it("is empty without focus today or yesterday", async () => {
    const byDay = new Map([[key(7), [focus(25, date(9, 0, 7))]]]);
    expect((await widgetFocusDays(key(9), (day) => byDay.get(day) ?? [])).size).toBe(0);
  });

  it("shows the running clock from the app's sources", () => {
    const now = date(15);
    const end = now + 600;
    const clock = new ProvidedFocus({ source: "focus", phase: "focus", label: "Focus", clock: { kind: "countdown", endsAt: end }, phaseLength: 1500 });
    const widget = WidgetState.fromActivity({
      pet: PetProfile.starter("dog"),
      timer: widgetTimerFrom(clock),
      todayRecords: [focus(50, date(10))],
      focusDays: new Set([key(8), key(9)]),
      now,
      timeZone: "UTC",
    });
    expect(widget.pet.equals(PetProfile.starter("dog"))).toBe(true);
    expect(widget.day).toBe(key(9));
    expect(widget.focusMinutes).toBe(50);
    expect(widget.streakDays).toBe(2);
    expect(widget.lastFocusDay).toBe(key(9));
    expect(widget.timer?.clock).toEqual({ kind: "countdown", endsAt: end });
  });

  it("has an empty and a sample state", () => {
    expect(WidgetState.empty(date(12), "UTC").focusMinutes).toBe(0);
    const sample = WidgetState.sample(date(12), "UTC");
    expect(sample.streakAt(date(12), "UTC")).toBe(5);
    expect(sample.timerAt(date(12))?.phase).toBe("focus");
  });
});
