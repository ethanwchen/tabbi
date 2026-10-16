/*
 * A segmented control in Tabbi's look, for a choice of two to about five
 * (the Settings window's pickers for the notch mode, the motion pace): a
 * capsule of segments on the surface, the selected one lifted onto
 * surfaceHover (or the theme's glass control), 24 px tall, body-emphasis
 * text, each segment a tactile control with a tooltip. Arrow keys move the
 * selection; the row mirrors in a right-to-left language.
 */

import { useRef, type CSSProperties, type KeyboardEvent } from "react";
import { TactileFeedback } from "../../core/motion/tactileFeedback";
import { useTransition } from "./context";
import { Icon } from "./Icon";
import { mergeHandlers, useTactile, type PreviewState } from "./tactile";
import { Tooltip } from "./Tooltip";

export interface Segment<T extends string> {
  readonly id: T;
  readonly title: string;
  /** A tooltip, which should say what the choice does. */
  readonly help?: string;
  /** An icon in place of, or beside, the title. */
  readonly symbol?: string;
}

export interface SegmentedControlProps<T extends string> {
  readonly segments: readonly Segment<T>[];
  readonly selected: T;
  readonly onSelect: (id: T) => void;
  readonly label: string;
  readonly disabled?: boolean;
  /** Forces one segment's hover or press state, for reviews. */
  readonly preview?: { readonly id: T; readonly state: PreviewState };
  readonly className?: string;
}

export function SegmentedControl<T extends string>({ segments, selected, onSelect, label, disabled = false, preview, className }: SegmentedControlProps<T>) {
  const group = useRef<HTMLDivElement>(null);
  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (disabled) return;
    const index = segments.findIndex((s) => s.id === selected);
    const rtl = getComputedStyle(event.currentTarget).direction === "rtl";
    let step: number;
    if (event.key === "ArrowRight") step = rtl ? -1 : 1;
    else if (event.key === "ArrowLeft") step = rtl ? 1 : -1;
    else if (event.key === "Home") step = -index;
    else if (event.key === "End") step = segments.length - 1 - index;
    else return;
    const next = segments[(index + step + segments.length) % segments.length];
    if (next) {
      onSelect(next.id);
      const buttons = event.currentTarget.querySelectorAll<HTMLButtonElement>("button");
      buttons[(index + step + segments.length) % segments.length]?.focus();
    }
    event.preventDefault();
  };
  return (
    <div
      ref={group}
      className={["kit-segmented", className].filter(Boolean).join(" ")}
      role="radiogroup"
      aria-label={label}
      aria-disabled={disabled || undefined}
      onKeyDown={onKeyDown}
    >
      {segments.map((segment) => (
        <SegmentButton
          key={segment.id}
          segment={segment}
          selected={segment.id === selected}
          disabled={disabled}
          preview={preview?.id === segment.id ? preview.state : undefined}
          onSelect={() => onSelect(segment.id)}
        />
      ))}
    </div>
  );
}

function SegmentButton<T extends string>({
  segment,
  selected,
  disabled,
  preview,
  onSelect,
}: {
  segment: Segment<T>;
  selected: boolean;
  disabled: boolean;
  preview: PreviewState;
  onSelect: () => void;
}) {
  const tactile = useTactile({ feedback: TactileFeedback.pill, disabled, preview });
  const transition = useTransition("snappy", ["background-color", "color", "box-shadow"]);
  const handlers = mergeHandlers<HTMLButtonElement>(tactile.handlers, {});
  const style: CSSProperties = { ...tactile.style, transition: [tactile.style.transition, transition].filter(Boolean).join(", ") };
  return (
    <Tooltip text={segment.help ?? segment.title}>
      <button
        type="button"
        role="radio"
        aria-checked={selected}
        aria-label={segment.title}
        className="kit-segment"
        data-selected={selected}
        disabled={disabled}
        tabIndex={selected ? 0 : -1}
        {...tactile.data}
        {...handlers}
        onClick={onSelect}
        style={style}
      >
        {segment.symbol && <Icon id={segment.symbol} size={12} />}
        <span>{segment.title}</span>
      </button>
    </Tooltip>
  );
}
