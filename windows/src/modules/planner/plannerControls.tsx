/*
 * The Today panel's own small controls, ports of the shared views in
 * DayPlanView.swift and PlannerPanel.swift: the capsule call to action
 * (filled with the accent when prominent, tinted otherwise), the quiet text
 * button for Cancel, the round glyph button rows use on hover, and the
 * message block for empty and error states.
 */

import type { CSSProperties, ReactNode } from "react";
import { TactileFeedback } from "../../core/motion/tactileFeedback";
import { Icon } from "../../ui/kit/Icon";
import { mergeHandlers, useTactile } from "../../ui/kit/tactile";
import { Tooltip } from "../../ui/kit/Tooltip";

export interface PlannerPillButtonProps {
  readonly title: string;
  readonly symbol?: string;
  readonly isProminent?: boolean;
  readonly height?: number;
  readonly help: string;
  readonly disabled?: boolean;
  readonly onClick: () => void;
  readonly className?: string;
}

/** Port of PlannerPillButton. */
export function PlannerPillButton({ title, symbol, isProminent = false, height = 22, help, disabled = false, onClick, className }: PlannerPillButtonProps) {
  const tactile = useTactile({ feedback: TactileFeedback.pill, disabled });
  const handlers = mergeHandlers(tactile.handlers, {});
  return (
    <Tooltip text={help}>
      <button
        type="button"
        className={["planner-pill", className].filter(Boolean).join(" ")}
        data-prominent={isProminent}
        disabled={disabled}
        aria-label={title}
        style={{ ...tactile.style, height } as CSSProperties}
        {...tactile.data}
        {...handlers}
        onClick={onClick}
      >
        {symbol !== undefined && <Icon id={symbol} size={11} />}
        <span>{title}</span>
      </button>
    </Tooltip>
  );
}

export interface PlannerTextButtonProps {
  readonly title: string;
  readonly help: string;
  readonly onClick: () => void;
}

/** Port of PlannerTextButton: a quiet text button for secondary actions such as Cancel. */
export function PlannerTextButton({ title, help, onClick }: PlannerTextButtonProps) {
  return (
    <Tooltip text={help}>
      <button type="button" className="planner-text-button" onClick={onClick}>
        {title}
      </button>
    </Tooltip>
  );
}

export interface PlannerGlyphButtonProps {
  readonly symbol: string;
  /** The hover color, as CSS; the accent by default. */
  readonly tint?: string;
  /** Shows the tint at rest too, for the positive action. */
  readonly isTinted?: boolean;
  readonly size?: number;
  readonly glyphSize?: number;
  readonly help: string;
  readonly onClick: () => void;
  readonly className?: string;
  readonly style?: CSSProperties;
}

/** A small round glyph button with a soft tinted hover (delete, focus, add and dismiss on rows). */
export function PlannerGlyphButton({ symbol, tint = "var(--accent)", isTinted = false, size = 20, glyphSize = 10, help, onClick, className, style }: PlannerGlyphButtonProps) {
  return (
    <Tooltip text={help}>
      <button
        type="button"
        className={["planner-glyph-button", className].filter(Boolean).join(" ")}
        data-tinted={isTinted}
        aria-label={help}
        style={{ "--glyph-tint": tint, width: size, height: size, ...style } as CSSProperties}
        onClick={(event) => {
          event.stopPropagation();
          onClick();
        }}
      >
        <Icon id={symbol} size={glyphSize} />
      </button>
    </Tooltip>
  );
}

export interface PlannerMessageProps {
  readonly symbol: string;
  /** The glyph color, as CSS. */
  readonly tint: string;
  readonly title: string;
  readonly detail: string;
  readonly action?: ReactNode;
}

/** Port of PlannerMessage: icon, title and detail in the checklist area, with an optional action below. */
export function PlannerMessage({ symbol, tint, title, detail, action }: PlannerMessageProps) {
  return (
    <div className="planner-message">
      <div className="planner-message-row">
        <span className="planner-message-icon" style={{ color: tint }}>
          <Icon id={symbol} size={20} />
        </span>
        <div className="planner-message-text">
          <div className="planner-message-title">{title}</div>
          <div className="planner-message-detail">{detail}</div>
        </div>
      </div>
      {action !== undefined && action !== null && <div className="planner-message-action">{action}</div>}
    </div>
  );
}
