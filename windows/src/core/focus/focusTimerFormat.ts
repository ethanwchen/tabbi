import { tr } from "../localization/tr";
import type { Seconds } from "../time";
import { roundHalfAwayFromZero, swiftInt } from "../studyMethods/swiftMath";
import { nextFocusPhase, type FocusPhase, type FocusPhaseCompletion, type FocusTimer, type FocusTimerConfig } from "./focusTimer";

/** Port of FocusTimerFormat: short strings for the focus timer in Today and the Focus tab. */

/**
 * Countdown as "25:00", "4:59" or "0:00". Seconds round up, so the display
 * shows the full length the moment the timer starts and reads "0:00" only
 * once the phase is really over.
 */
export function focusClock(remaining: Seconds): string {
  const total = Math.ceil(Math.max(remaining, 0));
  const minutes = Math.trunc(total / 60);
  const seconds = total % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

/** Phase label, "Focus" or "Break". */
export function focusPhaseName(phase: FocusPhase): string {
  return phase === "focus" ? tr("Focus") : tr("Break");
}

/** One line on where the timer stands, shown when no task is linked. */
export function focusStatus(timer: FocusTimer): string {
  if (timer.phase === "rest") return tr("Step away for a bit");
  switch (timer.runState.kind) {
    case "idle":
      return tr("%lld min, no distractions", swiftInt(timer.config.focusDuration / 60));
    case "paused":
      return tr("Paused");
    case "running":
      return tr("Heads down");
  }
}

/** Notification copy for a finished phase. */
export function focusCompletionMessage(
  completion: FocusPhaseCompletion,
  config: FocusTimerConfig,
): { title: string; body: string } {
  const minutes = swiftInt(roundHalfAwayFromZero(config.duration(nextFocusPhase(completion.phase)) / 60));
  if (completion.phase === "focus") {
    return { title: tr("Focus session done"), body: tr("Time for a %lld-minute break.", minutes) };
  }
  return { title: tr("Break's over"), body: tr("Ready for another %lld-minute focus session?", minutes) };
}
