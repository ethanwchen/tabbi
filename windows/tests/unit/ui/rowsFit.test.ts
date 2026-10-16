import { describe, expect, it } from "vitest";
import { rowsThatFit, stackHeight } from "../../../src/ui/kit/rowsFit";

describe("rowsThatFit (RowsThatFit)", () => {
  const rows = [20, 20, 20, 20, 20];

  it("shows every row when there is room", () => {
    expect(rowsThatFit({ available: 200, rowHeights: rows, spacing: 4 })).toBe(5);
    // Exactly the stack's height still fits.
    expect(rowsThatFit({ available: 5 * 20 + 4 * 4, rowHeights: rows, spacing: 4 })).toBe(5);
  });

  it("drops the last rows that do not fit, spacing included", () => {
    // Three rows take 68, four take 92.
    expect(rowsThatFit({ available: 91, rowHeights: rows, spacing: 4 })).toBe(3);
    expect(rowsThatFit({ available: 92, rowHeights: rows, spacing: 4 })).toBe(4);
  });

  it("counts the header and the gap under it", () => {
    expect(stackHeight({ rowHeights: rows, spacing: 4, headerHeight: 13 }, 2)).toBe(13 + 4 + 20 + 4 + 20);
    expect(rowsThatFit({ available: 56, rowHeights: rows, spacing: 4, headerHeight: 13 })).toBe(1);
    expect(rowsThatFit({ available: 61, rowHeights: rows, spacing: 4, headerHeight: 13 })).toBe(2);
  });

  it("always shows one row, and none for an empty list", () => {
    expect(rowsThatFit({ available: 5, rowHeights: rows })).toBe(1);
    expect(rowsThatFit({ available: 500, rowHeights: [] })).toBe(0);
  });

  it("takes uneven rows in order", () => {
    expect(rowsThatFit({ available: 50, rowHeights: [30, 10, 10, 10] })).toBe(3);
    expect(rowsThatFit({ available: 50, rowHeights: [10, 30, 10, 10] })).toBe(3);
  });
});
