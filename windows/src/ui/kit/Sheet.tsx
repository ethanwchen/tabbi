/*
 * A sheet in Tabbi's look, the Settings window's `.sheet(...)`: a card over
 * a dimmed backdrop inside the nearest positioned ancestor (the Settings
 * window), with a title, the sheet's content and a row of buttons at the
 * end. Esc and a click on the backdrop cancel. It is only ever one at a
 * time, so a sheet handing over to another closes first.
 */

import { useEffect, type CSSProperties, type ReactNode } from "react";
import { useTransition } from "./context";

export interface SheetProps {
  readonly title?: string;
  /** One or two lines under the title. */
  readonly intro?: string;
  /** A badge above the title: a symbol in a tinted square. */
  readonly badge?: ReactNode;
  readonly children?: ReactNode;
  /** The row at the end, usually Pills; the primary one last. */
  readonly actions?: ReactNode;
  /** Called on Esc and on a click outside the card. */
  readonly onCancel: () => void;
  readonly width?: number;
  /** The accessible name when there is no title. */
  readonly label?: string;
  readonly className?: string;
}

export function Sheet({ title, intro, badge, children, actions, onCancel, width = 520, label, className }: SheetProps) {
  const transition = useTransition("content", ["transform", "opacity"]);
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.stopPropagation();
        onCancel();
      }
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [onCancel]);
  return (
    <div className="kit-sheet-backdrop" onClick={onCancel} role="presentation">
      <div
        className={["kit-sheet", "kit-card", className].filter(Boolean).join(" ")}
        role="dialog"
        aria-modal="true"
        aria-label={title ?? label}
        style={{ width, transition } as CSSProperties}
        onClick={(event) => event.stopPropagation()}
      >
        {(badge !== undefined || title !== undefined || intro !== undefined) && (
          <div className="kit-sheet-head">
            {badge !== undefined && <div className="kit-sheet-badge">{badge}</div>}
            {title !== undefined && <h2 className="kit-sheet-title">{title}</h2>}
            {intro !== undefined && <p className="kit-sheet-intro">{intro}</p>}
          </div>
        )}
        {children !== undefined && children !== null && <div className="kit-sheet-body">{children}</div>}
        {actions !== undefined && actions !== null && <div className="kit-sheet-actions">{actions}</div>}
      </div>
    </div>
  );
}
