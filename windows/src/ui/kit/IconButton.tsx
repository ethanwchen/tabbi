/*
 * The Mac's `IconButton`: a round control (28 px by default) with a glyph
 * 0.46 of its size, the theme's control background on hover (surface to
 * surfaceHover, or glass where the theme asks), the tactile press, and a
 * tooltip that doubles as its accessible name. `tint` colors the glyph (the
 * paw takes the pet's accent on hover); `selected` keeps the background on.
 */

import type { ButtonHTMLAttributes, CSSProperties, MouseEvent } from "react";
import { TactileFeedback } from "../../core/motion/tactileFeedback";
import { Icon } from "./Icon";
import { mergeHandlers, useTactile, type PreviewState } from "./tactile";
import { Tooltip } from "./Tooltip";
import { useTransition } from "./context";

export interface IconButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "onClick" | "style"> {
  /** An icon id or SF Symbol name. */
  readonly symbol: string;
  readonly size?: number;
  /** The tooltip, which is also the accessible name. */
  readonly help: string;
  readonly onClick?: (event: MouseEvent<HTMLButtonElement>) => void;
  /** The glyph color; the palette's primary text by default. */
  readonly tint?: string;
  /** Keeps the control background on, for a toggle that is on. */
  readonly selected?: boolean;
  /** Grows a little on hover, for one primary control. */
  readonly lifts?: boolean;
  /** Turns the glyph while work runs. */
  readonly spinning?: boolean;
  readonly preview?: PreviewState;
  /** Shows the tooltip at once, for reviews. */
  readonly tooltipOpen?: boolean;
  readonly style?: CSSProperties;
}

export function IconButton({
  symbol,
  size = 28,
  help,
  onClick,
  tint,
  selected = false,
  lifts = false,
  spinning = false,
  preview,
  tooltipOpen,
  disabled = false,
  className,
  style,
  ...rest
}: IconButtonProps) {
  const tactile = useTactile({ feedback: TactileFeedback.control, lifts, disabled, preview });
  const transition = useTransition("snappy", ["background-color", "color"]);
  const handlers = mergeHandlers(tactile.handlers, rest);
  const merged: CSSProperties = {
    width: size,
    height: size,
    color: tint,
    ...tactile.style,
    transition: [tactile.style.transition, transition].filter(Boolean).join(", "),
    ...style,
  };
  return (
    <Tooltip text={help} open={tooltipOpen}>
      <button
        type="button"
        aria-label={help}
        aria-pressed={selected || undefined}
        className={["kit-icon-button", className].filter(Boolean).join(" ")}
        disabled={disabled}
        data-selected={selected}
        data-spinning={spinning || undefined}
        {...tactile.data}
        {...rest}
        {...handlers}
        onClick={onClick}
        style={merged}
      >
        <Icon id={symbol} size={Math.round(size * 0.46 * 100) / 100} />
      </button>
    </Tooltip>
  );
}
