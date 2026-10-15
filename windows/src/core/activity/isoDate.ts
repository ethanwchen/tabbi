import type { Instant } from "../time";

/*
 * Dates in activity day files are what Foundation's `.iso8601` date strategy
 * writes and reads: internet date-time with whole seconds, written in UTC
 * with a `Z` (`2026-10-02T09:00:00Z`), read with `Z` or a numeric offset and
 * no fractional seconds.
 */

/** `instant` as ISO 8601 in UTC, whole seconds (the caller rounds first). */
export function formatISODate(instant: Instant): string {
  const date = new Date(Math.round(instant) * 1000);
  const pad = (value: number, width = 2) => String(value).padStart(width, "0");
  return (
    `${pad(date.getUTCFullYear(), 4)}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}` +
    `T${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}:${pad(date.getUTCSeconds())}Z`
  );
}

/** The instant in an ISO 8601 internet date-time, or undefined when it isn't one. */
export function parseISODate(text: string): Instant | undefined {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(Z|[+-]\d{2}:?\d{2})$/.exec(text);
  if (!match) return undefined;
  const [year, month, day, hour, minute, second] = match.slice(1, 7).map(Number) as [
    number,
    number,
    number,
    number,
    number,
    number,
  ];
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 60) return undefined;
  const zone = match[7] ?? "Z";
  let offset = 0;
  if (zone !== "Z") {
    const digits = zone.slice(1).replace(":", "");
    offset = (Number(digits.slice(0, 2)) * 60 + Number(digits.slice(2))) * 60 * (zone.startsWith("-") ? -1 : 1);
  }
  const utc = Date.UTC(year, month - 1, day, hour, minute, second) / 1000;
  return utc - offset;
}
