import { SpringSpec } from "./springSpec";

/** Delay between items that enter one after another. */
const STAGGER_STEP = 0.03;
/** Upper bound on the total stagger, so long lists don't feel slow. */
const STAGGER_CAP = 0.15;

/*
 * Port of MotionTokens: Tabbi's motion values as pure numbers, in seconds.
 * The panel opens with a little stretch and closes critically damped (no
 * wobble on collapse), content trails the shape, and hover answers within
 * 150 to 300 ms. docs/design/motion.md explains each one.
 */
export const MotionTokens = {
  /** Opening: a calm stretch that settles. */
  open: new SpringSpec(0.45, 0.2),
  /** Closing: faster and with no overshoot, so it lands. */
  close: new SpringSpec(0.38, 0),
  /** Hover growth of the closed shape and hover lift of controls. */
  hover: new SpringSpec(0.25, 0.1),
  /** Selection, toggles and other small state changes. */
  snappy: new SpringSpec(0.26, 0.14),
  /** Content swaps inside the open panel (tabs, phases, list changes). */
  content: new SpringSpec(0.34, 0.1),
  /** A short spring for tactile press feedback. */
  press: new SpringSpec(0.18, 0),
  /** A checkbox turning on; its small overshoot is the toggle's bounce (see CheckDraw). */
  check: new SpringSpec(0.4, 0.25),

  /** How far the panel content trails the shape when it opens. */
  contentDelay: 0.08,
  /** Fade in of the panel content once it starts. */
  contentFadeIn: 0.22,
  /** Fade out of the panel content when it closes, before the shape collapses. */
  contentFadeOut: 0.12,

  /** The calm fallback under Reduce Motion: a short crossfade, no springs, no scale or slide. */
  reducedCrossfade: 0.18,

  staggerStep: STAGGER_STEP,
  staggerCap: STAGGER_CAP,

  /** Delay for the item at `index` in a staggered entrance, capped so the last never waits longer than `cap`. */
  stagger(index: number, step: number = STAGGER_STEP, cap: number = STAGGER_CAP): number {
    return Math.min(Math.max(index, 0) * step, cap);
  },
} as const;
