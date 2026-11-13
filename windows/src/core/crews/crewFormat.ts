import { currentLanguage, numberLocale, tr } from "../localization/tr";
import type { Instant } from "../time";
import type { CrewWeek } from "./crewModels";

/*
 * Port of CrewFormat: how Crews write hours, ranks and the week's countdown.
 * The structural parts (`crewHoursValue`, `crewRemainingValue`) are pinned
 * by shared/fixtures/crews; the text comes from the shared catalog keys, so
 * it reads the same as on the Mac in every language.
 */

/** Focus time on the board in tenths of an hour, rounded down, so the board never claims time not yet studied. */
export function crewTenths(minutes: number): number {
  return Math.trunc(Math.max(Math.trunc(minutes), 0) / 6);
}

/** A crew's or member's focus time: always one decimal and the localized unit ("0.5 h", "39.6 h", "39,6 Std."), in the app's number format. */
export function crewHours(minutes: number, language: string = currentLanguage()): string {
  const number = new Intl.NumberFormat(numberLocale(language), {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  }).format(crewTenths(minutes) / 10);
  return tr("%@ h", number);
}

/** The time left in the week, in the largest two units that matter. */
export type CrewRemaining =
  | { readonly form: "lessThanAMinute"; readonly values: readonly [] }
  | { readonly form: "minutes"; readonly values: readonly [number] }
  | {
      readonly form: "hoursMinutes";
      readonly values: readonly [number, number];
    }
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

/** "New week in 3d 4h", the weekly board's countdown. */
export function crewCountdown(week: CrewWeek, now: Instant): string {
  return tr("New week in %@", crewRemaining(week.endsAt, now));
}

/** The week's end in the user's own time zone, for the countdown's tooltip: "Sunday 11:59 PM". */
export function crewWeekEnd(week: CrewWeek, language: string = currentLanguage(), timeZone?: string): string {
  return new Intl.DateTimeFormat(numberLocale(language), {
    weekday: "long",
    hour: "numeric",
    minute: "2-digit",
    timeZone,
  }).format(new Date((week.endsAt - 1) * 1000));
}

const ENGLISH_ORDINALS: Record<string, string> = {
  one: "st",
  two: "nd",
  few: "rd",
  other: "th",
};

/** A place as the language writes it, as Foundation's ordinal style does: "1st" and "12th" in English, "12." in German, "第12" in Japanese, "12" in Arabic. */
export function crewOrdinal(place: number, language: string = currentLanguage()): string {
  const n = String(Math.trunc(place));
  switch (language.split("-")[0]) {
    case "en":
      return n + (ENGLISH_ORDINALS[new Intl.PluralRules("en", { type: "ordinal" }).select(place)] ?? "th");
    case "de":
      return `${n}.`;
    case "ja":
    case "zh":
      return `第${n}`;
    case "ko":
      return `${n}번째`;
    case "fr":
      return place === 1 ? "1er" : `${n}e`;
    case "es":
      return `${n}.º`;
    case "pt":
      return `${n}º`;
    case "fil":
      return `ika${n}`;
    default:
      return n;
  }
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

/** "12 of 20 members". */
export function crewMembersOf(count: number, max: number): string {
  return tr("%lld of %lld members", count, max);
}

/** "9 members". */
export function crewMemberCount(count: number): string {
  return tr("%lld members", count);
}

/** "Wk 45" (the ISO week number) for a crew's history. */
export function crewWeekLabel(week: CrewWeek): string {
  return tr("Wk %lld", Number.parseInt(week.id.split("W").pop() ?? "", 10) || 0);
}
