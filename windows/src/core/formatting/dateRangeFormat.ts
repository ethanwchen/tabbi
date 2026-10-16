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
 * The Mac's month-and-day interval patterns (ICU skeleton MMMd, and yMMMd
 * across a new year, from the CLDR the Mac ships), already in Tabbi's plain
 * spaces and hyphens, for the languages where V8's CLDR writes something
 * else, so both apps show the same text:
 * - ja and zh: V8 rebuilds the skeleton from the resolved pattern ("M月d日"
 *   reads as numeric Md) and writes "10/05～10/11" instead of "10月5日～11日";
 *   zh-Hans also joins two years with a dash on the Mac, not "至".
 * - es: the Mac spaces the dash inside one month ("5 - 11 oct").
 * - ko: the Mac writes no spaces around "~" across months or years.
 * - ru: the Mac's abbreviated March is "марта", and across years it writes
 *   "г." once, after the second date.
 * Placeholders: `y` year, `M` numeric month, `MMM` short month name, `d`
 * day, with 1 for the first day and 2 for the last. A granularity left out
 * falls back to formatRange.
 */
interface IntervalPatterns {
  readonly day?: string;
  readonly month?: string;
  readonly year?: string;
  /* Short month names (1 is January) where the Mac's CLDR differs from V8's. */
  readonly monthNames?: Readonly<Record<number, string>>;
}

const MAC_INTERVALS: Readonly<Record<string, IntervalPatterns>> = {
  ja: { day: "{M1}月{d1}日～{d2}日", month: "{M1}月{d1}日～{M2}月{d2}日", year: "{y1}年{M1}月{d1}日～{y2}年{M2}月{d2}日" },
  "zh-Hans": { day: "{M1}月{d1}日至{d2}日", month: "{M1}月{d1}日至{M2}月{d2}日", year: "{y1}年{M1}月{d1}日 - {y2}年{M2}月{d2}日" },
  "zh-Hant": { day: "{M1}月{d1}日至{d2}日", month: "{M1}月{d1}日至{M2}月{d2}日", year: "{y1}年{M1}月{d1}日至{y2}年{M2}月{d2}日" },
  es: { day: "{d1} - {d2} {MMM2}" },
  ko: { month: "{M1}월 {d1}일~{M2}월 {d2}일", year: "{y1}년 {M1}월 {d1}일~{y2}년 {M2}월 {d2}일" },
  ru: {
    day: "{d1}-{d2} {MMM2}",
    month: "{d1} {MMM1} - {d2} {MMM2}",
    year: "{d1} {MMM1} {y1} - {d2} {MMM2} {y2} г.",
    monthNames: { 3: "марта" },
  },
};

/* The Mac's patterns for `locale`, by language and script ("zh-TW" is zh-Hant). */
function macPatterns(locale: string): IntervalPatterns | undefined {
  const tag = new Intl.Locale(locale).maximize();
  if (tag.language === "zh") return tag.script === "Hant" ? MAC_INTERVALS["zh-Hant"] : MAC_INTERVALS["zh-Hans"];
  return Object.hasOwn(MAC_INTERVALS, tag.language) ? MAC_INTERVALS[tag.language] : undefined;
}

interface DayParts {
  readonly y: string;
  readonly M: string;
  readonly MMM: string;
  readonly d: string;
}

function dayParts(date: Date, locale: string, timeZone: string, patterns: IntervalPatterns): DayParts {
  const numeric = new Intl.DateTimeFormat(locale, { year: "numeric", month: "numeric", day: "numeric", timeZone }).formatToParts(date);
  const named = new Intl.DateTimeFormat(locale, { month: "short", day: "numeric", timeZone }).formatToParts(date);
  const part = (parts: Intl.DateTimeFormatPart[], type: Intl.DateTimeFormatPartTypes) =>
    parts.find((p) => p.type === type)?.value ?? "";
  const month = part(numeric, "month");
  const monthNumber = Number(new Intl.DateTimeFormat("en-US", { month: "numeric", timeZone }).format(date));
  const MMM = patterns.monthNames?.[monthNumber] ?? part(named, "month");
  return { y: part(numeric, "year"), M: month, MMM, d: part(named, "day") };
}

/**
 * The days from `first` to `last` (both shown, instants in seconds) as
 * month and day in `timeZone`, with the years only when they differ.
 */
export function dayRange(first: Instant, last: Instant, locale: string, timeZone: string): string {
  const start = dateFromInstant(first);
  const end = dateFromInstant(Math.max(first, last));
  const format = new Intl.DateTimeFormat(locale, { month: "short", day: "numeric", timeZone });
  const patterns = macPatterns(locale);
  if (!patterns) return plainRange(format.formatRange(start, end));
  const a = dayParts(start, locale, timeZone, patterns);
  const b = dayParts(end, locale, timeZone, patterns);
  if (a.y === b.y && a.M === b.M && a.d === b.d) {
    return plainRange(patterns.monthNames ? `${a.d} ${a.MMM}` : format.format(start));
  }
  const pattern = a.y !== b.y ? patterns.year : a.M !== b.M ? patterns.month : patterns.day;
  if (pattern === undefined) return plainRange(format.formatRange(start, end));
  const values: Record<string, string> = { y1: a.y, M1: a.M, MMM1: a.MMM, d1: a.d, y2: b.y, M2: b.M, MMM2: b.MMM, d2: b.d };
  return pattern.replace(/\{(\w+)\}/g, (match, name: string) => values[name] ?? match);
}
