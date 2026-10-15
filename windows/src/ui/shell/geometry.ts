/*
 * The island's shape and sizes, in logical pixels, ported from the Mac's
 * NotchShape, Theme.Layout and NotchViewModel so both apps draw the same
 * silhouette: a black body hanging from the top edge, with concave flares
 * where it meets the edge and rounded bottom corners.
 */

/* The open canvas (Theme.Layout.expandedSize, the regular panel size). */
export const CANVAS = { width: 560, height: 236 } as const;

/*
 * A notchless Mac draws a virtual notch 190 pt wide; Windows uses the same
 * width and the handoff's 32 px pill height, which is also the header height
 * (NotchTabBar: max(notch height, 32)).
 */
export const VIRTUAL_NOTCH = { width: 190, height: 32 } as const;

export const RADIUS = {
  closedTop: 6,
  closedBottom: 10,
  openTop: 12,
  openBottom: 26,
} as const;

/* Hovering the closed island grows it a little, as on the Mac (Theme.Layout.hoverGrowth). */
export const HOVER_GROWTH = { width: 16, height: 4 } as const;

/* The Mac accepts a pointer within 4 pt of the shape as on it. */
export const HIT_SLOP = 4;

export interface Silhouette {
  readonly width: number;
  readonly height: number;
  readonly topRadius: number;
  readonly bottomRadius: number;
}

export const OPEN: Silhouette = {
  width: CANVAS.width,
  height: CANVAS.height,
  topRadius: RADIUS.openTop,
  bottomRadius: RADIUS.openBottom,
};

/* The closed pill: the virtual notch plus its two top flares, with no wings yet. */
export const PILL: Silhouette = {
  width: VIRTUAL_NOTCH.width + 2 * RADIUS.closedTop,
  height: VIRTUAL_NOTCH.height,
  topRadius: RADIUS.closedTop,
  bottomRadius: RADIUS.closedBottom,
};

export const PILL_HOVERED: Silhouette = {
  ...PILL,
  width: PILL.width + HOVER_GROWTH.width,
  height: PILL.height + HOVER_GROWTH.height,
};

/* Nothing drawn: the pill collapsed into the top edge, so opening grows down from there. */
export const HIDDEN: Silhouette = { ...PILL, height: 0 };

/*
 * The NotchShape path, centered in the canvas. The flares and corners are
 * quadratic curves, and both radii shrink to fit a small shape, exactly as the
 * Swift path clamps them.
 */
export function notchPath(shape: Silhouette, canvasWidth: number = CANVAS.width): string {
  const w = Math.max(0, shape.width);
  const h = Math.max(0, shape.height);
  if (w === 0 || h === 0) return "";
  const t = Math.max(0, Math.min(shape.topRadius, w / 4, h / 2));
  const b = Math.max(0, Math.min(shape.bottomRadius, (w - 2 * t) / 2, h - t));
  const x = (canvasWidth - w) / 2;
  const n = (v: number) => Number(v.toFixed(3));
  const p = (px: number, py: number) => `${n(x + px)} ${n(py)}`;
  return [
    `M ${p(0, 0)}`,
    `Q ${p(t, 0)} ${p(t, t)}`,
    `L ${p(t, h - b)}`,
    `Q ${p(t, h)} ${p(t + b, h)}`,
    `L ${p(w - t - b, h)}`,
    `Q ${p(w - t, h)} ${p(w - t, h - b)}`,
    `L ${p(w - t, t)}`,
    `Q ${p(w - t, 0)} ${p(w, 0)}`,
    "Z",
  ].join(" ");
}

export interface HitRect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

/*
 * The window region for each hit shape, relative to the island window. The
 * pill's area covers its hovered size plus the Mac's 4 px slop, so growing on
 * hover never clips; the open panel uses the whole canvas.
 */
export function hitRect(shape: "open" | "pill"): HitRect {
  if (shape === "open") return { x: 0, y: 0, width: CANVAS.width, height: CANVAS.height };
  const width = PILL_HOVERED.width + 2 * HIT_SLOP;
  return { x: (CANVAS.width - width) / 2, y: 0, width, height: PILL_HOVERED.height + HIT_SLOP };
}
