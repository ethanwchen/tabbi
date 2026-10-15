import { afterEach, describe, expect, it } from "vitest";
import { dayRange, plainRange } from "../../../src/core/formatting/dateRangeFormat";
import {
  CARD_UNIT,
  durationCountdown,
  durationMinutes,
  durationProgress,
  durationQuantity,
  durationSeconds,
  MINUTE_UNIT,
} from "../../../src/core/formatting/durationFormat";
import { joinSentences } from "../../../src/core/formatting/sentences";
import { resetLanguage } from "../../../src/core/localization/lookup";
import { DAY } from "../../../src/core/time";
import { switchLanguage } from "../localization/catalogs";

afterEach(resetLanguage);

describe("DurationFormat", () => {
  it("uses the word under an hour", () => {
    switchLanguage("en");
    expect(durationMinutes(-5)).toBe("0 min");
    expect(durationMinutes(0)).toBe("0 min");
    expect(durationMinutes(45)).toBe("45 min");
    expect(durationMinutes(59)).toBe("59 min");
  });

  it("writes hours compactly", () => {
    switchLanguage("en");
    expect(durationMinutes(60)).toBe("1h");
    expect(durationMinutes(75)).toBe("1h 15m");
    expect(durationMinutes(120)).toBe("2h");
    expect(durationMinutes(125)).toBe("2h 5m");
  });

  it("rounds seconds up to the minute", () => {
    switchLanguage("en");
    expect(durationSeconds(0)).toBe("<1 min");
    expect(durationSeconds(30)).toBe("<1 min");
    expect(durationSeconds(60)).toBe("1 min");
    expect(durationSeconds(61)).toBe("2 min");
    expect(durationSeconds(2 * 3600 + 13 * 60 + 5)).toBe("2h 14m");
  });

  it("counts down", () => {
    switchLanguage("en");
    expect(durationCountdown(12)).toBe("in 12 min");
    expect(durationCountdown(60)).toBe("in 1h");
    expect(durationCountdown(94)).toBe("in 1h 34m");
  });

  it("writes a quantity of minutes as a duration", () => {
    switchLanguage("en");
    expect(durationQuantity(75, MINUTE_UNIT, "en")).toBe("1h 15m");
    expect(durationQuantity(30, "min", "en")).toBe("30 min");
    expect(durationQuantity(320, "cards", "en")).toBe("320 cards");
    expect(durationQuantity(12, "questions", "en")).toBe("12 questions");
    expect(durationQuantity(1500, "questions", "en")).toBe("1,500 questions");
    expect(durationQuantity(1500, "Fragen", "de")).toBe("1.500 Fragen");
  });

  it("counts cards as a plural, so one card never reads 1 cards", () => {
    switchLanguage("en");
    expect(durationQuantity(1, CARD_UNIT, "en")).toBe("1 card");
    expect(durationQuantity(128, CARD_UNIT, "en")).toBe("128 cards");
  });

  it("keeps one style in a progress label", () => {
    switchLanguage("en");
    expect(durationProgress(20, 45)).toBe("20 min of 45 min");
    expect(durationProgress(0, 240)).toBe("0m of 4h");
    expect(durationProgress(45, 120)).toBe("45m of 2h");
    expect(durationProgress(64, 120)).toBe("1h 4m of 2h");
    expect(durationProgress(75, 45)).toBe("1h 15m of 45m");
    expect(durationProgress(-3, 30)).toBe("0 min of 30 min");
  });

  it("follows the installed language", () => {
    switchLanguage("de");
    expect(durationMinutes(75)).toBe("1 h 15 min");
    expect(durationCountdown(12)).toBe("in 12 min");
    switchLanguage("ja");
    expect(durationMinutes(45)).toBe("45分");
    expect(durationCountdown(75)).toBe("1時間15分後");
    expect(durationQuantity(3, CARD_UNIT, "ja")).toBe("3枚");
  });
});

describe("DateRangeFormat", () => {
  /* Midnight in Los Angeles, as the Swift tests' calendar has it: UTC minus `offset` hours. */
  const midnight = (year: number, month: number, day: number, offset: number) =>
    Date.UTC(year, month - 1, day, offset) / 1000;
  const zone = "America/Los_Angeles";
  /* A Monday-to-Sunday week from its first day. */
  const week = (start: number, locale: string) => dayRange(start, start + 6 * DAY, locale, zone);

  const oct5 = midnight(2026, 10, 5, 7);
  const sep28 = midnight(2026, 9, 28, 7);
  const dec28 = midnight(2026, 12, 28, 8);

  it("names the month once or twice", () => {
    expect(week(oct5, "en-US")).toBe("Oct 5 - 11");
    expect(week(sep28, "en-US")).toBe("Sep 28 - Oct 4");
    expect(week(dec28, "en-US")).toBe("Dec 28, 2026 - Jan 3, 2027");
  });

  it("follows the locale with plain hyphens", () => {
    expect(week(oct5, "de")).toBe("5.-11. Okt.");
    expect(week(oct5, "ja")).toBe("10月5日～11日");
    expect(week(sep28, "ru")).toBe("28 сент. - 4 окт.");
  });

  it("spells out the CJK patterns V8 gets wrong", () => {
    expect(week(sep28, "ja")).toBe("9月28日～10月4日");
    expect(week(dec28, "ja")).toBe("2026年12月28日～2027年1月3日");
    expect(week(oct5, "zh-Hans")).toBe("10月5日至11日");
    expect(week(sep28, "zh-Hant")).toBe("9月28日至10月4日");
    expect(week(oct5, "zh-TW")).toBe("10月5日至11日");
    expect(week(oct5, "ko")).toBe("10월 5일~11일");
  });

  it("shows one day once, and a reversed span as its first day", () => {
    expect(dayRange(oct5, oct5 + 3600, "en-US", zone)).toBe("Oct 5");
    expect(dayRange(oct5, oct5 - DAY, "en-US", zone)).toBe("Oct 5");
    expect(dayRange(oct5, oct5, "ja", zone)).toBe("10月5日");
  });

  it("reads the days in the time zone it is given", () => {
    expect(dayRange(oct5, oct5 + 6 * DAY, "en-US", "Asia/Tokyo")).toBe("Oct 5 - 11");
    expect(dayRange(oct5, oct5 + 6 * DAY, "en-US", "Pacific/Honolulu")).toBe("Oct 4 - 10");
  });

  it("writes en dashes, em dashes and thin spaces plainly", () => {
    expect(plainRange("Oct\u20095\u2009\u2013\u200911")).toBe("Oct 5 - 11");
    expect(plainRange("a\u202Fb\u2014c")).toBe("a b-c");
  });
});

describe("Sentences", () => {
  it("spaces Latin sentences and skips empty ones", () => {
    expect(joinSentences(["Pay as you go.", "", "Your key stays in your Keychain."])).toBe(
      "Pay as you go. Your key stays in your Keychain.",
    );
    expect(joinSentences([" Kostenlos. ", "Sendet an Google."])).toBe("Kostenlos. Sendet an Google.");
    expect(joinSentences([])).toBe("");
  });

  it("adds no space after a full-width stop", () => {
    expect(joinSentences(["無料で使えます。", "質問内容はGoogleに送信されます。"])).toBe(
      "無料で使えます。質問内容はGoogleに送信されます。",
    );
    expect(joinSentences(["免费使用。", "Sends to Google."])).toBe("免费使用。Sends to Google.");
  });
});
