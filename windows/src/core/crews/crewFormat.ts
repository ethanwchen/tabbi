import { currentLanguage, numberLocale, tr } from "../localization/tr";
import type { Instant } from "../time";
import type { CrewWeek } from "./crewModels";

/*
 * Port of CrewFormat: how Crews write hours, ranks and the week's countdown.
 * The structural parts (`crewHoursValue`, `crewRemainingValue`) are pinned
 * by shared/fixtures/crews; the text comes from the shared catalog keys, so
 * it reads the same as on the Mac in every language.
 */

/** Whole hours from 10 hours up, otherwise tenths of an hour; rounded down, so the board never claims time not yet studied. */
export type CrewHours = { readonly form: "tenths"; readonly value: number } | { readonly form: "whole"; readonly value: number };

export function crewHoursValue(minutes: number): CrewHours {
  const m = Math.max(Math.trunc(minutes), 0);
  return m >= 600 ? { form: "whole", value: Math.trunc(m / 60) } : { form: "tenths", value: Math.trunc(m / 6) };
}

/** "0.5 h", "4.2 h", "12 h". */
export function crewHours(minutes: number, language: string = currentLanguage()): string {
  const hours = crewHoursValue(minutes);
  if (hours.form === "whole") return tr("%lld h", hours.value);
  const number = new Intl.NumberFormat(numberLocale(language), { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(hours.value / 10);
  return tr("%@ h", number);
}

/** The time left in the week, in the largest two units that matter. */
export type CrewRemaining =
  | { readonly form: "lessThanAMinute"; readonly values: readonly [] }
  | { readonly form: "minutes"; readonly values: readonly [number] }
  | { readonly form: "hoursMinutes"; readonly values: readonly [number, number] }
  | { readonly form: "daysHours"; readonly values: readonly [number, number] };

export function crewRemainingValue(end: Instant, now: Instant): CrewRemaining {
  const minutes = Math.trunc(Math.max(0, end - now) / 60);
  if (minutes < 1) return { form: "lessThanAMinute", values: [] };
  const days = Math.trunc(minutes / 1440);
  const hours = Math.trunc((minutes % 1440) / 60);
  const rest = minutes % 60;
  if (days > 0) return { form: "daysHours", values: [days, hours] };
  if (hours > 0) return { form: "hoursMinutes", values: [hours, rest] };
  return { form: "minutes", values: [rest] };
}

/** "2d 5h", "5h 12m", "12m", "<1m". */
export function crewRemaining(end: Instant, now: Instant): string {
  const value = crewRemainingValue(end, now);
  switch (value.form) {
    case "lessThanAMinute":
      return tr("<1m");
    case "minutes":
      return tr("%lldm", value.values[0]);
    case "hoursMinutes":
      return tr("%lldh %lldm", value.values[0], value.values[1]);
    case "daysHours":
      return tr("%lldd %lldh", value.values[0], value.values[1]);
  }
}

/** "Ends in 2d 5h", the board's countdown. */
export function crewCountdown(week: CrewWeek, now: Instant): string {
  return tr("Ends in %@", crewRemaining(week.endsAt, now));
}

/** When the countdown text next changes, so a view can tick exactly then. */
export function crewNextChange(week: CrewWeek, now: Instant): Instant {
  const left = week.endsAt - now;
  if (left <= 0) return week.endsAt;
  const step = left >= 86_400 ? 3600 : 60;
  const remainder = left % step;
  return now + (remainder > 0 ? remainder : step);
}

/** "#3" on a crew page. */
export function crewRank(rank: number): string {
  return tr("#%lld", rank);
}

/** "12 of 20" members. */
export function crewMembers(count: number, max: number): string {
  return tr("%lld of %lld", count, max);
}
