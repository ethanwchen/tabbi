/*
 * Port of FocusStore: the Pomodoro timer, shown as a card in Today and as
 * the Focus tab.
 *
 * The store owns the `FocusTimer`, so the countdown keeps going while the
 * island is closed: time comes from a wall-clock end, and a wall-clock
 * alarm fires at that date to roll into the next phase, show a toast and
 * celebrate. The view only ticks once a second while a panel shows it. The
 * timer is saved on every change, with a heartbeat while it runs, so a
 * relaunch after a crash ends the session where it really stopped. Finished
 * phases go to the activity log under the Focus module's id.
 *
 * A Windows toast replaces the Mac's scheduled local notification: it shows
 * the moment a phase ends while Tabbi runs (Windows holds it back during Do
 * not disturb). In demo mode the store shows a running sample session; in
 * demo and snapshot runs it never touches toasts, sounds or disk.
 */

import type { ModuleContext } from "../../app/context";
import { Emitter, Store } from "../../app/store";
import { completionActivityRecord, focusSessionsDone, stopActivityRecord } from "../../core/focus/focusTimerActivity";
import { focusCompletionMessage } from "../../core/focus/focusTimerFormat";
import { FocusTimer, type FocusPhaseCompletion, type FocusStop } from "../../core/focus/focusTimer";
import { MODULE_IDS } from "../../core/modules/moduleId";
import type { CelebrationStyle } from "../../core/motion/celebration";
import { plannerDayKeyOf } from "../../core/planner/plannerDayKey";
import { FocusTimerStorage } from "../../core/planner/focusTimerStorage";
import { samplePlannerDay } from "../../core/planner/plannerSampleData";
import type { Instant } from "../../core/time";
import { WallClockAlarm } from "../../ui/kit/clock";
import type { FocusController } from "./focusController";
import type { ModulePreferences } from "./modulePreferences";

/** A panel that shows the focus timer. */
export type FocusViewer = "today" | "focus";

export interface FocusTimerState {
  readonly timer: FocusTimer;
  /** The moment the view measures against; advances every second while visible. */
  readonly now: Instant;
  /** Focus stretches the Pomodoro finished today, from the activity log. */
  readonly sessionsToday: number;
}

/** A celebration a panel showing the timer should play: a confetti burst when a focus session ends. */
export interface FocusCelebration {
  readonly style: CelebrationStyle;
}

/** Fresh phase ends older than this stay quiet: the PC was asleep or Tabbi busy. */
const FRESH_END_SECONDS = 60;
/** How often the heartbeat saves; a crash can cost at most this much. */
export const HEARTBEAT_INTERVAL_SECONDS = 30;
/** A heartbeat this late means the PC slept: the session ends at the last beat, as the Mac ends it before sleeping. */
const SLEEP_GAP_SECONDS = 120;

export function focusTimersEqual(a: FocusTimer, b: FocusTimer): boolean {
  const ra = a.runState;
  const rb = b.runState;
  const sameRun =
    ra.kind === rb.kind &&
    (ra.kind !== "running" || rb.kind !== "running" || ra.endsAt === rb.endsAt) &&
    (ra.kind !== "paused" || rb.kind !== "paused" || ra.remaining === rb.remaining);
  return (
    sameRun &&
    a.phase === b.phase &&
    a.completedFocusCount === b.completedFocusCount &&
    a.linkedItemID === b.linkedItemID &&
    a.config.focusDuration === b.config.focusDuration &&
    a.config.restDuration === b.config.restDuration
  );
}

export class FocusStore extends Store<FocusTimerState> {
  /** A burst to play over whichever panel shows the timer. */
  readonly celebrations = new Emitter<FocusCelebration>();
  /** Resolves once the saved timer is in (at once in demo and snapshot runs). */
  readonly ready: Promise<void>;

  private readonly context: ModuleContext;
  private readonly preferences: ModulePreferences;
  private readonly focusMode: FocusController | undefined;
  private readonly storage: FocusTimerStorage;
  private readonly isDemo: boolean;
  /** Demo or snapshot run: nothing is saved, toasted, played or logged. */
  private readonly isEphemeral: boolean;
  /** Snapshot run: the clock never ticks. A demo's clock does, so it looks alive. */
  private readonly isSnapshot: boolean;
  private readonly viewers = new Set<FocusViewer>();
  private ticker: ReturnType<typeof setInterval> | undefined;
  private heartbeat: ReturnType<typeof setInterval> | undefined;
  private lastBeat: Instant | undefined;
  private readonly phaseEnd: WallClockAlarm;
  private loaded = false;

  constructor(context: ModuleContext, preferences: ModulePreferences, focusMode?: FocusController) {
    const now = context.now();
    const isDemo = context.isDemo;
    super({ timer: isDemo ? FocusStore.demoTimer(now, context.timeZone()) : new FocusTimer(), now, sessionsToday: isDemo ? 2 : 0 });
    this.context = context;
    this.preferences = preferences;
    this.focusMode = focusMode;
    this.storage = new FocusTimerStorage(preferences.defaults);
    this.isDemo = isDemo;
    this.isSnapshot = context.isSnapshot;
    this.isEphemeral = isDemo || context.isSnapshot;
    this.phaseEnd = new WallClockAlarm(() => this.catchUp());
    focusMode?.timerChanged(this.state.timer);
    if (isDemo) {
      this.ready = Promise.resolve();
      this.loaded = true;
      return;
    }
    this.ready = preferences.ready.then(() => this.load());
  }

  /* Takes on the saved timer once the preferences are in. */
  private load(): void {
    const now = this.context.now();
    let timer = this.storage.loadTimer();
    if (this.isEphemeral) {
      /* A snapshot shows the saved timer as it stands now and leaves it be. */
      timer.advance(now);
      this.loaded = true;
      this.changed({ ...this.state, timer, now });
      this.focusMode?.timerChanged(timer);
      return;
    }
    timer = this.recoverAtLaunch(timer, now);
    this.loaded = true;
    this.changed({ ...this.state, timer, now });
    this.focusMode?.timerChanged(timer);
    this.scheduleSideEffects();
    this.updateTicker();
    this.countSessionsToday();
  }

  get timer(): FocusTimer {
    return this.state.timer;
  }

  get remaining(): number {
    return this.state.timer.remaining(this.state.now);
  }

  get progress(): number {
    return this.state.timer.progress(this.state.now);
  }

  /** Call from a panel's mount and unmount; the clock ticks while any viewer is visible. */
  setVisible(visible: boolean, viewer: FocusViewer): void {
    const wasVisible = this.viewers.size > 0;
    if (visible) this.viewers.add(viewer);
    else this.viewers.delete(viewer);
    const isVisible = this.viewers.size > 0;
    if (isVisible === wasVisible) return;
    if (isVisible) this.countSessionsToday();
    this.catchUp();
    this.updateTicker();
  }

  toggleRunning(): void {
    if (this.state.timer.isRunning) this.pause();
    else this.start();
  }

  start(): void {
    this.catchUp();
    this.change((timer) => timer.start(this.state.now));
  }

  pause(): void {
    this.catchUp();
    this.change((timer) => timer.pause(this.state.now));
  }

  /** Ends the session and banks the focus time so far: the activity log gets the minutes, and the pet pays them from there. */
  stop(): void {
    this.catchUp();
    let stopped: FocusStop | undefined;
    this.change((timer) => {
      stopped = timer.stop(this.state.now);
    });
    this.recordStop(stopped);
  }

  /** Moves on to the next phase; a focus phase skipped part-way banks its time like `stop()`. */
  skip(): void {
    this.catchUp();
    let skipped: FocusStop | undefined;
    this.change((timer) => {
      skipped = timer.skip(this.state.now);
    });
    this.recordStop(skipped);
  }

  /** Links the timer to a checklist item, or clears the link with undefined. */
  link(itemID: string | undefined): void {
    this.change((timer) => {
      timer.linkedItemID = itemID;
    });
  }

  /** "Focus on this": links the item and, if nothing is under way yet, starts a focus session so it's one click from the checklist. */
  focusOn(itemID: string): void {
    this.link(itemID);
    const timer = this.state.timer;
    if (timer.runState.kind === "idle" && timer.phase === "focus") this.start();
  }

  /** Changes a copy of the timer and publishes it, so readers holding the old state never see it move; a change that leaves it equal is dropped. */
  change(mutate: (timer: FocusTimer) => void): void {
    const next = this.state.timer.clone();
    mutate(next);
    if (focusTimersEqual(next, this.state.timer)) return;
    this.changed({ ...this.state, timer: next });
    this.focusMode?.timerChanged(next);
    this.scheduleSideEffects();
    this.updateTicker();
  }

  /** Ends the session now, for the app quitting (the Mac's SessionInterruptions). */
  interrupt(): void {
    if (this.state.timer.runState.kind === "idle") return;
    this.stop();
  }

  /** Stops the clock and alarms, e.g. when the window closes. */
  dispose(): void {
    this.phaseEnd.dispose();
    this.viewers.clear();
    this.updateTicker();
    this.updateHeartbeat(false);
  }

  // MARK: Private

  /*
   * Settles what the last run left behind. Quitting stops the session, so
   * one still under way means Tabbi crashed or the PC lost power: it ends at
   * the last heartbeat and is credited once. Without a heartbeat a phase
   * that ran out is just caught up quietly.
   */
  private recoverAtLaunch(saved: FocusTimer, now: Instant): FocusTimer {
    const timer = saved.clone();
    let completions: FocusPhaseCompletion[];
    let stopped: FocusStop | undefined;
    const lastAlive = this.storage.lastAlive;
    if (timer.runState.kind !== "idle" && lastAlive !== undefined) {
      ({ completions, stop: stopped } = timer.recover(lastAlive, now));
    } else {
      completions = timer.advance(now);
    }
    this.storage.save(timer);
    this.preferences.save();
    const records = completions.map((completion) => completionActivityRecord(completion, timer.config, MODULE_IDS.focus));
    const stopRecord = stopped === undefined ? undefined : stopActivityRecord(stopped, MODULE_IDS.focus);
    if (stopRecord !== undefined) records.push(stopRecord);
    if (records.length > 0) void this.context.activityLog.record(records);
    return timer;
  }

  /** Moves `now` forward and applies phase ends that have passed, toasting and celebrating one that just happened. */
  private catchUp(): void {
    const now = this.context.now();
    const timer = this.state.timer.clone();
    const completions = timer.advance(now);
    if (completions.length === 0) {
      if (now !== this.state.now) this.changed({ ...this.state, now });
      return;
    }
    this.changed({ ...this.state, timer, now });
    this.focusMode?.timerChanged(timer);
    this.recordCompletions(completions, timer);
    const last = completions[completions.length - 1];
    if (!this.isEphemeral && last !== undefined && now - last.endedAt < FRESH_END_SECONDS) {
      const message = focusCompletionMessage(last, timer.config);
      void this.context.host.notify(message.title, message.body).catch((error: unknown) => this.context.logger.error("toast", error));
      if (last.phase === "focus") this.celebrations.emit({ style: "confetti" });
    }
    this.scheduleSideEffects();
    this.updateTicker();
  }

  private recordStop(stop: FocusStop | undefined): void {
    if (this.isEphemeral || stop === undefined) return;
    const record = stopActivityRecord(stop, MODULE_IDS.focus);
    if (record !== undefined) void this.context.activityLog.record(record);
  }

  private recordCompletions(completions: readonly FocusPhaseCompletion[], timer: FocusTimer): void {
    if (this.isEphemeral || completions.length === 0) return;
    void this.context.activityLog
      .record(completions.map((completion) => completionActivityRecord(completion, timer.config, MODULE_IDS.focus)))
      .then(() => this.countSessionsToday());
  }

  /** Recounts today's finished focus stretches, so a new day starts over at zero. */
  private countSessionsToday(): void {
    if (this.isDemo || !this.loaded) return;
    const day = plannerDayKeyOf(this.context.now(), this.context.timeZone());
    void this.context.activityLog.records(day).then((records) => {
      const sessionsToday = focusSessionsDone(records, MODULE_IDS.focus);
      if (sessionsToday !== this.state.sessionsToday) this.changed({ ...this.state, sessionsToday });
    });
  }

  /** Saves the timer and arms the phase-end alarm and the heartbeat. */
  private scheduleSideEffects(): void {
    if (this.isEphemeral || !this.loaded) return;
    this.storage.save(this.state.timer);
    this.updateHeartbeat(this.state.timer.isRunning);
    const endsAt = this.state.timer.endsAt;
    if (endsAt === undefined) this.phaseEnd.cancel();
    else this.phaseEnd.schedule(endsAt * 1000);
  }

  /*
   * Saves the last-alive time now and every `HEARTBEAT_INTERVAL_SECONDS`
   * while the clock runs. A beat that arrives minutes late means the PC
   * slept: the session is settled at the last beat, the way the Mac stops
   * it before sleeping, so the night never counts as focus.
   */
  private updateHeartbeat(running: boolean): void {
    const now = this.context.now();
    if (this.state.timer.runState.kind !== "idle") {
      this.storage.saveLastAlive(now);
      this.lastBeat = now;
    }
    this.preferences.save();
    if (!running) {
      if (this.heartbeat !== undefined) clearInterval(this.heartbeat);
      this.heartbeat = undefined;
      return;
    }
    if (this.heartbeat !== undefined) return;
    this.heartbeat = setInterval(() => this.beat(), HEARTBEAT_INTERVAL_SECONDS * 1000);
  }

  private beat(): void {
    const now = this.context.now();
    const last = this.lastBeat;
    if (last !== undefined && now - last > HEARTBEAT_INTERVAL_SECONDS + SLEEP_GAP_SECONDS) {
      this.settleAfterSleep(last, now);
      return;
    }
    this.lastBeat = now;
    this.storage.saveLastAlive(now);
    this.preferences.save();
  }

  private settleAfterSleep(lastAlive: Instant, now: Instant): void {
    const timer = this.state.timer.clone();
    const { completions, stop } = timer.recover(lastAlive, now);
    this.changed({ ...this.state, timer, now });
    this.focusMode?.timerChanged(timer);
    this.recordCompletions(completions, timer);
    this.recordStop(stop);
    this.scheduleSideEffects();
    this.updateTicker();
  }

  /** Ticks once a second, only while a panel shows the timer and the clock runs. The demo ticks too, so its running timer counts down. */
  private updateTicker(): void {
    const wanted = this.viewers.size > 0 && this.state.timer.isRunning && !this.isSnapshot;
    if (!wanted) {
      if (this.ticker !== undefined) clearInterval(this.ticker);
      this.ticker = undefined;
      return;
    }
    if (this.ticker !== undefined) return;
    this.ticker = setInterval(() => this.catchUp(), 1000);
  }

  /** A focus block a third of the way through, linked to the sample checklist's first open item. */
  static demoTimer(now: Instant, timeZone: string): FocusTimer {
    const day = samplePlannerDay(plannerDayKeyOf(now, timeZone), "work", timeZone);
    const timer = new FocusTimer(undefined, day.items.find((item) => !item.isDone)?.id);
    timer.start(now - (10 * 60 + 28));
    return timer;
  }
}
