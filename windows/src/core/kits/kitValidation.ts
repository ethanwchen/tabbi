import type { ModuleCatalog } from "../modules/moduleCatalog";
import type { ModuleID } from "../modules/moduleId";
import { allTickerKinds } from "../ticker/tickerKind";
import { themeIdForKitValue } from "../themes/themeCatalog";
import {
  CURRENT_KIT_FORMAT_VERSION,
  KitDecodingFailure,
  readKitManifest,
  type KitManifest,
} from "./kitManifest";
import { characterCount, type KitIssue } from "./kitSettingsSchema";

/** Port of KitError: why a kit file can't be used at all. */
export type KitError =
  /** Not JSON, or JSON missing required fields, with a short reason. */
  | { readonly kind: "malformed"; readonly reason: string }
  /** Written for a newer Tabbi. */
  | { readonly kind: "unsupportedVersion"; readonly version: number }
  /** `formatVersion` below 1, which no Tabbi ever wrote. */
  | { readonly kind: "invalidFormatVersion"; readonly version: number }
  | { readonly kind: "tooLarge" }
  /** A list or text goes past one of the limits, such as "more than 20 starter tasks". */
  | { readonly kind: "exceedsLimit"; readonly what: string }
  | { readonly kind: "questionWithoutOptions"; readonly id: string }
  | { readonly kind: "missingRequiredModules"; readonly ids: readonly ModuleID[] }
  | { readonly kind: "invalidID"; readonly id: string }
  | { readonly kind: "emptyName" }
  | { readonly kind: "noModules" }
  /** An imported kit reuses a built-in kit's id. */
  | { readonly kind: "reservedID"; readonly id: string };

/** Port of KitLimits: caps on what a kit may contain, so a sloppy or hostile file can't flood Today or break the picker. */
export const KIT_LIMITS = {
  maxFileBytes: 64 * 1024,
  maxIDLength: 64,
  /** Kit names and answer labels. */
  maxNameLength: 80,
  /** Summaries and question prompts. */
  maxTextLength: 160,
  maxVersionLength: 32,
  maxTaskLength: 120,
  maxModules: 16,
  maxQuestions: 10,
  maxOptions: 8,
  /** Starter tasks of the kit, and of each answer. */
  maxTasks: 20,
} as const;

/** The message the Mac shows for a kit it refuses. */
export function kitErrorDescription(error: KitError): string {
  switch (error.kind) {
    case "malformed":
      return `This isn't a valid kit file (${error.reason}).`;
    case "unsupportedVersion":
      return `This kit needs a newer Tabbi (format ${error.version}, this version reads ${CURRENT_KIT_FORMAT_VERSION}).`;
    case "invalidFormatVersion":
      return `The kit's formatVersion ${error.version} isn't valid. Use 1.`;
    case "tooLarge":
      return `The kit file is larger than ${KIT_LIMITS.maxFileBytes / 1024} KB.`;
    case "exceedsLimit":
      return `The kit has ${error.what}.`;
    case "questionWithoutOptions":
      return `Onboarding question "${error.id}" has no answers.`;
    case "missingRequiredModules":
      return `This kit needs a newer Tabbi with ${error.ids.map((id) => `"${id}"`).join(", ")}.`;
    case "invalidID":
      return `The kit id "${error.id}" must be lowercase letters, digits, and dashes.`;
    case "emptyName":
      return "The kit has no name.";
    case "noModules":
      return "The kit doesn't list any modules.";
    case "reservedID":
      return `The kit id "${error.id}" belongs to a built-in kit. Give your kit its own id.`;
  }
}

/** A kit that loaded, or why it can't be used. Kit loading never throws. */
export type KitLoadResult =
  | { readonly ok: true; readonly kit: KitManifest }
  | { readonly ok: false; readonly error: KitError };

/**
 * Port of KitManifest.decode(from:): reads and checks a kit file. Only
 * problems that make the kit unusable fail it; `kitIssues` lists the rest
 * as warnings.
 */
export function decodeKit(text: string): KitLoadResult {
  if (new TextEncoder().encode(text).length > KIT_LIMITS.maxFileBytes) return refused({ kind: "tooLarge" });
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    return refused({ kind: "malformed", reason: "not valid JSON" });
  }
  let kit: KitManifest;
  try {
    kit = readKitManifest(json);
  } catch (error) {
    const reason = error instanceof KitDecodingFailure ? error.reason : "unreadable JSON";
    return refused({ kind: "malformed", reason });
  }
  const error = validateKit(kit);
  return error ? refused(error) : { ok: true, kit };
}

function refused(error: KitError): KitLoadResult {
  return { ok: false, error };
}

/** Why the kit can't be used at all, or undefined when it can. */
export function validateKit(kit: KitManifest): KitError | undefined {
  if (kit.formatVersion < 1) return { kind: "invalidFormatVersion", version: kit.formatVersion };
  if (kit.formatVersion > CURRENT_KIT_FORMAT_VERSION) return { kind: "unsupportedVersion", version: kit.formatVersion };
  if (!isValidKitID(kit.id)) return { kind: "invalidID", id: kit.id };
  if (kit.name.trim() === "") return { kind: "emptyName" };
  if (kit.modules.length === 0) return { kind: "noModules" };
  const empty = kit.onboarding.find((question) => question.options.length === 0);
  if (empty) return { kind: "questionWithoutOptions", id: empty.id };
  const exceeded = firstExceededLimit(kit);
  if (exceeded !== undefined) return { kind: "exceedsLimit", what: exceeded };
  return undefined;
}

/** A slug of lowercase ASCII letters, digits and dashes, at most `maxIDLength` long. */
export function isValidKitID(id: string): boolean {
  return id.length > 0 && characterCount(id) <= KIT_LIMITS.maxIDLength && /^[a-z0-9-]+$/.test(id);
}

/** A description of the first limit `kit` goes past, or undefined. */
export function firstExceededLimit(kit: KitManifest): string | undefined {
  const limits = KIT_LIMITS;
  if (kit.modules.length > limits.maxModules) return `more than ${limits.maxModules} modules`;
  if (kit.onboarding.length > limits.maxQuestions) return `more than ${limits.maxQuestions} onboarding questions`;
  const crowded = kit.onboarding.find((question) => question.options.length > limits.maxOptions);
  if (crowded) return `more than ${limits.maxOptions} answers in question "${crowded.id}"`;
  if (kit.starterTasks.length > limits.maxTasks) return `more than ${limits.maxTasks} starter tasks`;
  const answers = kit.onboarding.flatMap((question) => question.options);
  const busy = answers.find((answer) => answer.tasks.length > limits.maxTasks);
  if (busy) return `more than ${limits.maxTasks} tasks in answer "${busy.id}"`;
  const texts: [string, string | undefined, number][] = [
    ["name", kit.name, limits.maxNameLength],
    ["summary", kit.summary, limits.maxTextLength],
    ["version", kit.version, limits.maxVersionLength],
    ...kit.onboarding.map((question): [string, string, number] => ["question prompt", question.prompt, limits.maxTextLength]),
    ...answers.map((answer): [string, string, number] => ["answer label", answer.label, limits.maxNameLength]),
    ...[...kit.starterTasks, ...answers.flatMap((answer) => answer.tasks)].map(
      (task): [string, string, number] => ["task title", task, limits.maxTaskLength],
    ),
  ];
  const long = texts.find(([, text, limit]) => characterCount(text ?? "") > limit);
  return long ? `a ${long[0]} longer than ${long[2]} characters` : undefined;
}

/** Modules in `requires` that `catalog` doesn't have, in kit order, once each. Importing refuses the kit when any are. */
export function missingKitRequirements(kit: KitManifest, catalog: ModuleCatalog): ModuleID[] {
  return [...new Set(kit.requires.modules.filter((id) => !catalog.contains(id)))];
}

/**
 * Port of KitManifest.issues(catalog:): the values this build doesn't
 * recognize, in the order they appear. Modules the edition leaves out are
 * skipped quietly: the kit is fine, this edition has no such tab.
 */
export function kitIssues(kit: KitManifest, catalog: ModuleCatalog): KitIssue[] {
  const issues: KitIssue[] = [];
  const seen = new Set<ModuleID>();
  const isUnknown = (id: ModuleID) => !catalog.contains(id) && !catalog.isUnavailable(id);
  for (const entry of kit.modules) {
    if (seen.has(entry.id)) issues.push({ kind: "duplicateModule", id: entry.id });
    else {
      seen.add(entry.id);
      if (isUnknown(entry.id)) issues.push({ kind: "unknownModule", id: entry.id });
    }
  }
  const answerModules = [
    ...kit.onboarding.flatMap((question) => question.options).flatMap((answer) => [...answer.enables, ...answer.disables]),
    ...(kit.accent === undefined ? [] : [kit.accent]),
  ];
  for (const id of answerModules) {
    if (isUnknown(id) && !seen.has(id)) {
      seen.add(id);
      issues.push({ kind: "unknownModule", id });
    }
  }
  const previews = new Set(allTickerKinds(catalog));
  const reportedPreviews = new Set<string>();
  for (const value of kit.defaults.ticker ?? []) {
    if (previews.has(value) || catalog.isUnavailable(value) || reportedPreviews.has(value)) continue;
    reportedPreviews.add(value);
    issues.push({ kind: "unknownTickerKind", value });
  }
  if (kit.defaults.theme !== undefined && themeIdForKitValue(kit.defaults.theme) === undefined) {
    issues.push({ kind: "unknownTheme", value: kit.defaults.theme });
  }
  const questions = new Set<string>();
  for (const question of kit.onboarding) {
    if (questions.has(question.id)) issues.push({ kind: "duplicateQuestion", id: question.id });
    questions.add(question.id);
    const answers = new Set<string>();
    for (const answer of question.options) {
      if (answers.has(answer.id)) issues.push({ kind: "duplicateAnswer", question: question.id, answer: answer.id });
      answers.add(answer.id);
    }
  }
  issues.push(...kit.unknownFields.map((path): KitIssue => ({ kind: "unknownField", path })));
  issues.push(...kit.defaults.legacyFields.map((field): KitIssue => ({ kind: "legacyField", field })));
  issues.push(...moduleSettingsIssues(kit, catalog));
  return issues;
}

/** Checks each `moduleSettings` section against the schema its module declares. */
function moduleSettingsIssues(kit: KitManifest, catalog: ModuleCatalog): KitIssue[] {
  const settings = kit.defaults.moduleSettings;
  return Object.keys(settings)
    .sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
    .flatMap((key): KitIssue[] => {
      if (!catalog.contains(key)) return catalog.isUnavailable(key) ? [] : [{ kind: "unknownModuleSettings", id: key }];
      const schema = catalog.descriptor(key).kitSettings;
      const section = settings[key];
      if (!schema || section === undefined) return [];
      return schema.issues(section, `moduleSettings.${key}`);
    });
}
