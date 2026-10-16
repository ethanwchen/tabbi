import type { ClaudeRateLimitSnapshot, ClaudeStreamEvent, ClaudeUsageWindow } from "../claude/claudeStreamEvent";
import { defaultsString, type Defaults } from "../persistence/defaults";
import { isJSONObject, type JSONObject, type JSONValue } from "../persistence/json";
import { VersionedJSON } from "../persistence/versionedJson";
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

/** The preferences key ClaudeUsageStore saves the record under, as JSON text (the Mac keeps it as `Data`). */
export const CLAUDE_LIMITS_DEFAULTS_KEY = "claudeUsage.limitsRecord";

/** Port of ClaudeLimitsRecord.schema: the stored format. Version 1 added the `schemaVersion` key. */
export const CLAUDE_LIMITS_SCHEMA = new VersionedJSON(1);

/** Seconds from 1970 to 2001, the reference date Foundation encodes dates against by default. */
const REFERENCE_DATE_OFFSET = 978_307_200;

function storedWindow(value: ClaudeUsageWindow | undefined): JSONObject | undefined {
  if (value === undefined) return undefined;
  const window: JSONObject = { utilization: value.utilization };
  if (value.resetsAt !== undefined) window.resetsAt = value.resetsAt - REFERENCE_DATE_OFFSET;
  return window;
}

/**
 * Port of ClaudeLimitsRecord.encoded(): the Swift's private `Stored` shape
 * (status, fiveHour, sevenDay, fetchedAt; dates as seconds since 2001, the
 * default JSONEncoder's), stamped with the schema version. Undefined when a
 * value can't be written as JSON.
 */
export function encodeLimitsRecord(record: ClaudeLimitsRecord): string | undefined {
  const stored: Record<string, JSONValue | undefined> = {
    status: record.snapshot.status,
    fiveHour: storedWindow(record.snapshot.fiveHour),
    sevenDay: storedWindow(record.snapshot.sevenDay),
    fetchedAt: record.fetchedAt - REFERENCE_DATE_OFFSET,
  };
  try {
    return CLAUDE_LIMITS_SCHEMA.encode(stored);
  } catch {
    return undefined;
  }
}

function finite(value: JSONValue | undefined, key: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new TypeError(`Invalid ${key}`);
  return value;
}

/* Like Swift's decodeIfPresent: missing or null is nothing, a value of another type is an error. */
function readWindow(value: JSONValue | undefined): ClaudeUsageWindow | undefined {
  if (value === undefined || value === null) return undefined;
  if (!isJSONObject(value)) throw new TypeError("Invalid window");
  const utilization = finite(value.utilization, "utilization");
  if (value.resetsAt === undefined || value.resetsAt === null) return { utilization };
  return { utilization, resetsAt: finite(value.resetsAt, "resetsAt") + REFERENCE_DATE_OFFSET };
}

/** Reads the `Stored` shape; throws when a key holds a value of the wrong type or `fetchedAt` is missing. */
function readLimitsRecord(document: JSONObject): ClaudeLimitsRecord {
  const status = document.status;
  if (status !== undefined && status !== null && typeof status !== "string") throw new TypeError("Invalid status");
  const fiveHour = readWindow(document.fiveHour);
  const sevenDay = readWindow(document.sevenDay);
  const snapshot: ClaudeRateLimitSnapshot = {};
  if (typeof status === "string") snapshot.status = status;
  if (fiveHour) snapshot.fiveHour = fiveHour;
  if (sevenDay) snapshot.sevenDay = sevenDay;
  return { snapshot, fetchedAt: finite(document.fetchedAt, "fetchedAt") + REFERENCE_DATE_OFFSET };
}

/**
 * Port of ClaudeLimitsRecord.init?(encoded:): undefined for missing or
 * corrupt data. A document from a newer build is read as it is, ignoring
 * keys it doesn't know, as VersionedJSON reads every format.
 */
export function decodeLimitsRecord(text: string | undefined): ClaudeLimitsRecord | undefined {
  if (text === undefined) return undefined;
  try {
    return CLAUDE_LIMITS_SCHEMA.decode(text, readLimitsRecord);
  } catch {
    return undefined;
  }
}

/** The saved record, as ClaudeUsageStore reads it at launch; undefined when none is saved or it can't be read. */
export function loadLimitsRecord(defaults: Defaults): ClaudeLimitsRecord | undefined {
  return decodeLimitsRecord(defaultsString(defaults, CLAUDE_LIMITS_DEFAULTS_KEY));
}

/** Saves `record` after a probe; one that can't be encoded clears the key, as setting nil does on the Mac. */
export function saveLimitsRecord(defaults: Defaults, record: ClaudeLimitsRecord): void {
  const text = encodeLimitsRecord(record);
  if (text === undefined) defaults.remove(CLAUDE_LIMITS_DEFAULTS_KEY);
  else defaults.set(CLAUDE_LIMITS_DEFAULTS_KEY, text);
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
