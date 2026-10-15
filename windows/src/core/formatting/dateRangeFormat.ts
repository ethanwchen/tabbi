/*
 * Port of DateRangeFormat: a span of days in the locale's own order and
 * words, "Oct 5 - 11" or "Sep 28 - Oct 4" in English, "5.-11. Okt." in
 * German, "10月5日～11日" in Japanese. The locale's interval pattern
 * (Intl's formatRange) decides what repeats, so no language gets an English
 * template; its en and em dashes become the plain hyphen Tabbi writes
 * everywhere.
 */

import { dateFromInstant, type Instant } from "../time";

/** Thin and narrow spaces as plain ones, en and em dashes as hyphens. */
export function plainRange(text: string): string {
  return text.replace(/[\u2009\u202F]/g, " ").replace(/[\u2013\u2014]/g, "-");
}

/*
 * CLDR's month-and-day interval patterns (skeleton MMMd, and yMMMd across a
 * new year) for the languages whose short month is a number with a suffix.
 * V8's formatRange rebuilds the skeleton from the resolved pattern ("M月d日"
 * reads as numeric Md) and writes "10/05～10/11" instead of the Mac's
 * "10月5日～11日", so these three spell the pattern out with Intl's numbers.
 */
interface IntervalPatterns {
  readonly day: string;
  readonly month: string;
  readonly year: string;
}

const CJK_INTERVALS: Readonly<Record<string, IntervalPatterns>> = {
  ja: { day: "{M1}月{d1}日～{d2}日", month: "{M1}月{d1}日～{M2}月{d2}日", year: "{y1}年{M1}月{d1}日～{y2}年{M2}月{d2}日" },
  "zh-Hans": { day: "{M1}月{d1}日至{d2}日", month: "{M1}月{d1}日至{M2}月{d2}日", year: "{y1}年{M1}月{d1}日至{y2}年{M2}月{d2}日" },
  "zh-Hant": { day: "{M1}月{d1}日至{d2}日", month: "{M1}月{d1}日至{M2}月{d2}日", year: "{y1}年{M1}月{d1}日至{y2}年{M2}月{d2}日" },
};

/* The CJK patterns for `locale`, by language and script ("zh-TW" is zh-Hant). */
function cjkPatterns(locale: string): IntervalPatterns | undefined {
  const tag = new Intl.Locale(locale).maximize();
  if (tag.language === "ja") return CJK_INTERVALS.ja;
  if (tag.language === "zh") return tag.script === "Hant" ? CJK_INTERVALS["zh-Hant"] : CJK_INTERVALS["zh-Hans"];
  return undefined;
}

interface DayParts {
  readonly y: string;
  readonly M: string;
  readonly d: string;
}

function dayParts(date: Date, locale: string, timeZone: string): DayParts {
  const parts = new Intl.DateTimeFormat(locale, { year: "numeric", month: "numeric", day: "numeric", timeZone }).formatToParts(date);
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find((p) => p.type === type)?.value ?? "";
  return { y: part("year"), M: part("month"), d: part("day") };
}

/**
 * The days from `first` to `last` (both shown, instants in seconds) as
 * month and day in `timeZone`, with the years only when they differ.
 */
export function dayRange(first: Instant, last: Instant, locale: string, timeZone: string): string {
  const start = dateFromInstant(first);
  const end = dateFromInstant(Math.max(first, last));
  const format = new Intl.DateTimeFormat(locale, { month: "short", day: "numeric", timeZone });
  const patterns = cjkPatterns(locale);
  if (!patterns) return plainRange(format.formatRange(start, end));
  const a = dayParts(start, locale, timeZone);
  const b = dayParts(end, locale, timeZone);
  if (a.y === b.y && a.M === b.M && a.d === b.d) return plainRange(format.format(start));
  const pattern = a.y !== b.y ? patterns.year : a.M !== b.M ? patterns.month : patterns.day;
  const values: Record<string, string> = { y1: a.y, M1: a.M, d1: a.d, y2: b.y, M2: b.M, d2: b.d };
  return pattern.replace(/\{(\w+)\}/g, (match, name: string) => values[name] ?? match);
}
