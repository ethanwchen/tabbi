/*
 * Port of DurationFormat: the one way Tabbi writes a length of time, so
 * every panel, the ticker and Settings read alike: "45 min" under an hour,
 * "2h" and "1h 15m" above it, and "in 12 min" or "in 1h 15m" for something
 * still to come. The units are catalog strings, so they follow the language
 * installed into `tr`; a plain count in a module's own unit is written with
 * the locale passed in.
 */

import { tr } from "../localization/tr";

/** The unit ProgressItems count minutes in, which `quantity` writes as a duration. */
export const MINUTE_UNIT = "min";
/** The unit Anki's review goal counts flashcards in, which `quantity` writes as a translated plural. */
export const CARD_UNIT = "cards";

/** "0 min", "45 min", "2h", "1h 15m". Negative values read as "0 min". */
export function durationMinutes(value: number): string {
  const minutes = Math.max(Math.trunc(value), 0);
  if (minutes < 60) return tr("%lld min", minutes);
  const hours = Math.trunc(minutes / 60);
  const rest = minutes % 60;
  return rest === 0 ? tr("%lldh", hours) : tr("%lldh %lldm", hours, rest);
}

/* "0m", "45m", "2h", "1h 15m": the hours form, also under an hour. */
function compact(minutes: number): string {
  return minutes < 60 ? tr("%lldm", minutes) : durationMinutes(minutes);
}

/**
 * Progress toward a length of time: "20 min of 45 min" under an hour, and
 * "45m of 2h" or "1h 4m of 2h" once either side reaches one, so a single
 * label never mixes the word "min" with the compact hours form.
 */
export function durationProgress(done: number, total: number): string {
  const d = Math.max(Math.trunc(done), 0);
  const t = Math.max(Math.trunc(total), 0);
  if (Math.max(d, t) < 60) return tr("%@ of %@", durationMinutes(d), durationMinutes(t));
  return tr("%@ of %@", compact(d), compact(t));
}

/** A span in seconds rounded up to the minute, with "<1 min" for less, so a countdown never claims nothing is left. */
export function durationSeconds(seconds: number): string {
  if (!(seconds >= 60)) return tr("<1 min");
  return durationMinutes(Math.ceil(seconds / 60));
}

/** "in 12 min", "in 1h", "in 1h 15m". */
export function durationCountdown(minutes: number): string {
  return tr("in %@", durationMinutes(minutes));
}

/**
 * A count in its own unit ("320 cards"), or a duration when the unit is
 * `MINUTE_UNIT` ("1h 15m" rather than "75 min"). Tabbi's own units are
 * translated plurals; any other unit is a module's own text, after the
 * number written in `locale`.
 */
export function durationQuantity(value: number, unit: string, locale: string): string {
  switch (unit) {
    case MINUTE_UNIT:
      return durationMinutes(value);
    case CARD_UNIT:
      return tr("%lld cards", value);
    default:
      return `${new Intl.NumberFormat(locale).format(Math.trunc(value))} ${unit}`;
  }
}
