/**
 * Aggregate counts for the maintainer (`GET /v1/admin/stats`). The app sends nothing for them: every
 * number is counted from rows the service already keeps to work (users, Apple account links, the last
 * heartbeat per user, parties), and only totals leave the server, never a friend code or a profile.
 */
import { utcDay } from "./lib";

/** How many UTC days of new friend codes the stats list, today included. */
export const SIGNUP_DAYS = 30;

/** The active-user windows: users whose last heartbeat is at most this old. */
export const ACTIVE_WINDOWS_S = { day: 86_400, week: 7 * 86_400, month: 30 * 86_400 } as const;

export type ActiveCounts = Record<keyof typeof ACTIVE_WINDOWS_S, number>;

/** A user's heartbeat as the Hub holds it in memory: the latest one, and when its row was last written. */
export interface LiveHeartbeat {
  lastSeen: number;
  flushedAt: number;
}

/**
 * Users active in each window. `persisted` counts presence rows by their written `last_seen`; a user
 * whose newer heartbeat is still only in memory (`live`) is added to a window their row misses. A row's
 * `last_seen` is the time it was flushed, so `flushedAt` says which windows the row already counts in.
 */
export function activeCounts(
  persisted: (since: number) => number, live: Iterable<LiveHeartbeat>, now: number,
): ActiveCounts {
  const counts = {} as ActiveCounts;
  const heartbeats = [...live];
  for (const [window, seconds] of Object.entries(ACTIVE_WINDOWS_S) as [keyof ActiveCounts, number][]) {
    const since = now - seconds;
    counts[window] = persisted(since) + heartbeats.filter((h) => h.lastSeen >= since && h.flushedAt < since).length;
  }
  return counts;
}

/**
 * New friend codes per UTC day for the last SIGNUP_DAYS days, oldest first, with every day listed
 * (zero when nobody signed up). `counts` maps a UTC day (`YYYY-MM-DD`) to its count.
 */
export function signupsByDay(counts: Map<string, number>, now: number): { day: string; users: number }[] {
  const days: { day: string; users: number }[] = [];
  for (let i = SIGNUP_DAYS - 1; i >= 0; i--) {
    const day = utcDay(now - i * 86_400);
    days.push({ day, users: counts.get(day) ?? 0 });
  }
  return days;
}

/** The first second of the oldest day `signupsByDay` lists. */
export const signupsSince = (now: number) => Math.floor(now / 86_400) * 86_400 - (SIGNUP_DAYS - 1) * 86_400;

/**
 * The public badge (`GET /v1/public/stats`) is computed at most this often and cached by the Hub, so a
 * README full of viewers costs at most one count per interval; the reply carries the same max-age.
 */
export const PUBLIC_STATS_TTL_S = 3600;
/** Public badge requests per minute per client IP; shields.io's own cache absorbs most traffic. */
export const PUBLIC_STATS_PER_MIN = 30;

/** Which number the public badge shows: users active in the last 7 days, or every friend code made. */
export type PublicMetric = "week" | "total";

/** The badge label for each metric. */
export const PUBLIC_LABELS: Record<PublicMetric, string> = {
  week: "focusing this week",
  total: "Tabbi friends",
};

/**
 * A count as the public may see it: rounded down to two significant digits with a `+`, so the badge
 * never moves by one person ("1.2k+", "87+"), and "under 10" below ten, so no tiny exact figure shows.
 */
export function roundedCount(n: number): string {
  if (!Number.isFinite(n) || n < 10) return "under 10";
  const step = 10 ** (Math.floor(Math.log10(n)) - 1);
  const rounded = Math.floor(n / step) * step;
  if (rounded >= 1_000_000) return `${trim(rounded / 1_000_000)}M+`;
  if (rounded >= 1_000) return `${trim(rounded / 1_000)}k+`;
  return `${rounded}+`;
}

const trim = (n: number) => String(Number(n.toFixed(1)));

/** A shields.io endpoint badge (https://shields.io/badges/endpoint-badge). */
export interface EndpointBadge {
  schemaVersion: 1;
  label: string;
  message: string;
  color: string;
  cacheSeconds: number;
}

/** The shields.io endpoint JSON for one metric, in Tabbi's accent color. */
export function publicBadge(metric: PublicMetric, counts: Record<PublicMetric, number>): EndpointBadge {
  return {
    schemaVersion: 1,
    label: PUBLIC_LABELS[metric],
    message: roundedCount(counts[metric]),
    color: "E8A15F",
    cacheSeconds: PUBLIC_STATS_TTL_S,
  };
}

/** The `metric` query parameter, `week` when absent; anything else is null (a 400). */
export function parsePublicMetric(value: string | null): PublicMetric | null {
  if (value === null || value === "") return "week";
  return value === "week" || value === "total" ? value : null;
}
