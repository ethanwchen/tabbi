/*
 * The Mac's `StudyCapsuleToggle` and the small chips beside it: a short
 * capsule that is a switch (Deep focus, Do Not Disturb, the long break) or
 * a one-of-many pick (a Timer length, a saved blend). Filled with the
 * accent while on, with the text in the panel's background color; a quiet
 * surface with a hairline stroke while off. The `soft` look (the Timer's
 * sound button) tints the capsule lightly instead and keeps the accent on
 * the text. Caption text, semibold, 20 px tall by default; an optional
 * glyph leads it. Every state has a hover and the tactile press.
 */

import type { ButtonHTMLAttributes, CSSProperties, MouseEvent } from "react";
import { TactileFeedback } from "../../core/motion/tactileFeedback";
import { useTransition } from "./context";
import { Icon } from "./Icon";
import { mergeHandlers, useTactile, type PreviewState } from "./tactile";
import { Tooltip } from "./Tooltip";

export interface CapsuleToggleProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "onClick" | "style" | "title"> {
  readonly title: string;
  /** An icon id or SF Symbol name shown before the title. */
  readonly symbol?: string;
  /** A second glyph after the title (the sound button's music note). */
  readonly trailingSymbol?: string;
  readonly isOn: boolean;
  /** The tooltip, which should say what a click does. */
  readonly help: string;
  /** `filled`: the accent fills the capsule while on. `soft`: a light tint with the accent on the text. */
  readonly look?: "filled" | "soft";
  /** Draws the hairline stroke while off. */
  readonly outlined?: boolean;
  readonly height?: number;
  /** The accent, as CSS; `var(--accent)` by default. */
  readonly tint?: string;
  /** Dims the on state a little, for a sound button whose sound is not playing right now. */
  readonly muted?: boolean;
  readonly onClick?: (event: MouseEvent<HTMLButtonElement>) => void;
  readonly preview?: PreviewState;
  readonly style?: CSSProperties;
}

export function CapsuleToggle({
  title,
  symbol,
  trailingSymbol,
  isOn,
  help,
  look = "filled",
  outlined = true,
  height = 20,
  tint,
  muted = false,
  onClick,
  preview,
  disabled = false,
  className,
  style,
  ...rest
}: CapsuleToggleProps) {
  const tactile = useTactile({ feedback: TactileFeedback.pill, disabled, preview });
  const transition = useTransition("snappy", ["background-color", "color", "box-shadow"]);
  const handlers = mergeHandlers(tactile.handlers, rest);
  const merged: CSSProperties = {
    height,
    ...(tint === undefined ? {} : { "--capsule-tint": tint }),
    ...tactile.style,
    transition: [tactile.style.transition, transition].filter(Boolean).join(", "),
    ...style,
  } as CSSProperties;
  return (
    <Tooltip text={help}>
      <button
        type="button"
        role="switch"
        aria-checked={isOn}
        aria-label={title}
        className={["kit-capsule-toggle", className].filter(Boolean).join(" ")}
        data-on={isOn}
        data-look={look}
        data-outlined={outlined}
        data-muted={muted || undefined}
        disabled={disabled}
        {...tactile.data}
        {...rest}
        {...handlers}
        onClick={onClick}
        style={merged}
      >
        {symbol && <Icon id={symbol} size={9} />}
        <span className="kit-capsule-toggle-title">{title}</span>
        {trailingSymbol && <Icon id={trailingSymbol} size={8} />}
      </button>
    </Tooltip>
  );
}
