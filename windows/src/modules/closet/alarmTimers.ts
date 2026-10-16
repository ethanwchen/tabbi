/*
 * The timers the Closet's wall-clock alarms run on: the global ones, so the
 * stores work in the browser and in Vitest's node environment alike (the
 * kit's default timers reach for `window`). Node returns a Timeout object
 * where the browser returns a number; the alarm only ever hands the value
 * back to `clearTimeout`, so the cast is safe.
 */

import type { AlarmTimers } from "../../ui/kit/clock";

export const portableTimers: AlarmTimers = {
  now: () => Date.now(),
  setTimeout: (callback, ms) => globalThis.setTimeout(callback, ms) as unknown as number,
  clearTimeout: (id) => globalThis.clearTimeout(id as unknown as ReturnType<typeof globalThis.setTimeout>),
};
