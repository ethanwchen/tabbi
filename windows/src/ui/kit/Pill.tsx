/*
 * A labeled pill button (the Focus, Study and Anki action pills, an empty
 * state's one action): 24 px tall, 12 px side padding, body-emphasis text,
 * an optional leading glyph, the surface that brightens on hover, and the
 * tactile press. `accent` colors it as the primary action; `lifts` makes it
 * grow a little on hover, for the one primary control of a panel.
 */

import type { ButtonHTMLAttributes, CSSProperties, MouseEvent } from "react";
import { TactileFeedback } from "../../core/motion/tactileFeedback";
import { useTransition } from "./context";
import { Icon } from "./Icon";
import { mergeHandlers, useTactile, type PreviewState } from "./tactile";
import { Tooltip } from "./Tooltip";

export interface PillProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "onClick" | "style"> {
  readonly title: string;
  readonly help?: string;
  readonly symbol?: string;
  readonly accent?: boolean;
  readonly lifts?: boolean;
  readonly onClick?: (event: MouseEvent<HTMLButtonElement>) => void;
  readonly preview?: PreviewState;
  readonly style?: CSSProperties;
}

export function Pill({ title, help, symbol, accent = false, lifts = false, onClick, preview, disabled = false, className, style, ...rest }: PillProps) {
  const tactile = useTactile({ feedback: TactileFeedback.pill, lifts, disabled, preview });
  const transition = useTransition("snappy", ["background-color", "color"]);
  const handlers = mergeHandlers(tactile.handlers, rest);
  const merged: CSSProperties = {
    ...tactile.style,
    transition: [tactile.style.transition, transition].filter(Boolean).join(", "),
    ...style,
  };
  return (
    <Tooltip text={help ?? title}>
      <button
        type="button"
        className={["kit-pill", className].filter(Boolean).join(" ")}
        disabled={disabled}
        data-accent={accent}
        {...tactile.data}
        {...rest}
        {...handlers}
        onClick={onClick}
        style={merged}
      >
        {symbol && <Icon id={symbol} size={12} />}
        <span>{title}</span>
      </button>
    </Tooltip>
  );
}
