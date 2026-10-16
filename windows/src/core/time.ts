/*
 * Time in the core is plain numbers, the way the golden fixtures record it:
 * an instant is seconds since 1970 (UTC), a length is seconds. Wall-clock
 * questions (which day, what hour) always name an IANA time zone; the core
 * never reads the machine's clock or zone.
 */

/** Seconds since 1970-01-01T00:00:00Z. */
export type Instant = number;

/** A length of time in seconds. */
export type Seconds = number;

export const MINUTE: Seconds = 60;
export const HOUR: Seconds = 3600;
export const DAY: Seconds = 86400;

export function instantFromDate(date: Date): Instant {
  return date.getTime() / 1000;
}

export function dateFromInstant(instant: Instant): Date {
  return new Date(instant * 1000);
}
