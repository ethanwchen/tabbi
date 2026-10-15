/** A rectangle in a top-left origin space, the core's stand-in for CGRect. */
export interface Rect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

export function rect(x: number, y: number, width: number, height: number): Rect {
  return { x, y, width, height };
}

export function maxX(r: Rect): number {
  return r.x + r.width;
}

export function maxY(r: Rect): number {
  return r.y + r.height;
}

/** `r` grown by `dx` on the left and right and `dy` on the top and bottom (negative insets, like CGRect.insetBy). */
export function insetBy(r: Rect, dx: number, dy: number): Rect {
  return { x: r.x + dx, y: r.y + dy, width: r.width - 2 * dx, height: r.height - 2 * dy };
}

/** Whether the rectangles share any area or a zero-width line inside both; touching edges don't count. */
export function intersects(a: Rect, b: Rect): boolean {
  return a.x < maxX(b) && b.x < maxX(a) && a.y < maxY(b) && b.y < maxY(a);
}
