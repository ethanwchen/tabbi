/*
 * The Mac's loaders (Sources/TabbiKit/Components/Loading/): `Spinner`, an
 * accent arc that turns once a second; `SkeletonLine` placeholder capsules
 * laid out like the content they stand in for, with `Shimmer` sweeping a
 * soft highlight across the group; `ProgressRing`, a track and an accent arc
 * that fills clockwise from twelve o'clock; and `PawLoader`, a trail of four
 * paw prints for longer waits. Each draws from the loader clock, capped at
 * 30 fps and paused off screen, and under Reduce Motion stands still and
 * breathes instead. `Placeholder` is the web's `.redacted(.placeholder)`.
 */

import { useRef, useState, type CSSProperties, type ReactNode } from "react";
import { tr } from "../../core/localization/tr";
import { LoaderClock } from "../../core/motion/loaderClock";
import { PawTrail } from "../../core/motion/pawTrail";
import { RingProgress } from "../../core/motion/ringProgress";
import { useKit } from "./context";
import { PAW_PRINT_PATH } from "./celebrationShapes";
import { useLoaderClock } from "./useLoaderClock";
import { useSpringValue } from "./useSpringValue";

export interface SpinnerProps {
  /** The arc color; the secondary text color by default. */
  readonly tint?: string;
  readonly size?: number;
  readonly lineWidth?: number;
  /** Draws this moment, in seconds, instead of the clock (for frame strips). */
  readonly time?: number;
}

export function Spinner({ tint = "var(--secondary-text)", size = 12, lineWidth, time }: SpinnerProps) {
  const { reduceMotion } = useKit();
  const element = useRef<SVGSVGElement>(null);
  const clock = useLoaderClock(time === undefined, element);
  const t = time ?? clock;
  const width = lineWidth ?? Math.max(1.5, size / 6);
  const r = (size - width) / 2;
  const circumference = 2 * Math.PI * r;
  const angle = reduceMotion ? -90 : LoaderClock.spinAngle(t);
  const opacity = reduceMotion ? LoaderClock.breathingOpacity(t) : 1;
  return (
    <svg ref={element} className="kit-spinner" width={size} height={size} viewBox={`0 0 ${size} ${size}`} role="img" aria-label={tr("Loading")}>
      <circle
        cx={size / 2}
        cy={size / 2}
        r={r}
        fill="none"
        stroke={tint}
        strokeWidth={width}
        strokeLinecap="round"
        strokeDasharray={`${circumference * 0.7} ${circumference}`}
        opacity={opacity}
        transform={`rotate(${angle} ${size / 2} ${size / 2})`}
      />
    </svg>
  );
}

export interface SkeletonLineProps {
  /** A line this fraction of the available width (0 to 1). */
  readonly fraction?: number;
  /** A line exactly this wide, for a fixed column such as a time. */
  readonly width?: number;
  readonly height?: number;
}

export function SkeletonLine({ fraction, width, height = 8 }: SkeletonLineProps) {
  const style: CSSProperties =
    width !== undefined ? { width, height } : { width: `${Math.min(Math.max(fraction ?? 1, 0), 1) * 100}%`, height };
  return <span className="kit-skeleton-line" style={style} aria-hidden="true" />;
}

export interface ShimmerProps {
  readonly active?: boolean;
  readonly children?: ReactNode;
  readonly className?: string;
  readonly style?: CSSProperties;
  readonly time?: number;
}

/** Sweeps a soft highlight across the skeleton lines inside while `active`; breathes under Reduce Motion. */
export function Shimmer({ active = true, children, className, style, time }: ShimmerProps) {
  const { reduceMotion } = useKit();
  const element = useRef<HTMLDivElement>(null);
  const clock = useLoaderClock(active && time === undefined, element);
  const t = time ?? clock;
  const offset = LoaderClock.shimmerOffset(t);
  const breathing = active && reduceMotion;
  const merged: CSSProperties = {
    ...style,
    opacity: breathing ? LoaderClock.breathingOpacity(t) : undefined,
    "--shimmer-offset": `${(offset * 100).toFixed(2)}%`,
    "--shimmer-band": `${LoaderClock.shimmerBand * 100}%`,
  } as CSSProperties;
  return (
    <div ref={element} className={["kit-shimmer", className].filter(Boolean).join(" ")} data-active={active && !reduceMotion} style={merged}>
      {children}
    </div>
  );
}

/** A figure still loading: a placeholder bar the size of the figure, the Mac's `.redacted(.placeholder)`. */
export function Placeholder({ width, height = 12, className }: { width: number | string; height?: number; className?: string }) {
  return <span className={["kit-placeholder", className].filter(Boolean).join(" ")} style={{ width, height }} aria-hidden="true" />;
}

export interface ProgressRingProps {
  /** The fraction done; clamped to 0...1, and undefined or non-finite draws an empty ring. */
  readonly progress: number | undefined;
  readonly tint?: string;
  /** The unfilled track; a faint tint by default. */
  readonly track?: string;
  readonly lineWidth?: number;
  readonly size?: number;
  readonly children?: ReactNode;
  readonly className?: string;
}

export function ProgressRing({ progress, tint = "var(--accent)", track, lineWidth = 2.5, size = 44, children, className }: ProgressRingProps) {
  const clamped = RingProgress.clamped(progress);
  /* The last value, kept as state so the change kind is known on the render that moves the arc. */
  const [last, setLast] = useState(clamped);
  const change = RingProgress.change(last, clamped);
  if (last !== clamped) setLast(clamped);
  /* A tick too small to see, or a restart, lands without a spring; the rest glides with the content spring. */
  const shown = useSpringValue(clamped, "content", { immediate: change === "step" || change === "restart" });
  const r = (size - lineWidth) / 2;
  const circumference = 2 * Math.PI * r;
  return (
    <div className={["kit-progress-ring", className].filter(Boolean).join(" ")} style={{ width: size, height: size }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true" focusable="false">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={track ?? "color-mix(in srgb, var(--accent) 20%, transparent)"} strokeWidth={lineWidth} style={track ? undefined : { stroke: track ?? undefined }} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={tint}
          strokeWidth={lineWidth}
          /* A round cap on an empty arc would still draw a dot at twelve o'clock. */
          strokeLinecap={shown > 0 ? "round" : "butt"}
          strokeDasharray={`${circumference * Math.min(Math.max(shown, 0), 1)} ${circumference}`}
          transform={`rotate(-90 ${size / 2} ${size / 2})`}
        />
      </svg>
      <div className="kit-progress-ring-content">{children}</div>
    </div>
  );
}

export interface PawLoaderProps {
  readonly tint?: string;
  /** The trail's height; it is about twice as wide. */
  readonly size?: number;
  /** What a screen reader says, such as "Thinking". */
  readonly label?: string;
  readonly time?: number;
  /** Draws the trail without the reveal delay. */
  readonly revealed?: boolean;
}

export function PawLoader({ tint = "var(--accent)", size = 16, label, time, revealed = false }: PawLoaderProps) {
  const { reduceMotion, loaderRevealDelay } = useKit();
  const element = useRef<HTMLDivElement>(null);
  const clock = useLoaderClock(time === undefined, element);
  const t = time ?? clock;
  const printSize = size * 0.46;
  const stride = size * 0.52;
  const width = printSize + (PawTrail.stepCount - 1) * stride;
  const calm = LoaderClock.breathingOpacity(t);
  const reveal = revealed || time !== undefined ? 1 : PawTrail.revealOpacity(t, loaderRevealDelay);
  const steps = [];
  for (let step = 0; step < PawTrail.stepCount; step++) {
    const opacity = reduceMotion ? calm : PawTrail.opacity(step, t);
    if (opacity <= 0) continue;
    const side = printSize * (reduceMotion ? 1 : PawTrail.scale(step, t));
    const lane = PawTrail.isLeftFoot(step) ? -1 : 1;
    const x = printSize / 2 + step * stride;
    const y = size / 2 + lane * size * 0.2;
    steps.push(
      <path
        key={step}
        d={PAW_PRINT_PATH}
        fill={tint}
        opacity={opacity}
        transform={`translate(${x} ${y}) rotate(90) scale(${side})`}
      />,
    );
  }
  return (
    <div ref={element} className="kit-paw-loader" role="img" aria-label={label ?? tr("Loading")} style={{ width, height: size, opacity: reveal }}>
      <svg width={width} height={size} viewBox={`0 0 ${width} ${size}`} aria-hidden="true" focusable="false">
        {steps}
      </svg>
    </div>
  );
}
