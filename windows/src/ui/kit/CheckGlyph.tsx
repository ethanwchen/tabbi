/*
 * The Mac's `CheckGlyph`: a round checkbox that turns on with a small
 * bounce. The accent fill pops in from the center and the check stroke
 * draws on, short leg first, along the check spring (its overshoot swells
 * the fill by at most 8%); turning off retracts it with the snappy spring.
 * The timing is the core's `checkDraw`. Under Reduce Motion the finished
 * check crossfades in over the ring. Only the glyph: wrap it in a control.
 */

import { checkDraw } from "../../core/motion/checkDraw";
import { useKit } from "./context";
import { useSpringValue } from "./useSpringValue";

export interface CheckGlyphProps {
  readonly isOn: boolean;
  /** The fill, usually the module accent; defaults to the `--accent` variable. */
  readonly tint?: string;
  /** The outline while off; null when the caller draws its own ring. */
  readonly ring?: string | null;
  /** The check stroke: the theme's on-accent color by default, for a `tint` that is the accent. */
  readonly mark?: string;
  readonly size?: number;
  /** Draws one frame at this progress (0 off, 1 on), for reviews. */
  readonly progress?: number;
}

/* The check mark as one stroke, short leg first, in the unit square. */
const CHECK = "M0.29 0.52 L0.44 0.67 L0.72 0.36";
const CHECK_LENGTH = Math.hypot(0.15, 0.15) + Math.hypot(0.28, 0.31);

export function CheckGlyph({ isOn, tint = "var(--accent)", ring = "var(--tertiary-text)", mark = "var(--on-accent)", size = 16, progress }: CheckGlyphProps) {
  const { reduceMotion } = useKit();
  const animated = useSpringValue(isOn ? 1 : 0, isOn ? "check" : "snappy");
  const state = checkDraw(progress ?? animated, reduceMotion);
  const half = size / 2;
  const fillScale = Math.max(0, state.fillScale);
  const strokeScale = Math.min(fillScale, 1);
  return (
    <svg className="kit-check-glyph" width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true" focusable="false">
      {ring !== null && (
        <circle cx={half} cy={half} r={half - 0.75} fill="none" stroke={ring} strokeWidth={1.5} opacity={state.ringOpacity} />
      )}
      <circle cx={half} cy={half} r={half} fill={tint} opacity={state.fillOpacity} transform={`translate(${half} ${half}) scale(${fillScale}) translate(${-half} ${-half})`} />
      <path
        d={CHECK}
        fill="none"
        stroke={mark}
        strokeWidth={0.12}
        strokeLinecap="round"
        strokeLinejoin="round"
        opacity={state.checkOpacity}
        pathLength={CHECK_LENGTH}
        strokeDasharray={CHECK_LENGTH}
        strokeDashoffset={CHECK_LENGTH * (1 - state.checkTrim)}
        transform={`translate(${half} ${half}) scale(${strokeScale * size}) translate(-0.5 -0.5)`}
      />
    </svg>
  );
}
