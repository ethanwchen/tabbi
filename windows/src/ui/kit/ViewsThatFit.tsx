/*
 * The Mac's horizontal `ViewThatFits` over a few layouts of one row: draws
 * the first variant whose content fits the width the row gets, roomiest
 * first, and the last variant whatever the width. It steps down one
 * variant at a time before paint while the content overflows, and starts
 * again from the roomiest when the row's width, the content (`fitKey`) or
 * the page's fonts change. Variants keep their items at their natural
 * width (`flex: none`, no wrapping), so an item that does not fit shows as
 * overflow here instead of squeezing, wrapping or cutting its text.
 */

import { useLayoutEffect, useRef, useState, type ReactNode } from "react";

export interface ViewsThatFitProps {
  /** How many variants there are; `render` gets 0 (roomiest) to count - 1. */
  readonly count: number;
  /** Changes whenever the content does, so the row fits again. */
  readonly fitKey: string;
  readonly className?: string;
  readonly render: (index: number) => ReactNode;
}

/** Whether a row's content is wider than the row (a pixel of rounding is fine). */
export function overflows(scrollWidth: number, clientWidth: number): boolean {
  return scrollWidth > clientWidth + 1;
}

export function ViewsThatFit({ count, fitKey, className, render }: ViewsThatFitProps) {
  const row = useRef<HTMLDivElement>(null);
  const [fitted, setFitted] = useState({ key: fitKey, width: -1, index: 0 });
  if (fitted.key !== fitKey) setFitted({ key: fitKey, width: -1, index: 0 });
  const index = Math.min(fitted.index, Math.max(count - 1, 0));

  useLayoutEffect(() => {
    const element = row.current;
    if (!element || index >= count - 1) return;
    if (overflows(element.scrollWidth, element.clientWidth)) {
      setFitted((current) => ({ ...current, index: current.index + 1 }));
    }
  }, [index, fitKey, count, fitted.width]);

  useLayoutEffect(() => {
    const element = row.current;
    if (!element) return;
    const refit = () => {
      const width = element.clientWidth;
      setFitted((current) => (Math.abs(current.width - width) < 0.5 ? current : { ...current, width, index: 0 }));
    };
    refit();
    let cancelled = false;
    if (typeof document !== "undefined" && "fonts" in document) {
      void document.fonts.ready.then(() => {
        if (!cancelled) setFitted((current) => ({ ...current, index: 0, width: element.clientWidth }));
      });
    }
    if (typeof ResizeObserver === "undefined") return () => void (cancelled = true);
    const observer = new ResizeObserver(refit);
    observer.observe(element);
    return () => {
      cancelled = true;
      observer.disconnect();
    };
  }, []);

  return (
    <div ref={row} className={["kit-views-fit", className].filter(Boolean).join(" ")} data-fit-index={index}>
      {render(index)}
    </div>
  );
}
