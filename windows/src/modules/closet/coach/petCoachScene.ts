/*
 * Port of PetCoachLine and PetCoachScene: what the pet comes out to say (a
 * coach nudge, a celebration of points just earned with the bar toward the
 * next unlock, now and then a Cat wisdom line after it, or nothing at all,
 * a silent glance from the island's edge) and the one stroll of one pet
 * with one line the overlay plays. Values of timestamps, so `date` fully
 * decides the picture and a snapshot can freeze any moment.
 */

import { PetCoach, type PetCoachNudge } from "../../../core/coach/petCoach";
import { PetCoachGlance } from "../../../core/coach/petCoachGlance";
import { nudgeReplies, type PetCoachReply } from "../../../core/coach/petCoachReply";
import { PetCoachStroll } from "../../../core/coach/petCoachStroll";
import type { PetStudyAward } from "../../../core/closet/petStudyCredit";
import type { CatWisdomLine } from "../../../core/motivation/catWisdom";
import type { SurpriseGiftDelivery } from "../../../core/motivation/surpriseGift";
import type { UnlockProgress } from "../../../core/motivation/unlockProgress";
import { PetClipSet } from "../../../core/pets/petAnimator";
import type { PetAnimation } from "../../../core/pets/petKinds";
import type { PetProfile } from "../../../core/pets/petProfile";
import type { Instant, Seconds } from "../../../core/time";

export type PetCoachLine =
  | { readonly kind: "nudge"; readonly nudge: PetCoachNudge }
  | {
      readonly kind: "celebration";
      readonly award: PetStudyAward;
      readonly progress: UnlockProgress | undefined;
      readonly wisdom?: CatWisdomLine;
      readonly gift?: SurpriseGiftDelivery;
    }
  | { readonly kind: "glance"; readonly glance: PetCoachGlance };

/** The Cat wisdom line a celebration moves on to, if any. */
export function lineWisdom(line: PetCoachLine): CatWisdomLine | undefined {
  return line.kind === "celebration" ? line.wisdom : undefined;
}

/** How long the bubble talks: a celebration, plus its wisdom line. */
export function lineTalkDuration(line: PetCoachLine): Seconds {
  return PetCoach.celebrationDuration + (lineWisdom(line) === undefined ? 0 : PetCoach.wisdomDuration);
}

/** Whether the bubble shows the wisdom line rather than the points after `elapsed` seconds of talking (holds not counted). */
export function lineShowsWisdom(line: PetCoachLine, elapsed: Seconds): boolean {
  return lineWisdom(line) !== undefined && elapsed >= PetCoach.celebrationDuration;
}

/** The bubble's buttons. A celebration has none: a click anywhere on the bubble sends the pet home. */
export function lineReplies(line: PetCoachLine): PetCoachReply[] {
  return line.kind === "nudge" ? nudgeReplies(line.nudge.kind) : [];
}

/** The clip the pet plays on arrival before it idles. */
export function lineArrival(line: PetCoachLine): PetAnimation {
  switch (line.kind) {
    case "nudge":
      return "alert";
    case "celebration":
      return "celebrate";
    case "glance":
      return "peekIn";
  }
}

export function lineHasBubble(line: PetCoachLine): boolean {
  return line.kind !== "glance";
}

/** What the coach overlay plays: one stroll of one pet with one line. Port of PetCoachScene. */
export class PetCoachScene {
  readonly clips: PetClipSet;

  constructor(
    readonly profile: PetProfile,
    readonly stroll: PetCoachStroll,
    readonly line: PetCoachLine,
    clips?: PetClipSet,
  ) {
    this.clips = clips ?? new PetClipSet({ breed: profile.breed, outfit: profile.outfit, accessories: profile.accessories, bond: profile.bondLook });
  }

  /** A silent glance timed by the pet's own peek clips. */
  static glance(profile: PetProfile, startedAt: Instant): PetCoachScene {
    const clips = new PetClipSet({ breed: profile.breed, outfit: profile.outfit, accessories: profile.accessories, bond: profile.bondLook });
    const glance = PetCoachGlance.timedBy(startedAt, clips);
    return new PetCoachScene(profile, glance.stroll, { kind: "glance", glance }, clips);
  }
}
