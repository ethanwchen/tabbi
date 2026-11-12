import { describe, expect, it } from "vitest";
import { codeFieldLayout, codeFieldMinWidth, codeFieldWidth } from "../../../src/modules/party/PartyComponents";
import { overflows } from "../../../src/ui/kit/ViewsThatFit";

/*
 * The friend and party code fields never cut their placeholder: Paste
 * shrinks to its icon first, then the field's symbol goes, and the field
 * never gets narrower than that last layout needs. The render check
 * (tests/snapshots/partyLayout.spec.ts) holds the drawn fields to it in
 * every language and panel size.
 */
describe("code field layout", () => {
  const paste = 38;
  it("keeps the word Paste while the placeholder fits beside it", () => {
    expect(codeFieldLayout(80, codeFieldWidth(80, "full", paste), paste)).toBe("full");
  });
  it("shrinks Paste to its icon before the placeholder is cut", () => {
    expect(codeFieldLayout(80, codeFieldWidth(80, "full", paste) - 1, paste)).toBe("pasteIcon");
  });
  it("drops the symbol last", () => {
    expect(codeFieldLayout(80, codeFieldWidth(80, "pasteIcon", paste) - 1, paste)).toBe("noSymbol");
  });
  it("is never narrower than the placeholder whole without the symbol", () => {
    expect(codeFieldMinWidth(80)).toBeGreaterThanOrEqual(codeFieldWidth(80, "noSymbol"));
    expect(codeFieldWidth(80, "noSymbol")).toBeLessThan(codeFieldWidth(80, "pasteIcon", paste));
  });
  it("draws the roomiest layout before anything is measured", () => {
    expect(codeFieldLayout(0, 0, paste)).toBe("full");
  });
  it("counts a row as overflowing only past a pixel of rounding", () => {
    expect(overflows(101, 100)).toBe(false);
    expect(overflows(102, 100)).toBe(true);
  });
});
