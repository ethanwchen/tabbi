/*
 * The size of an element, the web's stand-in for a GeometryReader: measured
 * before paint and again whenever it changes, so a chart can size its cells
 * to the room it gets without drawing twice.
 */

import { useLayoutEffect, useState, type RefObject } from "react";

export interface ElementSize {
  readonly width: number;
  readonly height: number;
}

export function useElementSize(ref: RefObject<HTMLElement | null>): ElementSize {
  const [size, setSize] = useState<ElementSize>({ width: 0, height: 0 });
  useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;
    const measure = () => {
      const next = { width: element.clientWidth, height: element.clientHeight };
      setSize((current) => (current.width === next.width && current.height === next.height ? current : next));
    };
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, [ref]);
  return size;
}
