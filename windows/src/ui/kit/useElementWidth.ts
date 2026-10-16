/*
 * The width of an element, kept current through a ResizeObserver, for a
 * layout that picks what fits (the Mac's ViewThatFits): a card that drops
 * its labels on a narrow panel, a heatmap that shows the latest days that
 * fit. The first render reports 0 until the element is measured, so a
 * layout should treat 0 as "not yet known" and draw its roomiest form.
 */

import { useLayoutEffect, useRef, useState, type RefObject } from "react";

export function useElementWidth<T extends HTMLElement>(): [RefObject<T | null>, number] {
  const element = useRef<T>(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const target = element.current;
    if (!target) return;
    const measure = () => setWidth((previous) => (Math.abs(previous - target.clientWidth) < 0.5 ? previous : target.clientWidth));
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(target);
    return () => observer.disconnect();
  }, []);
  return [element, width];
}
