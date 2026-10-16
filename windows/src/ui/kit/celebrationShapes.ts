/*
 * The particle shapes of CelebrationView.swift's `CelebrationShapes`, each
 * a path one unit across centered on the origin, so a particle only needs
 * a scale: a confetti strip, a four-pointed sparkle, a heart and a paw
 * print. As SVG path data for the paw loader and the sparkle badges, and as
 * `Path2D` for the celebration canvas.
 */

import type { CelebrationStyle } from "../../core/motion/celebration";

/** A small rounded strip, twice as long as it is wide. */
export const CONFETTI_PATH =
  "M-0.38 -0.25 H0.38 A0.12 0.12 0 0 1 0.5 -0.13 V0.13 A0.12 0.12 0 0 1 0.38 0.25 H-0.38 A0.12 0.12 0 0 1 -0.5 0.13 V-0.13 A0.12 0.12 0 0 1 -0.38 -0.25 Z";

/** A four-pointed star with concave sides. */
export const SPARKLE_PATH = "M0 -0.5 Q0 0 0.5 0 Q0 0 0 0.5 Q0 0 -0.5 0 Q0 0 0 -0.5 Z";

/** Two lobes meeting in a point at the bottom. */
export const HEART_PATH =
  "M0 0.42 C-0.18 0.28 -0.5 0.1 -0.5 -0.12 A0.25 0.25 0 0 1 0 -0.2 A0.25 0.25 0 0 1 0.5 -0.12 C0.5 0.1 0.18 0.28 0 0.42 Z";

function ellipse(cx: number, cy: number, rx: number, ry: number): string {
  return `M${cx - rx} ${cy} a${rx} ${ry} 0 1 0 ${rx * 2} 0 a${rx} ${ry} 0 1 0 ${-rx * 2} 0 Z`;
}

/** A main pad with four toes fanned above it. */
export const PAW_PRINT_PATH = [
  ellipse(0, 0.19, 0.26, 0.21),
  ellipse(-0.36, -0.12, 0.1, 0.12),
  ellipse(-0.13, -0.34, 0.1, 0.12),
  ellipse(0.13, -0.34, 0.1, 0.12),
  ellipse(0.36, -0.12, 0.1, 0.12),
].join(" ");

export function unitPath(style: CelebrationStyle): string {
  switch (style) {
    case "confetti":
      return CONFETTI_PATH;
    case "sparkles":
      return SPARKLE_PATH;
    case "hearts":
      return HEART_PATH;
    case "pawPrints":
      return PAW_PRINT_PATH;
  }
}

const paths = new Map<CelebrationStyle, Path2D>();

/** The unit shape for `style` as a `Path2D`, built once. */
export function unitPath2D(style: CelebrationStyle): Path2D {
  let path = paths.get(style);
  if (!path) {
    path = new Path2D(unitPath(style));
    paths.set(style, path);
  }
  return path;
}
