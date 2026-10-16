import type { PetAnimation } from "../pets/petKinds";
import type { Instant } from "../time";
import type { CoachClipTimings, PetCoachGlance } from "./petCoachGlance";
import type { PetCoachStroll } from "./petCoachStroll";

/*
 * Port of PetCoachRedraw: when the coach overlay's picture next changes,
 * so it redraws only then. Walking moves the pet every frame; standing,
 * peeking and talking follow the clips' own frame boundaries, which change
 * only a few times a second. Dates land a hair after each change, so
 * rounding can never show the old frame.
 */

/** How often a walking pet moves: 64 per second at 30 fps is about 2 a step. */
export const COACH_WALK_FRAME_RATE = 30;

const LAG = 0.001;

/**
 * The stroll's next redraw after `date`: every walking frame, each frame
 * change of the `arrival` clip and then the idle loop while talking, and
 * the moments the pet sets off, arrives and turns back. Undefined once the
 * pet is home. `marks` are other moments the bubble changes (a celebration
 * moving on to a Cat wisdom line), redrawn while talking.
 */
export function strollNextRedraw(
  stroll: PetCoachStroll,
  date: Instant,
  clips: CoachClipTimings,
  arrival: PetAnimation,
  marks: readonly Instant[] = [],
  walkFrameRate: number = COACH_WALK_FRAME_RATE,
): Instant | undefined {
  const step = 1 / Math.max(walkFrameRate, 1);
  /* Still tucked under the island before the start: nothing moves yet. */
  if (date < stroll.startedAt) return stroll.startedAt + LAG;
  switch (stroll.phase(date)) {
    case "walkingOut":
      return Math.min(date + step, stroll.arrivesAt + LAG);
    case "talking": {
      const elapsed = date - stroll.arrivesAt;
      const arrivalClip = clips.clip(arrival);
      let boundary: number | undefined;
      if (elapsed < arrivalClip.duration) {
        boundary = arrivalClip.nextFrameBoundary(elapsed) ?? arrivalClip.duration;
      } else {
        const idle = clips.clip("idle").nextFrameBoundary(elapsed - arrivalClip.duration);
        boundary = idle === undefined ? undefined : idle + arrivalClip.duration;
      }
      const later = marks.filter((mark) => mark > date);
      const turn = Math.min(stroll.turnsBackAt + LAG, ...later.map((mark) => mark + LAG));
      return boundary === undefined ? turn : Math.min(stroll.arrivesAt + boundary + LAG, turn);
    }
    case "walkingBack":
      return Math.min(date + step, stroll.endsAt + LAG);
    case "finished":
      return undefined;
  }
}

/**
 * The glance's next redraw after `date`: each frame change of the peek
 * clips, the moment the pet starts pulling back up, and its exit.
 * Undefined once it's back inside. The hold shows `peekIn`'s last frame,
 * so nothing redraws while the pet just looks.
 */
export function glanceNextRedraw(glance: PetCoachGlance, date: Instant, clips: CoachClipTimings): Instant | undefined {
  const elapsed = date - glance.startedAt;
  if (elapsed < 0) return glance.startedAt + LAG;
  if (elapsed >= glance.duration) return undefined;
  const leavesAt = glance.enter + glance.hold;
  let boundary: number;
  if (elapsed < leavesAt) {
    boundary = Math.min(clips.clip("peekIn").nextFrameBoundary(elapsed) ?? leavesAt, leavesAt);
  } else {
    const next = clips.clip("peekOut").nextFrameBoundary(elapsed - leavesAt);
    boundary = Math.min(next === undefined ? glance.duration : next + leavesAt, glance.duration);
  }
  return glance.startedAt + boundary + LAG;
}
