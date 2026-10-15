import { isJSONObject, type JSONObject, type JSONValue } from "./json";
import type { DocumentStore } from "./documentStore";

/**
 * Preferences as the Mac keeps them in `UserDefaults`: one JSON value per
 * key, read and written synchronously, so settings code can load and save
 * a value the way the Swift does. A value the Mac stores as `Data` (an
 * encoded JSON document such as the hotkey) is kept here as that JSON text.
 *
 * The host loads every key once at launch (`loadDefaults`) and writes them
 * back as one document after changes (`saveDefaults`).
 */
export interface Defaults {
  get(key: string): JSONValue | undefined;
  set(key: string, value: JSONValue): void;
  remove(key: string): void;
  /** Every key and value, for saving. */
  entries(): JSONObject;
}

/** Typed reads that, like `UserDefaults`, give nothing for a value of another type. */
export function defaultsString(defaults: Defaults, key: string): string | undefined {
  const value = defaults.get(key);
  return typeof value === "string" ? value : undefined;
}

export function defaultsBool(defaults: Defaults, key: string): boolean | undefined {
  const value = defaults.get(key);
  return typeof value === "boolean" ? value : undefined;
}

export function defaultsInteger(defaults: Defaults, key: string): number | undefined {
  const value = defaults.get(key);
  return typeof value === "number" && Number.isInteger(value) ? value : undefined;
}

/** A list of strings, or nothing when any element isn't a string (`stringArray(forKey:)`). */
export function defaultsStringArray(defaults: Defaults, key: string): string[] | undefined {
  const value = defaults.get(key);
  return Array.isArray(value) && value.every((item) => typeof item === "string") ? (value as string[]) : undefined;
}

export function defaultsObject(defaults: Defaults, key: string): JSONObject | undefined {
  const value = defaults.get(key);
  return isJSONObject(value) ? value : undefined;
}

/**
 * Port of InMemoryDefaults: preferences that live only in this object, for
 * tests, demo data and snapshot runs, and the in-memory copy the host
 * loads at launch. Values are copied in and out, so a caller changing an
 * array it read never changes the stored one.
 */
export class InMemoryDefaults implements Defaults {
  private readonly values = new Map<string, JSONValue>();

  constructor(initial: JSONObject = {}) {
    for (const [key, value] of Object.entries(initial)) this.values.set(key, clone(value));
  }

  get(key: string): JSONValue | undefined {
    const value = this.values.get(key);
    return value === undefined ? undefined : clone(value);
  }

  set(key: string, value: JSONValue): void {
    this.values.set(key, clone(value));
  }

  remove(key: string): void {
    this.values.delete(key);
  }

  entries(): JSONObject {
    const result: JSONObject = {};
    for (const [key, value] of this.values) result[key] = clone(value);
    return result;
  }
}

function clone(value: JSONValue): JSONValue {
  return typeof value === "object" && value !== null ? (JSON.parse(JSON.stringify(value)) as JSONValue) : value;
}

/** Reads the preferences document `name` from `store`; empty when there is none or it can't be read. */
export async function loadDefaults(store: DocumentStore, name: string): Promise<InMemoryDefaults> {
  try {
    const text = await store.read(name);
    const parsed: unknown = text === undefined ? undefined : JSON.parse(text);
    return new InMemoryDefaults(isJSONObject(parsed) ? parsed : {});
  } catch {
    return new InMemoryDefaults();
  }
}

/** Writes every preference in `defaults` to the document `name`. */
export async function saveDefaults(store: DocumentStore, name: string, defaults: Defaults): Promise<void> {
  await store.write(name, JSON.stringify(defaults.entries(), null, 2));
}
