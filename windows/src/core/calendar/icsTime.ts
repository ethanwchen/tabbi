import type { Instant, Seconds } from "../time";
import { instantOf, isKnownTimeZone, wallTime, type LocalTime } from "./zonedCalendar";
import { param, properties, property, type IcsComponent, type IcsProperty } from "./icsLexer";
import { windowsZoneToIANA } from "./windowsZones";

/*
 * Times in an ICS feed: DATE and DATE-TIME values, DURATION, and the zones
 * a DATE-TIME can name (an IANA zone, a Windows zone id, the feed's own
 * VTIMEZONE, a fixed offset, UTC, or none at all, which is floating).
 */

/** A calendar date. */
export interface IcsDate {
  readonly year: number;
  readonly month: number;
  readonly day: number;
}

/** A local date and time. */
export interface IcsWall extends IcsDate {
  readonly hour: number;
  readonly minute: number;
  readonly second: number;
}

/** A DATE, or a DATE-TIME that is UTC (`Z`), in a named zone (`tzid`), or floating (neither). */
export type IcsDateValue =
  | { readonly kind: "date"; readonly date: IcsDate }
  | { readonly kind: "dateTime"; readonly wall: IcsWall; readonly utc: boolean; readonly tzid?: string };

/** Reads `20261015`, `20261015T093000` or `20261015T163000Z` (dashes and colons tolerated), or undefined. */
export function parseDateValue(text: string, tzid?: string, forceDate = false): IcsDateValue | undefined {
  const compact = text.trim().replace(/[-:]/g, "");
  const match = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(?:\.\d+)?(Z)?)?$/i.exec(compact);
  if (!match) return undefined;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (month < 1 || month > 12 || day < 1 || day > 31) return undefined;
  if (match[4] === undefined || forceDate) return { kind: "date", date: { year, month, day } };
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6] ?? "0");
  if (hour > 24 || minute > 59 || second > 60) return undefined;
  const utc = match[7] !== undefined;
  const wall = { year, month, day, hour, minute, second: Math.min(second, 59) };
  return utc || tzid === undefined ? { kind: "dateTime", wall, utc } : { kind: "dateTime", wall, utc, tzid };
}

/** The date-time values of a property (DTSTART, EXDATE, RDATE...), honoring VALUE=DATE and TZID. */
export function propertyDates(entry: IcsProperty): IcsDateValue[] {
  const isDate = param(entry, "VALUE")?.toUpperCase() === "DATE";
  const tzid = param(entry, "TZID");
  return entry.value
    .split(",")
    .map((piece) => parseDateValue(piece.split("/")[0] ?? "", tzid, isDate))
    .filter((value): value is IcsDateValue => value !== undefined);
}

/** A DURATION: whole days (nominal, so a day across a clock change is still a day) plus exact seconds. */
export interface IcsDuration {
  readonly days: number;
  readonly seconds: Seconds;
}

/** Reads `P1D`, `PT1H30M`, `-PT15M`, `P2W`, or undefined. */
export function parseDuration(text: string): IcsDuration | undefined {
  const match = /^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/i.exec(text.trim());
  if (!match || /^[+-]?PT?$/i.test(text.trim())) return undefined;
  const sign = match[1] === "-" ? -1 : 1;
  const number = (index: number) => Number(match[index] ?? "0");
  return {
    days: sign * (number(2) * 7 + number(3)),
    seconds: sign * (number(4) * 3600 + number(5) * 60 + number(6)),
  };
}

/** A way to turn local times into instants and back. */
export interface EventZone {
  /** A stable name, for ids and tests. */
  readonly name: string;
  wall(instant: Instant): IcsWall;
  instant(local: LocalTime): Instant;
}

/* Seconds of a wall time read as if it were UTC. */
export function wallSeconds(local: LocalTime): number {
  const date = new Date(0);
  date.setUTCFullYear(local.year, local.month - 1, local.day);
  date.setUTCHours(local.hour ?? 0, local.minute ?? 0, 0, 0);
  return date.getTime() / 1000 + (local.second ?? 0);
}

/* The wall fields of seconds read as UTC. */
export function wallFromSeconds(seconds: number): IcsWall {
  const date = new Date(Math.floor(seconds) * 1000);
  return {
    year: date.getUTCFullYear(),
    month: date.getUTCMonth() + 1,
    day: date.getUTCDate(),
    hour: date.getUTCHours(),
    minute: date.getUTCMinutes(),
    second: date.getUTCSeconds(),
  };
}

/** An IANA zone, through Intl. */
export function ianaZone(name: string): EventZone {
  return {
    name,
    wall: (instant) => wallTime(instant, name),
    instant: (local) => instantOf(local, name),
  };
}

/** A zone a fixed `offset` seconds ahead of UTC. */
export function fixedZone(offset: Seconds, name = `UTC${offset >= 0 ? "+" : "-"}${Math.abs(offset)}`): EventZone {
  return {
    name,
    wall: (instant) => wallFromSeconds(instant + offset),
    instant: (local) => wallSeconds(local) - offset,
  };
}

export const UTC_ZONE: EventZone = fixedZone(0, "UTC");

/* `+0530` or `-08:00` as seconds, or undefined. */
function parseOffset(text: string): Seconds | undefined {
  const match = /^([+-])(\d{2}):?(\d{2})(?::?(\d{2}))?$/.exec(text.trim());
  if (!match) return undefined;
  const value = Number(match[2]) * 3600 + Number(match[3]) * 60 + Number(match[4] ?? "0");
  return match[1] === "-" ? -value : value;
}

/* One STANDARD or DAYLIGHT block of a VTIMEZONE. */
interface Observance {
  readonly start: IcsWall;
  readonly offsetFrom: Seconds;
  readonly offsetTo: Seconds;
  readonly rule?: { readonly month: number; readonly weekday?: number; readonly ordinal?: number; readonly monthDay?: number };
  readonly until?: number;
  readonly dates: readonly IcsWall[];
}

const WEEKDAY_CODES: Readonly<Record<string, number>> = { SU: 1, MO: 2, TU: 3, WE: 4, TH: 5, FR: 6, SA: 7 };

function readObservance(component: IcsComponent): Observance | undefined {
  const startProperty = property(component, "DTSTART");
  const start = startProperty === undefined ? undefined : parseDateValue(startProperty.value);
  const offsetFrom = parseOffset(property(component, "TZOFFSETFROM")?.value ?? "");
  const offsetTo = parseOffset(property(component, "TZOFFSETTO")?.value ?? "");
  if (start === undefined || offsetTo === undefined) return undefined;
  const startWall: IcsWall = start.kind === "date" ? { ...start.date, hour: 0, minute: 0, second: 0 } : start.wall;
  const observance: { -readonly [Key in keyof Observance]: Observance[Key] } = {
    start: startWall,
    offsetFrom: offsetFrom ?? offsetTo,
    offsetTo,
    dates: properties(component, "RDATE").flatMap(propertyDates).map((value) =>
      value.kind === "date" ? { ...value.date, hour: startWall.hour, minute: startWall.minute, second: startWall.second } : value.wall,
    ),
  };
  const rrule = property(component, "RRULE")?.value;
  if (rrule !== undefined) {
    const parts = new Map(rrule.split(";").map((part) => {
      const [key = "", value = ""] = part.split("=");
      return [key.toUpperCase(), value.toUpperCase()] as const;
    }));
    if (parts.get("FREQ") === "YEARLY") {
      const month = Number(parts.get("BYMONTH") ?? startWall.month);
      const byDay = /^([+-]?\d{1,2})?(SU|MO|TU|WE|TH|FR|SA)$/.exec(parts.get("BYDAY") ?? "");
      const monthDay = parts.get("BYMONTHDAY");
      observance.rule = byDay
        ? { month, weekday: WEEKDAY_CODES[byDay[2] ?? "SU"] ?? 1, ordinal: Number(byDay[1] ?? "1") }
        : { month, monthDay: monthDay === undefined ? startWall.day : Number(monthDay) };
      const until = parts.get("UNTIL");
      const untilValue = until === undefined ? undefined : parseDateValue(until);
      if (untilValue !== undefined) {
        observance.until =
          untilValue.kind === "date" ? wallSeconds(untilValue.date) + 86_399 : wallSeconds(untilValue.wall) + (untilValue.utc ? offsetTo : 0);
      }
    }
  }
  return observance;
}

/** The day of month of the `ordinal`-th `weekday` (1 Sunday ... 7 Saturday) of a month; negative counts from the end. */
export function nthWeekday(year: number, month: number, weekday: number, ordinal: number): number | undefined {
  const last = new Date(0);
  last.setUTCFullYear(year, month, 0);
  const length = last.getUTCDate();
  const first = new Date(0);
  first.setUTCFullYear(year, month - 1, 1);
  const firstWeekday = first.getUTCDay() + 1;
  const days: number[] = [];
  for (let day = 1 + ((weekday - firstWeekday + 7) % 7); day <= length; day += 7) days.push(day);
  return ordinal > 0 ? days[ordinal - 1] : days[days.length + ordinal];
}

/* Local onsets (as wall seconds) of an observance in `year`. */
function onsets(observance: Observance, year: number): number[] {
  const time = { hour: observance.start.hour, minute: observance.start.minute, second: observance.start.second };
  const startSeconds = wallSeconds(observance.start);
  const result: number[] = [];
  if (observance.rule !== undefined) {
    const rule = observance.rule;
    const day =
      rule.weekday !== undefined ? nthWeekday(year, rule.month, rule.weekday, rule.ordinal ?? 1) : rule.monthDay;
    if (day !== undefined) {
      const seconds = wallSeconds({ year, month: rule.month, day, ...time });
      if (seconds >= startSeconds && (observance.until === undefined || seconds <= observance.until)) result.push(seconds);
    }
  } else if (observance.start.year === year) {
    result.push(startSeconds);
  }
  for (const date of observance.dates) if (date.year === year) result.push(wallSeconds(date));
  return result;
}

/**
 * A zone from a feed's VTIMEZONE: its STANDARD and DAYLIGHT observances
 * with their yearly rules (or one-off onsets). Outside every rule it keeps
 * the earliest observance's offset.
 */
export function vtimezoneZone(component: IcsComponent, name: string): EventZone | undefined {
  const observances = component.components
    .filter((child) => child.name === "STANDARD" || child.name === "DAYLIGHT")
    .map(readObservance)
    .filter((observance): observance is Observance => observance !== undefined);
  if (observances.length === 0) return undefined;
  const earliest = observances.reduce((a, b) => (wallSeconds(a.start) <= wallSeconds(b.start) ? a : b));
  const offsetAt = (instant: Instant): Seconds => {
    const year = new Date(Math.floor(instant) * 1000).getUTCFullYear();
    let best: { at: number; offset: Seconds } | undefined;
    for (const observance of observances) {
      for (const candidateYear of [year - 1, year, year + 1]) {
        for (const onset of onsets(observance, candidateYear)) {
          const at = onset - observance.offsetFrom;
          if (at <= instant && (best === undefined || at > best.at)) best = { at, offset: observance.offsetTo };
        }
      }
    }
    return best?.offset ?? earliest.offsetFrom;
  };
  const offsets = [...new Set(observances.flatMap((observance) => [observance.offsetFrom, observance.offsetTo]))];
  return {
    name,
    wall: (instant) => wallFromSeconds(instant + offsetAt(instant)),
    instant: (local) => {
      const seconds = wallSeconds(local);
      const valid = offsets.map((offset) => seconds - offset).filter((candidate) => offsetAt(candidate) === seconds - candidate);
      if (valid.length > 0) return Math.min(...valid);
      /* Skipped by a jump forward: read with the offset before the jump, landing just after it. */
      const before = Math.min(...offsets);
      return seconds - before;
    },
  };
}

/* Candidate IANA names inside a TZID such as "/mozilla.org/20050126_1/America/New_York". */
function ianaCandidates(tzid: string): string[] {
  const trimmed = tzid.trim().replace(/^"|"$/g, "");
  const segments = trimmed.split("/").filter((segment) => segment !== "");
  const candidates = [trimmed];
  for (let start = 1; start < segments.length; start++) candidates.push(segments.slice(start).join("/"));
  return candidates;
}

/**
 * The zone a TZID names: an IANA zone, a Windows zone id or Outlook
 * display name, the feed's VTIMEZONE of that id, or a `(UTC+hh:mm)` offset.
 * Undefined when nothing fits, so the caller can treat the time as floating.
 */
export function resolveTZID(tzid: string, vtimezones: ReadonlyMap<string, IcsComponent>): EventZone | undefined {
  const cleaned = tzid.trim().replace(/^"|"$/g, "");
  if (/^(utc|gmt|z|etc\/utc|etc\/gmt)$/i.test(cleaned)) return UTC_ZONE;
  for (const candidate of ianaCandidates(cleaned)) {
    if (candidate.includes("/") && isKnownTimeZone(candidate)) return ianaZone(candidate);
  }
  for (const candidate of ianaCandidates(cleaned)) {
    const windows = windowsZoneToIANA(candidate);
    if (windows !== undefined && isKnownTimeZone(windows)) return ianaZone(windows);
  }
  const definition = vtimezones.get(cleaned);
  if (definition !== undefined) {
    const location = property(definition, "X-LIC-LOCATION")?.value.trim();
    if (location !== undefined && isKnownTimeZone(location)) return ianaZone(location);
    const zone = vtimezoneZone(definition, cleaned);
    if (zone !== undefined) return zone;
  }
  const offset = /\((?:UTC|GMT)\s*([+-]\d{1,2}):?(\d{2})?\)/i.exec(cleaned);
  if (offset) {
    const hours = Number(offset[1]);
    const minutes = Number(offset[2] ?? "0") * (hours < 0 || offset[1]?.startsWith("-") ? -1 : 1);
    return fixedZone(hours * 3600 + minutes * 60, cleaned);
  }
  if (/^(?:UTC|GMT)$/i.test(cleaned.replace(/^\((?:UTC|GMT)\)\s*/i, ""))) return UTC_ZONE;
  if (isKnownTimeZone(cleaned) && !/^[+-]/.test(cleaned)) return ianaZone(cleaned);
  return undefined;
}
