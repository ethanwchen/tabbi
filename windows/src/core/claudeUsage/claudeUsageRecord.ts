import type { Instant } from "../time";

/** Port of ClaudeTokenUsage: token counts of one or more assistant messages. */
export interface ClaudeTokenUsage {
  input: number;
  output: number;
  cacheRead: number;
  cacheCreation: number;
}

export function tokenUsage(fields: Partial<ClaudeTokenUsage> = {}): ClaudeTokenUsage {
  return { input: 0, output: 0, cacheRead: 0, cacheCreation: 0, ...fields };
}

export const ZERO_TOKENS: Readonly<ClaudeTokenUsage> = tokenUsage();

/** Every token the model processed, including cache reads and writes. */
export function totalTokens(usage: ClaudeTokenUsage): number {
  return usage.input + usage.output + usage.cacheRead + usage.cacheCreation;
}

export function addTokens(a: ClaudeTokenUsage, b: ClaudeTokenUsage): ClaudeTokenUsage {
  return {
    input: a.input + b.input,
    output: a.output + b.output,
    cacheRead: a.cacheRead + b.cacheRead,
    cacheCreation: a.cacheCreation + b.cacheCreation,
  };
}

/** One assistant message from a Claude Code session transcript (`%USERPROFILE%\.claude\projects\**\*.jsonl`). */
export interface ClaudeUsageRecord {
  /**
   * API message id. Claude Code writes one line per content block, all
   * sharing the message id and its usage, so this is the dedupe key.
   */
  messageID: string;
  model: string;
  timestamp: Instant;
  usage: ClaudeTokenUsage;
}

/** A field of the wrong type, which makes Foundation's decoder reject the whole line. */
class WrongType extends Error {}

function optionalString(value: unknown): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") throw new WrongType();
  return value;
}

function optionalInt(value: unknown): number | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "number" || !Number.isInteger(value)) throw new WrongType();
  return value;
}

function optionalObject(value: unknown): Record<string, unknown> | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "object" || Array.isArray(value)) throw new WrongType();
  return value as Record<string, unknown>;
}

const ISO_8601 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$/;

/** An ISO 8601 timestamp with or without fractional seconds, as seconds since 1970; undefined otherwise. */
export function parseISOTimestamp(text: string): Instant | undefined {
  if (!ISO_8601.test(text)) return undefined;
  const milliseconds = Date.parse(text);
  return Number.isNaN(milliseconds) ? undefined : milliseconds / 1000;
}

/**
 * Parses one transcript line. Undefined for anything that isn't an assistant
 * message with usage, including malformed JSON and the `<synthetic>`
 * placeholder messages Claude Code writes for local errors. Most lines are
 * user turns or tool results, so they are turned away by a plain text
 * search before any JSON work.
 */
export function parseUsageRecord(line: string): ClaudeUsageRecord | undefined {
  if (!line.includes('"assistant"') || !line.includes('"usage"')) return undefined;
  try {
    const object = optionalObject(JSON.parse(line));
    if (!object || optionalString(object.type) !== "assistant") return undefined;
    const message = optionalObject(object.message);
    const timestampText = optionalString(object.timestamp);
    if (!message) return undefined;
    const id = optionalString(message.id);
    const model = optionalString(message.model);
    const usage = optionalObject(message.usage);
    if (id === undefined || model === undefined || model.startsWith("<") || !usage || timestampText === undefined) return undefined;
    const timestamp = parseISOTimestamp(timestampText);
    if (timestamp === undefined) return undefined;
    return {
      messageID: id,
      model,
      timestamp,
      usage: {
        input: optionalInt(usage.input_tokens) ?? 0,
        output: optionalInt(usage.output_tokens) ?? 0,
        cacheRead: optionalInt(usage.cache_read_input_tokens) ?? 0,
        cacheCreation: optionalInt(usage.cache_creation_input_tokens) ?? 0,
      },
    };
  } catch {
    return undefined;
  }
}
