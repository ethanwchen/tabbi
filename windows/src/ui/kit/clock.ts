/*
 * Port of WallClockAlarm (Sources/TabbiKit/Clock/): a one-shot timer for a
 * moment on the wall clock. A plain `setTimeout` counts only the time the
 * machine is awake (and WebView2 throttles timers in a hidden window), so
 * one armed before the lid closes fires late by however long the PC slept:
 * a focus phase that ended during sleep would sit at 0:00 for the rest of
 * its old countdown. The alarm re-arms itself when the page wakes (a
 * visibility change, a drift in a short watchdog tick), so it fires right
 * away if its moment passed during sleep and on time otherwise. `useWallClockAlarm`
 * is the hook form; `WallClockAlarm` is the class, with the clock and the
 * timers injectable for tests.
 */

import { useEffect, useRef } from "react";

export interface AlarmTimers {
  readonly now: () => number;
  readonly setTimeout: (callback: () => void, ms: number) => number;
  readonly clearTimeout: (id: number) => void;
}

const BROWSER_TIMERS: AlarmTimers = {
  now: () => Date.now(),
  setTimeout: (callback, ms) => window.setTimeout(callback, ms),
  clearTimeout: (id) => window.clearTimeout(id),
};

/** How often the watchdog checks the wall clock against the timer's expectation, in milliseconds. */
export const WATCHDOG_INTERVAL = 15_000;
/** A watchdog tick arriving this much later than expected means the machine slept (or the page was throttled). */
export const DRIFT_TOLERANCE = 2_000;

export class WallClockAlarm {
  private readonly action: () => void;
  private readonly timers: AlarmTimers;
  private fireAt: number | undefined;
  private timer: number | undefined;
  private watchdog: number | undefined;
  private expectedTick = 0;
  private readonly onVisibility: () => void;

  /** - action: runs when the alarm goes off. `timers` is the clock, in epoch milliseconds, and the timeouts. */
  constructor(action: () => void, timers: AlarmTimers = BROWSER_TIMERS) {
    this.action = action;
    this.timers = timers;
    this.onVisibility = () => {
      if (typeof document !== "undefined" && document.visibilityState === "visible") this.arm();
    };
    if (typeof document !== "undefined") document.addEventListener("visibilitychange", this.onVisibility);
  }

  /** The moment the alarm goes off, in epoch milliseconds, or undefined when it is not set. */
  get date(): number | undefined {
    return this.fireAt;
  }

  /** Sets the alarm for `at` (epoch milliseconds), replacing any earlier one. A past moment goes off on the next tick. */
  schedule(at: number): void {
    this.fireAt = at;
    this.arm();
  }

  cancel(): void {
    this.fireAt = undefined;
    this.disarm();
  }

  /** Stops watching the page; the alarm is no longer usable. */
  dispose(): void {
    this.cancel();
    if (typeof document !== "undefined") document.removeEventListener("visibilitychange", this.onVisibility);
  }

  /** Re-checks the wall clock now, for a host that reports a resume from sleep. */
  wake(): void {
    this.arm();
  }

  private disarm(): void {
    if (this.timer !== undefined) this.timers.clearTimeout(this.timer);
    if (this.watchdog !== undefined) this.timers.clearTimeout(this.watchdog);
    this.timer = undefined;
    this.watchdog = undefined;
  }

  /** (Re)creates the timeout, which converts the moment into awake time as of now. */
  private arm(): void {
    this.disarm();
    const fireAt = this.fireAt;
    if (fireAt === undefined) return;
    const wait = Math.max(0, fireAt - this.timers.now());
    this.timer = this.timers.setTimeout(() => this.fire(), wait);
    if (wait > WATCHDOG_INTERVAL) this.tickWatchdog();
  }

  private tickWatchdog(): void {
    this.expectedTick = this.timers.now() + WATCHDOG_INTERVAL;
    this.watchdog = this.timers.setTimeout(() => {
      const late = this.timers.now() - this.expectedTick;
      if (late > DRIFT_TOLERANCE) {
        /* The clock jumped: re-arm from the wall clock, which fires at once if the moment has passed. */
        this.arm();
        return;
      }
      if (this.fireAt !== undefined && this.fireAt - this.timers.now() > WATCHDOG_INTERVAL) this.tickWatchdog();
    }, WATCHDOG_INTERVAL);
  }

  private fire(): void {
    this.fireAt = undefined;
    this.disarm();
    this.action();
  }
}

/** An alarm that goes off at `at` (epoch milliseconds, or undefined for none) and runs the latest `action`. */
export function useWallClockAlarm(at: number | undefined, action: () => void): void {
  const latest = useRef(action);
  useEffect(() => {
    latest.current = action;
  }, [action]);
  const alarm = useRef<WallClockAlarm | undefined>(undefined);
  useEffect(() => {
    const instance = new WallClockAlarm(() => latest.current());
    alarm.current = instance;
    return () => {
      instance.dispose();
      alarm.current = undefined;
    };
  }, []);
  useEffect(() => {
    const instance = alarm.current;
    if (!instance) return;
    if (at === undefined) instance.cancel();
    else instance.schedule(at);
  }, [at]);
}
