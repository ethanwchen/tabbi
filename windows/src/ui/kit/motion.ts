/*
 * The Mac's `Motion` (Sources/TabbiKit/Design/Motion/Motion.swift) for the
 * web: a spring becomes a CSS transition whose `linear()` easing samples the
 * spring's own curve, so a hover lift or a selection change moves exactly
 * as SwiftUI's `spring(duration:bounce:)` would, overshoot included. The
 * Reduce Motion fallback is the short crossfade from MotionTokens, and the
 * Instant pace lands in the next frame.
 */

import { MotionTokens } from "../../core/motion/motionTokens";
import { isAnimated, type MotionPace } from "../../core/motion/motionPace";
import { SpringSpec } from "../../core/motion/springSpec";

export interface CssTransition {
  /** Milliseconds. */
  readonly duration: number;
  /** A CSS easing function. */
  readonly easing: string;
}

const SAMPLE_RATE = 60;

/**
 * `spec` as a CSS transition: its settling time, and a `linear()` easing
 * with one stop per frame along the spring. Values above 1 are kept, so a
 * bouncy spring still overshoots.
 */
export function springTransition(spec: SpringSpec): CssTransition {
  const settle = spec.settlingTime(0.005);
  const steps = Math.max(2, Math.ceil(settle * SAMPLE_RATE));
  const stops: string[] = [];
  for (let i = 0; i <= steps; i++) {
    const t = (i / steps) * settle;
    stops.push(spec.value(t).toFixed(4));
  }
  /* The last stop sits exactly on the target, so nothing is left a hair off. */
  stops[stops.length - 1] = "1";
  return { duration: Math.round(settle * 1000), easing: `linear(${stops.join(", ")})` };
}

/** The Reduce Motion replacement for every spring: a short ease-in-out crossfade. */
export const REDUCED: CssTransition = { duration: Math.round(MotionTokens.reducedCrossfade * 1000), easing: "ease-in-out" };

/** Instant's stand-in: the change lands in the next frame. */
export const INSTANT: CssTransition = { duration: 0, easing: "linear" };

/** `spec` as a transition, or the calm crossfade under Reduce Motion and nothing at the Instant pace. */
export function adaptedTransition(spec: SpringSpec, reduceMotion: boolean, pace: MotionPace = "smooth"): CssTransition {
  if (pace === "instant") return INSTANT;
  if (reduceMotion) return REDUCED;
  return springTransition(spec);
}

/** A CSS `transition` value for `properties` along `transition`. */
export function transitionCss(properties: readonly string[], transition: CssTransition, delayMs = 0): string {
  const delay = delayMs > 0 ? ` ${Math.round(delayMs)}ms` : "";
  return properties.map((p) => `${p} ${transition.duration}ms ${transition.easing}${delay}`).join(", ");
}

/** The delay for item `index` of a staggered entrance, in milliseconds: none under Reduce Motion or at Instant. */
export function staggerDelay(index: number, reduceMotion: boolean, pace: MotionPace = "smooth"): number {
  if (!isAnimated(pace, reduceMotion)) return 0;
  return Math.round(MotionTokens.stagger(index) * 1000);
}

/** The springs by token name, so a component can ask for `springs.snappy`. */
export const springs = {
  open: MotionTokens.open,
  close: MotionTokens.close,
  hover: MotionTokens.hover,
  snappy: MotionTokens.snappy,
  content: MotionTokens.content,
  press: MotionTokens.press,
  check: MotionTokens.check,
} as const satisfies Record<string, SpringSpec>;
