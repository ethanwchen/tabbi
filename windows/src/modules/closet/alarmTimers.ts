/*
 * The timers the Closet's wall-clock alarms run on: the global ones, so the
 * stores work in the browser and in Vitest's node environment alike (the
 * kit's default timers reach for `window`). Node returns a Timeout object
 * where the browser returns a number; the alarm only ever hands the value
 * back to `clearTimeout`, so the cast is safe.
 *
 * The alarm reads the app's clock, the same one its fire times are planned
 * on. Reading the machine's clock instead made an alarm planned on a pinned
 * clock (demo, snapshot and test runs) always look overdue: it fired at once,
 * planned the same moment again and spun forever.
 */

import type { AlarmTimers } from "../../ui/kit/clock";
import type { Instant } from "../../core/time";

const portableTimers: Omit<AlarmTimers, "now"> = {
  setTimeout: (callback, ms) => globalThis.setTimeout(callback, ms) as unknown as number,
  clearTimeout: (id) => globalThis.clearTimeout(id as unknown as ReturnType<typeof globalThis.setTimeout>),
};

/** Timers whose clock is `now` (the module context's, in seconds). */
export function alarmTimers(now: () => Instant): AlarmTimers {
  return {
    now: () => now() * 1000,
    setTimeout: portableTimers.setTimeout,
    clearTimeout: portableTimers.clearTimeout,
  };
}
