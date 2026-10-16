import type { PetAnimation } from "../pets/petKinds";
import type { Instant, Seconds } from "../time";
import { PetCoachStroll } from "./petCoachStroll";

/*
 * Port of PetCoachGlance: the coach's silent first step (the `lookOver`
 * decision). The pet lowers its head out of the island's edge, looks at
 * the user for a moment, and pulls back up. No bubble, no sound, nothing
 * to click. A value of timestamps like PetCoachStroll.
 */

/** The clip timings the coach overlay needs; a `PetClipSet` provides them. */
export interface CoachClipTimings {
  clip(animation: PetAnimation): {
    readonly duration: Seconds;
    nextFrameBoundary(elapsed: Seconds): Seconds | undefined;
  };
}

export interface PetCoachGlancePose {
  readonly animation: PetAnimation;
  readonly elapsed: Seconds;
}

export class PetCoachGlance {
  /** A look long enough to notice and short enough to never be in the way. */
  static readonly standardHold: Seconds = 2.5;

  readonly startedAt: Instant;
  /** Length of the `peekIn` clip (lowering into view). */
  readonly enter: Seconds;
  /** How long the pet hangs there looking. */
  readonly hold: Seconds;
  /** Length of the `peekOut` clip (pulling back up). */
  readonly leave: Seconds;

  constructor(startedAt: Instant, enter: Seconds, leave: Seconds, hold: Seconds = PetCoachGlance.standardHold) {
    this.startedAt = startedAt;
    this.enter = Math.max(enter, 0);
    this.hold = Math.max(hold, 0);
    this.leave = Math.max(leave, 0);
  }

  /** Timed by the pet's own peek clips, so the head lowers and lifts at the sprite's pace. */
  static timedBy(startedAt: Instant, clips: CoachClipTimings, hold: Seconds = PetCoachGlance.standardHold): PetCoachGlance {
    return new PetCoachGlance(startedAt, clips.clip("peekIn").duration, clips.clip("peekOut").duration, hold);
  }

  get duration(): Seconds {
    return this.enter + this.hold + this.leave;
  }

  /** Back inside the island; the overlay can close. */
  get endsAt(): Instant {
    return this.startedAt + this.duration;
  }

  /**
   * The clip to show at `date` and the time into it, or undefined while the
   * pet is tucked away. The hold keeps `peekIn` past its end, which holds
   * its last frame.
   */
  pose(date: Instant): PetCoachGlancePose | undefined {
    const elapsed = date - this.startedAt;
    if (elapsed < 0 || elapsed >= this.duration) return undefined;
    if (elapsed < this.enter + this.hold) return { animation: "peekIn", elapsed };
    return { animation: "peekOut", elapsed: elapsed - this.enter - this.hold };
  }

  /** A stroll that never leaves the edge and lasts as long as the glance, so the overlay sizes and closes itself the same way for both. */
  get stroll(): PetCoachStroll {
    return new PetCoachStroll(this.startedAt, { distance: 0, talkDuration: this.duration });
  }
}
