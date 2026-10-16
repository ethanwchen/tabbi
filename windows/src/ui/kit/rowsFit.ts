/*
 * The math behind RowsThatFit, the Mac's `ViewThatFits` over row counts:
 * how many leading rows fit the height on offer, counting the header and
 * the spacing between every pair of shown items. At least one row always
 * shows, as on the Mac, where the single-row layout is the last candidate.
 */

export interface RowsThatFitInput {
  /** The height on offer, in pixels. */
  readonly available: number;
  /** Every row's height, in order. */
  readonly rowHeights: readonly number[];
  /** The gap between the header and the first row and between rows. */
  readonly spacing?: number;
  /** The header's height, 0 when there is none. */
  readonly headerHeight?: number;
}

/** The total height of the header plus the first `count` rows with `spacing` between every shown item. */
export function stackHeight({ rowHeights, spacing = 0, headerHeight = 0 }: Omit<RowsThatFitInput, "available">, count: number): number {
  const shown = Math.max(0, Math.min(count, rowHeights.length));
  const items = shown + (headerHeight > 0 ? 1 : 0);
  let total = headerHeight;
  for (let index = 0; index < shown; index++) total += rowHeights[index] ?? 0;
  return total + Math.max(0, items - 1) * spacing;
}

/** How many leading rows fit; never fewer than one when there are rows at all. */
export function rowsThatFit(input: RowsThatFitInput): number {
  const { available, rowHeights } = input;
  if (rowHeights.length === 0) return 0;
  const fits = (count: number) => stackHeight(input, count) <= available + 1e-6;
  for (let count = rowHeights.length; count > 1; count--) {
    if (fits(count)) return count;
  }
  return 1;
}
