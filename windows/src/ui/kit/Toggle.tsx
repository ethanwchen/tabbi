/*
 * A switch in Tabbi's look, the Settings window's `Toggle`: a 26 by 16
 * capsule, surfaceHover off and the accent on, with a 12 px knob that
 * slides along the snappy spring and sinks a little while pressed. It
 * mirrors in a right-to-left language, so "on" is toward the reading end.
 */

import type { CSSProperties } from "react";
import { TactileFeedback } from "../../core/motion/tactileFeedback";
import { useTransition } from "./context";
import { mergeHandlers, useTactile, type PreviewState } from "./tactile";
import { Tooltip } from "./Tooltip";

export interface ToggleProps {
  readonly isOn: boolean;
  readonly onChange: (isOn: boolean) => void;
  /** The accessible name. */
  readonly label: string;
  /** The tooltip; the label when omitted. */
  readonly help?: string;
  readonly disabled?: boolean;
  readonly preview?: PreviewState;
  readonly className?: string;
}

export function Toggle({ isOn, onChange, label, help, disabled = false, preview, className }: ToggleProps) {
  const tactile = useTactile({ feedback: TactileFeedback.pill, disabled, preview });
  const transition = useTransition("snappy", ["background-color", "inset-inline-start", "box-shadow"]);
  const handlers = mergeHandlers<HTMLButtonElement>(tactile.handlers, {});
  const style: CSSProperties = { ...tactile.style };
  return (
    <Tooltip text={help ?? label}>
      <button
        type="button"
        role="switch"
        aria-checked={isOn}
        aria-label={label}
        className={["kit-toggle", className].filter(Boolean).join(" ")}
        data-on={isOn}
        disabled={disabled}
        {...tactile.data}
        {...handlers}
        onClick={() => onChange(!isOn)}
        style={style}
      >
        <span className="kit-toggle-track" style={{ transition }}>
          <span className="kit-toggle-knob" style={{ transition }} />
        </span>
      </button>
    </Tooltip>
  );
}
