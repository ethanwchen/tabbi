/*
 * The Mac's `TrackSlider`: the panel's thin slider, a capsule track, an
 * accent fill and a round knob. The knob stays on the track at both ends
 * with its center under the pointer (TrackSliderGeometry); the drag-driven
 * knob and fill never animate, so they follow the pointer exactly, and only
 * the hover and drag highlight (a 1.25x knob, a thicker track) springs. The
 * highlight holds for the whole drag, even off the thin track. Values run
 * left to right in every language, as Tabbi's bars do. Arrow keys move it
 * by `step`.
 */

import { useCallback, useId, useLayoutEffect, useRef, useState, type CSSProperties, type KeyboardEvent, type PointerEvent } from "react";
import { useTransition } from "./context";
import { Tooltip } from "./Tooltip";

export const ACTIVE_KNOB_SCALE = 1.25;

/** Port of TrackSliderGeometry: where the fill ends and the knob sits for a value, and the value under a pointer. */
export class TrackSliderGeometry {
  constructor(
    readonly width: number,
    /** The knob's diameter when grown, which must still fit the track at both ends. */
    readonly knobDiameter: number,
  ) {}

  /** How far the knob's center can travel. */
  get travel(): number {
    return Math.max(0, this.width - this.knobDiameter);
  }

  private clamp(value: number): number {
    return Number.isFinite(value) ? Math.min(Math.max(value, 0), 1) : 0;
  }

  /** The knob's leading edge for `value`. */
  knobOffset(value: number): number {
    return this.clamp(value) * this.travel;
  }

  /** The knob's center for `value`. */
  knobCenter(value: number): number {
    return this.knobOffset(value) + this.knobDiameter / 2;
  }

  /** The fill ends under the knob's center. */
  fillWidth(value: number): number {
    return this.knobCenter(value);
  }

  /** The value whose knob center is under `x`. */
  fraction(x: number): number {
    if (this.travel <= 0) return 0;
    return this.clamp((x - this.knobDiameter / 2) / this.travel);
  }
}

export interface TrackSliderProps {
  /** The current value, 0...1 (clamped for drawing). */
  readonly value: number;
  /** The fill, usually the module accent. */
  readonly tint?: string;
  /** The fill while neither hovered nor dragged, if it differs. */
  readonly idleTint?: string;
  readonly trackHeight?: number;
  /** The track's thickness while hovered or dragged. */
  readonly activeTrackHeight?: number;
  readonly knobDiameter?: number;
  /** `always`, or `whileActive` to show the knob only while hovered or dragged (the scrubber). */
  readonly knobVisibility?: "always" | "whileActive";
  /** How far the arrow keys move it. */
  readonly step?: number;
  /** The tooltip, which should name the value. */
  readonly help: string;
  readonly label: string;
  /** The value as a screen reader says it. */
  readonly valueText?: string;
  readonly onChange: (value: number) => void;
  /** Called once with the final value when a drag ends. */
  readonly onCommit?: (value: number) => void;
  readonly disabled?: boolean;
  readonly width?: number | string;
  readonly height?: number;
  readonly preview?: "hover" | "pressed";
  readonly className?: string;
}

export function TrackSlider({
  value,
  tint = "var(--accent)",
  idleTint,
  trackHeight = 4,
  activeTrackHeight,
  knobDiameter = 8,
  knobVisibility = "always",
  step = 0.1,
  help,
  label,
  valueText,
  onChange,
  onCommit,
  disabled = false,
  width = "100%",
  height = 20,
  preview,
  className,
}: TrackSliderProps) {
  const id = useId();
  const element = useRef<HTMLDivElement>(null);
  const [hovering, setHovering] = useState(false);
  const [dragging, setDragging] = useState(false);
  const [w, setWidth] = useState(0);
  useLayoutEffect(() => {
    const node = element.current;
    if (!node) return;
    setWidth(node.clientWidth);
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(() => setWidth(node.clientWidth));
    observer.observe(node);
    return () => observer.disconnect();
  }, []);
  const active = !disabled && (preview !== undefined || hovering || dragging);
  const transition = useTransition("snappy", ["height", "transform", "opacity", "background-color"]);
  const grown = knobDiameter * ACTIVE_KNOB_SCALE;
  const activeHeight = activeTrackHeight ?? trackHeight;

  const geometry = useCallback(() => new TrackSliderGeometry(element.current?.clientWidth ?? 0, grown), [grown]);

  const fractionAt = useCallback(
    (event: PointerEvent<HTMLElement>) => {
      const rect = element.current?.getBoundingClientRect();
      if (!rect) return value;
      return geometry().fraction(event.clientX - rect.left);
    },
    [geometry, value],
  );

  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (disabled || event.button !== 0) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    setDragging(true);
    onChange(fractionAt(event));
  };
  const onPointerMove = (event: PointerEvent<HTMLDivElement>) => {
    if (!dragging) return;
    onChange(fractionAt(event));
  };
  const onPointerUp = (event: PointerEvent<HTMLDivElement>) => {
    if (!dragging) return;
    setDragging(false);
    const final = fractionAt(event);
    onChange(final);
    onCommit?.(final);
  };
  const commit = (next: number) => {
    const clamped = Math.min(Math.max(next, 0), 1);
    onChange(clamped);
    onCommit?.(clamped);
  };
  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (disabled) return;
    /* The slider runs left to right in every language, so the arrows keep their physical meaning. */
    if (event.key === "ArrowRight" || event.key === "ArrowUp") commit(value + step);
    else if (event.key === "ArrowLeft" || event.key === "ArrowDown") commit(value - step);
    else if (event.key === "Home") commit(0);
    else if (event.key === "End") commit(1);
    else return;
    event.preventDefault();
  };

  const g = new TrackSliderGeometry(w, grown);
  const clamped = Number.isFinite(value) ? Math.min(Math.max(value, 0), 1) : 0;
  const trackStyle: CSSProperties = { height: active ? activeHeight : trackHeight, transition };
  const fillStyle: CSSProperties = {
    ...trackStyle,
    width: w > 0 ? g.fillWidth(clamped) : `${clamped * 100}%`,
    background: active ? tint : (idleTint ?? tint),
  };
  const knobStyle: CSSProperties = {
    width: knobDiameter,
    height: knobDiameter,
    left: w > 0 ? g.knobOffset(clamped) + (grown - knobDiameter) / 2 : `calc(${clamped * 100}% - ${knobDiameter / 2}px)`,
    transform: active ? `scale(${ACTIVE_KNOB_SCALE})` : undefined,
    opacity: knobVisibility === "always" || active ? 1 : 0,
    transition,
  };
  return (
    <Tooltip text={help}>
      <div
        ref={element}
        id={id}
        className={["kit-track-slider", className].filter(Boolean).join(" ")}
        role="slider"
        aria-label={label}
        aria-valuemin={0}
        aria-valuemax={1}
        aria-valuenow={Math.round(clamped * 1000) / 1000}
        aria-valuetext={valueText}
        aria-disabled={disabled || undefined}
        tabIndex={disabled ? -1 : 0}
        data-active={active}
        data-disabled={disabled || undefined}
        style={{ width, height, "--slider-tint": tint } as CSSProperties}
        onPointerEnter={() => setHovering(true)}
        onPointerLeave={() => setHovering(false)}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        onKeyDown={onKeyDown}
      >
        <div className="kit-track-slider-track" style={trackStyle} />
        <div className="kit-track-slider-fill" style={fillStyle} />
        <div className="kit-track-slider-knob" style={knobStyle} />
      </div>
    </Tooltip>
  );
}
