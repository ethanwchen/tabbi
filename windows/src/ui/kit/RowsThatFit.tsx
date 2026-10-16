/*
 * The Mac's `RowsThatFit`: a short top-down list that shows as many of its
 * leading rows as fit the height it is offered, so a card designed for the
 * Regular panel drops its last rows on a shorter one instead of being
 * clipped. With room for every row it is a plain stack. An optional header
 * sits above the rows and is told how many rows show, so it can offer a way
 * to the rest ("All N"). Rows are measured in a layout pass before paint,
 * and again whenever the container or the data changes.
 */

import { useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { rowsThatFit } from "./rowsFit";

export interface RowsThatFitProps<T> {
  readonly data: readonly T[];
  readonly keyOf: (item: T, index: number) => string | number;
  readonly spacing?: number;
  readonly header?: (shown: number) => ReactNode;
  readonly row: (item: T, index: number) => ReactNode;
  readonly className?: string;
  readonly style?: CSSProperties;
}

export function RowsThatFit<T>({ data, keyOf, spacing = 0, header, row, className, style }: RowsThatFitProps<T>) {
  const container = useRef<HTMLDivElement>(null);
  /* null means "render every row, then measure". */
  const [shown, setShown] = useState<number | null>(null);
  const [epoch, setEpoch] = useState(0);
  /* New data or a resized container re-measures: the state follows the props on the render that changes them. */
  const [measured, setMeasured] = useState<{ data: readonly T[]; epoch: number }>({ data, epoch });
  if (measured.data !== data || measured.epoch !== epoch) {
    setMeasured({ data, epoch });
    setShown(null);
  }

  useLayoutEffect(() => {
    if (shown !== null) return;
    const element = container.current;
    if (!element) return;
    const headerElement = element.querySelector<HTMLElement>(":scope > .kit-rows-header");
    const rows = [...element.querySelectorAll<HTMLElement>(":scope > .kit-rows-row")];
    const count = rowsThatFit({
      available: element.clientHeight,
      rowHeights: rows.map((r) => r.getBoundingClientRect().height),
      spacing,
      headerHeight: headerElement ? headerElement.getBoundingClientRect().height : 0,
    });
    setShown(count);
  }, [shown, spacing]);

  useLayoutEffect(() => {
    const element = container.current;
    if (!element || typeof ResizeObserver === "undefined") return;
    let last = element.clientHeight;
    const observer = new ResizeObserver(() => {
      if (element.clientHeight !== last) {
        last = element.clientHeight;
        setEpoch((e) => e + 1);
      }
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const visible = shown ?? data.length;
  return (
    <div ref={container} className={["kit-rows", className].filter(Boolean).join(" ")} style={{ gap: spacing, ...style }}>
      {header && <div className="kit-rows-header">{header(visible)}</div>}
      {data.map((item, index) => (
        <div key={keyOf(item, index)} className="kit-rows-row" hidden={index >= visible}>
          {row(item, index)}
        </div>
      ))}
    </div>
  );
}
