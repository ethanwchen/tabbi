import { PET_EYES, PET_MOUTHS, petPose, SITTING, type PetGesture, type PetPose, type PetProp, type PetStance } from "./petPose";
import { isOneOf } from "./petKinds";

/*
 * Port of PetTimeline: one animation as `animations.json` (`pets.v1`)
 * defines it, so the Mac app and this port play the very same frames.
 */

/** Where an effect lands on one axis: a fixed frame pixel, or pixels from the head's top-right corner. */
export type TimelineCoordinate = { readonly frame: number } | { readonly head: number };

export interface TimelineEffect {
  readonly grid: string;
  readonly x: TimelineCoordinate;
  readonly y: TimelineCoordinate;
}

export interface TimelineFrame {
  readonly duration: number;
  readonly pose: PetPose;
  readonly stance: PetStance;
  /** Rows the whole frame moves down (negative: up), for the peek. */
  readonly shiftY: number;
  readonly effects: readonly TimelineEffect[];
  /** The `prop.json` steam wisp rising from the mug. */
  readonly steam?: number;
  readonly dust: boolean;
  readonly bubble: boolean;
}

export interface PetTimeline {
  readonly loops: boolean;
  /** The frame a still pet shows; undefined means a loop's first frame and a one-shot clip's last. */
  readonly still?: number;
  readonly frames: readonly TimelineFrame[];
}

export function stillIndex(timeline: PetTimeline): number {
  return timeline.still ?? (timeline.loops ? 0 : timeline.frames.length - 1);
}

/** A broken art file, with where and why. Port of PetArtFile.LoadError. */
export class PetArtLoadError extends Error {}

export function invalidValue(path: string, value: string): PetArtLoadError {
  return new PetArtLoadError(`${path}: unknown value "${value}"`);
}

type Json = Record<string, unknown>;

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function int(raw: Json, key: string, path: string): number | undefined {
  const value = raw[key];
  if (value === undefined) return undefined;
  if (typeof value !== "number" || !Number.isInteger(value)) throw invalidValue(`${path}.${key}`, String(value));
  return value;
}

function bool(raw: Json, key: string, path: string): boolean | undefined {
  const value = raw[key];
  if (value === undefined) return undefined;
  if (typeof value !== "boolean") throw invalidValue(`${path}.${key}`, String(value));
  return value;
}

function text(raw: Json, key: string, path: string): string | undefined {
  const value = raw[key];
  if (value === undefined) return undefined;
  if (typeof value !== "string") throw invalidValue(`${path}.${key}`, String(value));
  return value;
}

function coordinate(value: unknown, path: string): TimelineCoordinate {
  if (typeof value === "number" && Number.isInteger(value)) return { frame: value };
  if (isObject(value) && typeof value.head === "number" && Number.isInteger(value.head)) return { head: value.head };
  throw invalidValue(path, JSON.stringify(value));
}

function prop(raw: unknown, path: string): PetProp {
  if (!isObject(raw)) throw invalidValue(path, JSON.stringify(raw));
  const kind = text(raw, "kind", path);
  switch (kind) {
    case "laptop":
      return { kind, tap: int(raw, "tap", path) ?? 0 };
    case "mug":
      return { kind, raise: int(raw, "raise", path) ?? 0 };
    case "toy":
      return {
        kind,
        roll: int(raw, "roll", path) ?? 0,
        bounce: int(raw, "bounce", path) ?? 0,
        bat: bool(raw, "bat", path) ?? false,
      };
    default:
      throw invalidValue(`${path}.kind`, String(kind));
  }
}

function gesture(raw: unknown, path: string): PetGesture {
  if (!isObject(raw)) throw invalidValue(path, JSON.stringify(raw));
  const kind = text(raw, "kind", path);
  switch (kind) {
    case "wave":
      return { kind, swing: int(raw, "swing", path) ?? 0 };
    case "groom":
      return { kind, reach: int(raw, "reach", path) ?? 0 };
    default:
      throw invalidValue(`${path}.kind`, String(kind));
  }
}

function pose(raw: unknown, path: string): PetPose {
  if (!isObject(raw)) throw invalidValue(path, JSON.stringify(raw));
  const eyes = text(raw, "eyes", path) ?? "open";
  const mouth = text(raw, "mouth", path) ?? "closed";
  if (!isOneOf(PET_EYES, eyes)) throw invalidValue(`${path}.eyes`, eyes);
  if (!isOneOf(PET_MOUTHS, mouth)) throw invalidValue(`${path}.mouth`, mouth);
  return petPose({
    eyes,
    mouth,
    ...(raw.prop === undefined ? {} : { prop: prop(raw.prop, `${path}.prop`) }),
    ...(raw.gesture === undefined ? {} : { gesture: gesture(raw.gesture, `${path}.gesture`) }),
    tailSwing: int(raw, "tailSwing", path) ?? 0,
    headDrop: int(raw, "headDrop", path) ?? 0,
    lift: int(raw, "lift", path) ?? 0,
  });
}

function stance(raw: unknown, path: string): PetStance {
  if (!isObject(raw)) throw invalidValue(path, JSON.stringify(raw));
  const kind = text(raw, "kind", path);
  switch (kind) {
    case "sitting":
      return SITTING;
    case "hanging":
      return { kind };
    case "walking":
      return { kind, step: int(raw, "step", path) ?? 0 };
    case "stretching":
      return { kind, depth: int(raw, "depth", path) ?? 0, wag: int(raw, "wag", path) ?? 0 };
    case "curled":
      return { kind, breath: int(raw, "breath", path) ?? 0 };
    default:
      throw invalidValue(`${path}.kind`, String(kind));
  }
}

/** Checks a raw timeline; `path` names it in errors (`animations.sleep`). */
export function parseTimeline(raw: unknown, path: string): PetTimeline {
  if (!isObject(raw)) throw invalidValue(path, JSON.stringify(raw));
  const frames = raw.frames;
  if (!Array.isArray(frames) || frames.length === 0) throw invalidValue(`${path}.frames`, "[]");
  const loops = bool(raw, "loops", path);
  if (loops === undefined) throw invalidValue(`${path}.loops`, "undefined");
  const still = int(raw, "still", path);
  if (still !== undefined && (still < 0 || still >= frames.length)) throw invalidValue(`${path}.still`, String(still));
  return {
    loops,
    ...(still === undefined ? {} : { still }),
    frames: frames.map((frame: unknown, index): TimelineFrame => {
      const framePath = `${path}.frames[${index}]`;
      if (!isObject(frame)) throw invalidValue(framePath, JSON.stringify(frame));
      const duration = frame.duration;
      if (typeof duration !== "number" || !(duration > 0)) throw invalidValue(`${framePath}.duration`, String(duration));
      const effects = frame.effects ?? [];
      if (!Array.isArray(effects)) throw invalidValue(`${framePath}.effects`, JSON.stringify(effects));
      const steam = int(frame, "steam", framePath);
      return {
        duration,
        pose: frame.pose === undefined ? petPose() : pose(frame.pose, `${framePath}.pose`),
        stance: frame.stance === undefined ? SITTING : stance(frame.stance, `${framePath}.stance`),
        shiftY: int(frame, "shiftY", framePath) ?? 0,
        effects: effects.map((effect: unknown, effectIndex) => {
          const effectPath = `${framePath}.effects[${effectIndex}]`;
          if (!isObject(effect) || typeof effect.grid !== "string") throw invalidValue(effectPath, JSON.stringify(effect));
          return {
            grid: effect.grid,
            x: coordinate(effect.x, `${effectPath}.x`),
            y: coordinate(effect.y, `${effectPath}.y`),
          };
        }),
        ...(steam === undefined ? {} : { steam }),
        dust: bool(frame, "dust", framePath) ?? false,
        bubble: bool(frame, "bubble", framePath) ?? false,
      };
    }),
  };
}
