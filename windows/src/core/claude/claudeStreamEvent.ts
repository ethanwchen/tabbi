import type { Instant } from "../time";

/** One window of the Claude subscription usage limit (5-hour or weekly). */
export interface ClaudeUsageWindow {
  /** 0 to 1, above 1 when over the limit. */
  utilization: number;
  resetsAt?: Instant;
}

/** Live usage the `claude` CLI reports in its `rate_limit_event`. */
export interface ClaudeRateLimitSnapshot {
  status?: string;
  fiveHour?: ClaudeUsageWindow;
  sevenDay?: ClaudeUsageWindow;
}

export interface ClaudeResult {
  text?: string;
  sessionID?: string;
  isError: boolean;
}

/**
 * Port of ClaudeStreamEvent: a parsed line of
 * `claude -p --output-format stream-json --verbose` output.
 */
export type ClaudeStreamEvent =
  /** `system/init`; carries the session id used for `--resume`. */
  | { type: "sessionStarted"; sessionID?: string }
  /** Usage-limit utilization, emitted on every call. */
  | { type: "rateLimit"; snapshot: ClaudeRateLimitSnapshot }
  /** Incremental text (requires `--include-partial-messages`). */
  | { type: "textDelta"; text: string }
  /** The joined text blocks of one complete assistant message. */
  | { type: "assistantText"; text: string }
  /** Final event of a run. */
  | { type: "result"; result: ClaudeResult }
  /** Anything else (tool use, hooks, unparseable lines). */
  | { type: "other" };

type JsonObject = Record<string, unknown>;

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function string(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

/** A JSON number as Foundation's `NSNumber` bridging reads it (a JSON bool is 1 or 0). */
function number(value: unknown): number | undefined {
  if (typeof value === "number") return value;
  if (typeof value === "boolean") return value ? 1 : 0;
  return undefined;
}

/** A JSON value as Foundation's `as? Bool` reads it: a bool, or the numbers 0 and 1. */
function bool(value: unknown): boolean | undefined {
  if (typeof value === "boolean") return value;
  if (value === 0 || value === 1) return value === 1;
  return undefined;
}

function window(value: unknown): ClaudeUsageWindow | undefined {
  if (!isObject(value)) return undefined;
  const utilization = number(value.utilization);
  if (utilization === undefined) return undefined;
  const resetsAt = number(value.resetsAt);
  return resetsAt === undefined ? { utilization } : { utilization, resetsAt };
}

/** Parses one JSONL line. Never throws: unknown shapes become `other`. */
export function parseClaudeStreamLine(line: string): ClaudeStreamEvent {
  let object: unknown;
  try {
    object = JSON.parse(line);
  } catch {
    return { type: "other" };
  }
  if (!isObject(object)) return { type: "other" };
  const type = string(object.type);
  if (type === undefined) return { type: "other" };

  switch (type) {
    case "system": {
      if (object.subtype !== "init") return { type: "other" };
      const sessionID = string(object.session_id);
      return sessionID === undefined ? { type: "sessionStarted" } : { type: "sessionStarted", sessionID };
    }
    case "rate_limit_event": {
      const info = object.rate_limit_info;
      if (!isObject(info)) return { type: "other" };
      const windows = isObject(info.unifiedWindows) ? info.unifiedWindows : undefined;
      const snapshot: ClaudeRateLimitSnapshot = {};
      const status = string(info.status);
      if (status !== undefined) snapshot.status = status;
      const fiveHour = window(windows?.five_hour);
      if (fiveHour) snapshot.fiveHour = fiveHour;
      const sevenDay = window(windows?.seven_day);
      if (sevenDay) snapshot.sevenDay = sevenDay;
      return { type: "rateLimit", snapshot };
    }
    case "stream_event": {
      const event = object.event;
      if (!isObject(event) || event.type !== "content_block_delta") return { type: "other" };
      const delta = event.delta;
      if (!isObject(delta) || delta.type !== "text_delta") return { type: "other" };
      const text = string(delta.text);
      return text === undefined ? { type: "other" } : { type: "textDelta", text };
    }
    case "assistant": {
      const message = object.message;
      if (!isObject(message) || !Array.isArray(message.content)) return { type: "other" };
      if (!message.content.every(isObject)) return { type: "other" };
      const text = (message.content as JsonObject[])
        .filter((block) => block.type === "text")
        .map((block) => string(block.text) ?? "")
        .join("");
      return text.length === 0 ? { type: "other" } : { type: "assistantText", text };
    }
    case "result": {
      const result: ClaudeResult = { isError: bool(object.is_error) ?? object.subtype !== "success" };
      const text = string(object.result);
      if (text !== undefined) result.text = text;
      const sessionID = string(object.session_id);
      if (sessionID !== undefined) result.sessionID = sessionID;
      return { type: "result", result };
    }
    default:
      return { type: "other" };
  }
}
