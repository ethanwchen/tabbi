/*
 * JSON values as the core reads and writes them, plus the one serializer
 * every persisted file goes through, so a document always comes out the
 * same way for the same value.
 */

export type JSONPrimitive = string | number | boolean | null;
export type JSONValue = JSONPrimitive | JSONValue[] | JSONObject;
export interface JSONObject {
  [key: string]: JSONValue;
}

/** True for a plain JSON object (not an array, not null). */
export function isJSONObject(value: unknown): value is JSONObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Options for `stringifyJSON`, after Foundation's `JSONEncoder.OutputFormatting`. */
export interface JSONFormatting {
  /** Two-space indents and `"key" : value`, the way `.prettyPrinted` writes. */
  readonly pretty?: boolean;
  /** Keys in code-unit order, the way `.sortedKeys` writes. */
  readonly sortedKeys?: boolean;
}

/**
 * Serializes `value` like Foundation's `JSONEncoder`: forward slashes are
 * escaped (`\/`) as the Mac writes them, keys can be sorted, and pretty
 * output puts a space on both sides of the colon and writes an empty array
 * or object as its brackets around a blank line. `undefined` members are
 * left out, as a Swift optional that is nil is.
 */
export function stringifyJSON(value: unknown, formatting: JSONFormatting = {}): string {
  return write(value, formatting, "");
}

function write(value: unknown, formatting: JSONFormatting, indent: string): string {
  if (value === null) return "null";
  if (typeof value === "string") return quote(value);
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new TypeError("JSON can't hold a non-finite number");
    return JSON.stringify(value);
  }
  if (typeof value === "boolean") return value ? "true" : "false";
  const inner = formatting.pretty ? `${indent}  ` : "";
  const newline = formatting.pretty ? "\n" : "";
  if (Array.isArray(value)) {
    if (value.length === 0) return formatting.pretty ? `[\n\n${indent}]` : "[]";
    const items = value.map((item: unknown) => inner + write(item === undefined ? null : item, formatting, inner));
    return `[${newline}${items.join(`,${newline}`)}${newline}${formatting.pretty ? indent : ""}]`;
  }
  if (typeof value === "object") {
    let keys = Object.keys(value).filter((key) => (value as Record<string, unknown>)[key] !== undefined);
    if (formatting.sortedKeys) keys = keys.sort(compareCodeUnits);
    if (keys.length === 0) return formatting.pretty ? `{\n\n${indent}}` : "{}";
    const colon = formatting.pretty ? " : " : ":";
    const members = keys.map(
      (key) => inner + quote(key) + colon + write((value as Record<string, unknown>)[key], formatting, inner),
    );
    return `{${newline}${members.join(`,${newline}`)}${newline}${formatting.pretty ? indent : ""}}`;
  }
  throw new TypeError(`JSON can't hold a ${typeof value}`);
}

function quote(text: string): string {
  return JSON.stringify(text).replace(/\//g, "\\/");
}

function compareCodeUnits(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}
