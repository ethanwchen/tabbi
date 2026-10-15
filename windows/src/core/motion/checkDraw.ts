/*
 * Port of CheckDraw: how a round checkbox turns on, as pure functions of one
 * progress value. The accent fill pops in from the center, then the check
 * stroke draws on. The view animates `progress` from 0 to 1 with the
 * MotionTokens.check spring, so the spring's small overshoot is the toggle's
 * bounce. Progress past 1 swells the fill a little (capped) while the stroke
 * never overdraws. Under Reduce Motion the finished checkbox crossfades in.
 */

export interface CheckDraw {
  /** Ring opacity: the outline fades out as the fill arrives. */
  readonly ringOpacity: number;
  readonly fillOpacity: number;
  /** From `CHECK_START_SCALE` to 1, a little above 1 while the spring overshoots. */
  readonly fillScale: number;
  /** How much of the check stroke is drawn, 0 to 1. */
  readonly checkTrim: number;
  /** So a half-drawn stroke never shows on an empty box. */
  readonly checkOpacity: number;
}

export const CheckDrawTiming = {
  /** The fill starts at this fraction of the box and grows to full size. */
  startScale: 0.4,
  /** Progress by which the fill reaches full size. */
  fillEnd: 0.55,
  /** Progress at which the check starts drawing, while the fill still grows. */
  checkStart: 0.3,
  /** The fill never swells past this while the spring overshoots. */
  maxSwell: 1.08,
} as const;

/** The checkbox at `progress` (0 off, 1 on). */
export function checkDraw(progress: number, reduceMotion = false): CheckDraw {
  const p = Number.isFinite(progress) ? Math.max(progress, 0) : 0;
  const { startScale, fillEnd, checkStart, maxSwell } = CheckDrawTiming;
  if (reduceMotion) {
    const fade = Math.min(p, 1);
    return { ringOpacity: 1 - fade, fillOpacity: fade, fillScale: 1, checkTrim: 1, checkOpacity: fade };
  }
  const grow = Math.min(p / fillEnd, 1);
  const checkTrim = Math.min(Math.max((p - checkStart) / (1 - checkStart), 0), 1);
  return {
    ringOpacity: 1 - Math.min(p / checkStart, 1),
    fillOpacity: Math.min(p / 0.2, 1),
    fillScale: p <= 1 ? startScale + (1 - startScale) * grow : Math.min(1 + (p - 1), maxSwell),
    checkTrim,
    checkOpacity: checkTrim > 0 ? 1 : 0,
  };
}
