/*
 * Port of PetPoint, PetPose and PetComposer.Stance: how the pet holds itself
 * in one frame, as small offsets from the plain sitting frame so every
 * costume follows along for free.
 */

/** A pixel position inside a frame (top-left origin, in sprite pixels). Port of PetPoint. */
export interface PetPoint {
  x: number;
  y: number;
}

export const PET_EYES = ["open", "closed", "sleepy", "happy", "squeezed"] as const;
export type PetEyes = (typeof PET_EYES)[number];

export const PET_MOUTHS = ["closed", "open", "wide"] as const;
export type PetMouth = (typeof PET_MOUTHS)[number];

/** Something held in front of the sitting pet. */
export type PetProp =
  | { readonly kind: "laptop"; readonly tap: number }
  | { readonly kind: "mug"; readonly raise: number }
  | { readonly kind: "toy"; readonly roll: number; readonly bounce: number; readonly bat: boolean };

/** A front paw lifted off the floor. */
export type PetGesture =
  | { readonly kind: "wave"; readonly swing: number }
  | { readonly kind: "groom"; readonly reach: number };

export interface PetPose {
  readonly eyes: PetEyes;
  readonly mouth: PetMouth;
  readonly prop?: PetProp;
  readonly gesture?: PetGesture;
  /** Pixels the tip of a sitting pet's tail leans out (0 at rest). */
  readonly tailSwing: number;
  /** Pixels the head sinks into the shoulders; negative tips it back. */
  readonly headDrop: number;
  /** Pixels the whole pet rises off the baseline (hops). */
  readonly lift: number;
}

export function petPose(pose: Partial<PetPose> = {}): PetPose {
  return { eyes: "open", mouth: "closed", tailSwing: 0, headDrop: 0, lift: 0, ...pose };
}

/** How the body under the head is drawn. Port of PetComposer.Stance. */
export type PetStance =
  | { readonly kind: "sitting" }
  | { readonly kind: "hanging" }
  | { readonly kind: "walking"; readonly step: number }
  | { readonly kind: "stretching"; readonly depth: number; readonly wag: number }
  | { readonly kind: "curled"; readonly breath: number };

export const SITTING: PetStance = { kind: "sitting" };

/** A stable text key for a pose and stance, for caching composed frames. */
export function poseKey(pose: PetPose, stance: PetStance): string {
  return JSON.stringify([pose.eyes, pose.mouth, pose.prop ?? null, pose.gesture ?? null, pose.tailSwing, pose.headDrop, pose.lift, stance]);
}
