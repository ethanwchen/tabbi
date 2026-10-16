/*
 * A thin bar that fills from the left, the read-only sibling of TrackSlider:
 * the Mac's PressureBar in System (a capsule colored by memory pressure)
 * and the track bar of a player that cannot seek. The fill is `tint` and
 * the track the surface hover color, and it runs left to right in every
 * language, as every bar in Tabbi does. A change in value glides on the
 * content spring, unless `still` (a value that ticks every second).
 */

import type { CSSProperties } from "react";
import { useTransition } from "./context";
import { Tooltip } from "./Tooltip";

export interface ProgressBarProps {
  /** The fraction filled, 0 to 1 (clamped). */
  readonly value: number;
  /** The fill; the accent by default. */
  readonly tint?: string;
  readonly height?: number;
  /** The tooltip. */
  readonly help?: string;
  /** The accessible name. */
  readonly label: string;
  /** The value as a screen reader says it. */
  readonly valueText?: string;
  /** Lands the fill at once instead of gliding. */
  readonly still?: boolean;
  readonly width?: number | string;
  readonly className?: string;
  readonly style?: CSSProperties;
}

export function ProgressBar({ value, tint = "var(--accent)", height = 4, help = "", label, valueText, still = false, width = "100%", className, style }: ProgressBarProps) {
  const transition = useTransition("content", ["width"]);
  const clamped = Number.isFinite(value) ? Math.min(Math.max(value, 0), 1) : 0;
  return (
    <Tooltip text={help}>
      <div
        className={["kit-progress-bar", className].filter(Boolean).join(" ")}
        role="progressbar"
        aria-label={label}
        aria-valuemin={0}
        aria-valuemax={1}
        aria-valuenow={Math.round(clamped * 1000) / 1000}
        aria-valuetext={valueText}
        style={{ width, height, ...style }}
      >
        <div className="kit-progress-bar-fill" style={{ width: `${clamped * 100}%`, background: tint, transition: still ? undefined : transition }} />
      </div>
    </Tooltip>
  );
}
