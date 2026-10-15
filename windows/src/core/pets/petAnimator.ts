import { NO_BOND_LOOK, type PetBondLook } from "./petBond";
import { PetClip, PetFrame, animationLoops, composeClip } from "./petClip";
import type { PetAccessory, PetOutfit } from "./petCostume";
import { PET_ANIMATIONS, type PetAnimation, type PetBreed } from "./petKinds";

/*
 * Port of PetAnimator.swift: every clip for one dressed pet (PetClipSet), and
 * the pure state machine that decides which animation plays and since when.
 */

/** What a dressed pet looks like, for a clip set. */
export interface PetLook {
  readonly breed: PetBreed;
  readonly outfit?: PetOutfit;
  readonly accessories?: readonly PetAccessory[];
  readonly bond?: PetBondLook;
}

/** What the closed notch's pet does. Port of PetMood. */
export type PetMood = "studying" | "onBreak" | "awake" | "asleep";

/** Where the pet is relative to the notch (here, the island). */
export type PetPlace = "beside" | "hanging" | "hidden";

/** What the user is doing, which picks the resting animation of a pet awake beside the notch. */
export type PetActivity = "free" | "studying" | "onBreak";

export function restingAnimation(activity: PetActivity): PetAnimation {
  return activity === "free" ? "idle" : activity === "studying" ? "typing" : "coffee";
}

/** The activity the closed notch's pet follows for its mood. */
export function activityForMood(mood: PetMood): PetActivity {
  return mood === "studying" ? "studying" : mood === "onBreak" ? "onBreak" : "free";
}

export type PetAnimatorEvent =
  | { readonly kind: "nudge" }
  | { readonly kind: "celebrate" }
  | { readonly kind: "sleep" }
  | { readonly kind: "wake" }
  | { readonly kind: "peekIn" }
  | { readonly kind: "peekOut" }
  | { readonly kind: "appear" }
  | { readonly kind: "disappear" }
  | { readonly kind: "activity"; readonly activity: PetActivity };

/** The clip on screen and when it started. */
export interface PetPlayback {
  readonly animation: PetAnimation;
  readonly startedAt: number;
}

export function playbackElapsed(playback: PetPlayback, time: number): number {
  return time - playback.startedAt;
}

/** Every clip for one dressed pet, built once so a player never composes frames while animating. Port of PetClipSet. */
export class PetClipSet {
  readonly clips: ReadonlyMap<PetAnimation, PetClip>;

  /** `ceiling` keeps every frame below that row, for a view that cuts off the frame's top. */
  constructor(look: PetLook, ceiling?: number) {
    const clips = new Map<PetAnimation, PetClip>();
    for (const animation of PET_ANIMATIONS) {
      clips.set(
        animation,
        composeClip(animation, look.breed, {
          outfit: look.outfit ?? "none",
          accessories: look.accessories ?? [],
          bond: look.bond ?? NO_BOND_LOOK,
          ...(ceiling === undefined ? {} : { ceiling }),
        }),
      );
    }
    this.clips = clips;
  }

  clip(animation: PetAnimation): PetClip {
    const clip = this.clips.get(animation);
    if (!clip) throw new Error(`No ${animation} clip`);
    return clip;
  }

  /** One-pass length of every clip, which is all the animator needs. */
  get durations(): ReadonlyMap<PetAnimation, number> {
    return new Map([...this.clips].map(([animation, clip]) => [animation, clip.duration]));
  }

  /** The frame to draw for `playback` at `time`, or undefined while the pet is tucked away. */
  frame(playback: PetPlayback | undefined, time: number): PetFrame | undefined {
    if (!playback) return undefined;
    return this.clip(playback.animation).frame(playbackElapsed(playback, time)).atItemTime(time);
  }

  /** The next moment after `time` the drawn frame can change; `animator` must be advanced to `time`. */
  nextChange(animator: PetAnimator, time: number): number | undefined {
    const playback = animator.playback;
    if (!playback) return undefined;
    const clip = this.clip(playback.animation);
    const elapsed = playbackElapsed(playback, time);
    const boundary = clip.nextFrameBoundary(elapsed);
    const item = clip.frame(elapsed).nextItemChange(time);
    const blink = animator.nextBlinkAt !== undefined && animator.nextBlinkAt > time ? animator.nextBlinkAt : undefined;
    const candidates = [boundary === undefined ? undefined : playback.startedAt + boundary, item, blink].filter(
      (value): value is number => value !== undefined,
    );
    return candidates.length === 0 ? undefined : Math.min(...candidates);
  }

  /** The still picture under Reduce Motion: blinks and swishes draw as the idle pose they interrupt. */
  stillFrame(animator: PetAnimator): PetFrame | undefined {
    const playback = animator.playback;
    if (!playback) return undefined;
    return this.clip(IDLE_BEATS.has(playback.animation) ? "idle" : playback.animation).stillFrame;
  }

  /** When the still picture can next change after `time`: the end of a one-shot clip. */
  nextStillChange(animator: PetAnimator, time: number): number | undefined {
    const playback = animator.playback;
    if (!playback || animationLoops(playback.animation) || IDLE_BEATS.has(playback.animation)) return undefined;
    const end = playback.startedAt + this.clip(playback.animation).duration;
    return end > time ? end : undefined;
  }
}

/** What an idling pet plays between rests: a blink, or for a happy pet now and then a tail swish. */
export const IDLE_BEATS: ReadonlySet<PetAnimation> = new Set<PetAnimation>(["blink", "tailSwish"]);

const MASK = (1n << 64n) - 1n;

/** A tiny seeded generator (SplitMix64), so blink timing is reproducible. */
export class SplitMix64 {
  private state: bigint;

  constructor(seed: bigint | number = 0) {
    this.state = BigInt(seed) & MASK;
  }

  copy(): SplitMix64 {
    const copy = new SplitMix64();
    copy.state = this.state;
    return copy;
  }

  next(): bigint {
    this.state = (this.state + 0x9e3779b97f4a7c15n) & MASK;
    let z = this.state;
    z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & MASK;
    z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & MASK;
    return z ^ (z >> 31n);
  }

  /** A double uniformly drawn from `lower...upper`. */
  nextIn(lower: number, upper: number): number {
    const unit = Number(this.next() >> 11n) / 2 ** 53;
    return lower + unit * (upper - lower);
  }
}

/**
 * Decides which animation the pet plays and since when. A pure value
 * driven by timestamps (any monotonic clock in seconds) and a seeded
 * generator, so it is fully deterministic. Call `advance` before reading
 * `playback` for a new time. Port of PetAnimator.
 */
export class PetAnimator {
  /** A happy pet swishes its tail in place of every this many blinks. */
  static readonly happyBeatEvery = 3;
  /** Seconds between blinks are drawn uniformly from this range. */
  static readonly blinkInterval = { lower: 2.5, upper: 6 } as const;
  /** Focus this long in one go earns a yawn when it ends. */
  static readonly longSession = 45 * 60;

  private placeValue: PetPlace;
  private asleep: boolean;
  private activityValue: PetActivity;
  readonly isHappy: boolean;
  private since: number;
  private playbackValue: PetPlayback | undefined;
  private blinkAt: number | undefined;
  private readonly durations: ReadonlyMap<PetAnimation, number>;
  /** An event that arrived during a peek transition, applied once it ends. Latest wins. */
  private pending: PetAnimatorEvent | undefined;
  /** A long focus stretch ended while another one-shot clip played: yawn next. */
  private yawnsNext = false;
  private beats = 0;
  private random: SplitMix64;

  constructor(
    durations: ReadonlyMap<PetAnimation, number>,
    options: {
      place?: PetPlace;
      asleep?: boolean;
      activity?: PetActivity;
      activitySince?: number;
      happy?: boolean;
      at?: number;
      seed?: bigint | number;
    } = {},
  ) {
    const time = options.at ?? 0;
    this.durations = durations;
    this.isHappy = options.happy ?? false;
    this.placeValue = options.place ?? "beside";
    this.asleep = (options.asleep ?? false) && this.placeValue === "beside";
    this.activityValue = options.activity ?? "free";
    this.since = options.activitySince ?? time;
    this.random = new SplitMix64(options.seed ?? 0);
    this.rest(time);
  }

  get place(): PetPlace {
    return this.placeValue;
  }

  get isAsleep(): boolean {
    return this.asleep;
  }

  get activity(): PetActivity {
    return this.activityValue;
  }

  /** When the current activity started. */
  get activitySince(): number {
    return this.since;
  }

  /** What to draw; undefined while the pet is hidden. */
  get playback(): PetPlayback | undefined {
    return this.playbackValue;
  }

  /** When the next idle blink starts, if the pet is idling. */
  get nextBlinkAt(): number | undefined {
    return this.blinkAt;
  }

  /** Whether a peek transition is playing and can't be interrupted. */
  isTransitioning(time: number): boolean {
    const playback = this.playbackValue;
    if (!playback || (playback.animation !== "peekIn" && playback.animation !== "peekOut")) return false;
    return playbackElapsed(playback, time) < this.duration(playback.animation);
  }

  /**
   * Handles `event` at `time`. Returns false when the event doesn't apply
   * where the pet is. Events during a peek transition are deferred and count
   * as accepted.
   */
  send(event: PetAnimatorEvent, time: number): boolean {
    this.advance(time);
    if (this.isTransitioning(time)) {
      this.pending = event;
      return true;
    }
    return this.apply(event, time);
  }

  /** Finishes every one-shot clip and starts every blink due by `time`. */
  advance(time: number): void {
    for (;;) {
      const current = this.playbackValue;
      if (!current) return;
      const animation = current.animation;
      const end = current.startedAt + this.duration(animation);
      if (animation === "idle" && this.blinkAt !== undefined && this.blinkAt <= time) {
        this.beats += 1;
        const swishes = this.isHappy && this.beats % PetAnimator.happyBeatEvery === 0;
        this.playbackValue = { animation: swishes ? "tailSwish" : "blink", startedAt: this.blinkAt };
        this.blinkAt = undefined;
        continue;
      }
      if (animationLoops(animation) || !(end <= time)) return;
      switch (animation) {
        case "peekIn": {
          /* Hanging is peekIn's held last frame; only a deferred event moves on. */
          const event = this.pending;
          if (!event) return;
          this.pending = undefined;
          this.apply(event, end);
          break;
        }
        case "peekOut": {
          this.playbackValue = undefined;
          const event = this.pending;
          if (event) {
            this.pending = undefined;
            this.apply(event, end);
          }
          break;
        }
        default:
          if (this.yawnsNext && this.placeValue === "beside" && animation !== "yawn") {
            this.yawnsNext = false;
            this.play("yawn", end);
          } else {
            this.rest(end);
          }
      }
    }
  }

  private apply(event: PetAnimatorEvent, time: number): boolean {
    switch (event.kind) {
      case "appear":
        this.placeValue = "beside";
        this.asleep = false;
        this.rest(time);
        return true;
      case "disappear":
        this.placeValue = "hidden";
        this.asleep = false;
        this.yawnsNext = false;
        this.rest(time);
        return true;
      case "sleep":
        if (this.placeValue !== "beside" || this.asleep) return false;
        this.asleep = true;
        /* A running alert or celebration plays out before the pet dozes. */
        if (!this.isPlayingOneShot(time)) this.rest(time);
        return true;
      case "wake":
        if (this.placeValue !== "beside" || !this.asleep) return false;
        this.asleep = false;
        /* Waking on its own earns a slow stretch first. */
        if (!this.isPlayingOneShot(time)) this.play("stretch", time);
        return true;
      case "activity": {
        const next = event.activity;
        if (next === this.activityValue) return false;
        const tired = this.activityValue === "studying" && time - this.since >= PetAnimator.longSession;
        this.activityValue = next;
        this.since = time;
        if (this.placeValue !== "beside" || this.asleep) return true;
        if (this.isPlayingOneShot(time)) {
          /* Let a celebration play out, then yawn. */
          this.yawnsNext = this.yawnsNext || tired;
        } else if (tired) {
          this.play("yawn", time);
        } else {
          this.rest(time);
        }
        return true;
      }
      case "nudge":
        switch (this.placeValue) {
          case "beside":
            /* Never cut a celebration short to nag. */
            if (this.playbackValue?.animation === "celebrate" && this.isPlayingOneShot(time)) return false;
            this.asleep = false;
            this.play("alert", time);
            return true;
          case "hidden":
            return this.apply({ kind: "peekIn" }, time);
          case "hanging":
            return false;
        }
        return false;
      case "celebrate":
        if (this.placeValue !== "beside") return false;
        this.asleep = false;
        this.play("celebrate", time);
        return true;
      case "peekIn":
        if (this.placeValue !== "hidden") return false;
        this.placeValue = "hanging";
        this.play("peekIn", time);
        return true;
      case "peekOut":
        if (this.placeValue !== "hanging") return false;
        this.placeValue = "hidden";
        this.play("peekOut", time);
        return true;
    }
  }

  /** Alert, celebrate, the wake-up stretch or a yawn still running (blinks yield). */
  private isPlayingOneShot(time: number): boolean {
    const playback = this.playbackValue;
    if (!playback || !["alert", "celebrate", "stretch", "yawn"].includes(playback.animation)) return false;
    return playbackElapsed(playback, time) < this.duration(playback.animation);
  }

  private play(animation: PetAnimation, time: number): void {
    this.playbackValue = { animation, startedAt: time };
    this.blinkAt = undefined;
  }

  /** Starts the resting animation for the current place at `time`. */
  private rest(time: number): void {
    this.blinkAt = undefined;
    switch (this.placeValue) {
      case "hidden":
        this.playbackValue = undefined;
        return;
      case "hanging":
        /* Started one clip-length ago, so the held last frame shows at once. */
        this.playbackValue = { animation: "peekIn", startedAt: time - this.duration("peekIn") };
        return;
      case "beside":
        if (this.asleep) {
          this.playbackValue = { animation: "sleep", startedAt: time };
        } else if (this.activityValue !== "free") {
          this.playbackValue = { animation: restingAnimation(this.activityValue), startedAt: time };
        } else {
          this.playbackValue = { animation: "idle", startedAt: time };
          this.blinkAt = time + this.random.nextIn(PetAnimator.blinkInterval.lower, PetAnimator.blinkInterval.upper);
        }
    }
  }

  private duration(animation: PetAnimation): number {
    return this.durations.get(animation) ?? 0;
  }
}

const CLIP_CACHE_SIZE = 6;
const clipCache: { key: string; clips: PetClipSet }[] = [];

/**
 * The clips for `look`, composed once and kept for the next view that shows
 * the same look: composing every clip takes a noticeable moment. A handful
 * of looks are kept, newest last.
 */
export function cachedClipSet(look: PetLook, ceiling?: number): PetClipSet {
  const bond = look.bond ?? NO_BOND_LOOK;
  const key = JSON.stringify([look.breed, look.outfit ?? "none", look.accessories ?? [], bond.collar, bond.happyIdle, bond.sparkle, ceiling ?? null]);
  const hit = clipCache.find((entry) => entry.key === key);
  if (hit) return hit.clips;
  const clips = new PetClipSet(look, ceiling);
  clipCache.push({ key, clips });
  if (clipCache.length > CLIP_CACHE_SIZE) clipCache.splice(0, clipCache.length - CLIP_CACHE_SIZE);
  return clips;
}
