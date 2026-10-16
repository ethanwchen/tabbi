/*
 * Port of PetPlayer: plays one pet. It owns the prebuilt clips for the
 * pet's look and the core's `PetAnimator` deciding what is on screen; views
 * draw it with `PetView`, and study features drive it with `send` (nudge
 * when the user drifts, celebrate a finished session). The clock is seconds
 * on `performance.now()`'s timeline by default, so events and redraws share
 * one timeline; tests pass their own.
 */

import { PetAnimator, cachedClipSet, type PetActivity, type PetAnimatorEvent, type PetClipSet, type PetPlace } from "../../core/pets/petAnimator";
import type { PetFrame } from "../../core/pets/petClip";
import type { PetPalette } from "../../core/pets/petPalette";
import type { PetProfile } from "../../core/pets/petProfile";

export interface PetPlayerOptions {
  readonly place?: PetPlace;
  readonly asleep?: boolean;
  readonly activity?: PetActivity;
  readonly activitySince?: number;
  readonly at?: number;
  readonly seed?: number | bigint;
  /** The row nothing may be drawn above, for a view that cuts off the frame's top. */
  readonly ceiling?: number;
}

/** Seconds on the animation clock. */
export function petClockNow(): number {
  return performance.now() / 1000;
}

type Listener = () => void;

export class PetPlayer {
  private profileValue: PetProfile;
  private clipsValue: PetClipSet;
  private animator: PetAnimator;
  readonly ceiling: number | undefined;
  /** Counts the events and looks sent so far, so a view can tell the redraw schedule changed. */
  private revisionValue = 0;
  private readonly listeners = new Set<Listener>();

  constructor(profile: PetProfile, options: PetPlayerOptions = {}) {
    this.profileValue = profile;
    this.ceiling = options.ceiling;
    this.clipsValue = PetPlayer.clips(profile, options.ceiling);
    const at = options.at ?? petClockNow();
    this.animator = new PetAnimator(this.clipsValue.durations, {
      place: options.place ?? "beside",
      asleep: options.asleep ?? false,
      activity: options.activity ?? "free",
      ...(options.activitySince === undefined ? {} : { activitySince: options.activitySince }),
      happy: profile.bondLook.happyIdle,
      at,
      seed: options.seed ?? PetPlayer.randomSeed(),
    });
  }

  private static clips(profile: PetProfile, ceiling: number | undefined): PetClipSet {
    return cachedClipSet(
      { breed: profile.breed, outfit: profile.outfit, accessories: profile.accessories, bond: profile.bondLook },
      ceiling,
    );
  }

  private static randomSeed(): number {
    return Math.floor(Math.random() * 0x1_0000_0000);
  }

  get profile(): PetProfile {
    return this.profileValue;
  }

  get clips(): PetClipSet {
    return this.clipsValue;
  }

  get place(): PetPlace {
    return this.animator.place;
  }

  get palette(): PetPalette {
    return this.profileValue.palette;
  }

  get revision(): number {
    return this.revisionValue;
  }

  /** Called whenever the redraw schedule changes (an event, a new look). */
  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private changed(): void {
    this.revisionValue += 1;
    for (const listener of this.listeners) listener();
  }

  /** Sends `event` to the animator; false when it doesn't apply where the pet is. */
  send(event: PetAnimatorEvent, at: number = petClockNow()): boolean {
    const accepted = this.animator.send(event, at);
    this.changed();
    return accepted;
  }

  /** Swaps in a new look (breed, colors, outfit) without moving the pet. */
  update(profile: PetProfile, at: number = petClockNow()): void {
    if (profile.equals(this.profileValue) && profile.bondLook === this.profileValue.bondLook) return;
    this.animator.advance(at);
    this.profileValue = profile;
    this.clipsValue = PetPlayer.clips(profile, this.ceiling);
    /* Durations can differ between looks, so restart in the same place. */
    this.animator = new PetAnimator(this.clipsValue.durations, {
      place: this.animator.place,
      asleep: this.animator.isAsleep,
      activity: this.animator.activity,
      activitySince: this.animator.activitySince,
      happy: profile.bondLook.happyIdle,
      at,
      seed: PetPlayer.randomSeed(),
    });
    this.changed();
  }

  /** The frame to draw at `at`, or undefined while the pet is inside the notch. */
  frame(at: number = petClockNow()): PetFrame | undefined {
    this.animator.advance(at);
    return this.clipsValue.frame(this.animator.playback, at);
  }

  /** The still picture to draw at `at` under Reduce Motion. */
  stillFrame(at: number = petClockNow()): PetFrame | undefined {
    this.animator.advance(at);
    return this.clipsValue.stillFrame(this.animator);
  }

  /**
   * When the drawn picture can next change after `at`, or undefined while it
   * holds (hidden, hanging, or any resting pet when `still`). The next event
   * starts a fresh schedule.
   */
  nextChange(at: number = petClockNow(), still = false): number | undefined {
    this.animator.advance(at);
    return still ? this.clipsValue.nextStillChange(this.animator, at) : this.clipsValue.nextChange(this.animator, at);
  }
}
