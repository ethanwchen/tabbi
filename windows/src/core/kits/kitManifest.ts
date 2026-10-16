import { MODULE_IDS, type ModuleID } from "../modules/moduleId";
import { isJSONObject, type JSONObject, type JSONValue } from "../persistence/json";

/**
 * Port of KitLegacyField: a field that kit format 1 first had at the top of
 * `defaults` and that now belongs to one module's `moduleSettings` section.
 * Kits that still use the old name keep working, with a warning.
 */
export interface KitLegacyField {
  /** The old name under `defaults`, such as "studyMethods". */
  readonly name: string;
  readonly module: ModuleID;
  /** The key in the module's section, such as "methods". */
  readonly key: string;
  readonly oldPath: string;
  readonly newPath: string;
}

function legacyField(name: string, module: ModuleID, key: string): KitLegacyField {
  return { name, module, key, oldPath: `defaults.${name}`, newPath: `defaults.moduleSettings.${module}.${key}` };
}

export const KIT_LEGACY_FIELDS: readonly KitLegacyField[] = [
  legacyField("studyMethods", MODULE_IDS.study, "methods"),
  legacyField("studyMethod", MODULE_IDS.study, "method"),
  legacyField("focusSounds", MODULE_IDS.focus, "sounds"),
  legacyField("pet", MODULE_IDS.closet, "pet"),
];

/** Port of KitRequirements: modules that must exist in this build for the kit to be imported. */
export interface KitRequirements {
  readonly modules: readonly ModuleID[];
}

/** Port of KitModuleEntry: one tab in a kit, written as a bare id or as `{"id", "enabled"}`. */
export interface KitModuleEntry {
  readonly id: ModuleID;
  readonly enabled: boolean;
}

export function kitModuleEntry(id: ModuleID, enabled = true): KitModuleEntry {
  return { id, enabled };
}

/**
 * Port of KitDefaults: settings a kit starts the user with. Every field is
 * optional: absent means "keep the app default". Each module's own
 * defaults are in its `moduleSettings` section, keyed by module id.
 */
export interface KitDefaults {
  /** Closed-notch previews to show: built-in preview kinds and module ids. */
  readonly ticker?: readonly string[];
  /** Theme id ("notch", the old name, means Midnight). */
  readonly theme?: string;
  readonly moduleSettings: Readonly<Record<string, JSONValue>>;
  /** Old top-level fields this kit still uses, already moved into their module's section. */
  readonly legacyFields: readonly KitLegacyField[];
}

export function kitDefaults(
  input: { ticker?: readonly string[]; theme?: string; moduleSettings?: Readonly<Record<string, JSONValue>> } = {},
): KitDefaults {
  const defaults: { -readonly [Key in keyof KitDefaults]: KitDefaults[Key] } = {
    moduleSettings: { ...(input.moduleSettings ?? {}) },
    legacyFields: [],
  };
  if (input.ticker !== undefined) defaults.ticker = [...input.ticker];
  if (input.theme !== undefined) defaults.theme = input.theme;
  return defaults;
}

/** Settings for one module, if the kit has any. */
export function kitModuleSettings(defaults: KitDefaults, module: ModuleID): JSONValue | undefined {
  return defaults.moduleSettings[module];
}

/** Port of KitAnswer: one option of a first-run question, which can switch modules and add tasks. */
export interface KitAnswer {
  readonly id: string;
  readonly label: string;
  /** Optional SF Symbol name shown beside the label. */
  readonly symbol?: string;
  readonly enables: readonly ModuleID[];
  readonly disables: readonly ModuleID[];
  readonly tasks: readonly string[];
}

export function kitAnswer(input: {
  id: string;
  label: string;
  symbol?: string;
  enables?: readonly ModuleID[];
  disables?: readonly ModuleID[];
  tasks?: readonly string[];
}): KitAnswer {
  const answer: KitAnswer = {
    id: input.id,
    label: input.label,
    enables: [...(input.enables ?? [])],
    disables: [...(input.disables ?? [])],
    tasks: [...(input.tasks ?? [])],
  };
  return input.symbol === undefined ? answer : { ...answer, symbol: input.symbol };
}

/** Port of KitQuestion: a first-run question that tailors the kit. */
export interface KitQuestion {
  readonly id: string;
  readonly prompt: string;
  /** Whether several answers may be picked. */
  readonly allowsMultiple: boolean;
  readonly options: readonly KitAnswer[];
}

export function kitQuestion(input: {
  id: string;
  prompt: string;
  allowsMultiple?: boolean;
  options: readonly KitAnswer[];
}): KitQuestion {
  return { id: input.id, prompt: input.prompt, allowsMultiple: input.allowsMultiple ?? false, options: [...input.options] };
}

/**
 * Port of KitManifest: a declarative, human-editable bundle of modules and
 * defaults for one audience (Essentials, Med School). Decoding is strict
 * about structure but lenient about values: an id this build doesn't know is
 * kept as written, reported by `kitIssues`, and skipped when applied.
 */
export interface KitManifest {
  readonly formatVersion: number;
  /** The author's own version, free text. */
  readonly version?: string;
  readonly requires: KitRequirements;
  /** Stable slug (`[a-z0-9-]+`), saved in settings. */
  readonly id: string;
  readonly name: string;
  readonly summary: string;
  /** SF Symbol name shown in the kit picker. */
  readonly symbol: string;
  /** The module whose accent tints the kit's symbol; undefined uses the first tab. */
  readonly accent?: ModuleID;
  /** The tabs, in order. */
  readonly modules: readonly KitModuleEntry[];
  readonly defaults: KitDefaults;
  readonly onboarding: readonly KitQuestion[];
  /** Tasks added to Today the first time the kit is applied. */
  readonly starterTasks: readonly string[];
  /** Where a bundled kit sits in the picker; lower first, kits without one follow by id. */
  readonly pickerOrder?: number;
  /** Fields of the decoded file the format doesn't read, as paths like `defaults.tickers`. Never encoded. */
  readonly unknownFields: readonly string[];
}

/** The newest kit format this build reads. */
export const CURRENT_KIT_FORMAT_VERSION = 1;

export interface KitManifestInput {
  formatVersion?: number;
  version?: string;
  requires?: KitRequirements;
  id: string;
  name: string;
  summary: string;
  symbol: string;
  accent?: ModuleID;
  modules: readonly KitModuleEntry[];
  defaults?: KitDefaults;
  onboarding?: readonly KitQuestion[];
  starterTasks?: readonly string[];
  pickerOrder?: number;
}

/** A kit with the Mac initializer's defaults filled in. */
export function kitManifest(input: KitManifestInput): KitManifest {
  const kit: { -readonly [Key in keyof KitManifest]: KitManifest[Key] } = {
    formatVersion: input.formatVersion ?? CURRENT_KIT_FORMAT_VERSION,
    requires: { modules: [...(input.requires?.modules ?? [])] },
    id: input.id,
    name: input.name,
    summary: input.summary,
    symbol: input.symbol,
    modules: [...input.modules],
    defaults: input.defaults ?? kitDefaults(),
    onboarding: [...(input.onboarding ?? [])],
    starterTasks: [...(input.starterTasks ?? [])],
    unknownFields: [],
  };
  if (input.version !== undefined) kit.version = input.version;
  if (input.accent !== undefined) kit.accent = input.accent;
  if (input.pickerOrder !== undefined) kit.pickerOrder = input.pickerOrder;
  return kit;
}

/** Module ids in kit order, duplicates dropped. */
export function kitModuleIDs(kit: KitManifest): ModuleID[] {
  return [...new Set(kit.modules.map((entry) => entry.id))];
}

/* Decoding, as strict as the Mac's Codable types. */

type PathKey = string | number;

/** A structural problem, with the short reason the Mac's KitError.malformed carries. */
export class KitDecodingFailure extends Error {
  constructor(readonly reason: string) {
    super(reason);
  }
}

/** `onboarding.[0].prompt`, the way the Mac names a coding path in a malformed-kit reason. */
function reasonPath(path: readonly PathKey[]): string {
  return path.length === 0 ? "the top level" : path.map((key) => (typeof key === "number" ? `[${key}]` : key)).join(".");
}

/** `defaults.focusSounds[0].volume`, the way kit authors write a field's path. */
function kitPath(path: readonly PathKey[]): string {
  return path.reduce<string>((result, key) => {
    if (typeof key === "number") return `${result}[${key}]`;
    return result === "" ? key : `${result}.${key}`;
  }, "");
}

function mismatch(path: readonly PathKey[]): KitDecodingFailure {
  return new KitDecodingFailure(`unexpected value at ${reasonPath(path)}`);
}

class Reader {
  readonly unknown: string[] = [];

  object(value: unknown, path: readonly PathKey[], known: readonly string[]): JSONObject {
    if (!isJSONObject(value)) throw mismatch(path);
    for (const key of Object.keys(value)) {
      if (!known.includes(key)) this.unknown.push(kitPath([...path, key]));
    }
    return value;
  }

  required<T>(object: JSONObject, key: string, path: readonly PathKey[], read: (value: unknown, path: PathKey[]) => T): T {
    const value = object[key];
    if (value === undefined || value === null) {
      if (value === null) throw mismatch([...path, key]);
      throw new KitDecodingFailure(`missing "${key}"`);
    }
    return read(value, [...path, key]);
  }

  optional<T>(
    object: JSONObject,
    key: string,
    path: readonly PathKey[],
    read: (value: unknown, path: PathKey[]) => T,
  ): T | undefined {
    const value = object[key];
    if (value === undefined || value === null) return undefined;
    return read(value, [...path, key]);
  }
}

function readString(value: unknown, path: readonly PathKey[]): string {
  if (typeof value !== "string") throw mismatch(path);
  return value;
}

function readInt(value: unknown, path: readonly PathKey[]): number {
  if (typeof value !== "number") throw mismatch(path);
  /*
   * Swift's decoder reports a number that doesn't fit a whole-number field
   * (`1.5`) as corrupt data, which the Mac words like a truncated file.
   */
  if (!Number.isInteger(value)) throw new KitDecodingFailure("not valid JSON");
  return value;
}

function readBool(value: unknown, path: readonly PathKey[]): boolean {
  if (typeof value !== "boolean") throw mismatch(path);
  return value;
}

function readList<T>(read: (value: unknown, path: PathKey[]) => T) {
  return (value: unknown, path: readonly PathKey[]): T[] => {
    if (!Array.isArray(value)) throw mismatch(path);
    return value.map((item, index) => read(item, [...path, index]));
  };
}

const readStrings = readList(readString);

function readJSONObject(value: unknown, path: readonly PathKey[]): JSONObject {
  if (!isJSONObject(value)) throw mismatch(path);
  return value;
}

function readEntry(reader: Reader) {
  return (value: unknown, path: PathKey[]): KitModuleEntry => {
    if (typeof value === "string") return kitModuleEntry(value);
    const object = reader.object(value, path, ["id", "enabled"]);
    return kitModuleEntry(
      reader.required(object, "id", path, readString),
      reader.optional(object, "enabled", path, readBool) ?? true,
    );
  };
}

function readDefaults(reader: Reader) {
  return (value: unknown, path: PathKey[]): KitDefaults => {
    const object = reader.object(value, path, [
      "ticker",
      "theme",
      "moduleSettings",
      ...KIT_LEGACY_FIELDS.map((field) => field.name),
    ]);
    const ticker = reader.optional(object, "ticker", path, readStrings);
    const theme = reader.optional(object, "theme", path, readString);
    const moduleSettings: Record<string, JSONValue> = {
      ...(reader.optional(object, "moduleSettings", path, readJSONObject) ?? {}),
    };
    const legacyFields: KitLegacyField[] = [];
    for (const field of KIT_LEGACY_FIELDS) {
      const legacy = object[field.name];
      if (legacy === undefined || legacy === null) continue;
      legacyFields.push(field);
      /* The new key wins when the kit sets both. */
      const section = moduleSettings[field.module] ?? {};
      if (!isJSONObject(section) || section[field.key] !== undefined) continue;
      moduleSettings[field.module] = { ...section, [field.key]: legacy };
    }
    const defaults = kitDefaults({ ticker, theme, moduleSettings });
    return { ...defaults, legacyFields };
  };
}

function readAnswer(reader: Reader) {
  return (value: unknown, path: PathKey[]): KitAnswer => {
    const object = reader.object(value, path, ["id", "label", "symbol", "enables", "disables", "tasks"]);
    return kitAnswer({
      id: reader.required(object, "id", path, readString),
      label: reader.required(object, "label", path, readString),
      symbol: reader.optional(object, "symbol", path, readString),
      enables: reader.optional(object, "enables", path, readStrings),
      disables: reader.optional(object, "disables", path, readStrings),
      tasks: reader.optional(object, "tasks", path, readStrings),
    });
  };
}

function readQuestion(reader: Reader) {
  return (value: unknown, path: PathKey[]): KitQuestion => {
    const object = reader.object(value, path, ["id", "prompt", "allowsMultiple", "options"]);
    return kitQuestion({
      id: reader.required(object, "id", path, readString),
      prompt: reader.required(object, "prompt", path, readString),
      allowsMultiple: reader.optional(object, "allowsMultiple", path, readBool),
      options: reader.required(object, "options", path, readList(readAnswer(reader))),
    });
  };
}

/**
 * Reads a kit document's structure, throwing a `KitDecodingFailure` with the
 * Mac's reason when a required field is missing or a value has the wrong
 * type. Values are not checked here (`validateKit` does that).
 */
export function readKitManifest(json: unknown): KitManifest {
  const reader = new Reader();
  const path: PathKey[] = [];
  const object = reader.object(json, path, [
    "formatVersion",
    "version",
    "requires",
    "id",
    "name",
    "summary",
    "symbol",
    "accent",
    "modules",
    "defaults",
    "onboarding",
    "starterTasks",
    "pickerOrder",
  ]);
  const formatVersion = reader.required(object, "formatVersion", path, readInt);
  const version = reader.optional(object, "version", path, readString);
  const requires = reader.optional(object, "requires", path, (value, at) => {
    const requirements = reader.object(value, at, ["modules"]);
    return { modules: reader.optional(requirements, "modules", at, readStrings) ?? [] };
  });
  const id = reader.required(object, "id", path, readString);
  const name = reader.required(object, "name", path, readString);
  const summary = reader.optional(object, "summary", path, readString) ?? "";
  const symbol = reader.optional(object, "symbol", path, readString) ?? "square.grid.2x2";
  const accent = reader.optional(object, "accent", path, readString);
  const modules = reader.required(object, "modules", path, readList(readEntry(reader)));
  const defaults = reader.optional(object, "defaults", path, readDefaults(reader));
  const onboarding = reader.optional(object, "onboarding", path, readList(readQuestion(reader)));
  const starterTasks = reader.optional(object, "starterTasks", path, readStrings);
  const pickerOrder = reader.optional(object, "pickerOrder", path, readInt);
  const kit = kitManifest({
    formatVersion,
    version,
    requires,
    id,
    name,
    summary,
    symbol,
    accent,
    modules,
    defaults,
    onboarding,
    starterTasks,
    pickerOrder,
  });
  return { ...kit, unknownFields: [...reader.unknown].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0)) };
}

/** The kit as the Mac encodes it: enabled entries as bare ids, nil fields left out, no unknown or legacy fields. */
export function encodeKitManifest(kit: KitManifest): JSONObject {
  const defaults: JSONObject = {};
  if (kit.defaults.ticker !== undefined) defaults.ticker = [...kit.defaults.ticker];
  if (kit.defaults.theme !== undefined) defaults.theme = kit.defaults.theme;
  if (Object.keys(kit.defaults.moduleSettings).length > 0) defaults.moduleSettings = { ...kit.defaults.moduleSettings };
  const json: JSONObject = {
    formatVersion: kit.formatVersion,
    requires: { modules: [...kit.requires.modules] },
    id: kit.id,
    name: kit.name,
    summary: kit.summary,
    symbol: kit.symbol,
    modules: kit.modules.map((entry) => (entry.enabled ? entry.id : { id: entry.id, enabled: false })),
    defaults,
    onboarding: kit.onboarding.map((question) => ({
      id: question.id,
      prompt: question.prompt,
      allowsMultiple: question.allowsMultiple,
      options: question.options.map((answer) => {
        const option: JSONObject = {
          id: answer.id,
          label: answer.label,
          enables: [...answer.enables],
          disables: [...answer.disables],
          tasks: [...answer.tasks],
        };
        if (answer.symbol !== undefined) option.symbol = answer.symbol;
        return option;
      }),
    })),
    starterTasks: [...kit.starterTasks],
  };
  if (kit.version !== undefined) json.version = kit.version;
  if (kit.accent !== undefined) json.accent = kit.accent;
  if (kit.pickerOrder !== undefined) json.pickerOrder = kit.pickerOrder;
  return json;
}

/** Whether two plain data values (kits, answers, settings sections) are equal, ignoring object key order. */
export function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a instanceof Set || b instanceof Set) {
    return a instanceof Set && b instanceof Set && a.size === b.size && [...a].every((value) => b.has(value));
  }
  if (Array.isArray(a) || Array.isArray(b)) {
    return Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((value, i) => deepEqual(value, b[i]));
  }
  if (typeof a !== "object" || typeof b !== "object" || a === null || b === null) return false;
  const aRecord = a as Record<string, unknown>;
  const bRecord = b as Record<string, unknown>;
  const aKeys = Object.keys(aRecord).filter((key) => aRecord[key] !== undefined);
  const bKeys = Object.keys(bRecord).filter((key) => bRecord[key] !== undefined);
  return aKeys.length === bKeys.length && aKeys.every((key) => deepEqual(aRecord[key], bRecord[key]));
}
