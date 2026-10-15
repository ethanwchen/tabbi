import { isJSONObject, stringifyJSON, type JSONFormatting, type JSONObject } from "./json";

/** One step: upgrades a document at `version - 1` to `version` by rewriting its top-level object in place. */
export interface Migration {
  readonly version: number;
  readonly migrate: (document: JSONObject) => void;
}

/**
 * Port of VersionedJSON: the format of one kind of JSON document Tabbi
 * persists, with the ordered steps that bring older documents up to it.
 *
 * Every document is a JSON object carrying a top-level `schemaVersion`;
 * documents written before versions existed have none and count as 0.
 * Decoding first runs each step newer than the document's version on the
 * raw object, so a renamed or reshaped field is fixed up once, in one place,
 * before the reader sees it. To change a format, add a step at the end;
 * never edit a step that has shipped.
 *
 * A document from a newer build (after a downgrade) is read as it is: the
 * readers ignore keys they don't know and default the ones they miss.
 */
export class VersionedJSON {
  static readonly versionKey = "schemaVersion";

  /**
   * A format at `current` whose older versions need the given steps, in
   * order and ending at or below `current`. Versions with no step (such as
   * 0 to 1 when the version key was added) only change the recorded number.
   */
  constructor(
    readonly current: number,
    readonly migrations: readonly Migration[] = [],
  ) {
    const versions = migrations.map((step) => step.version);
    if (versions.some((version, index) => index > 0 && version < (versions[index - 1] ?? version))) {
      throw new Error("Migrations must be in version order");
    }
    if ((versions[versions.length - 1] ?? 0) > current) {
      throw new Error("A migration goes past the current version");
    }
  }

  /** The version recorded in `text` (0 when there is none, it isn't an integer, or `text` isn't an object). */
  static version(text: string): number {
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      return 0;
    }
    return VersionedJSON.versionOf(parsed);
  }

  /** The version recorded in an already parsed document. */
  static versionOf(document: unknown): number {
    if (!isJSONObject(document)) return 0;
    const version = document[VersionedJSON.versionKey];
    return typeof version === "number" && Number.isInteger(version) ? version : 0;
  }

  /**
   * The document in `text` as an object, after the steps its version hasn't
   * had yet (and stamped with `current` when any ran). Throws when `text`
   * isn't JSON or isn't an object.
   */
  upgrade(text: string): JSONObject {
    const parsed: unknown = JSON.parse(text);
    if (!isJSONObject(parsed)) throw new SyntaxError("Expected a JSON object");
    const stored = VersionedJSON.versionOf(parsed);
    const pending = this.migrations.filter((step) => step.version > stored);
    if (pending.length === 0) return parsed;
    for (const step of pending) step.migrate(parsed);
    parsed[VersionedJSON.versionKey] = this.current;
    return parsed;
  }

  /** Reads `text` with `read` after running the steps its version hasn't had yet. */
  decode<Value>(text: string, read: (document: JSONObject) => Value): Value {
    return read(this.upgrade(text));
  }

  /** Writes `value`'s keys with this schema's `current` version alongside them. */
  encode(value: JSONObject | Readonly<Record<string, unknown>>, formatting: JSONFormatting = {}): string {
    return stringifyJSON({ ...value, [VersionedJSON.versionKey]: this.current }, formatting);
  }
}
