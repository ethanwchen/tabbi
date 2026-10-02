// Presence: what a user is doing right now, as reported by heartbeats.
import { HEARTBEAT_SECONDS, HttpError, Obj, STATUSES, STUDY_METHODS, int, oneOf, parseDay, utcDay } from "./lib";

/** Body fields accepted by `POST /v1/presence`. */
export const PRESENCE_FIELDS = [
  "status", "method", "phaseEndsAt", "sessionMinutes", "todayMinutes", "streakDays", "day",
] as const;

/**
 * The last heartbeat of a user. `lastSeen` is server time (unix seconds). `day` is the client's local
 * calendar day that `todayMinutes` counts; the weekly leaderboard sums `todayMinutes` per day.
 */
export interface Presence {
  status: string;
  method: string | null;
  phaseEndsAt: number | null;
  sessionMinutes: number;
  todayMinutes: number;
  streakDays: number;
  day: string;
  lastSeen: number;
}

/** How far `phaseEndsAt` may be from now; generous to absorb client clock skew and long time blocks. */
const PHASE_WINDOW_S = 86_400;
const MINUTES_PER_DAY = 1440;

/** Recommended seconds until the next heartbeat for a status; `null` means stop sending (offline). */
export function heartbeatSeconds(status: string): number | null {
  return HEARTBEAT_SECONDS[status] ?? null;
}

/**
 * A user counts as online while their last heartbeat is younger than 2.5 heartbeat intervals, so one
 * lost or late heartbeat does not flicker them offline. An explicit `offline` heartbeat ends it at once.
 */
export function isOnline(p: Presence | null, now: number): boolean {
  if (!p) return false;
  const interval = heartbeatSeconds(p.status);
  return interval !== null && now - p.lastSeen <= interval * 2.5;
}

/**
 * Validates a heartbeat body and merges it over the previous presence. `status` is required; omitted
 * counters keep their previous value (0 for a first heartbeat, and `todayMinutes` restarts at 0 on a new
 * `day`). `day` defaults to the UTC day. `method` and `phaseEndsAt` describe the current session, so
 * they are cleared when the status is `idle` or `offline`.
 */
export function parseHeartbeat(body: Obj, prev: Presence | null, now: number): Presence {
  if (body.status === undefined) throw new HttpError(400, "invalid_field", "status is required");
  const status = oneOf(body.status, STATUSES, "status");
  const method = body.method === undefined || body.method === null ? null : oneOf(body.method, STUDY_METHODS, "method");
  const phaseEndsAt = body.phaseEndsAt === undefined || body.phaseEndsAt === null
    ? null
    : int(body.phaseEndsAt, "phaseEndsAt", now - PHASE_WINDOW_S, now + PHASE_WINDOW_S);
  const day = body.day === undefined ? utcDay(now) : parseDay(body.day, now);
  const inSession = status === "studying" || status === "break";
  const counter = (field: "sessionMinutes" | "todayMinutes" | "streakDays", max: number) =>
    body[field] !== undefined ? int(body[field], field, 0, max)
      : field === "todayMinutes" && prev?.day !== day ? 0
      : (prev?.[field] ?? 0);
  return {
    status,
    method: inSession ? method : null,
    phaseEndsAt: inSession ? phaseEndsAt : null,
    sessionMinutes: inSession ? counter("sessionMinutes", MINUTES_PER_DAY) : 0,
    todayMinutes: counter("todayMinutes", MINUTES_PER_DAY),
    streakDays: counter("streakDays", 36_500),
    day,
    lastSeen: now,
  };
}

/**
 * Whether a heartbeat changes what friends see in a way worth a storage write right away. Minute
 * counters and `lastSeen` tick every heartbeat, so they are only flushed periodically (see the Hub).
 */
export function presenceChanged(a: Presence, b: Presence): boolean {
  return a.status !== b.status || a.method !== b.method || a.phaseEndsAt !== b.phaseEndsAt || a.streakDays !== b.streakDays;
}

/** What friends see: a user who is not online shows as `offline` with no session. */
export function publicPresence(p: Presence | null, now: number): Presence | null {
  if (!p || isOnline(p, now)) return p;
  return { ...p, status: "offline", method: null, phaseEndsAt: null, sessionMinutes: 0 };
}
