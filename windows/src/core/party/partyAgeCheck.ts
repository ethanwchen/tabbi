import { instantFromZoned, zonedParts } from "../anki/ankiDay";
import type { Instant } from "../time";

/*
 * Port of PartyAgeCheck: Party's age screen. Party (and a Tabbi account) is
 * for people 13 and older, so before Party talks to the friends server for
 * the first time it asks the month and year the user was born, on the
 * device.
 *
 * The question is neutral: it doesn't say which answer lets you in, and
 * someone told they are too young can't just answer again. Only the day
 * the user is surely old enough (`eligibleFrom`) is kept, in
 * `PartySettings` on this PC; neither the birth date nor the answer ever
 * goes to the server.
 *
 * Birth years are Gregorian whatever the system calendar is, and wall-clock
 * math names an IANA time zone.
 */

export const MINIMUM_AGE = 13;

/** The answer as picked: a month (1 to 12) and a year. */
export interface PartyBirth {
  readonly month: number;
  readonly year: number;
}

export type PartyAgeStatus =
  /** Not asked yet: Party waits for the answer. */
  | { readonly kind: "unanswered" }
  /** Under 13 when asked; Party stays off on this PC until `until`. */
  | { readonly kind: "tooYoung"; readonly until: Instant }
  /** Old enough: Party may connect. */
  | { readonly kind: "passed" };

/**
 * The first moment someone born in `month` of `year` is surely 13: local
 * midnight on the first of the month after their 13th birthday's month,
 * since the day isn't asked. Undefined for a month or year that can't be a
 * birth date.
 */
export function eligibleFrom(birth: PartyBirth, timeZone: string): Instant | undefined {
  const { month, year } = birth;
  if (!Number.isInteger(month) || !Number.isInteger(year) || month < 1 || month > 12 || year <= 1900) return undefined;
  const months = (year + MINIMUM_AGE) * 12 + (month - 1) + 1;
  return instantFromZoned(Math.floor(months / 12), (months % 12) + 1, 1, 0, timeZone);
}

/** Where someone stands at `now`, from what `eligibleFrom` saved. */
export function ageStatus(eligible: Instant | undefined, now: Instant): PartyAgeStatus {
  if (eligible === undefined) return { kind: "unanswered" };
  return eligible <= now ? { kind: "passed" } : { kind: "tooYoung", until: eligible };
}

/** The years the birth year picker offers, newest first: this year back a century, so none is suggested. */
export function birthYears(now: Instant, timeZone: string): number[] {
  const year = zonedParts(now, timeZone).year;
  return Array.from({ length: 101 }, (_, index) => year - index);
}

/** The month picker's names, January first, in `locale`. */
export function monthNames(locale: string): string[] {
  const format = new Intl.DateTimeFormat(locale, { month: "long", timeZone: "UTC", calendar: "gregory" });
  return Array.from({ length: 12 }, (_, index) => format.format(new Date(Date.UTC(2001, index, 15))));
}

/** When Party opens for someone too young, as the panel says it ("May 2028"). */
export function opensText(date: Instant, locale: string, timeZone: string): string {
  return new Intl.DateTimeFormat(locale, { month: "long", year: "numeric", timeZone, calendar: "gregory" }).format(new Date(date * 1000));
}
