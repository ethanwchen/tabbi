/*
 * A labeled pill button (the Focus, Study and Anki action pills, an empty
 * state's one action): 24 px tall, 12 px side padding, body-emphasis text,
 * an optional leading glyph, the surface that brightens on hover, and the
 * tactile press. `accent` colors it as the primary action on the soft
 * accent; `prominent` fills it with the accent and sets the text in the
 * panel background (the Mac's AnkiPrimaryButton and PartyPillButton's
 * prominent form); `badge` adds a count after the title (the favorite
 * deck's cards due); `height` picks 28 for a panel's one primary control.
 * `lifts` makes it grow a little on hover. A pill with no title shows the
 * glyph alone, named by its tooltip, for a narrow panel.
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
  /** Where the glyph sits; trailing for a chevron that says a list expands. */
  readonly symbolPosition?: "leading" | "trailing";
  readonly accent?: boolean;
  readonly prominent?: boolean;
  readonly badge?: number;
  readonly height?: 20 | 24 | 28;
  readonly lifts?: boolean;
  /** Dims the pill and ignores clicks while its action runs. */
  readonly busy?: boolean;
  /** The title holds text the user typed or a service sent (a deck name), which keeps its own direction. */
  readonly userText?: boolean;
  readonly onClick?: (event: MouseEvent<HTMLButtonElement>) => void;
  readonly preview?: PreviewState;
  readonly style?: CSSProperties;
}

export function Pill({
  title,
  help,
  symbol,
  symbolPosition = "leading",
  accent = false,
  prominent = false,
  badge,
  height = 24,
  lifts = false,
  busy = false,
  userText = false,
  onClick,
  preview,
  disabled = false,
  className,
  style,
  ...rest
}: PillProps) {
  const inert = disabled || busy;
  const tactile = useTactile({ feedback: TactileFeedback.pill, lifts, disabled: inert, preview });
  const transition = useTransition("snappy", ["background-color", "color", "opacity"]);
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
        disabled={inert}
        aria-label={title === "" ? help : undefined}
        aria-busy={busy || undefined}
        data-accent={accent}
        data-prominent={prominent}
        data-busy={busy || undefined}
        data-height={height}
        data-icon-only={title === "" || undefined}
        {...tactile.data}
        {...rest}
        {...handlers}
        onClick={onClick}
        style={merged}
      >
        {symbol && symbolPosition === "leading" && <Icon id={symbol} size={height === 28 ? 12 : 11} />}
        {title !== "" && <span className={userText ? "kit-pill-title kit-user-text" : "kit-pill-title"}>{title}</span>}
        {badge !== undefined && <span className="kit-pill-badge">{badge}</span>}
        {symbol && symbolPosition === "trailing" && <Icon id={symbol} size={height === 20 ? 9 : 11} />}
      </button>
    </Tooltip>
  );
}
