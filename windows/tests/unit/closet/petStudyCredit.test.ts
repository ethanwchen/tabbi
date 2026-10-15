import { describe, expect, it } from "vitest";
import { PetCloset } from "../../../src/core/closet/petCloset";
import {
  awardHeadline,
  awardIsLevelUp,
  awardPointsText,
  awardUnlockLine,
  creditFocus,
  creditRecord,
  type PetStudyAward,
} from "../../../src/core/closet/petStudyCredit";
import {
  FOCUS_COMPLETED,
  MINUTES_UNIT,
  OUTCOME_KEY,
  type StudyActivityRecord,
} from "../../../src/core/closet/studyActivity";
import { ProvidedFocus } from "../../../src/core/providers/providedFocus";
import type { ProvidedFocusClock as FocusClock } from "../../../src/core/providers/providedFocus";
import type { FocusPhase } from "../../../src/core/focus/focusTimer";
import { accessoryItem, itemDisplayName, outfitItem } from "../../../src/core/pets/petItem";
import { PetPointsRules } from "../../../src/core/pets/petPointsRules";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { PetSave } from "../../../src/core/pets/petSave";
import { PetPointsLedger } from "../../../src/core/pets/petUnlocks";

// Port of PetStudyCreditTests. The Pomodoro (FocusTimer) is another port's,
// so a small stand-in here mirrors the Mac timer's rules (25 minute focus, 5
// minute rest, start, pause, reset, stop, skip and advance) and shares its
// clock the way `FocusTimer.provided(by: .planner)` does.
const t0 = 700_000_000 + 978_307_200;
const FOCUS = 25 * 60;
const REST = 5 * 60;

type Run = { kind: "idle" } | { kind: "running"; endsAt: number } | { kind: "paused"; remaining: number };

class TestTimer {
  phase: FocusPhase = "focus";
  run: Run = { kind: "idle" };
  completedFocusCount = 0;

  copy(): TestTimer {
    const copy = new TestTimer();
    copy.phase = this.phase;
    copy.run = this.run;
    copy.completedFocusCount = this.completedFocusCount;
    return copy;
  }

  get phaseDuration(): number {
    return this.phase === "focus" ? FOCUS : REST;
  }

  remaining(now: number): number {
    switch (this.run.kind) {
      case "idle":
        return this.phaseDuration;
      case "running":
        return Math.max(this.run.endsAt - now, 0);
      case "paused":
        return this.run.remaining;
    }
  }

  start(now: number): void {
    if (this.run.kind === "idle") this.run = { kind: "running", endsAt: now + this.phaseDuration };
    else if (this.run.kind === "paused") this.run = { kind: "running", endsAt: now + this.run.remaining };
  }

  pause(now: number): void {
    if (this.run.kind === "running") this.run = { kind: "paused", remaining: this.remaining(now) };
  }

  reset(): void {
    this.phase = "focus";
    this.run = { kind: "idle" };
  }

  private cutShort(now: number, outcome: string): { focused: number; endedAt: number; outcome: string } | undefined {
    const focused = this.phase === "focus" && this.run.kind !== "idle" ? this.phaseDuration - this.remaining(now) : 0;
    return focused > 0 ? { focused, endedAt: now, outcome } : undefined;
  }

  stop(now: number): { focused: number; endedAt: number; outcome: string } | undefined {
    const stopped = this.cutShort(now, "abandoned");
    this.reset();
    return stopped;
  }

  skip(now: number): { focused: number; endedAt: number; outcome: string } | undefined {
    const skipped = this.cutShort(now, "skipped");
    const wasRunning = this.run.kind === "running";
    this.phase = this.phase === "focus" ? "rest" : "focus";
    this.run = wasRunning ? { kind: "running", endsAt: now + this.phaseDuration } : { kind: "idle" };
    return skipped;
  }

  advance(now: number): void {
    while (this.run.kind === "running" && this.run.endsAt <= now) {
      const endsAt = this.run.endsAt;
      if (this.phase === "focus") {
        this.completedFocusCount += 1;
        this.phase = "rest";
        this.run = { kind: "running", endsAt: endsAt + REST };
      } else {
        this.phase = "focus";
        this.run = { kind: "idle" };
      }
    }
  }

  get shared(): ProvidedFocus {
    const clock: FocusClock =
      this.run.kind === "idle"
        ? { kind: "idle" }
        : this.run.kind === "running"
          ? { kind: "countdown", endsAt: this.run.endsAt }
          : { kind: "paused", shown: this.run.remaining };
    return new ProvidedFocus({
      source: "planner",
      phase: this.phase,
      clock,
      phaseLength: this.phaseDuration,
      focusLength: FOCUS,
      completedFocusCount: this.completedFocusCount,
      logsEarlyEnds: true,
    });
  }

  /** The same clock from an engine that logs nothing when a focus phase is cut short. */
  get unlogged(): ProvidedFocus {
    return new ProvidedFocus({ ...this.shared, logsEarlyEnds: false });
  }
}

/** FocusStop.activityRecord: minutes focused, the outcome and the method. */
function stopRecord(stop: { focused: number; endedAt: number; outcome: string }, source: string): StudyActivityRecord {
  return {
    id: `stop-${stop.endedAt}`,
    source,
    kind: FOCUS_COMPLETED,
    end: stop.endedAt,
    quantity: stop.focused / 60,
    unit: MINUTES_UNIT,
    metadata: { method: "pomodoro", [OUTCOME_KEY]: stop.outcome },
  };
}

/** `credited` null means no timer seen yet (an undefined argument would take the default). */
function closet(earned = 0, credited: number | null = 0): PetCloset {
  const save = new PetSave(PetProfile.starter("cat"), new PetPointsLedger({ earned }));
  save.creditedFocusCount = credited ?? undefined;
  return new PetCloset(save);
}

/** A 25 minute focus phase started at t0. */
function running(): TestTimer {
  const timer = new TestTimer();
  timer.start(t0);
  return timer;
}

function must<T>(value: T | undefined): T {
  if (value === undefined) throw new Error("expected a value");
  return value;
}

function award(completedSessions: number, minutes: number, points: number, unlocked: PetStudyAward["unlocked"] = []): PetStudyAward {
  return { completedSessions, minutes, points, unlocked };
}

describe("PetStudyCredit", () => {
  it("a completed session earns minutes plus the bonus", () => {
    const c = closet();
    const old = running();
    const next = old.copy();
    next.advance(t0 + 25 * 60);
    const result = must(creditFocus(c, old.shared, next.shared, t0 + 25 * 60));
    expect(result.completedSessions).toBe(1);
    expect(result.minutes).toBe(25);
    expect(result.points).toBe(25 + PetPointsRules.completionBonus);
    expect(c.balance).toBe(35);
    expect(c.save.creditedFocusCount).toBe(1);
  });

  it("a completion is paid only once", () => {
    const c = closet();
    const done = running();
    done.advance(t0 + 25 * 60);
    expect(creditFocus(c, running().shared, done.shared, t0 + 25 * 60)).toBeDefined();
    expect(creditFocus(c, done.shared, done.shared, t0 + 26 * 60)).toBeUndefined();
    expect(creditFocus(c, undefined, done.shared, t0 + 27 * 60), "a relaunch sees the same count").toBeUndefined();
    expect(c.balance).toBe(35);
  });

  it("the first timer only sets the baseline", () => {
    const c = closet(0, null);
    const timer = running();
    timer.advance(t0 + 25 * 60);
    expect(creditFocus(c, undefined, timer.shared, t0 + 25 * 60)).toBeUndefined();
    expect(c.balance, "history from before the pet existed is not paid out").toBe(0);
    expect(c.save.creditedFocusCount).toBe(1);
  });

  it("sessions that ended while closed are paid at launch", () => {
    const c = closet();
    const timer = running();
    // Asleep through the focus end and the break end.
    timer.advance(t0 + 40 * 60);
    const result = must(creditFocus(c, undefined, timer.shared, t0 + 40 * 60));
    expect(result.completedSessions).toBe(1);
    expect(result.points).toBe(35);
  });

  it("a reset timer history rebaselines without paying", () => {
    const c = closet(0, 4);
    expect(creditFocus(c, undefined, new TestTimer().shared, t0)).toBeUndefined();
    expect(c.save.creditedFocusCount).toBe(0);
    const done = running();
    done.advance(t0 + 25 * 60);
    expect(creditFocus(c, running().shared, done.shared, t0 + 25 * 60)?.points).toBe(35);
  });

  it("skipping mid focus earns the minutes studied without the bonus", () => {
    const c = closet();
    const old = running();
    const now = t0 + 12 * 60 + 40;
    const skipped = old.copy();
    skipped.skip(now);
    const result = must(creditFocus(c, old.unlogged, skipped.unlogged, now));
    expect(result.completedSessions).toBe(0);
    expect(result.minutes).toBe(12);
    expect(result.points).toBe(12);
  });

  it("resetting a paused focus earns the minutes studied", () => {
    const c = closet();
    const paused = running();
    paused.pause(t0 + 9 * 60);
    const reset = paused.copy();
    reset.reset();
    expect(creditFocus(c, paused.unlogged, reset.unlogged, t0 + 60 * 60)?.points, "time spent paused doesn't count").toBe(9);
  });

  it("short or non-focus changes earn nothing", () => {
    let c = closet();
    const old = running();
    const reset = old.copy();
    reset.reset();
    expect(creditFocus(c, old.unlogged, reset.unlogged, t0 + 3 * 60), "under the minimum").toBeUndefined();

    const paused = old.copy();
    paused.pause(t0 + 10 * 60);
    expect(creditFocus(c, old.unlogged, paused.unlogged, t0 + 10 * 60), "pausing is not ending").toBeUndefined();

    const onBreak = old.copy();
    onBreak.advance(t0 + 25 * 60);
    const skippedBreak = onBreak.copy();
    skippedBreak.skip(t0 + 26 * 60);
    c = closet(0, 1);
    expect(creditFocus(c, onBreak.unlogged, skippedBreak.unlogged, t0 + 26 * 60), "skipping a break").toBeUndefined();
    expect(creditFocus(c, old.unlogged, undefined, t0 + 10 * 60), "the timer going away").toBeUndefined();
    expect(c.balance).toBe(0);
  });

  it("a clock that logs its early ends is paid from the log once", () => {
    const c = closet();
    const timer = running();
    const before = timer.copy();
    const now = t0 + 14 * 60 + 30;
    const stop = must(timer.stop(now));
    expect(creditFocus(c, before.shared, timer.shared, now), "the clock going idle pays nothing").toBeUndefined();
    const result = must(creditRecord(c, stopRecord(stop, "focus")));
    expect(result.completedSessions).toBe(0);
    expect(result.minutes).toBe(14);
    expect(result.points, "minutes studied, no completion bonus").toBe(14);
    expect(c.balance).toBe(14);
  });

  it("a skip is logged and paid like a stop", () => {
    const c = closet();
    const timer = running();
    const skip = must(timer.skip(t0 + 20 * 60));
    expect(timer.phase).toBe("rest");
    const record = stopRecord(skip, "focus");
    expect(record.metadata?.[OUTCOME_KEY]).toBe("skipped");
    expect(creditRecord(c, record)?.points).toBe(20);
    expect(timer.skip(t0 + 21 * 60), "skipping the break banks nothing").toBeUndefined();
  });

  it("a study stop is paid from its record after its clock is gone", () => {
    // Study's clock disappears when the session goes idle, so the record is
    // the only trace of the time studied.
    const c = closet();
    const record: StudyActivityRecord = {
      id: "study-stop",
      source: "study",
      kind: FOCUS_COMPLETED,
      end: t0 + 18 * 60,
      quantity: 18,
      unit: MINUTES_UNIT,
      metadata: { [OUTCOME_KEY]: "abandoned" },
    };
    expect(creditRecord(c, record)?.minutes).toBe(18);
    expect(c.balance).toBe(18);
  });

  it("only cut short focus records are paid", () => {
    const c = closet();
    const record = (kind: string, outcome: string | undefined, minutes = 20): StudyActivityRecord => ({
      id: `${kind}-${outcome ?? "none"}-${minutes}`,
      source: "focus",
      kind,
      end: t0 + minutes * 60,
      quantity: minutes,
      unit: MINUTES_UNIT,
      metadata: outcome === undefined ? {} : { [OUTCOME_KEY]: outcome },
    });
    expect(creditRecord(c, record(FOCUS_COMPLETED, "completed")), "paid from the completion count").toBeUndefined();
    expect(creditRecord(c, record(FOCUS_COMPLETED, "stopped")), "a Flowtime stop is a completion").toBeUndefined();
    expect(creditRecord(c, record(FOCUS_COMPLETED, undefined)), "Party's own sessions pay through Party").toBeUndefined();
    expect(creditRecord(c, record("break.taken", "skipped")), "breaks earn nothing").toBeUndefined();
    expect(creditRecord(c, record(FOCUS_COMPLETED, "abandoned", 3)), "under the minimum").toBeUndefined();
    expect(c.balance).toBe(0);
  });

  it("the award names items that just became affordable", () => {
    const c = closet(20);
    const done = running();
    done.advance(t0 + 25 * 60);
    const first = must(creditFocus(c, running().shared, done.shared, t0 + 25 * 60));
    expect(c.balance).toBe(55);
    expect(first.unlocked).toEqual([accessoryItem("beanie"), accessoryItem("roundGlasses")]);
    expect(awardIsLevelUp(first)).toBe(true);

    const next = done.copy();
    next.advance(t0 + 30 * 60);
    next.start(t0 + 30 * 60);
    const started = next.copy();
    next.advance(t0 + 55 * 60);
    const second = must(creditFocus(c, started.shared, next.shared, t0 + 55 * 60));
    expect(second.unlocked, "only newly affordable items").toEqual([
      accessoryItem("ninjaHeadband"),
      accessoryItem("bunnyEars"),
      accessoryItem("coolSunglasses"),
    ]);
  });

  it("switching to another clock only sets a new baseline", () => {
    const c = closet();
    const pomodoro = running();
    pomodoro.advance(t0 + 25 * 60);
    expect(creditFocus(c, running().shared, pomodoro.shared, t0 + 25 * 60)).toBeDefined();
    const balance = c.balance;

    // A Study session starts at zero; then the Pomodoro, with its lifetime
    // total, comes back. Neither switch is a completed session.
    const study = new ProvidedFocus({ source: "study", phase: "focus", clock: { kind: "countUp", since: t0 }, completedFocusCount: 0 });
    expect(creditFocus(c, pomodoro.shared, study, t0 + 26 * 60)).toBeUndefined();
    expect(creditFocus(c, study, pomodoro.shared, t0 + 27 * 60)).toBeUndefined();
    expect(c.balance).toBe(balance);
    expect(c.save.creditedFocusSource).toBe(pomodoro.shared.source);

    // The baseline still pays the Pomodoro's next completion once.
    const next = pomodoro.copy();
    next.advance(t0 + 30 * 60);
    next.start(t0 + 30 * 60);
    const started = next.copy();
    next.advance(t0 + 55 * 60);
    expect(creditFocus(c, started.shared, next.shared, t0 + 55 * 60)?.completedSessions).toBe(1);
  });

  it("the credited count survives saving", () => {
    const save = new PetSave(PetProfile.starter("dog"));
    save.creditedFocusCount = 7;
    save.creditedFocusSource = "study";
    expect(PetSave.decode(JSON.parse(save.encoded())).creditedFocusCount).toBe(7);
    expect(PetSave.decode(JSON.parse(save.encoded())).creditedFocusSource).toBe("study");
    const old = {
      version: 1,
      profile: PetProfile.starter("cat").toJSON(),
      ledger: { earned: 0, spent: 0, purchased: [] },
    };
    expect(PetSave.decode(old).creditedFocusCount, "saves from before credits decode").toBeUndefined();
  });

  it("celebration copy", () => {
    const done = award(1, 25, 35);
    expect(awardHeadline(done)).not.toBe("");
    expect(awardUnlockLine(done)).toBeUndefined();
    expect(awardIsLevelUp(done)).toBe(false);
    expect(awardPointsText(done)).toBe("+35");
    expect(awardHeadline(award(0, 12, 12))).toBe("12 minutes in the bank.");
    expect(awardHeadline(award(2, 50, 70))).toBe("2 sessions done. Wow!");

    expect(awardUnlockLine(award(1, 25, 35, [outfitItem("scrubs")]))).toBe("Enough for the Scrubs now.");
    const three = award(1, 25, 35, [accessoryItem("scarf"), accessoryItem("beanie"), accessoryItem("roundGlasses")]);
    expect(awardUnlockLine(three), "names at most two so the line fits the bubble").toBe(
      `Enough for the ${itemDisplayName(accessoryItem("scarf"))} and the ${itemDisplayName(accessoryItem("beanie"))} now.`,
    );
  });
});
