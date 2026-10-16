import { instantOf } from "../calendar/zonedCalendar";
import type { Instant } from "../time";

/*
 * The Chinese calendar days a seasonal event is written in, read in an IANA
 * zone. `Intl` (ICU) knows which lunation is which month, leap months
 * included, but its new moon approximation puts a few month starts a day
 * off when the new moon falls close to midnight in China (Lunar New Year
 * 2027 reads as 7 February instead of the 6th, 2030 as 2 February instead
 * of the 3rd). The Mac gets those days right, so a month's first day here
 * is the day of the true new moon in China time (UTC+8), from Meeus'
 * algorithm, and ICU only names the month. Like Foundation, a Chinese date
 * is the same local calendar day in every zone.
 */

/* ICU reads Chinese dates in UTC here: a Chinese date is the same local calendar day in every zone. */
const formatter = new Intl.DateTimeFormat("en-US-u-ca-chinese", { timeZone: "UTC", month: "numeric", day: "numeric" });

/** ICU's Chinese month and day of a Gregorian day; a leap month reads as undefined. */
function icuMonthDay(utcNoon: number): { month: number; day: number } | undefined {
  const parts = formatter.formatToParts(new Date(utcNoon * 1000));
  const month = parts.find((part) => part.type === "month")?.value ?? "";
  const day = parts.find((part) => part.type === "day")?.value ?? "";
  if (!/^\d+$/.test(month) || !/^\d+$/.test(day)) return undefined;
  return { month: Number(month), day: Number(day) };
}

const SYNODIC_MONTH = 29.530588861;
const UNIX_EPOCH_JD = 2440587.5;
const CHINA_OFFSET = 8 * 3600;

function sinDegrees(degrees: number): number {
  return Math.sin((degrees * Math.PI) / 180);
}

/** Seconds Terrestrial Time runs ahead of UTC around `year` (NASA's 2005 to 2050 polynomial). */
function deltaT(year: number): number {
  const t = year - 2000;
  return 62.92 + 0.32217 * t + 0.005589 * t * t;
}

/** The instant of new moon number `k` (0 is January 2000), Meeus, Astronomical Algorithms, chapter 49. */
export function newMoon(k: number): Instant {
  const t = k / 1236.85;
  const t2 = t * t;
  const t3 = t2 * t;
  const t4 = t3 * t;
  let jde = 2451550.09766 + SYNODIC_MONTH * k + 0.00015437 * t2 - 0.00000015 * t3 + 0.00000000073 * t4;
  const e = 1 - 0.002516 * t - 0.0000074 * t2;
  const m = 2.5534 + 29.1053567 * k - 0.0000014 * t2 - 0.00000011 * t3;
  const mp = 201.5643 + 385.81693528 * k + 0.0107582 * t2 + 0.00001238 * t3 - 0.000000058 * t4;
  const f = 160.7108 + 390.67050284 * k - 0.0016118 * t2 - 0.00000227 * t3 + 0.000000011 * t4;
  const omega = 124.7746 - 1.56375588 * k + 0.0020672 * t2 + 0.00000215 * t3;
  jde +=
    -0.4072 * sinDegrees(mp) +
    0.17241 * e * sinDegrees(m) +
    0.01608 * sinDegrees(2 * mp) +
    0.01039 * sinDegrees(2 * f) +
    0.00739 * e * sinDegrees(mp - m) -
    0.00514 * e * sinDegrees(mp + m) +
    0.00208 * e * e * sinDegrees(2 * m) -
    0.00111 * sinDegrees(mp - 2 * f) -
    0.00057 * sinDegrees(mp + 2 * f) +
    0.00056 * e * sinDegrees(2 * mp + m) -
    0.00042 * sinDegrees(3 * mp) +
    0.00042 * e * sinDegrees(m + 2 * f) +
    0.00038 * e * sinDegrees(m - 2 * f) -
    0.00024 * e * sinDegrees(2 * mp - m) -
    0.00017 * sinDegrees(omega) -
    0.00007 * sinDegrees(mp + 2 * m) +
    0.00004 * sinDegrees(2 * mp - 2 * f) +
    0.00004 * sinDegrees(3 * m) +
    0.00003 * sinDegrees(mp + m - 2 * f) +
    0.00003 * sinDegrees(2 * mp + 2 * f) -
    0.00003 * sinDegrees(mp + m + 2 * f) +
    0.00003 * sinDegrees(mp - m + 2 * f) -
    0.00002 * sinDegrees(mp - m - 2 * f) -
    0.00002 * sinDegrees(3 * mp + m) +
    0.00002 * sinDegrees(4 * mp);
  const planetary: readonly (readonly [number, number, number])[] = [
    [0.000325, 299.77 + 0.107408 * k - 0.009173 * t2, 0],
    [0.000165, 251.88, 0.016321],
    [0.000164, 251.83, 26.651886],
    [0.000126, 349.42, 36.412478],
    [0.00011, 84.66, 18.206239],
    [0.000062, 141.74, 53.303771],
    [0.00006, 207.14, 2.453732],
    [0.000056, 154.84, 7.30686],
    [0.000047, 34.52, 27.261239],
    [0.000042, 207.19, 0.121824],
    [0.00004, 291.34, 1.844379],
    [0.000037, 161.72, 24.198154],
    [0.000035, 239.56, 25.513099],
    [0.000023, 331.55, 3.592518],
  ];
  for (const [coefficient, base, rate] of planetary) jde += coefficient * sinDegrees(base + rate * k);
  const terrestrial = (jde - UNIX_EPOCH_JD) * 86400;
  return terrestrial - deltaT(2000 + k / 12.3685);
}

/** The Gregorian date, in China time, of the new moon nearest `instant`. */
function newMoonDayNear(instant: Instant): { year: number; month: number; day: number } {
  const reference = (2451550.09766 - UNIX_EPOCH_JD) * 86400;
  const k = Math.round((instant - reference) / (SYNODIC_MONTH * 86400));
  const china = new Date((newMoon(k) + CHINA_OFFSET) * 1000);
  return { year: china.getUTCFullYear(), month: china.getUTCMonth() + 1, day: china.getUTCDate() };
}

interface CivilDay {
  readonly year: number;
  readonly month: number;
  readonly day: number;
}

const monthStartCache = new Map<string, readonly CivilDay[]>();

/** The true first days (Gregorian, China time) of Chinese month `month` that ICU starts in Gregorian `year`. */
function monthStarts(year: number, month: number): readonly CivilDay[] {
  const key = `${year}-${month}`;
  const cached = monthStartCache.get(key);
  if (cached) return cached;
  const starts: CivilDay[] = [];
  for (let noon = Date.UTC(year, 0, 1, 12) / 1000; noon < Date.UTC(year + 1, 0, 1) / 1000; noon += 86400) {
    const date = icuMonthDay(noon);
    if (date && date.month === month && date.day === 1) starts.push(newMoonDayNear(noon));
  }
  monthStartCache.set(key, starts);
  return starts;
}

/**
 * The first local midnight of Chinese `month`/`day` (never a leap month)
 * strictly after `after` in `timeZone`, or with `backward` the last one
 * strictly before it, as Foundation's `nextDate(after:matching:)` finds it
 * on a Chinese calendar in that zone.
 */
export function chineseMidnight(
  month: number,
  day: number,
  after: Instant,
  timeZone: string,
  backward = false,
): Instant | undefined {
  const year = new Date(after * 1000).getUTCFullYear();
  const candidates = [year - 2, year - 1, year, year + 1, year + 2]
    .flatMap((each) => monthStarts(each, month))
    .map((start) => {
      const date = new Date(Date.UTC(start.year, start.month - 1, start.day + day - 1));
      return instantOf({ year: date.getUTCFullYear(), month: date.getUTCMonth() + 1, day: date.getUTCDate() }, timeZone);
    })
    .sort((a, b) => a - b);
  return backward ? candidates.filter((candidate) => candidate < after).pop() : candidates.find((candidate) => candidate > after);
}
