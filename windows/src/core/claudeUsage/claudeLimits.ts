import type { ClaudeRateLimitSnapshot, ClaudeStreamEvent, ClaudeUsageWindow } from "../claude/claudeStreamEvent";
import type { Instant } from "../time";

/**
 * Port of ClaudeLimitsRecord: the last live limits probe and when it
 * happened, persisted so the panel shows numbers at once on launch without
 * spending a probe.
 */
export interface ClaudeLimitsRecord {
  snapshot: ClaudeRateLimitSnapshot;
  fetchedAt: Instant;
}

/**
 * Each probe runs a tiny `claude -p` request that counts against the user's
 * own limits, so opening the panel only re-probes after this long.
 */
export const LIMITS_STALE_AFTER = 10 * 60;

/**
 * Whether opening the panel should probe. Never before the first manual
 * refresh: spending the user's usage is opt-in. Manual refresh always probes.
 */
export function shouldRefreshOnOpen(record: ClaudeLimitsRecord | undefined, now: Instant): boolean {
  if (!record) return false;
  return now - record.fetchedAt >= LIMITS_STALE_AFTER;
}

/** The stored form, version 1 with a `schemaVersion` key; times are seconds since 1970. */
export function encodeLimitsRecord(record: ClaudeLimitsRecord): string {
  return JSON.stringify({ schemaVersion: 1, ...record.snapshot, fetchedAt: record.fetchedAt });
}

function storedWindow(value: unknown): ClaudeUsageWindow | undefined | null {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "object") return null;
  const { utilization, resetsAt } = value as { utilization?: unknown; resetsAt?: unknown };
  if (typeof utilization !== "number" || (resetsAt !== undefined && resetsAt !== null && typeof resetsAt !== "number")) return null;
  return typeof resetsAt === "number" ? { utilization, resetsAt } : { utilization };
}

/** Decodes `encodeLimitsRecord` output; undefined for missing or corrupt data. */
export function decodeLimitsRecord(text: string | undefined): ClaudeLimitsRecord | undefined {
  if (text === undefined) return undefined;
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return undefined;
  }
  if (typeof value !== "object" || value === null) return undefined;
  const stored = value as Record<string, unknown>;
  if (stored.schemaVersion !== 1 || typeof stored.fetchedAt !== "number") return undefined;
  if (stored.status !== undefined && stored.status !== null && typeof stored.status !== "string") return undefined;
  const fiveHour = storedWindow(stored.fiveHour);
  const sevenDay = storedWindow(stored.sevenDay);
  if (fiveHour === null || sevenDay === null) return undefined;
  const snapshot: ClaudeRateLimitSnapshot = {};
  if (typeof stored.status === "string") snapshot.status = stored.status;
  if (fiveHour) snapshot.fiveHour = fiveHour;
  if (sevenDay) snapshot.sevenDay = sevenDay;
  return { snapshot, fetchedAt: stored.fetchedAt };
}

/** Why a limits probe found nothing. */
export type LimitsProbeFailure =
  /** The CLI finished without reporting limits (an API-key login has no subscription windows). */
  | { kind: "noLimitsReported" }
  /** The CLI reported an error result, e.g. not logged in. */
  | { kind: "cliError"; message?: string }
  /** No limits arrived in time. */
  | { kind: "timedOut" };

export class LimitsProbeError extends Error {
  constructor(readonly failure: LimitsProbeFailure) {
    super(`Claude limits probe: ${failure.kind}`);
    this.name = "LimitsProbeError";
  }
}

/** The probe's `claude -p` arguments: a trivial prompt to the cheapest model. */
export const LIMITS_PROBE_PROMPT = "ok";
export const LIMITS_PROBE_ARGUMENTS = ["--model", "haiku"] as const;

/**
 * Port of ClaudeLimitsProbe.firstSnapshot: the first rate-limit event that
 * carries a usage window. The CLI reports one near the start of every
 * request, so the probe stops consuming `events` (which stops the process)
 * as soon as it arrives, before an answer is generated. A `signal` that
 * times out (`AbortSignal.timeout`) fails with `timedOut`.
 */
export async function firstLimitsSnapshot(events: AsyncIterable<ClaudeStreamEvent>, signal?: AbortSignal): Promise<ClaudeRateLimitSnapshot> {
  const timedOut = () => new LimitsProbeError({ kind: "timedOut" });
  if (signal?.aborted) throw timedOut();
  let onAbort: (() => void) | undefined;
  const abort = new Promise<never>((_, reject) => {
    onAbort = () => reject(timedOut());
    signal?.addEventListener("abort", onAbort, { once: true });
  });
  abort.catch(() => undefined);
  const iterator = events[Symbol.asyncIterator]();
  try {
    for (;;) {
      const step = await Promise.race([iterator.next(), abort]);
      if (step.done) throw new LimitsProbeError({ kind: "noLimitsReported" });
      const event = step.value;
      if (event.type === "rateLimit" && (event.snapshot.fiveHour || event.snapshot.sevenDay)) return event.snapshot;
      if (event.type === "result" && event.result.isError) {
        throw new LimitsProbeError(event.result.text === undefined ? { kind: "cliError" } : { kind: "cliError", message: event.result.text });
      }
    }
  } finally {
    if (onAbort) signal?.removeEventListener("abort", onAbort);
    iterator.return?.()?.catch(() => undefined);
  }
}
