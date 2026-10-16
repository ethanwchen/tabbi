/*
 * The panel's clock: `now` from the module context, redrawn every `period`
 * seconds while `active` (once a second for a running timer, once a minute
 * for the greeting and the Wrap up hour). A still render reads the pinned
 * clock once and never ticks. Not a timer engine: the stores keep their own
 * wall-clock alarms; this only redraws what shows the time.
 */

import { useEffect, useState } from "react";
import type { ModuleContext } from "../../app/context";
import type { Instant } from "../../core/time";
import { useKit } from "../../ui/kit/context";

export function useClock(context: ModuleContext, period: number, active = true): Instant {
  const { still } = useKit();
  const [now, setNow] = useState(() => context.now());
  const ticks = active && !still && !context.isSnapshot;
  useEffect(() => {
    if (!ticks) return;
    /* Lands just after each boundary, so a minute clock changes with the wall clock. */
    let handle: ReturnType<typeof setTimeout> | undefined;
    const schedule = () => {
      const current = context.now();
      const wait = period - (current % period) + 0.02;
      handle = setTimeout(() => {
        setNow(context.now());
        schedule();
      }, wait * 1000);
    };
    schedule();
    return () => {
      if (handle !== undefined) clearTimeout(handle);
    };
  }, [context, period, ticks]);
  return now;
}
