import { afterEach, describe, expect, it } from "vitest";
import { dayRange } from "../../src/core/formatting/dateRangeFormat";
import {
  CARD_UNIT,
  durationCountdown,
  durationMinutes,
  durationProgress,
  durationQuantity,
  durationSeconds,
  MINUTE_UNIT,
} from "../../src/core/formatting/durationFormat";
import { LANGUAGES } from "../../src/core/localization/languages";
import { resetLanguage } from "../../src/core/localization/lookup";
import { switchLanguage } from "../support/catalogs";
import { loadFixture } from "../support/fixtures";

/*
 * Replays shared/fixtures/formatting (written by FormattingGoldenTests on the
 * Mac): DurationFormat and DateRangeFormat in all twelve shipped languages.
 * The Mac wrote the non-English durations through a mirror that fills the
 * same catalog keys from each language's compiled strings with
 * String(format:locale:), so each language's durations are replayed here
 * with that language's real catalog installed into `tr`.
 */

interface LanguageEntry {
  language: string;
  locale: string;
  bcp47: string;
}

interface DurationOutputs {
  language: string;
  minutes: string[];
  seconds: string[];
  countdown: string[];
  progress: string[];
  quantities: string[];
}

interface RangeCase {
  name: string;
  timeZone: string;
  first: number;
  last: number;
}

interface FormattingFile {
  schema: string;
  version: number;
  constants: { minuteUnit: string; cardUnit: string; sourceLanguage: string };
  languages: LanguageEntry[];
  durations: {
    inputs: {
      minutes: number[];
      seconds: number[];
      countdownMinutes: number[];
      progress: { done: number; total: number }[];
      quantities: { value: number; unit: string }[];
    };
    outputs: DurationOutputs[];
  };
  dateRanges: { cases: RangeCase[]; outputs: { language: string; days: string[] }[] };
}

const golden = loadFixture<FormattingFile>("formatting/formatting.json");
const inputs = golden.durations.inputs;

afterEach(resetLanguage);

function languageEntry(language: string): LanguageEntry {
  const entry = golden.languages.find((candidate) => candidate.language === language);
  if (!entry) throw new Error(`no language entry for ${language}`);
  return entry;
}

describe("formatting golden fixture", () => {
  it("has the expected header and constants", () => {
    expect(golden.schema).toBe("tabbi.formatting.golden");
    expect(golden.version).toBe(1);
    expect(golden.constants).toEqual({ minuteUnit: MINUTE_UNIT, cardUnit: CARD_UNIT, sourceLanguage: "en" });
  });

  it("covers every shipped language", () => {
    expect(golden.languages.map((entry) => entry.language)).toEqual([...LANGUAGES]);
    expect(golden.durations.outputs.map((entry) => entry.language)).toEqual([...LANGUAGES]);
    expect(golden.dateRanges.outputs.map((entry) => entry.language)).toEqual([...LANGUAGES]);
  });

  describe.each(golden.durations.outputs)("DurationFormat in $language", (expected) => {
    const { bcp47 } = languageEntry(expected.language);

    it("writes minutes", () => {
      switchLanguage(expected.language);
      expect(inputs.minutes.map((value) => durationMinutes(value))).toEqual(expected.minutes);
    });

    it("writes seconds", () => {
      switchLanguage(expected.language);
      expect(inputs.seconds.map((value) => durationSeconds(value))).toEqual(expected.seconds);
    });

    it("counts down", () => {
      switchLanguage(expected.language);
      expect(inputs.countdownMinutes.map((value) => durationCountdown(value))).toEqual(expected.countdown);
    });

    it("writes progress", () => {
      switchLanguage(expected.language);
      expect(inputs.progress.map(({ done, total }) => durationProgress(done, total))).toEqual(expected.progress);
    });

    it("writes quantities", () => {
      switchLanguage(expected.language);
      expect(inputs.quantities.map(({ value, unit }) => durationQuantity(value, unit, bcp47))).toEqual(expected.quantities);
    });
  });

  describe.each(golden.dateRanges.outputs)("DateRangeFormat in $language", (expected) => {
    const { bcp47 } = languageEntry(expected.language);

    it.each(golden.dateRanges.cases.map((range, index) => ({ range, index })))("$range.name", ({ range, index }) => {
      expect(dayRange(range.first, range.last, bcp47, range.timeZone)).toBe(expected.days[index]);
    });
  });
});
