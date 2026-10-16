import { describe, expect, it } from "vitest";
import { inlineRuns } from "../../../src/core/claudeAsk/claudeAskInline";
import { simplifyBlocks } from "../../../src/core/claudeAsk/claudeAskMarkdown";

const plain = (text: string) => ({ text, bold: false, italic: false, code: false });
const bold = (text: string) => ({ text, bold: true, italic: false, code: false });
const italic = (text: string) => ({ text, bold: false, italic: true, code: false });
const code = (text: string) => ({ text, bold: false, italic: false, code: true });

describe("inlineRuns", () => {
  it("styles bold, italic and code and keeps the rest plain", () => {
    expect(inlineRuns("Start around **0.5 s** and *double* the `wait`.")).toEqual([
      plain("Start around "),
      bold("0.5 s"),
      plain(" and "),
      italic("double"),
      plain(" the "),
      code("wait"),
      plain("."),
    ]);
  });

  it("nests bold inside italic and keeps bold code bold", () => {
    expect(inlineRuns("*a **b** c*")).toEqual([italic("a "), { text: "b", bold: true, italic: true, code: false }, italic(" c")]);
    expect(inlineRuns("**`retryWithBackoff`**")).toEqual([{ text: "retryWithBackoff", bold: true, italic: false, code: true }]);
  });

  it("keeps line breaks and spaces, as the Mac's whitespace-preserving parser does", () => {
    expect(inlineRuns("one\n• two\n\n**three**")).toEqual([plain("one\n• two\n\n"), bold("three")]);
    expect(inlineRuns(simplifyBlocks("- a\n- b"))).toEqual([plain("• a\n• b")]);
  });

  it("leaves unmatched and in-word markers alone", () => {
    expect(inlineRuns("2 * 3 and snake_case and *open")).toEqual([plain("2 * 3 and snake_case and *open")]);
    expect(inlineRuns("a ** b")).toEqual([plain("a ** b")]);
    expect(inlineRuns("un`matched")).toEqual([plain("un`matched")]);
  });

  it("shows a link's text and drops its address", () => {
    expect(inlineRuns("see [the docs](https://example.org) now")).toEqual([plain("see the docs now")]);
  });

  it("keeps backticks inside a double-backtick span and unescapes punctuation", () => {
    expect(inlineRuns("`` a`b ``")).toEqual([code("a`b")]);
    expect(inlineRuns("\\*not bold\\*")).toEqual([plain("*not bold*")]);
  });
});
