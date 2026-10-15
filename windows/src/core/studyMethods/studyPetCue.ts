import type { StudySession } from "./studySession";

/*
 * The pet animator events Study sends. This is the slice of the Mac's
 * PetAnimator.Event that the Study tab uses, kept narrow until the pet port
 * owns the full enum.
 */
export type StudyPetEvent = "celebrate" | "sleep" | "wake";

/**
 * Port of StudyPetCue: how the pet in the Study panel's corner follows the
 * timer. Awake while the clock runs, dozing while it is paused or has not
 * started, and a happy hop whenever a focus block is finished.
 */

/** Whether the pet should be asleep for `session`. */
export function studyPetIsDozing(session: StudySession): boolean {
  return !session.isRunning;
}

/**
 * The animator events that take the pet from `old` to `next`, in order. A
 * finished focus block celebrates (then dozes off if the timer stopped);
 * otherwise the pet only reacts when the clock starts or stops. Resetting or
 * switching methods never celebrates.
 */
export function studyPetEvents(old: StudySession, next: StudySession): StudyPetEvent[] {
  const finishedBlock = next.method.kind === old.method.kind && next.completedFocusCount > old.completedFocusCount;
  const dozing = studyPetIsDozing(next);
  if (finishedBlock) return dozing ? ["celebrate", "sleep"] : ["celebrate"];
  if (dozing === studyPetIsDozing(old)) return [];
  return [dozing ? "sleep" : "wake"];
}
