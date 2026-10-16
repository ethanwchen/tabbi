/**
 * Port of RowViewport: the tallest height up to `available` that holds a
 * whole number of equally tall rows, so a clipped list ends on a whole row
 * and its edge fade reads as "more below". A space shorter than one row is
 * kept (never negative), so a squeezed list still shows what it can.
 */
export function rowViewportHeight(available: number, rowHeight: number): number {
  if (!(rowHeight > 0) || available < rowHeight) return Math.max(available, 0);
  return Math.floor(available / rowHeight) * rowHeight;
}
