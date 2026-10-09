/**
 * Structured logs: one JSON object per line, which Workers Logs indexes field by field, so the
 * dashboard can filter on `event`, `route` or `status` and alert on `level`.
 *
 * Privacy: a log line carries only what is passed in here, and callers pass route templates, status
 * codes, durations and error names. Paths are reduced to templates (`/v1/friends/:id`) before they are
 * logged, so friend codes, party codes and ids never reach a log; tokens, IP addresses, names and
 * request bodies are never passed at all. Cloudflare's own invocation logs (which carry the full URL
 * and headers) are turned off in wrangler.toml for the same reason.
 */

export type LogLevel = "info" | "warn" | "error";
export type LogValue = string | number | boolean | null;

/** Share of successful, fast requests that get a `request` line; errors and slow requests always do. */
export const REQUEST_SAMPLE_RATE = 0.01;
/** A request slower than this is always logged, as a warning. */
export const SLOW_REQUEST_MS = 2_000;

/** Every fixed path segment of the API. Any other segment is an id and is logged as `:id`. */
const STATIC_SEGMENTS = new Set([
  "v1", "admin", "apple", "auth", "ban", "blocks", "catalog", "dismiss", "export", "friends", "grants", "health",
  "join", "leaderboard", "leave", "me", "party", "presence", "register", "rename", "reports", "restore", "session",
  "signout", "stats", "suggestions", "sync", "users",
]);

/**
 * The route template of a path: `/v1/admin/users/AB3D5F7H/ban` becomes `/v1/admin/users/:id/ban`.
 * Paths outside `/v1/` (scanners probing `/wp-login.php`) all become `other`, so they cannot flood the
 * logs with distinct values.
 */
export function routeOf(path: string): string {
  const trimmed = path.replace(/\/+$/, "") || "/";
  if (trimmed === "/") return "/";
  const segments = trimmed.split("/").slice(1);
  if (segments[0] !== "v1") return "other";
  return "/" + segments.map((s) => (STATIC_SEGMENTS.has(s) ? s : ":id")).join("/");
}

/** Writes one structured line. `error` goes to console.error so it shows as an error in Workers Logs. */
export function logEvent(level: LogLevel, event: string, fields: Record<string, LogValue> = {}): void {
  const line = JSON.stringify({ level, event, ...fields });
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
}

/**
 * The fields of an unexpected exception: its name and the first line of its message, cut to 200
 * characters. Messages come from our own code and from SQLite (`UNIQUE constraint failed: users.code`)
 * and name tables and columns, never values.
 */
export function errorFields(e: unknown): Record<string, LogValue> {
  if (e instanceof Error) return { errorName: e.name, errorMessage: e.message.split("\n", 1)[0].slice(0, 200) };
  return { errorName: typeof e, errorMessage: null };
}

export interface RequestOutcome {
  method: string;
  path: string;
  status: number;
  ms: number;
}

/**
 * Whether and how a finished request is logged: every 5xx as an error, every slow request as a
 * warning, and a `REQUEST_SAMPLE_RATE` sample of the rest (4xx included, so rate limiting and bad
 * tokens show up) as info. Sampling keeps the log volume (and its cost on the Paid plan) at about one
 * line per hundred requests while still showing per-route latency and status mix.
 * `random` is a number in [0, 1), injected so tests can decide the sample.
 */
export function requestLog(outcome: RequestOutcome, random: number): { level: LogLevel; fields: Record<string, LogValue> } | null {
  const level: LogLevel | null = outcome.status >= 500 ? "error"
    : outcome.ms >= SLOW_REQUEST_MS ? "warn"
    : random < REQUEST_SAMPLE_RATE ? "info"
    : null;
  if (!level) return null;
  return {
    level,
    fields: {
      method: outcome.method.toUpperCase().slice(0, 8),
      route: routeOf(outcome.path),
      status: outcome.status,
      ms: Math.round(outcome.ms),
      sampled: level === "info",
    },
  };
}
