import { NO_BOND_LOOK, type PetBondLook } from "./petBond";
import type { PetCanvas } from "./petCanvas";
import { EffectArt, PropArt } from "./petArtPieces";
import { petArt } from "./petArt";
import { FRAME_SIZE, compose, itemLoopLength, type Composed } from "./petComposer";
import type { PetAccessory, PetOutfit } from "./petCostume";
import type { PetAnimation, PetBreed } from "./petKinds";
import { poseKey, type PetPoint } from "./petPose";
import { stillIndex, type PetTimeline, type TimelineCoordinate, type TimelineFrame } from "./petTimeline";

/*
 * Port of PetFrame, PetClip and PetComposer.clip: an animation built for a
 * dressed breed from its timeline in `animations.json`.
 */

/** How an animation plays, from `animations.json`. */
export function animationTimeline(animation: PetAnimation): PetTimeline {
  return petArt("animations").timeline(animation);
}

/** Whether the clip repeats forever or stops on its last frame. */
export function animationLoops(animation: PetAnimation): boolean {
  return animationTimeline(animation).loops;
}

let itemDuration: number | undefined;

/** Seconds per tick of the item clock, the pet's own frame rate, from `costume.json`. */
export function itemFrameDuration(): number {
  if (itemDuration === undefined) {
    const duration = petArt("costume").itemFrameDuration;
    if (duration === undefined) throw new Error("costume.json sets no itemFrameDuration");
    itemDuration = duration;
  }
  return itemDuration;
}

/** The item clock's tick at `time` (seconds on any shared clock). */
export function itemTick(time: number): number {
  return Math.floor(time / itemFrameDuration());
}

/** One frame of an animation. Port of PetFrame. */
export class PetFrame {
  constructor(
    readonly canvas: PetCanvas,
    /** Seconds this frame stays on screen. */
    readonly duration: number,
    /** Where a speech bubble's tail should point, in frame pixels. */
    readonly bubbleAnchor?: PetPoint,
    /**
     * The frame on each tick of the item clock while an animated costume
     * item plays its loop, starting with `canvas`. Empty when nothing worn
     * moves in this frame.
     */
    readonly itemFrames: readonly PetCanvas[] = [],
  ) {}

  /** This frame as drawn at `time` on the item clock. */
  atItemTime(time: number): PetFrame {
    if (this.itemFrames.length === 0) return this;
    const canvas = this.itemFrames[itemTick(time) % this.itemFrames.length] ?? this.canvas;
    return new PetFrame(canvas, this.duration, this.bubbleAnchor, this.itemFrames);
  }

  /** When the item loop next changes the picture after `time`, skipping ticks that look the same. */
  nextItemChange(time: number): number | undefined {
    const count = this.itemFrames.length;
    if (count === 0) return undefined;
    const tick = itemTick(time);
    const shown = this.itemFrames[tick % count];
    for (let step = 1; step <= count; step++) {
      const next = this.itemFrames[(tick + step) % count];
      if (shown && next && !next.equals(shown)) return (tick + step) * itemFrameDuration();
    }
    return undefined;
  }
}

/**
 * Timestamps arrive as `start + boundary` and are turned back into elapsed
 * time by subtraction, which can land a hair before the boundary.
 */
const ROUNDING = 1e-9;

/** A playable animation: frames plus timing. Port of PetClip. */
export class PetClip {
  readonly animation: PetAnimation;
  readonly frames: readonly PetFrame[];

  constructor(animation: PetAnimation, frames: readonly PetFrame[]) {
    if (frames.length === 0) throw new Error("A clip needs at least one frame");
    this.animation = animation;
    this.frames = frames;
  }

  get loops(): boolean {
    return animationLoops(this.animation);
  }

  /** Length of one pass through every frame, in seconds. */
  get duration(): number {
    return this.frames.reduce((sum, frame) => sum + frame.duration, 0);
  }

  /** The frame to show `elapsed` seconds after the clip started; loops wrap, one-shots hold their last frame. */
  frameIndex(elapsed: number): number {
    if (!(elapsed > 0)) return 0;
    const total = this.duration;
    let time = this.loops && total > 0 ? elapsed % total : elapsed;
    for (let index = 0; index < this.frames.length; index++) {
      const frame = this.frames[index];
      if (!frame) break;
      if (time < frame.duration - ROUNDING) return index;
      time -= frame.duration;
    }
    return this.loops ? 0 : this.frames.length - 1;
  }

  frame(elapsed: number): PetFrame {
    return this.frames[this.frameIndex(elapsed)] ?? (this.frames[0] as PetFrame);
  }

  /** The one frame a still pet shows for this clip under Reduce Motion. */
  get stillFrame(): PetFrame {
    const index = Math.min(stillIndex(animationTimeline(this.animation)), this.frames.length - 1);
    return this.frames[index] ?? (this.frames[0] as PetFrame);
  }

  /** When the shown frame next changes, in seconds since the clip started, strictly after `elapsed`. */
  nextFrameBoundary(elapsedIn: number): number | undefined {
    const elapsed = Math.max(0, elapsedIn);
    const total = this.duration;
    if (!(total > 0)) return undefined;
    let base = 0;
    let offset = elapsed;
    if (this.loops) {
      if (this.frames.length <= 1) return undefined;
      const cycles = Math.floor(elapsed / total);
      base = cycles * total;
      offset = elapsed - base;
    }
    let boundary = 0;
    for (const frame of this.frames) {
      boundary += frame.duration;
      if (offset < boundary - ROUNDING) return base + boundary;
    }
    /* Rounding put `offset` on the loop's end: the next change is one frame in. */
    return this.loops ? base + total + (this.frames[0]?.duration ?? 0) : undefined;
  }
}

function place(coordinate: TimelineCoordinate, origin: number): number {
  return "frame" in coordinate ? coordinate.frame : origin + coordinate.head;
}

/**
 * Builds `animation` for a dressed breed. `ceiling` is for a view that cuts
 * off the frame's top rows (the closed notch): nothing is drawn above that
 * row and nothing is ever drawn cut in half.
 */
export function composeClip(
  animation: PetAnimation,
  breed: PetBreed,
  options: {
    outfit?: PetOutfit;
    accessories?: readonly PetAccessory[];
    bond?: PetBondLook;
    ceiling?: number;
  } = {},
): PetClip {
  const outfit = options.outfit ?? "none";
  const accessories = options.accessories ?? [];
  const bond = options.bond ?? NO_BOND_LOOK;
  const ceiling = options.ceiling;
  const timeline = animationTimeline(animation);
  const loop = itemLoopLength(outfit, accessories, bond);
  /* One composed frame per tick of the item loop, so animated items stay anchored to every pose. Frames that repeat a pose share it. */
  const cache = new Map<string, Composed[]>();
  const phases = timeline.frames.map((step) => {
    const key = poseKey(step.pose, step.stance);
    let composed = cache.get(key);
    if (!composed) {
      composed = [];
      for (let phase = 0; phase < loop; phase++) {
        composed.push(compose(breed, step.pose, outfit, accessories, bond, step.stance, phase));
      }
      cache.set(key, composed);
    }
    return composed;
  });
  /* Effects placed by the head follow the clip's first frame, so a drifting "z" doesn't bob with each breath. */
  const head = phases[0]?.[0]?.headTopRight ?? { x: 0, y: 0 };

  const finish = (step: TimelineFrame, composed: Composed, drop: number): PetCanvas => {
    const pet = composed.canvas.shifted(0, step.shiftY + drop);
    let canvas = pet;
    for (const effect of step.effects) {
      const grid = petArt("effect").grid(effect.grid);
      const y = place(effect.y, head.y) + drop;
      canvas = canvas.adding(grid, place(effect.x, head.x), Math.max(y, ceiling ?? y));
    }
    if (step.steam !== undefined && composed.mugTop) {
      const wisp = PropArt.steam()[step.steam];
      /* Painted over the chest, not behind the pet like other effects. */
      if (wisp) {
        if (canvas === pet) canvas = pet.copy();
        canvas.stamp(wisp, composed.mugTop.x + 1, composed.mugTop.y + drop - wisp.height);
      }
    }
    if (step.dust) {
      /* Puffs on the floor just outside the paws (the bottom row). */
      const floor = Math.min(FRAME_SIZE - 1, FRAME_SIZE - 1 - step.pose.lift + drop);
      let left = -1;
      let right = -1;
      for (let x = 0; x < FRAME_SIZE; x++) {
        if (canvas.pixel(x, floor) === 0) continue;
        if (left < 0) left = x;
        right = x;
      }
      if (left >= 0) {
        const dustLeft = EffectArt.dustLeft();
        const y = FRAME_SIZE - dustLeft.height;
        canvas = canvas.adding(dustLeft, left - dustLeft.width, y).adding(EffectArt.dustRight(), right + 1, y);
      }
    }
    /* Only effects get an outline ring cut into wings; petals sit on them plainly. */
    const effects = canvas.added(pet);
    if (composed.aura) {
      canvas = canvas.scattering(ceiling === undefined ? composed.aura : composed.aura.keepingParticles(ceiling));
    }
    /* Wings go behind the pet and its effects. */
    if (composed.back) canvas = canvas.overRinging(composed.back.shifted(0, step.shiftY + drop), effects);
    return canvas;
  };

  /* How far a step moves down to clear `ceiling`: what its highest tick needs, no more than its lowest has room for. */
  const fittingDrop = (step: TimelineFrame, composed: readonly Composed[]): number => {
    if (ceiling === undefined) return 0;
    let minY = Infinity;
    let maxY = -Infinity;
    for (const item of composed) {
      for (const layer of [item.canvas, item.back]) {
        const bounds = layer?.opaqueBounds;
        if (!bounds) continue;
        minY = Math.min(minY, bounds.minY);
        maxY = Math.max(maxY, bounds.maxY);
      }
    }
    if (minY === Infinity) return 0;
    const top = Math.max(0, minY + step.shiftY);
    const bottom = Math.min(FRAME_SIZE - 1, maxY + step.shiftY);
    return Math.max(0, Math.min(ceiling - top, FRAME_SIZE - 1 - bottom));
  };

  const frames = timeline.frames.map((step, index) => {
    const composed = phases[index] ?? [];
    const drop = fittingDrop(step, composed);
    const canvases = composed.map((item) => finish(step, item, drop));
    const first = canvases[0];
    if (!first) throw new Error(`No frame composed for ${animation}`);
    /* A frame where the moving item is out of sight (a hanging pet shows no body) holds still. */
    const moves = canvases.some((canvas) => !canvas.equals(first));
    const anchor = composed[0]?.headTopRight ?? head;
    return new PetFrame(
      first,
      step.duration,
      step.bubble ? { x: anchor.x, y: anchor.y + drop } : undefined,
      moves ? canvases : [],
    );
  });
  return new PetClip(animation, frames);
}
