import type { FocusActivity } from "../focus/focusSession";
import type { ModuleID } from "../modules/moduleId";
import { ProvidedFocus, type ProvidedFocusClock } from "../providers/providedFocus";
import type { Instant } from "../time";
import { isBreakPhase } from "./studyMethod";
import type { StudySession } from "./studySession";
import { studyPhaseName } from "./studyTimerFormat";

/**
 * Port of StudySession.sharedFocus(by:isDeep:at:): the session as the shared
 * focus clock, so the ticker and anything that follows focus (the pet coach)
 * see a study block like any other timer.
 *
 * Only a session under way is shared: an idle one would only hide another
 * module's timer. Phases with no length count up. Focus and review read as
 * focus, either break as rest. The value never depends on `now` beyond the
 * session's own state, so it is not republished every second.
 */
export function sharedStudyFocus(session: StudySession, source: ModuleID, isDeep: boolean, now: Instant): ProvidedFocus | undefined {
  if (session.runState === "idle") return undefined;
  const isFocus = !isBreakPhase(session.phase);
  const endsAt = session.endsAt;
  const runningSince = session.runningSince;
  let clock: ProvidedFocusClock;
  if (endsAt !== undefined) {
    clock = { kind: "countdown", endsAt };
  } else if (runningSince !== undefined) {
    clock = { kind: "countUp", since: runningSince };
  } else {
    clock = { kind: "paused", shown: session.remaining(now) ?? session.elapsed(now) };
  }
  const focusLength = isFocus ? session.phaseDuration : (session.method.duration("focus") ?? session.lastFocusWorked);
  return new ProvidedFocus({
    source,
    phase: isFocus ? "focus" : "rest",
    label: studyPhaseName(session.phase, session.method),
    clock,
    phaseLength: session.phaseDuration,
    ...(focusLength === undefined ? {} : { focusLength }),
    completedFocusCount: session.completedFocusCount,
    isDeep,
    /* Every phase that ends early is logged as a StudyPhaseRecord. */
    logsEarlyEnds: true,
  });
}

/**
 * Port of FocusActivity(_:deepFocus:): what a study session asks of focus
 * mode. With deep focus off the Study tab never touches it; with it on, a
 * running focus or review phase turns on the sound and Do Not Disturb, a
 * break or pause interrupts them, and an idle session ends them.
 */
export function studyFocusActivity(session: StudySession, deepFocus: boolean): FocusActivity {
  if (!deepFocus) return "idle";
  switch (session.runState) {
    case "running":
      return isBreakPhase(session.phase) ? "interrupted" : "focusing";
    case "paused":
      return "interrupted";
    case "idle":
      return "idle";
  }
}
