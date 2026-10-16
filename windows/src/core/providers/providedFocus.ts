import { focusPhaseName } from "../focus/focusTimerFormat";
import type { FocusPhase } from "../focus/focusTimer";
import type { ModuleID } from "../modules/moduleId";
import type { Instant, Seconds } from "../time";

/** Port of ProvidedFocus.Clock: where a shared focus clock stands. */
export type ProvidedFocusClock =
  /** Set up but not started. */
  | { readonly kind: "idle" }
  /** Counting down to a wall-clock end. */
  | { readonly kind: "countdown"; readonly endsAt: Instant }
  /** An open-ended phase counting up from a wall-clock start (pauses already taken out). */
  | { readonly kind: "countUp"; readonly since: Instant }
  /** Stopped part-way; `shown` is the frozen clock: time left for a phase with a length, time worked otherwise. */
  | { readonly kind: "paused"; readonly shown: Seconds };

export interface ProvidedFocusInit {
  source: ModuleID;
  phase: FocusPhase;
  label?: string;
  clock: ProvidedFocusClock;
  phaseLength?: Seconds | undefined;
  focusLength?: Seconds;
  completedFocusCount?: number;
  isDeep?: boolean;
  logsEarlyEnds?: boolean;
}

function clocksEqual(a: ProvidedFocusClock, b: ProvidedFocusClock): boolean {
  switch (a.kind) {
    case "idle":
      return b.kind === "idle";
    case "countdown":
      return b.kind === "countdown" && a.endsAt === b.endsAt;
    case "countUp":
      return b.kind === "countUp" && a.since === b.since;
    case "paused":
      return b.kind === "paused" && a.shown === b.shown;
  }
}

/**
 * Port of ProvidedFocus: a focus or break clock some module runs, as the rest
 * of the app sees it.
 *
 * Neutral on purpose: the Pomodoro (`FocusTimer`) and Study's session both map
 * into it, including phases with no length (a Flowtime stretch or a card
 * sprint counts up), so the ticker, the pet, the coach and Party read one
 * shape. The value only changes when the clock's state changes, never every
 * second: a running clock carries an instant to count from.
 */
export class ProvidedFocus {
  /** The module running the clock. */
  readonly source: ModuleID;
  /** Focus or break; review and long breaks map onto these two. */
  readonly phase: FocusPhase;
  /** The engine's own name for the phase, e.g. "Focus", "Review" or "Long break". */
  readonly label: string;
  readonly clock: ProvidedFocusClock;
  /** Full length of the current phase; undefined while it counts up. */
  readonly phaseLength: Seconds | undefined;
  /**
   * How long a focus phase runs with this clock: the current one's length
   * during focus, otherwise the planned or last worked one. Sizes the points
   * a finished session earns; undefined when unknown.
   */
  readonly focusLength: Seconds | undefined;
  /** Focus phases finished so far; only grows while the same clock runs. */
  readonly completedFocusCount: number;
  /** The user asked for deep focus with this clock (Study's switch). */
  readonly isDeep: boolean;
  /** The module logs a focus phase cut short in the activity log, with its minutes. */
  readonly logsEarlyEnds: boolean;

  constructor(init: ProvidedFocusInit) {
    this.source = init.source;
    this.phase = init.phase;
    this.label = init.label ?? focusPhaseName(init.phase);
    this.clock = init.clock;
    this.phaseLength = init.phaseLength;
    this.focusLength = init.focusLength ?? (init.phase === "focus" ? init.phaseLength : undefined);
    this.completedFocusCount = Math.max(init.completedFocusCount ?? 0, 0);
    this.isDeep = init.isDeep ?? false;
    this.logsEarlyEnds = init.logsEarlyEnds ?? false;
  }

  /** The same clock from another module, as `ProviderSnapshot` stamps it when merging. */
  withSource(source: ModuleID): ProvidedFocus {
    return new ProvidedFocus({ ...this.init(), source });
  }

  private init(): ProvidedFocusInit {
    return {
      source: this.source,
      phase: this.phase,
      label: this.label,
      clock: this.clock,
      phaseLength: this.phaseLength,
      ...(this.focusLength === undefined ? {} : { focusLength: this.focusLength }),
      completedFocusCount: this.completedFocusCount,
      isDeep: this.isDeep,
      logsEarlyEnds: this.logsEarlyEnds,
    };
  }

  equals(other: ProvidedFocus): boolean {
    return (
      this.source === other.source &&
      this.phase === other.phase &&
      this.label === other.label &&
      clocksEqual(this.clock, other.clock) &&
      this.phaseLength === other.phaseLength &&
      this.focusLength === other.focusLength &&
      this.completedFocusCount === other.completedFocusCount &&
      this.isDeep === other.isDeep &&
      this.logsEarlyEnds === other.logsEarlyEnds
    );
  }

  get isRunning(): boolean {
    return this.clock.kind === "countdown" || this.clock.kind === "countUp";
  }

  get isPaused(): boolean {
    return this.clock.kind === "paused";
  }

  /** Running or paused: the user is mid-session. */
  get isActive(): boolean {
    return this.clock.kind !== "idle";
  }

  /** Whether the clock counts up instead of down. */
  get countsUp(): boolean {
    return this.phaseLength === undefined;
  }

  /** When a countdown runs out; undefined otherwise. */
  get endsAt(): Instant | undefined {
    return this.clock.kind === "countdown" ? this.clock.endsAt : undefined;
  }

  /** Time left at `now`, never negative; undefined for a phase that counts up. */
  remaining(now: Instant): Seconds | undefined {
    const phaseLength = this.phaseLength;
    if (phaseLength === undefined) return undefined;
    const clock = this.clock;
    switch (clock.kind) {
      case "idle":
        return phaseLength;
      case "countdown":
        return Math.max(clock.endsAt - now, 0);
      case "countUp":
        return Math.max(phaseLength - (now - clock.since), 0);
      case "paused":
        return clock.shown;
    }
  }

  /** Time worked in the current phase at `now`, excluding pauses. */
  elapsed(now: Instant): Seconds {
    const clock = this.clock;
    switch (clock.kind) {
      case "idle":
        return 0;
      case "countUp":
        return Math.max(now - clock.since, 0);
      case "paused":
        return this.phaseLength === undefined ? clock.shown : Math.max(this.phaseLength - clock.shown, 0);
      case "countdown": {
        const remaining = this.remaining(now);
        if (this.phaseLength === undefined || remaining === undefined) return 0;
        return Math.max(this.phaseLength - remaining, 0);
      }
    }
  }

  /** What a clock face shows at `now`: time left, or time worked for a phase that counts up. */
  shownTime(now: Instant): Seconds {
    return this.remaining(now) ?? this.elapsed(now);
  }

  /**
   * When a clock face (whole seconds rounded up) next shows a different time
   * after `date`, a hair late so rounding can't show the old one; undefined
   * while nothing moves (idle, paused, or run out). A view that redraws only
   * then stays still while the clock is stopped.
   */
  nextShownChange(date: Instant): Instant | undefined {
    const lag = 0.001;
    const clock = this.clock;
    let end: Instant;
    switch (clock.kind) {
      case "idle":
      case "paused":
        return undefined;
      case "countdown":
        end = clock.endsAt;
        break;
      case "countUp": {
        if (this.phaseLength === undefined) {
          /* Counting up shows ceil(elapsed), which turns just after each whole second. */
          const elapsed = Math.max(date - clock.since, 0);
          return clock.since + Math.ceil(elapsed) + lag;
        }
        end = clock.since + this.phaseLength;
        break;
      }
    }
    const left = end - date;
    if (!(left > 0)) return undefined;
    /* The face shows ceil(left) and drops a second when `left` reaches the next whole second down. */
    return end - (Math.ceil(left) - 1) + lag;
  }
}
