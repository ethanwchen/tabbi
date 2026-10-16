/*
 * A rounded card on the panel background, the Mac's `Card`: the theme's
 * surface with a hairline stroke and a 10 px corner, padded 12 px, or a
 * frosted glass pane (the painted GlassSheen: a top-lit fill, a glint near
 * the top-leading corner and a lit rim) when the theme's surfaces are glass.
 * kit.css draws both from `data-surfaces` on the themed root.
 */

import type { CSSProperties, HTMLAttributes, ReactNode } from "react";
import { Spacing } from "./tokens";

export interface CardProps extends HTMLAttributes<HTMLDivElement> {
  readonly padding?: number;
  readonly children?: ReactNode;
}

export function Card({ padding = Spacing.m, children, className, style, ...rest }: CardProps) {
  const merged: CSSProperties = { padding, ...style };
  return (
    <div className={["kit-card", className].filter(Boolean).join(" ")} style={merged} {...rest}>
      {children}
    </div>
  );
}
