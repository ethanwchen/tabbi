import type { Instant } from "../time";

/**
 * A local day as `yyyy-MM-dd`, the name of an activity day file. A narrow
 * stand-in for the Planner's PlannerDayKey (the planner port owns the full
 * type); the string form is the same, so the two are interchangeable.
 */
export type DayKey = string;

/** Whether `raw` is a well-formed `yyyy-MM-dd` that names a real date (PlannerDayKey(rawValue:)). */
export function isDayKey(raw: string): raw is DayKey {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (!match) return false;
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  if (month < 1 || month > 12 || day < 1) return false;
  return day <= new Date(Date.UTC(year, month, 0)).getUTCDate();
}

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatter(timeZone: string): Intl.DateTimeFormat {
  let cached = formatters.get(timeZone);
  if (!cached) {
    cached = new Intl.DateTimeFormat("en-US", {
      timeZone,
      calendar: "gregory",
      numberingSystem: "latn",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    formatters.set(timeZone, cached);
  }
  return cached;
}

/** The day containing `instant` on the wall clock of the IANA zone `timeZone`. */
export function dayKeyOf(instant: Instant, timeZone: string): DayKey {
  const parts = formatter(timeZone).formatToParts(new Date(instant * 1000));
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find((p) => p.type === type)?.value ?? "0";
  const year = Number(part("year"));
  return `${String(year).padStart(4, "0")}-${part("month").padStart(2, "0")}-${part("day").padStart(2, "0")}`;
}
