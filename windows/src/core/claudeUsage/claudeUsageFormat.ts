import { durationSeconds } from "../formatting/durationFormat";
import type { Instant } from "../time";

/** Port of ClaudeUsageLevel: how close a usage window is to its limit; drives the ring color. */
export type ClaudeUsageLevel = "normal" | "warning" | "critical";

/** Under 70% normal, 70% up to 90% warning, above 90% critical. */
export function usageLevel(utilization: number): ClaudeUsageLevel {
  if (utilization < 0.7) return "normal";
  if (utilization <= 0.9) return "warning";
  return "critical";
}

/** Swift's `.rounded()`: half away from zero. */
function round(value: number): number {
  return Math.sign(value) * Math.round(Math.abs(value));
}

function number(value: number): string {
  if (value >= 99.95) return String(round(value));
  const rounded = round(value * 10) / 10;
  return rounded === round(rounded) ? String(round(rounded)) : rounded.toFixed(1);
}

/**
 * Compact token count: 950, 12.3K, 1.2M, 3.4B. One decimal below 100 of a
 * unit, none above, and never a trailing ".0".
 */
export function compactTokens(count: number): string {
  const value = Math.max(count, 0);
  const units: [number, string][] = [
    [1e9, "B"],
    [1e6, "M"],
    [1e3, "K"],
  ];
  /* Thresholds sit just below each unit so 999,950 reads "1M", not "1000K". */
  for (const [size, suffix] of units) if (value >= size * 0.9995) return number(value / size) + suffix;
  return String(Math.trunc(value));
}

/** Whole percent, clamped at 0 but allowed above 100 (over the limit). */
export function percentText(utilization: number): string {
  return `${round(Math.max(utilization, 0) * 100)}%`;
}

/**
 * "resets in 2h 14m" when the reset is within a day, otherwise the weekday
 * and time, e.g. "resets Thu 9:00 AM". Undefined without a reset time.
 */
export function resetDescription(resetsAt: Instant | undefined, now: Instant, timeZone: string, locale = "en-US"): string | undefined {
  if (resetsAt === undefined) return undefined;
  const seconds = resetsAt - now;
  if (seconds <= 0) return "resets now";
  if (seconds < 24 * 3600) return "resets in " + durationSeconds(seconds);
  const text = new Intl.DateTimeFormat(locale, { timeZone, weekday: "short", hour: "numeric", minute: "2-digit" }).format(
    new Date(resetsAt * 1000),
  );
  return "resets " + text;
}

/** "Updated just now", "Updated 3m ago", "Updated 2h ago", "Updated 3d ago". */
export function updatedDescription(fetchedAt: Instant, now: Instant): string {
  const seconds = Math.max(now - fetchedAt, 0);
  if (seconds < 60) return "Updated just now";
  if (seconds < 3600) return `Updated ${Math.trunc(seconds / 60)}m ago`;
  if (seconds < 24 * 3600) return `Updated ${Math.trunc(seconds / 3600)}h ago`;
  return `Updated ${Math.trunc(seconds / 86_400)}d ago`;
}

const allDigits = (text: string) => text.length > 0 && /^\p{Nd}+$/u.test(text);

/**
 * Human model name from an API model id: "claude-opus-4-5-20251101" reads
 * "Opus 4.5", "claude-3-5-sonnet-20241022" reads "Sonnet 3.5", and OpenAI's
 * "gpt-5-codex" reads "GPT-5 Codex". Unknown ids are returned unchanged.
 */
export function modelName(id: string): string {
  if (id.toLowerCase().startsWith("gpt-")) return openAIModelName(id);
  let parts = id
    .toLowerCase()
    .split("-")
    .filter((part) => part.length > 0);
  if (parts[0] !== "claude") return id;
  parts = parts.slice(1);
  /* Drop a trailing date stamp (YYYYMMDD) and context suffixes like "[1m]". */
  parts = parts.filter((part) => !([...part].length === 8 && allDigits(part)));
  const familyIndex = parts.findIndex((part) => /^\p{L}/u.test(part));
  const familyPart = parts[familyIndex];
  if (familyIndex < 0 || familyPart === undefined) return id;
  const family = familyPart.replaceAll("[1m]", "");
  const version = parts
    .filter((_, index) => index !== familyIndex)
    .map((part) => part.replaceAll("[1m]", ""))
    .filter(allDigits);
  if (family.length === 0) return id;
  const name = family.slice(0, 1).toUpperCase() + family.slice(1);
  return version.length === 0 ? name : `${name} ${version.join(".")}`;
}

/** "gpt-5.1-codex-mini" reads "GPT-5.1 Codex Mini": the version stays joined to GPT, the rest are capitalized words. */
function openAIModelName(id: string): string {
  const parts = id.split("-").filter((part) => part.length > 0);
  const version = parts[1];
  if (version === undefined) return id;
  const words = parts.slice(2).map((part) => part.slice(0, 1).toUpperCase() + part.slice(1));
  return ["GPT-" + version, ...words].join(" ");
}
