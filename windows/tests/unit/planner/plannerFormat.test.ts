import { describe, expect, it } from "vitest";
import { blockRange, formatDate } from "../../../src/modules/planner/plannerFormat";
import { candidateThatFits } from "../../../src/ui/kit/TextThatFits";

/* Saturday 2026-10-10 12:00 UTC. */
const SATURDAY = 1_791_633_600;

describe("plannerFormat", () => {
  it("writes a weekday with its day the Mac's way in English, weekday first", () => {
    expect(formatDate(SATURDAY, { weekday: "short", day: "numeric" }, "en", "UTC")).toBe("Sat 10");
    expect(formatDate(SATURDAY, { weekday: "short", month: "short", day: "numeric" }, "en", "UTC")).toBe("Sat, Oct 10");
  });

  it("leaves other languages to Intl", () => {
    expect(formatDate(SATURDAY, { weekday: "short", day: "numeric" }, "de", "UTC")).toBe("Sa., 10.");
    expect(formatDate(SATURDAY, { weekday: "short", day: "numeric" }, "ja", "UTC")).toBe("10日(土)");
  });

  it("writes a block's range without AM or PM", () => {
    expect(blockRange({ start: SATURDAY, end: SATURDAY + 45 * 60 }, "en", "UTC")).toBe("12:00-12:45");
    expect(blockRange({ start: SATURDAY, end: SATURDAY + 45 * 60 }, "de", "UTC")).toBe("12:00-12:45");
  });
});

describe("TextThatFits", () => {
  it("picks the first wording that fits and the last one otherwise", () => {
    expect(candidateThatFits([120, 60, 30], 200)).toBe(0);
    expect(candidateThatFits([120, 60, 30], 80)).toBe(1);
    expect(candidateThatFits([120, 60, 30], 10)).toBe(2);
    expect(candidateThatFits([], 10)).toBe(0);
  });
});
