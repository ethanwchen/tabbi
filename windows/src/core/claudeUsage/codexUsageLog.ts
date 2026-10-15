import type { ClaudeRateLimitSnapshot, ClaudeUsageWindow } from "../claude/claudeStreamEvent";
import type { Instant } from "../time";
import type { ClaudeLimitsRecord } from "./claudeLimits";
import { aggregateUsage, type ClaudeLocalStats, windowStart } from "./claudeLocalStats";
import { type ClaudeTokenUsage, type ClaudeUsageRecord, parseISOTimestamp, tokenUsage, totalTokens, ZERO_TOKENS } from "./claudeUsageRecord";

/**
 * Port of CodexUsage: what the Codex CLI's own session logs say about usage,
 * its latest 5-hour and weekly limits and the tokens it used today and this
 * week. Reading them costs the user nothing, unlike a live Claude probe.
 */
export interface CodexUsage {
  /** The newest limits any session logged, stamped with when; undefined with no limits (API-key sign-in). */
  limits?: ClaudeLimitsRecord;
  stats: ClaudeLocalStats;
}

/** Shown when a session never named its model (very old Codex versions). */
export const CODEX_DEFAULT_MODEL = "codex";

/** `%CODEX_HOME%\sessions`, or `%USERPROFILE%\.codex\sessions` when CODEX_HOME is unset. */
export function codexSessionsRoot(userProfile: string, codexHome?: string): string {
  const home = codexHome && codexHome.length > 0 ? codexHome : `${userProfile.replace(/[\\/]+$/, "")}\\.codex`;
  return `${home.replace(/[\\/]+$/, "")}\\sessions`;
}

/** Which session files to read: every `*.jsonl` touched in the last seven days. */
export function codexFilesToRead<T extends { path: string; modified: Instant }>(files: readonly T[], now: Instant, timeZone: string): T[] {
  const start = windowStart(now, timeZone);
  return files.filter((file) => file.path.toLowerCase().endsWith(".jsonl") && file.modified >= start);
}

type CodexLine = { kind: "model"; name: string } | { kind: "tokens"; timestamp: Instant; total: ClaudeTokenUsage; limits?: ClaudeRateLimitSnapshot };

function object(value: unknown): Record<string, unknown> | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : undefined;
}

function num(value: unknown): number | undefined {
  return typeof value === "number" ? value : undefined;
}

/** One `primary` or `secondary` window, with `resets_at` epoch seconds or the older `resets_in_seconds`. */
function codexWindow(value: unknown, timestamp: Instant): ClaudeUsageWindow | undefined {
  const window = object(value);
  const usedPercent = num(window?.used_percent);
  if (!window || usedPercent === undefined) return undefined;
  const resetsAt = num(window.resets_at) ?? (num(window.resets_in_seconds) === undefined ? undefined : timestamp + (num(window.resets_in_seconds) ?? 0));
  return resetsAt === undefined ? { utilization: usedPercent / 100 } : { utilization: usedPercent / 100, resetsAt };
}

/**
 * Codex has logged limits in two shapes: nested `primary`/`secondary`
 * windows, and before those flat `primary_used_percent` fields with no reset
 * time. Its primary window is the 5-hour one and its secondary the weekly one.
 */
function codexLimits(value: unknown, timestamp: Instant): ClaudeRateLimitSnapshot | undefined {
  const limits = object(value);
  if (!limits) return undefined;
  const flat = (key: string): ClaudeUsageWindow | undefined => {
    const percent = num(limits[key]);
    return percent === undefined ? undefined : { utilization: percent / 100 };
  };
  const fiveHour = codexWindow(limits.primary, timestamp) ?? flat("primary_used_percent");
  const weekly = codexWindow(limits.secondary, timestamp) ?? flat("secondary_used_percent");
  if (!fiveHour && !weekly) return undefined;
  return { ...(fiveHour ? { fiveHour } : {}), ...(weekly ? { sevenDay: weekly } : {}) };
}

/** Parses one rollout line; undefined for anything but a model change or a token count. */
export function parseCodexLine(line: string): CodexLine | undefined {
  const isTokens = line.includes('"token_count"');
  if (!isTokens && !line.includes('"turn_context"')) return undefined;
  let entry: Record<string, unknown> | undefined;
  try {
    entry = object(JSON.parse(line));
  } catch {
    return undefined;
  }
  const payload = object(entry?.payload);
  if (!entry || !payload) return undefined;
  if (entry.type === "turn_context") {
    return typeof payload.model === "string" && payload.model.length > 0 ? { kind: "model", name: payload.model } : undefined;
  }
  if (entry.type !== "event_msg" || payload.type !== "token_count" || typeof entry.timestamp !== "string") return undefined;
  const timestamp = parseISOTimestamp(entry.timestamp);
  if (timestamp === undefined) return undefined;
  const usage = object(object(payload.info)?.total_token_usage);
  /* Codex counts cached input inside input_tokens, and reasoning inside output_tokens. */
  const total = usage
    ? (() => {
        const cached = num(usage.cached_input_tokens) ?? 0;
        return tokenUsage({ input: Math.max((num(usage.input_tokens) ?? 0) - cached, 0), output: num(usage.output_tokens) ?? 0, cacheRead: cached });
      })()
    : undefined;
  const limits = codexLimits(payload.rate_limits, timestamp);
  if (!total && !limits) return undefined;
  return limits ? { kind: "tokens", timestamp, total: total ?? { ...ZERO_TOKENS }, limits } : { kind: "tokens", timestamp, total: total ?? { ...ZERO_TOKENS } };
}

function difference(a: ClaudeTokenUsage, b: ClaudeTokenUsage): ClaudeTokenUsage {
  return tokenUsage({
    input: Math.max(a.input - b.input, 0),
    output: Math.max(a.output - b.output, 0),
    cacheRead: Math.max(a.cacheRead - b.cacheRead, 0),
  });
}

/**
 * `window` as of `now`: empty once its reset time has passed, or, for old
 * logs with no reset time, once a whole window has gone by.
 */
function current(window: ClaudeUsageWindow | undefined, length: number, fetchedAt: Instant, now: Instant): ClaudeUsageWindow | undefined {
  if (!window) return undefined;
  const hasReset = window.resetsAt !== undefined ? window.resetsAt <= now : now - fetchedAt >= length;
  return hasReset ? { utilization: 0 } : window;
}

/** Aggregates the given session files, each one rollout's text. */
export function summarizeCodexSessions(sessions: readonly string[], now: Instant, timeZone: string): CodexUsage {
  const records: ClaudeUsageRecord[] = [];
  let latest: ClaudeLimitsRecord | undefined;
  for (const session of sessions) {
    let model = CODEX_DEFAULT_MODEL;
    let previous: ClaudeTokenUsage = { ...ZERO_TOKENS };
    for (const text of session.split("\n")) {
      const line = parseCodexLine(text);
      if (!line) continue;
      if (line.kind === "model") {
        model = line.name;
        continue;
      }
      /* Totals are cumulative per session; each increase is one model turn. A drop means the counter restarted. */
      const delta = totalTokens(line.total) < totalTokens(previous) ? line.total : difference(line.total, previous);
      previous = line.total;
      if (totalTokens(delta) > 0) records.push({ messageID: "", model, timestamp: line.timestamp, usage: delta });
      if (line.limits && line.timestamp <= now && line.timestamp > (latest?.fetchedAt ?? -Infinity)) {
        latest = { snapshot: line.limits, fetchedAt: line.timestamp };
      }
    }
  }
  if (latest) {
    /* Codex only logs limits when it runs, so a window that has reset since the last session is empty now. */
    const { snapshot, fetchedAt } = latest;
    const fiveHour = current(snapshot.fiveHour, 5 * 3600, fetchedAt, now);
    const sevenDay = current(snapshot.sevenDay, 7 * 86_400, fetchedAt, now);
    latest = {
      fetchedAt,
      snapshot: {
        ...(snapshot.status === undefined ? {} : { status: snapshot.status }),
        ...(fiveHour ? { fiveHour } : {}),
        ...(sevenDay ? { sevenDay } : {}),
      },
    };
  }
  const stats = aggregateUsage(records, now, timeZone);
  return latest ? { limits: latest, stats } : { stats };
}
