/*
 * A stepper in Tabbi's look (the plain Timer's minutes, a session count):
 * the value in tabular figures between a minus and a plus icon button,
 * each 20 px with a tooltip, held in one capsule on the surface. The
 * buttons disable at the ends of the range; arrow keys step the value too.
 * The order is minus, value, plus in every language, since a number line
 * runs one way.
 */

import { useId, type KeyboardEvent } from "react";
import { tr } from "../../core/localization/tr";
import { IconButton } from "./IconButton";
import type { PreviewState } from "./tactile";

export interface StepperProps {
  readonly value: number;
  readonly onChange: (value: number) => void;
  readonly min?: number;
  readonly max?: number;
  readonly step?: number;
  readonly label: string;
  /** The value as shown ("25 min"); the plain number when omitted. */
  readonly format?: (value: number) => string;
  readonly disabled?: boolean;
  readonly preview?: { readonly button: "minus" | "plus"; readonly state: PreviewState };
  readonly className?: string;
}

export function Stepper({ value, onChange, min = 0, max = Number.POSITIVE_INFINITY, step = 1, label, format, disabled = false, preview, className }: StepperProps) {
  const id = useId();
  const clamp = (v: number) => Math.min(Math.max(v, min), max);
  const decrease = () => onChange(clamp(value - step));
  const increase = () => onChange(clamp(value + step));
  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (disabled) return;
    if (event.key === "ArrowUp" || event.key === "ArrowRight") increase();
    else if (event.key === "ArrowDown" || event.key === "ArrowLeft") decrease();
    else return;
    event.preventDefault();
  };
  return (
    <div
      className={["kit-stepper", className].filter(Boolean).join(" ")}
      role="group"
      aria-labelledby={`${id}-label`}
      data-disabled={disabled || undefined}
      onKeyDown={onKeyDown}
    >
      <IconButton
        symbol="minus"
        size={20}
        help={tr("Less")}
        disabled={disabled || value - step < min}
        preview={preview?.button === "minus" ? preview.state : undefined}
        onClick={decrease}
      />
      <span id={`${id}-label`} className="kit-stepper-value" aria-label={label} aria-live="polite">
        {format ? format(value) : String(value)}
      </span>
      <IconButton
        symbol="plus"
        size={20}
        help={tr("More")}
        disabled={disabled || value + step > max}
        preview={preview?.button === "plus" ? preview.state : undefined}
        onClick={increase}
      />
    </div>
  );
}
