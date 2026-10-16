/*
 * The `.help(...)` tooltip of every control: a small Tabbi-styled label that
 * appears under the pointer's control after a short rest and goes away when
 * the pointer leaves or the control is pressed. It wraps its control in a
 * box-less `display: contents` span, so pointer and focus events bubble to
 * it and the control stays one DOM node; the tooltip itself is portaled to
 * the body and positioned from the control's box. With `nativeTooltips` on
 * in the kit environment it sets the browser's `title` instead. An empty
 * text draws nothing.
 */

import { useCallback, useEffect, useLayoutEffect, useRef, useState, type FocusEvent, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { useKit } from "./context";

/** How long the pointer rests before the tooltip shows, in milliseconds. */
export const TOOLTIP_DELAY = 600;
/** The gap between the control and its tooltip. */
const GAP = 6;
/** Keeps the tooltip inside the viewport. */
const MARGIN = 8;

export interface TooltipProps {
  readonly text: string;
  /** The one control the tooltip explains. */
  readonly children: ReactNode;
  /** Shows the tooltip at once, for reviews and tests. */
  readonly open?: boolean;
  /** Where the tooltip sits relative to the control. */
  readonly placement?: "below" | "above";
}

interface Position {
  readonly left: number;
  readonly top: number;
}

export function Tooltip({ text, children, open = false, placement = "below" }: TooltipProps) {
  const { nativeTooltips } = useKit();
  const [shown, setShown] = useState(false);
  const [position, setPosition] = useState<Position | null>(null);
  const timer = useRef<number | undefined>(undefined);
  const anchor = useRef<HTMLSpanElement>(null);
  const bubble = useRef<HTMLDivElement>(null);

  const cancel = useCallback(() => {
    if (timer.current !== undefined) window.clearTimeout(timer.current);
    timer.current = undefined;
  }, []);

  const hide = useCallback(() => {
    cancel();
    setShown(false);
    setPosition(null);
  }, [cancel]);

  const schedule = useCallback(() => {
    cancel();
    timer.current = window.setTimeout(() => setShown(true), TOOLTIP_DELAY);
  }, [cancel]);

  useEffect(() => cancel, [cancel]);

  const visible = text.length > 0 && (open || shown);

  useLayoutEffect(() => {
    if (!visible) return;
    const control = anchor.current?.firstElementChild;
    const tip = bubble.current;
    if (!control || !tip) return;
    /* Page coordinates, so a tooltip in a tall page (the gallery) sits by its control wherever the page is scrolled. */
    const a = control.getBoundingClientRect();
    const t = tip.getBoundingClientRect();
    const width = window.innerWidth;
    const height = window.innerHeight;
    let left = a.left + a.width / 2 - t.width / 2;
    left = Math.max(MARGIN, Math.min(left, width - t.width - MARGIN));
    const below = a.bottom + GAP;
    const above = a.top - GAP - t.height;
    let top = placement === "below" ? below : above;
    /* Flips only for a control in view; one scrolled past the fold (a long page) keeps its side. */
    const inView = a.bottom > 0 && a.top < height;
    if (inView && placement === "below" && top + t.height > height - MARGIN && above >= MARGIN) top = above;
    if (inView && placement === "above" && top < MARGIN) top = below;
    const next = { left: Math.round(left + window.scrollX), top: Math.round(top + window.scrollY) };
    setPosition((current) => (current && current.left === next.left && current.top === next.top ? current : next));
  }, [visible, placement, text]);

  if (text.length === 0) return children;

  /* The browser's own tooltip: a title on the wrapper reaches the control's box the same way. */
  if (nativeTooltips) {
    return (
      <span className="kit-tooltip-anchor" title={text}>
        {children}
      </span>
    );
  }

  const onFocus = (event: FocusEvent<HTMLElement>) => {
    if (event.target instanceof HTMLElement && event.target.matches(":focus-visible")) schedule();
  };

  return (
    <>
      <span ref={anchor} className="kit-tooltip-anchor" onPointerEnter={schedule} onPointerLeave={hide} onPointerDown={hide} onFocus={onFocus} onBlur={hide}>
        {children}
      </span>
      {visible &&
        createPortal(
          <div
            ref={bubble}
            role="tooltip"
            className="kit-tooltip"
            data-visible={position !== null}
            style={position ? { left: position.left, top: position.top } : { left: 0, top: 0 }}
          >
            {text}
          </div>,
          document.body,
        )}
    </>
  );
}
