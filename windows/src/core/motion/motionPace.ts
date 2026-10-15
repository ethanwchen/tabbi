import { tr } from "../localization/tr";
import { SpringSpec } from "./springSpec";

/*
 * Port of MotionPace: how lively Tabbi's animations are, chosen in Settings >
 * General. It scales every MotionTokens value on top of the theme's motion,
 * and Reduce Motion still wins over Smooth and Fast (see `isAnimated`).
 */
export type MotionPace = "smooth" | "fast" | "instant";

export const MOTION_PACES: readonly MotionPace[] = ["smooth", "fast", "instant"];

export const DEFAULT_MOTION_PACE: MotionPace = "smooth";

/** Whether a stored value is one of the raw values Settings keeps. */
export function isMotionPace(value: unknown): value is MotionPace {
  return typeof value === "string" && (MOTION_PACES as readonly string[]).includes(value);
}

/** The share of each duration Fast keeps. */
export const FAST_SCALE = 0.6;

export function motionPaceTitle(pace: MotionPace): string {
  switch (pace) {
    case "smooth":
      return tr("Smooth");
    case "fast":
      return tr("Fast");
    case "instant":
      return tr("Instant");
  }
}

/** One line for Settings saying what the choice feels like. */
export function motionPaceCaption(pace: MotionPace): string {
  switch (pace) {
    case "smooth":
      return tr("Springy, with a little bounce.");
    case "fast":
      return tr("Quick and crisp, with no bounce.");
    case "instant":
      return tr("Changes appear at once, with no animation.");
  }
}

/** `spec` at this pace, or undefined when it should not animate. */
export function adjustedSpring(pace: MotionPace, spec: SpringSpec): SpringSpec | undefined {
  switch (pace) {
    case "smooth":
      return spec;
    case "fast":
      return new SpringSpec(spec.duration * FAST_SCALE, 0);
    case "instant":
      return undefined;
  }
}

/** A fade's or delay's `seconds` at this pace: 0 for Instant. */
export function pacedDuration(pace: MotionPace, seconds: number): number {
  switch (pace) {
    case "smooth":
      return seconds;
    case "fast":
      return seconds * FAST_SCALE;
    case "instant":
      return 0;
  }
}

/**
 * Whether anything moves: false for Instant, and under Reduce Motion for
 * every pace, so Reduce Motion behaves like Instant apart from its crossfade.
 */
export function isAnimated(pace: MotionPace, reduceMotion: boolean): boolean {
  return pace !== "instant" && !reduceMotion;
}
