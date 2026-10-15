import type { ModuleID } from "../modules/moduleId";
import { ProvidedFocus, type ProvidedFocusClock } from "../providers/providedFocus";
import type { Instant, Seconds } from "../time";

/** Port of FocusPhase: which half of a Pomodoro cycle the focus timer is in. */
export type FocusPhase = "focus" | "rest";

/** The phase that follows `phase`. */
export function nextFocusPhase(phase: FocusPhase): FocusPhase {
  return phase === "focus" ? "rest" : "focus";
}

/** Port of FocusTimerConfig: phase lengths, the classic 25/5 by default, each at least a second. */
export class FocusTimerConfig {
  readonly focusDuration: Seconds;
  readonly restDuration: Seconds;

  constructor(focusDuration: Seconds = 25 * 60, restDuration: Seconds = 5 * 60) {
    this.focusDuration = Math.max(focusDuration, 1);
    this.restDuration = Math.max(restDuration, 1);
  }

  duration(phase: FocusPhase): Seconds {
    return phase === "focus" ? this.focusDuration : this.restDuration;
  }
}

/** Port of FocusRunState: whether the clock is moving. */
export type FocusRunState =
  /** Not started; the full phase duration remains. */
  | { readonly kind: "idle" }
  /** Counting down to a wall-clock end. */
  | { readonly kind: "running"; readonly endsAt: Instant }
  /** Stopped part-way with this much time left. */
  | { readonly kind: "paused"; readonly remaining: Seconds };

/** Port of StudyPhaseOutcome's values a FocusStop carries. */
export type FocusStopOutcome = "abandoned" | "skipped";

/** Port of FocusPhaseCompletion: a phase that ran to its end, reported so the app can notify the user. */
export interface FocusPhaseCompletion {
  readonly phase: FocusPhase;
  readonly endedAt: Instant;
}

/**
 * Port of FocusStop: a focus stretch the user ended before it ran out, so the
 * app can credit the time actually focused.
 */
export interface FocusStop {
  /** Time the clock ran in the stopped focus phase, excluding pauses. */
  readonly focused: Seconds;
  readonly endedAt: Instant;
  /** `abandoned` for a stop, `skipped` for a skip to the break. */
  readonly outcome: FocusStopOutcome;
}

/**
 * Port of FocusTimer: the Pomodoro that Today, Focus and the pet coach share.
 *
 * Time comes from a wall-clock end rather than a ticking counter, so the
 * timer stays right while the island is closed or the PC sleeps, and every
 * call takes `now`, which keeps transitions deterministic. When a focus
 * phase ends the break starts on its own; when a break ends the timer waits
 * idle for the user, so it never runs on while they are away.
 */
export class FocusTimer {
  private phaseValue: FocusPhase = "focus";
  private runStateValue: FocusRunState = { kind: "idle" };
  private completedValue = 0;
  config: FocusTimerConfig;
  /** Checklist item the user is focusing on, shown as "Focusing on: ...". */
  linkedItemID: string | undefined;

  constructor(config: FocusTimerConfig = new FocusTimerConfig(), linkedItemID?: string) {
    this.config = config;
    this.linkedItemID = linkedItemID;
  }

  /** A timer in a given state, for modules that run their own clock and share it. */
  static withState(phase: FocusPhase, runState: FocusRunState, config: FocusTimerConfig, completedFocusCount = 0): FocusTimer {
    const timer = new FocusTimer(config);
    timer.phaseValue = phase;
    timer.runStateValue = runState;
    timer.completedValue = Math.max(completedFocusCount, 0);
    return timer;
  }

  clone(): FocusTimer {
    const copy = FocusTimer.withState(this.phaseValue, this.runStateValue, this.config, this.completedValue);
    copy.linkedItemID = this.linkedItemID;
    return copy;
  }

  get phase(): FocusPhase {
    return this.phaseValue;
  }

  get runState(): FocusRunState {
    return this.runStateValue;
  }

  /** Focus phases finished by running out (skips don't count), across sessions. */
  get completedFocusCount(): number {
    return this.completedValue;
  }

  get isRunning(): boolean {
    return this.runStateValue.kind === "running";
  }

  get isPaused(): boolean {
    return this.runStateValue.kind === "paused";
  }

  /** Length of the current phase. */
  get phaseDuration(): Seconds {
    return this.config.duration(this.phaseValue);
  }

  /** Time left in the current phase at `now`, never negative. */
  remaining(now: Instant): Seconds {
    const state = this.runStateValue;
    switch (state.kind) {
      case "idle":
        return this.phaseDuration;
      case "running":
        return Math.max(state.endsAt - now, 0);
      case "paused":
        return state.remaining;
    }
  }

  /** Fraction of the current phase already elapsed, 0...1, for the ring. */
  progress(now: Instant): number {
    const fraction = 1 - this.remaining(now) / this.phaseDuration;
    return Math.min(Math.max(fraction, 0), 1);
  }

  /** When the running phase ends, for scheduling a notification. */
  get endsAt(): Instant | undefined {
    return this.runStateValue.kind === "running" ? this.runStateValue.endsAt : undefined;
  }

  /** Starts from idle or resumes from pause. No-op while running. */
  start(now: Instant): void {
    const state = this.runStateValue;
    switch (state.kind) {
      case "idle":
        this.runStateValue = { kind: "running", endsAt: now + this.phaseDuration };
        break;
      case "paused":
        this.runStateValue = { kind: "running", endsAt: now + state.remaining };
        break;
      case "running":
        break;
    }
  }

  /**
   * Freezes the remaining time. No-op unless running. Call `advance` first so
   * a phase that already ended is not paused with zero seconds left.
   */
  pause(now: Instant): void {
    if (this.runStateValue.kind !== "running") return;
    this.runStateValue = { kind: "paused", remaining: this.remaining(now) };
  }

  /** Back to an idle focus phase at full length. Keeps the linked item and the count. */
  reset(): void {
    this.phaseValue = "focus";
    this.runStateValue = { kind: "idle" };
  }

  /**
   * Ends the session like `reset`, and reports how long the focus phase under
   * way ran so it can be credited pro rata; undefined when nothing was
   * focused. Call `advance` first so a phase that already ran out counts as
   * completed rather than stopped.
   */
  stop(now: Instant): FocusStop | undefined {
    const stopped = this.focusCutShort(now, "abandoned");
    this.reset();
    return stopped;
  }

  /**
   * Ends the current phase early and moves to the next one; the next keeps
   * running if the timer was running. Skipped phases don't count as completed
   * and produce no notification.
   */
  skip(now: Instant): FocusStop | undefined {
    const skipped = this.focusCutShort(now, "skipped");
    const wasRunning = this.isRunning;
    this.phaseValue = nextFocusPhase(this.phaseValue);
    this.runStateValue = wasRunning ? { kind: "running", endsAt: now + this.phaseDuration } : { kind: "idle" };
    return skipped;
  }

  private focusCutShort(now: Instant, outcome: FocusStopOutcome): FocusStop | undefined {
    const focused = this.phaseValue === "focus" && this.runStateValue.kind !== "idle" ? this.phaseDuration - this.remaining(now) : 0;
    if (!(focused > 0)) return undefined;
    return { focused, endedAt: now, outcome };
  }

  /**
   * Applies every phase end that has passed by `now` and reports them, oldest
   * first, each stamped with its real end (after a long sleep, a focus end and
   * the auto-started break's end).
   */
  advance(now: Instant): FocusPhaseCompletion[] {
    const completions: FocusPhaseCompletion[] = [];
    for (;;) {
      const state = this.runStateValue;
      if (state.kind !== "running" || state.endsAt > now) break;
      const endsAt = state.endsAt;
      completions.push({ phase: this.phaseValue, endedAt: endsAt });
      if (this.phaseValue === "focus") {
        this.completedValue += 1;
        this.phaseValue = "rest";
        this.runStateValue = { kind: "running", endsAt: endsAt + this.phaseDuration };
      } else {
        this.phaseValue = "focus";
        this.runStateValue = { kind: "idle" };
      }
    }
    return completions;
  }

  /**
   * Settles a session that was under way when Tabbi stopped without saying so
   * (a crash, power loss): phases that ran out before `lastAlive` count as
   * completed, and the focus phase under way is stopped there. `lastAlive` is
   * clamped to `now`, so a clock set back never credits time from the future.
   */
  recover(lastAlive: Instant, now: Instant): { completions: FocusPhaseCompletion[]; stop: FocusStop | undefined } {
    if (this.runStateValue.kind === "idle") return { completions: [], stop: undefined };
    const end = Math.min(lastAlive, now);
    const completions = this.advance(end);
    const stop = this.stop(end);
    return { completions, stop };
  }

  /**
   * Port of FocusTimer.provided(by:): the timer as the shared focus clock.
   * Its owner logs a focus phase cut short, so the clock says so.
   */
  provided(source: ModuleID): ProvidedFocus {
    const state = this.runStateValue;
    let clock: ProvidedFocusClock;
    switch (state.kind) {
      case "idle":
        clock = { kind: "idle" };
        break;
      case "running":
        clock = { kind: "countdown", endsAt: state.endsAt };
        break;
      case "paused":
        clock = { kind: "paused", shown: state.remaining };
        break;
    }
    return new ProvidedFocus({
      source,
      phase: this.phaseValue,
      clock,
      phaseLength: this.phaseDuration,
      focusLength: this.config.focusDuration,
      completedFocusCount: this.completedValue,
      logsEarlyEnds: true,
    });
  }
}
