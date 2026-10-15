import type { ModuleID } from "../modules/moduleId";
import { isJSONObject, type JSONValue } from "../persistence/json";
import type { KitLegacyField } from "./kitManifest";

/**
 * Port of KitIssue: something in a usable kit this build will skip, shown
 * as a warning when importing so kit authors can fix typos. Warnings never
 * stop a kit from loading.
 */
export type KitIssue =
  | { readonly kind: "unknownModule"; readonly id: ModuleID }
  | { readonly kind: "duplicateModule"; readonly id: ModuleID }
  | { readonly kind: "unknownTickerKind"; readonly value: string }
  | { readonly kind: "unknownTheme"; readonly value: string }
  | { readonly kind: "duplicateQuestion"; readonly id: string }
  | { readonly kind: "duplicateAnswer"; readonly question: string; readonly answer: string }
  | { readonly kind: "unknownField"; readonly path: string }
  | { readonly kind: "unknownModuleSettings"; readonly id: ModuleID }
  | { readonly kind: "invalidModuleSetting"; readonly path: string; readonly expected: string }
  | { readonly kind: "legacyField"; readonly field: KitLegacyField };

/** The warning a kit author reads, word for word as on the Mac. */
export function kitIssueDescription(issue: KitIssue): string {
  switch (issue.kind) {
    case "unknownModule":
      return `Unknown module "${issue.id}" will be skipped.`;
    case "duplicateModule":
      return `Module "${issue.id}" is listed more than once.`;
    case "unknownTickerKind":
      return `Unknown preview "${issue.value}" will be skipped.`;
    case "unknownTheme":
      return `Unknown theme "${issue.value}" will be ignored.`;
    case "duplicateQuestion":
      return `Onboarding question "${issue.id}" is listed more than once.`;
    case "duplicateAnswer":
      return `Answer "${issue.answer}" is listed more than once in question "${issue.question}".`;
    case "unknownField":
      return `Unknown field "${issue.path}" will be ignored.`;
    case "unknownModuleSettings":
      return `Settings for unknown module "${issue.id}" will be ignored.`;
    case "invalidModuleSetting":
      return `"${issue.path}" should be ${issue.expected}; other values are skipped or kept in range.`;
    case "legacyField":
      return `"${issue.field.oldPath}" has moved to "${issue.field.newPath}". It still works for now.`;
  }
}

/** Port of KitSettingType: a value a module accepts in its kit settings. */
export type KitSettingType =
  | { readonly type: "bool" }
  /** A number within `min...max`. */
  | { readonly type: "number"; readonly min: number; readonly max: number }
  /** Text of at most `maxLength` characters. */
  | { readonly type: "text"; readonly maxLength: number }
  /** One of a fixed set of strings. */
  | { readonly type: "choice"; readonly values: readonly string[] }
  /** A single line or a list of up to `maxCount` lines, each at most `maxLength` characters. */
  | { readonly type: "lines"; readonly maxLength: number; readonly maxCount: number }
  /** An object with these optional keys. */
  | { readonly type: "object"; readonly fields: Readonly<Record<string, KitSettingType>> }
  /** A list of up to `maxCount` items, each checked against `item`. */
  | { readonly type: "list"; readonly item: KitSettingType; readonly maxCount: number };

/** Builders that read like the Swift cases: `kitSetting.number(0, 1)`. */
export const kitSetting = {
  bool: { type: "bool" } as KitSettingType,
  number: (min: number, max: number): KitSettingType => ({ type: "number", min, max }),
  text: (maxLength: number): KitSettingType => ({ type: "text", maxLength }),
  choice: (values: readonly string[]): KitSettingType => ({ type: "choice", values }),
  lines: (maxLength: number, maxCount: number): KitSettingType => ({ type: "lines", maxLength, maxCount }),
  object: (fields: Readonly<Record<string, KitSettingType>>): KitSettingType => ({ type: "object", fields }),
  list: (item: KitSettingType, maxCount: number): KitSettingType => ({ type: "list", item, maxCount }),
};

/**
 * Port of KitSettingsSchema: the shape of one module's section in a kit's
 * `moduleSettings`, declared on its descriptor, so kit validation can warn
 * about a mistyped key or a value of the wrong kind without knowing the
 * module. There is no type for URLs, paths or commands.
 */
export class KitSettingsSchema {
  constructor(readonly fields: Readonly<Record<string, KitSettingType>>) {}

  /** What's wrong with `section`, with paths starting at `path`, in key order. */
  issues(section: JSONValue, path: string): KitIssue[] {
    return settingIssues({ type: "object", fields: this.fields }, section, path);
  }
}

const numberFormat = new Intl.NumberFormat("en-US", { maximumFractionDigits: 15 });

/** What the value should be, for a warning: "a number from 0 to 22". */
export function kitSettingExpectation(setting: KitSettingType): string {
  switch (setting.type) {
    case "bool":
      return "true or false";
    case "number":
      return `a number from ${numberFormat.format(setting.min)} to ${numberFormat.format(setting.max)}`;
    case "text":
      return `text of at most ${setting.maxLength} characters`;
    case "choice":
      return "one of " + setting.values.map((value) => `"${value}"`).join(", ");
    case "lines":
      return `a line or a list of up to ${setting.maxCount} lines, each at most ${setting.maxLength} characters`;
    case "object":
      return "an object";
    case "list":
      return `a list of up to ${setting.maxCount} items`;
  }
}

const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });

/** The length Swift's `String.count` gives: user-perceived characters. */
export function characterCount(text: string): number {
  return [...segmenter.segment(text)].length;
}

function compareCodeUnits(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

function settingIssues(setting: KitSettingType, value: JSONValue, path: string): KitIssue[] {
  if (setting.type === "object" && isJSONObject(value)) {
    return Object.keys(value)
      .sort(compareCodeUnits)
      .flatMap((key) => {
        const child = `${path}.${key}`;
        const type = setting.fields[key];
        if (type === undefined) return [{ kind: "unknownField", path: child } as const];
        return settingIssues(type, value[key] ?? null, child);
      });
  }
  if (setting.type === "list" && Array.isArray(value) && value.length <= setting.maxCount) {
    return value.flatMap((item, index) => settingIssues(setting.item, item, `${path}[${index}]`));
  }
  let fits = false;
  switch (setting.type) {
    case "bool":
      fits = typeof value === "boolean";
      break;
    case "number":
      fits = typeof value === "number" && value >= setting.min && value <= setting.max;
      break;
    case "text":
      fits = typeof value === "string" && characterCount(value) <= setting.maxLength;
      break;
    case "choice":
      fits = typeof value === "string" && setting.values.includes(value);
      break;
    case "lines":
      if (typeof value === "string") fits = characterCount(value) <= setting.maxLength;
      else if (Array.isArray(value)) {
        fits =
          value.length <= setting.maxCount &&
          value.every((item) => typeof item === "string" && characterCount(item) <= setting.maxLength);
      }
      break;
    case "object":
    case "list":
      fits = false;
      break;
  }
  return fits ? [] : [{ kind: "invalidModuleSetting", path, expected: kitSettingExpectation(setting) }];
}
