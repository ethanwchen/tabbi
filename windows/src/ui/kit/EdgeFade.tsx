/*
 * The Mac's `.edgeFade(_:)`: a list cut off by its frame fades out over
 * `length` (16 px, Theme.Spacing.l, by default; the Mac's default is 12)
 * at the edge where more rows hide, instead of ending in a hard clip
 * through a row. It wraps the clipped content and masks it, so the content
 * keeps its own scrolling. `edges` picks top, bottom or both; the list
 * inside keeps a matching margin so its last row can scroll clear. The
 * inline edges (`start`, `end`) follow the element's reading direction.
 */

import { useLayoutEffect, useRef, useState, type CSSProperties, type HTMLAttributes, type ReactNode } from "react";
import { Spacing } from "./tokens";

export type FadeEdge = "top" | "bottom" | "both" | "start" | "end" | "horizontal";

export interface EdgeFadeProps extends HTMLAttributes<HTMLDivElement> {
  readonly edge?: FadeEdge;
  readonly length?: number;
  readonly children?: ReactNode;
}

/** The CSS mask for `edge` over `length` pixels, with `start` and `end` resolved for `direction`. */
export function edgeFadeMask(edge: FadeEdge, length: number, direction: "ltr" | "rtl" = "ltr"): string {
  const px = `${length}px`;
  const toEnd = direction === "rtl" ? "to left" : "to right";
  switch (edge) {
    case "top":
      return `linear-gradient(to bottom, transparent, black ${px})`;
    case "bottom":
      return `linear-gradient(to bottom, black calc(100% - ${px}), transparent)`;
    case "both":
      return `linear-gradient(to bottom, transparent, black ${px}, black calc(100% - ${px}), transparent)`;
    case "start":
      return `linear-gradient(${toEnd}, transparent, black ${px})`;
    case "end":
      return `linear-gradient(${toEnd}, black calc(100% - ${px}), transparent)`;
    case "horizontal":
      return `linear-gradient(${toEnd}, transparent, black ${px}, black calc(100% - ${px}), transparent)`;
  }
}

export function EdgeFade({ edge = "bottom", length = Spacing.l, children, className, style, ...rest }: EdgeFadeProps) {
  const element = useRef<HTMLDivElement>(null);
  const [direction, setDirection] = useState<"ltr" | "rtl">("ltr");
  useLayoutEffect(() => {
    if (!element.current) return;
    setDirection(getComputedStyle(element.current).direction === "rtl" ? "rtl" : "ltr");
  }, []);
  const mask = edgeFadeMask(edge, length, direction);
  const merged: CSSProperties = { WebkitMaskImage: mask, maskImage: mask, ...style };
  return (
    <div ref={element} className={["kit-edge-fade", className].filter(Boolean).join(" ")} data-edge={edge} style={merged} {...rest}>
      {children}
    </div>
  );
}
