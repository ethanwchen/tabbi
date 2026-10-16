/*
 * The Mac's `StudyPrimaryButton` and `FocusPrimaryButton`: the one primary
 * action of a timer panel, a filled accent capsule 28 px tall with a bold
 * glyph and body-emphasis title in the panel's background color. It
 * brightens from 88 to 100 percent accent on hover and sinks with the
 * tactile press. One per panel; secondary actions are `Pill`s and
 * `IconButton`s.
 */

import type { ButtonHTMLAttributes, CSSProperties, MouseEvent } from "react";
import { TactileFeedback } from "../../core/motion/tactileFeedback";
import { useTransition } from "./context";
import { Icon } from "./Icon";
import { mergeHandlers, useTactile, type PreviewState } from "./tactile";
import { Tooltip } from "./Tooltip";

export interface PrimaryPillProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "onClick" | "style" | "title"> {
  readonly title: string;
  /** An icon id or SF Symbol name. */
  readonly symbol: string;
  /** The tooltip, which should say what a click does. */
  readonly help: string;
  readonly onClick?: (event: MouseEvent<HTMLButtonElement>) => void;
  readonly preview?: PreviewState;
  readonly style?: CSSProperties;
}

export function PrimaryPill({ title, symbol, help, onClick, preview, disabled = false, className, style, ...rest }: PrimaryPillProps) {
  const tactile = useTactile({ feedback: TactileFeedback.pill, disabled, preview });
  const transition = useTransition("snappy", ["background-color"]);
  const handlers = mergeHandlers(tactile.handlers, rest);
  const merged: CSSProperties = {
    ...tactile.style,
    transition: [tactile.style.transition, transition].filter(Boolean).join(", "),
    ...style,
  };
  return (
    <Tooltip text={help}>
      <button
        type="button"
        aria-label={help}
        className={["kit-primary-pill", className].filter(Boolean).join(" ")}
        disabled={disabled}
        {...tactile.data}
        {...rest}
        {...handlers}
        onClick={onClick}
        style={merged}
      >
        <Icon id={symbol} size={10} />
        <span>{title}</span>
      </button>
    </Tooltip>
  );
}
