import type { Instant, Seconds } from "../time";
import { MINIMUM_PHASE, SPRINT_BREAK_CARDS, SPRINT_BREAK_INTERVAL, StudyMethod, isBreakPhase, type StudyPhaseKind } from "./studyMethod";
import { countsAsDone, type StudyPhaseOutcome, type StudyPhaseRecord, type StudyRunState } from "./studyPhaseRecord";

/**
 * Port of StudySession: the study-timer state machine every `StudyMethod`
 * shares.
 *
 * Time comes from wall-clock instants (when the clock last resumed plus the
 * time banked before that), never a ticking counter, so the session stays
 * right while the island is closed or the PC sleeps. Every call takes `now`,
 * which keeps transitions deterministic and testable.
 *
 * When focus (or review) ends the next phase starts on its own; when a break
 * ends the next focus phase waits idle, so the timer never runs on while the
 * user is away. The plain Timer has no breaks: its countdown ends into a
 * fresh idle one. Open-ended Flowtime focus ends with `stopFocus`; Anki
 * sprint focus ends when `recordReviewedToday` reaches the card goal.
 */
/** Every stored field of a session, as `StudySession.stored` reads them and `fromStored` takes them back. */
export interface StudySessionStoredState {
  readonly method: StudyMethod;
  readonly phase: StudyPhaseKind;
  readonly phaseDuration: Seconds | undefined;
  readonly completedFocusCount: number;
  readonly cardsDone: number;
  readonly log: readonly StudyPhaseRecord[];
  readonly banked: Seconds;
  readonly resumedAt: Instant | undefined;
  readonly phaseStartedAt: Instant | undefined;
  readonly lastFocusWorked: Seconds;
  readonly lastFocusCounted: boolean;
  readonly cardBaseline: number | undefined;
}

export class StudySession {
  private methodValue: StudyMethod;
  private phaseValue: StudyPhaseKind = "focus";
  /** Length of the current phase; fixed when it begins, so a proportional break keeps its length. */
  private phaseDurationValue: Seconds | undefined;
  private completedFocusCountValue = 0;
  private cardsDoneValue = 0;
  private logValue: StudyPhaseRecord[] = [];
  /** Running time banked before the current run segment. */
  private banked: Seconds = 0;
  /** Start of the current run segment; undefined while idle or paused. */
  private resumedAt: Instant | undefined;
  /** First start of the current phase; undefined while idle. */
  private phaseStartedAt: Instant | undefined;
  /** Active time of the last focus phase, which sizes Flowtime breaks. */
  private lastFocusWorkedValue: Seconds = 0;
  /** Whether the last focus phase counted, so a skipped one never earns a long break. */
  private lastFocusCounted = false;
  /** Last reviewed-today count seen from Anki; cards are its deltas. */
  private cardBaseline: number | undefined;

  constructor(method: StudyMethod) {
    this.methodValue = method;
    this.phaseDurationValue = method.duration("focus");
  }

  clone(): StudySession {
    const copy = new StudySession(this.methodValue);
    Object.assign(copy, this);
    copy.logValue = [...this.logValue];
    return copy;
  }

  get method(): StudyMethod {
    return this.methodValue;
  }

  get phase(): StudyPhaseKind {
    return this.phaseValue;
  }

  /** Length of the current phase, or undefined for open-ended or card-goal focus. */
  get phaseDuration(): Seconds | undefined {
    return this.phaseDurationValue;
  }

  /** Focus phases finished this session (completed or stopped; skips don't count). */
  get completedFocusCount(): number {
    return this.completedFocusCountValue;
  }

  /** Cards answered in the current sprint focus phase. */
  get cardsDone(): number {
    return this.cardsDoneValue;
  }

  /** Phases that ran, oldest first, until the app collects them with `takeLog`. */
  get log(): readonly StudyPhaseRecord[] {
    return this.logValue;
  }

  /** Active time of the last focus phase. */
  get lastFocusWorked(): Seconds {
    return this.lastFocusWorkedValue;
  }

  // MARK: Saving

  /** The fields a saved session carries, the Mac's Codable shape before dates and methods are encoded. */
  get stored(): StudySessionStoredState {
    return {
      method: this.methodValue,
      phase: this.phaseValue,
      phaseDuration: this.phaseDurationValue,
      completedFocusCount: this.completedFocusCountValue,
      cardsDone: this.cardsDoneValue,
      log: [...this.logValue],
      banked: this.banked,
      resumedAt: this.resumedAt,
      phaseStartedAt: this.phaseStartedAt,
      lastFocusWorked: this.lastFocusWorkedValue,
      lastFocusCounted: this.lastFocusCounted,
      cardBaseline: this.cardBaseline,
    };
  }

  /**
   * Port of StudySession.init(from:): a session from saved fields, repairing
   * what a corrupt or hand-edited file could carry: a phase shorter than the
   * minimum (which would complete instantly), non-finite or negative banked
   * time, negative tallies, and a running clock on a phase that never started.
   */
  static fromStored(state: StudySessionStoredState): StudySession {
    const nonNegative = (value: number): number => (Number.isFinite(value) ? Math.max(value, 0) : 0);
    const session = new StudySession(state.method);
    session.phaseValue = state.phase;
    session.phaseDurationValue =
      state.phaseDuration === undefined ? undefined : Number.isNaN(state.phaseDuration) ? MINIMUM_PHASE : Math.max(state.phaseDuration, MINIMUM_PHASE);
    session.completedFocusCountValue = Math.max(state.completedFocusCount, 0);
    session.cardsDoneValue = Math.max(state.cardsDone, 0);
    session.logValue = [...state.log];
    session.banked = nonNegative(state.banked);
    session.resumedAt = state.resumedAt;
    session.phaseStartedAt = state.phaseStartedAt ?? state.resumedAt;
    session.lastFocusWorkedValue = nonNegative(state.lastFocusWorked);
    session.lastFocusCounted = state.lastFocusCounted;
    session.cardBaseline = state.cardBaseline;
    return session;
  }

  // MARK: Reading

  get runState(): StudyRunState {
    if (this.resumedAt !== undefined) return "running";
    return this.phaseStartedAt === undefined ? "idle" : "paused";
  }

  private isIdle(): boolean {
    return this.runState === "idle";
  }

  get isRunning(): boolean {
    return this.runState === "running";
  }

  /** Running time in the current phase at `now`, excluding pauses. */
  elapsed(now: Instant): Seconds {
    if (this.resumedAt === undefined) return this.banked;
    return this.banked + Math.max(now - this.resumedAt, 0);
  }

  /** The moment the running phase would have started had it never paused; undefined unless running. */
  get runningSince(): Instant | undefined {
    return this.resumedAt === undefined ? undefined : this.resumedAt - this.banked;
  }

  /** Time left at `now`, never negative; undefined when the phase has no length. */
  remaining(now: Instant): Seconds | undefined {
    return this.phaseDurationValue === undefined ? undefined : Math.max(this.phaseDurationValue - this.elapsed(now), 0);
  }

  /** When the running phase runs out, for scheduling a notification. */
  get endsAt(): Instant | undefined {
    if (this.resumedAt === undefined || this.phaseDurationValue === undefined) return undefined;
    return this.resumedAt + (this.phaseDurationValue - this.banked);
  }

  /** Fraction done, 0...1: time for timed phases, cards for a sprint, undefined for open-ended focus. */
  progress(now: Instant): number | undefined {
    let fraction: number;
    const goal = this.methodValue.cardGoal;
    if (this.phaseDurationValue !== undefined) {
      fraction = this.elapsed(now) / this.phaseDurationValue;
    } else if (this.phaseValue === "focus" && goal !== undefined) {
      fraction = this.cardsDoneValue / goal;
    } else {
      return undefined;
    }
    return Math.min(Math.max(fraction, 0), 1);
  }

  /** Whether a sprint has gone long enough to suggest a pause even before the card goal. */
  suggestsSprintBreak(now: Instant): boolean {
    if (this.phaseValue !== "focus" || this.methodValue.cardGoal === undefined) return false;
    return this.cardsDoneValue >= SPRINT_BREAK_CARDS || this.elapsed(now) >= SPRINT_BREAK_INTERVAL;
  }

  // MARK: Controls

  /**
   * Starts an idle phase or resumes a paused one. No-op while running. For
   * sprint focus the next `recordReviewedToday` sets a fresh card baseline.
   */
  start(now: Instant): void {
    if (this.resumedAt !== undefined) return;
    if (this.phaseStartedAt === undefined) this.phaseStartedAt = now;
    this.resumedAt = now;
    this.dropStaleCardBaseline();
  }

  /** Freezes the clock. No-op unless running. Call `advance` first. */
  pause(now: Instant): void {
    if (this.resumedAt === undefined) return;
    this.banked = this.elapsed(now);
    this.resumedAt = undefined;
  }

  /**
   * Ends the current phase early and moves on. The next phase keeps running
   * if the clock was running; a method without breaks (the Timer) just stops.
   */
  skip(now: Instant): void {
    const wasRunning = this.isRunning;
    this.endPhase(now, "skipped", wasRunning && this.methodValue.hasBreaks);
  }

  /** Ends an open-ended Flowtime focus phase and starts its break. False (and nothing) for any other phase. */
  stopFocus(now: Instant): boolean {
    if (this.phaseValue !== "focus" || this.methodValue.focus.kind !== "openEnded" || this.phaseStartedAt === undefined) {
      return false;
    }
    this.endPhase(now, "stopped", true);
    return true;
  }

  /** Back to an idle first focus phase; logs the current phase as abandoned if it had started. */
  reset(now: Instant): void {
    this.switchMethod(this.methodValue, now);
  }

  /**
   * Settles a session that was under way when Tabbi stopped without saying so:
   * phases that ran out before `lastAlive` are logged as completed, and the
   * phase under way is logged as abandoned there. An idle session is left alone.
   */
  recover(lastAlive: Instant, now: Instant): void {
    if (this.runState === "idle") return;
    const end = Math.min(lastAlive, now);
    this.advance(end);
    /* Advancing may have ended the phase; a getter is re-read, never narrowed. */
    if (this.isIdle()) return;
    this.reset(end);
  }

  /** Starts over with another method, logging the current phase as abandoned. */
  switchMethod(newMethod: StudyMethod, now: Instant): void {
    const record = this.currentRecord(now, "abandoned");
    if (record !== undefined) this.logValue.push(record);
    const log = this.logValue;
    const baseline = this.cardBaseline;
    Object.assign(this, new StudySession(newMethod));
    this.logValue = log;
    this.cardBaseline = baseline;
  }

  /**
   * Swaps in new lengths for the same kind of method without starting over.
   * The current phase takes its new length, but a phase already past it ends
   * no sooner than a minute from `now`. False (and nothing) for another kind.
   */
  retune(newMethod: StudyMethod, now: Instant): boolean {
    if (newMethod.kind !== this.methodValue.kind) return false;
    this.methodValue = newMethod;
    const length = newMethod.duration(this.phaseValue, this.lastFocusWorkedValue);
    this.phaseDurationValue =
      length === undefined
        ? undefined
        : this.phaseStartedAt === undefined
          ? length
          : Math.max(length, this.elapsed(now) + MINIMUM_PHASE);
    return true;
  }

  // MARK: Time and cards

  /** Applies every phase end that has passed by `now` and returns them, oldest first. */
  advance(now: Instant): StudyPhaseRecord[] {
    const ended: StudyPhaseRecord[] = [];
    for (;;) {
      const endsAt = this.endsAt;
      if (endsAt === undefined || endsAt > now) break;
      /* A break, or a Timer's countdown, ends into an idle phase that waits for the user. */
      const record = this.endPhase(endsAt, "completed", !isBreakPhase(this.phaseValue) && this.methodValue.hasBreaks);
      if (record !== undefined) ended.push(record);
    }
    return ended;
  }

  /**
   * Feeds Anki's reviewed-today count. Cards answered while a sprint focus
   * phase runs count toward its goal; reaching it ends the phase. Only
   * increases count, and the first reading after a sprint starts or resumes
   * only sets the baseline. Applies `advance` first and returns every phase
   * that ended.
   */
  recordReviewedToday(count: number, now: Instant): StudyPhaseRecord[] {
    const ended = this.advance(now);
    const baseline = this.cardBaseline;
    try {
      if (baseline === undefined) return ended;
      const delta = count - baseline;
      const goal = this.methodValue.cardGoal;
      if (!(delta > 0) || !this.isRunning || this.phaseValue !== "focus" || goal === undefined) return ended;
      this.cardsDoneValue += delta;
      if (this.cardsDoneValue >= goal) {
        const record = this.endPhase(now, "completed", true);
        if (record !== undefined) ended.push(record);
      }
      return ended;
    } finally {
      this.cardBaseline = count;
    }
  }

  /** Hands the logged phases to the caller and clears them. */
  takeLog(): StudyPhaseRecord[] {
    const taken = this.logValue;
    this.logValue = [];
    return taken;
  }

  // MARK: Transitions

  private currentRecord(end: Instant, outcome: StudyPhaseOutcome): StudyPhaseRecord | undefined {
    if (this.phaseStartedAt === undefined) return undefined;
    const isSprintFocus = this.phaseValue === "focus" && this.methodValue.cardGoal !== undefined;
    return {
      method: this.methodValue.kind,
      phase: this.phaseValue,
      startedAt: this.phaseStartedAt,
      endedAt: end,
      activeDuration: this.elapsed(end),
      outcome,
      ...(isSprintFocus ? { cards: this.cardsDoneValue } : {}),
    };
  }

  /*
   * Closes the current phase at `end` and enters the next one, running from
   * `end` if `startNext`, otherwise idle. Returns the logged record, or
   * undefined when the phase never started.
   */
  private endPhase(end: Instant, outcome: StudyPhaseOutcome, startNext: boolean): StudyPhaseRecord | undefined {
    const record = this.currentRecord(end, outcome);
    if (record !== undefined) this.logValue.push(record);

    if (this.phaseValue === "focus") {
      this.lastFocusWorkedValue = this.elapsed(end);
      this.lastFocusCounted = countsAsDone(outcome);
      if (this.lastFocusCounted) this.completedFocusCountValue += 1;
    }
    /* A skipped focus phase passes 0 so it can never land on a long break. */
    const next = this.methodValue.nextPhase(this.phaseValue, this.lastFocusCounted ? this.completedFocusCountValue : 0);

    this.phaseValue = next;
    this.phaseDurationValue = this.methodValue.duration(next, this.lastFocusWorkedValue);
    this.banked = 0;
    this.cardsDoneValue = 0;
    this.phaseStartedAt = startNext ? end : undefined;
    this.resumedAt = startNext ? end : undefined;
    if (startNext) this.dropStaleCardBaseline();
    return record;
  }

  /*
   * Forgets the card baseline when a sprint focus run segment begins. The app
   * may not poll while the island is closed, so an older reading would count
   * cards answered before the sprint started or while paused.
   */
  private dropStaleCardBaseline(): void {
    if (this.phaseValue === "focus" && this.methodValue.cardGoal !== undefined) this.cardBaseline = undefined;
  }
}
