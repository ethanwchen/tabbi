import type { TimerActivityRecord } from "../../src/core/focus/timerActivity";
import type { ProvidedFocus } from "../../src/core/providers/providedFocus";
import type { Instant } from "../../src/core/time";

/*
 * The shapes focus-timer.json and study-session.json share: an activity
 * record and the shared focus clock, written the way the Swift goldens write
 * them (FocusTimerGoldenFixture.Completion.Activity and .Provided).
 */

/** The activity record as the fixture writes it. */
export function activityJson(record: TimerActivityRecord): Record<string, unknown> {
  return {
    kind: record.kind,
    start: record.start,
    end: record.end,
    quantity: record.quantity,
    unit: record.unit,
    metadata: record.metadata,
  };
}

/** The shared focus clock as the fixture writes it, read at `now`. */
export function providedJson(focus: ProvidedFocus, now: Instant): Record<string, unknown> {
  const clock = focus.clock;
  return {
    phase: focus.phase,
    label: focus.label,
    clock:
      clock.kind === "countdown"
        ? { kind: clock.kind, endsAt: clock.endsAt }
        : clock.kind === "countUp"
          ? { kind: clock.kind, since: clock.since }
          : clock.kind === "paused"
            ? { kind: clock.kind, shown: clock.shown }
            : { kind: clock.kind },
    phaseLength: focus.phaseLength,
    focusLength: focus.focusLength,
    completedFocusCount: focus.completedFocusCount,
    isRunning: focus.isRunning,
    isActive: focus.isActive,
    remaining: focus.remaining(now),
    elapsed: focus.elapsed(now),
    shownTime: focus.shownTime(now),
  };
}
