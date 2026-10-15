/**
 * Port of StudyMethodFile: `study-methods.json`, every study method's default
 * parameters and copy in picker order, plus the limits of the Timer and
 * Custom steppers.
 *
 * The Mac app and this port read the same file in place
 * (`Sources/TabbiKitCore/StudyMethods/study-methods.json`); the rules that
 * run the methods stay in code and are pinned for both apps by
 * `shared/fixtures/study-methods`. `decodeStudyMethodFile` runs the same
 * checks as the Swift decoder, so a broken file stops with the reason
 * instead of running timers on made-up lengths.
 */

export const STUDY_METHOD_SCHEMA_NAME = "study-methods.v1";

/** Port of StudyMethodKind, in `allCases` order. */
export const STUDY_METHOD_KINDS = [
  "pomodoro",
  "fiftyTwoSeventeen",
  "ultradian",
  "flowtime",
  "ankiSprint",
  "questionBlock",
  "custom",
  "timer",
] as const;
export type StudyMethodKind = (typeof STUDY_METHOD_KINDS)[number];

/** Port of StudyEvidenceLevel, in `allCases` order. */
export const STUDY_EVIDENCE_LEVELS = ["strong", "mixed", "weak"] as const;
export type StudyEvidenceLevel = (typeof STUDY_EVIDENCE_LEVELS)[number];

/** Port of FlowtimeBreakScheme, in `allCases` order. */
export const FLOWTIME_BREAK_SCHEMES = ["tiered", "fifth"] as const;
export type FlowtimeBreakScheme = (typeof FLOWTIME_BREAK_SCHEMES)[number];

/** The Custom rhythm's steppers (StudyCustomRhythm.Field), in `allCases` order. */
export const CUSTOM_RHYTHM_FIELDS = ["focus", "shortBreak", "longBreak", "longBreakEvery"] as const;
export type CustomRhythmField = (typeof CUSTOM_RHYTHM_FIELDS)[number];

export interface StudyMethodFileStepper {
  readonly min: number;
  readonly max: number;
  readonly step: number;
}

export interface StudyMethodFileLongBreak {
  readonly minutes: number;
  readonly every: number;
}

/** `"openEnded"`, `{"minutes": n}` or `{"cards": n}`. */
export type StudyMethodFileFocus =
  | { readonly kind: "minutes"; readonly minutes: number }
  | { readonly kind: "openEnded" }
  | { readonly kind: "cards"; readonly cards: number };

/** `"none"`, `{"minutes": n}` or `{"flowtime": scheme}`. */
export type StudyMethodFileBreak =
  | { readonly kind: "minutes"; readonly minutes: number }
  | { readonly kind: "flowtime"; readonly scheme: FlowtimeBreakScheme }
  | { readonly kind: "none" };

/** One method: its default parameters and its info copy. */
export interface StudyMethodFileMethod {
  readonly kind: StudyMethodKind;
  readonly focus: StudyMethodFileFocus;
  readonly break: StudyMethodFileBreak;
  readonly longBreak?: StudyMethodFileLongBreak;
  /** Review length in minutes. */
  readonly review?: number;
  readonly questionCount?: number;
  readonly name: string;
  readonly tagline: string;
  readonly howTo: string;
  readonly evidence: string;
  readonly evidenceLevel?: StudyEvidenceLevel;
}

export interface StudyMethodFile {
  readonly schema: string;
  readonly phaseMinutes: { readonly min: number; readonly max: number };
  readonly footnote: string;
  readonly evidenceLevels: Readonly<Record<StudyEvidenceLevel, string>>;
  readonly ankiSprint: { readonly breakAfterCards: number; readonly breakAfterMinutes: number };
  readonly timer: { readonly minMinutes: number; readonly maxMinutes: number; readonly presetMinutes: readonly number[] };
  readonly custom: {
    readonly longBreak: StudyMethodFileLongBreak;
    readonly fields: Readonly<Record<CustomRhythmField, StudyMethodFileStepper>>;
  };
  readonly methods: readonly StudyMethodFileMethod[];
}

/** Why a file was refused, worded like the Swift `LoadError`. */
export class StudyMethodFileError extends Error {}

type JsonObject = Record<string, unknown>;

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function fail(path: string, reason: string): never {
  throw new StudyMethodFileError(`${path}: ${reason}`);
}

function object(value: unknown, path: string): JsonObject {
  if (!isObject(value)) fail(path, "expected an object");
  return value;
}

function number(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) fail(path, "expected a number");
  return value;
}

function integer(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) fail(path, "expected an integer");
  return value;
}

function string(value: unknown, path: string): string {
  if (typeof value !== "string") fail(path, "expected a string");
  return value;
}

function oneOf<T extends string>(value: unknown, options: readonly T[], path: string): T {
  const found = options.find((option) => option === value);
  if (found === undefined) fail(path, `unknown value ${JSON.stringify(value)}`);
  return found;
}

function stepper(value: unknown, path: string): StudyMethodFileStepper {
  const entry = object(value, path);
  return { min: integer(entry.min, `${path}.min`), max: integer(entry.max, `${path}.max`), step: integer(entry.step, `${path}.step`) };
}

function longBreak(value: unknown, path: string): StudyMethodFileLongBreak {
  const entry = object(value, path);
  return { minutes: number(entry.minutes, `${path}.minutes`), every: integer(entry.every, `${path}.every`) };
}

function focus(value: unknown, path: string): StudyMethodFileFocus {
  if (typeof value === "string") {
    if (value !== "openEnded") fail(path, `Unknown focus "${value}"`);
    return { kind: "openEnded" };
  }
  const entry = object(value, path);
  if (entry.cards !== undefined) return { kind: "cards", cards: integer(entry.cards, `${path}.cards`) };
  return { kind: "minutes", minutes: number(entry.minutes, `${path}.minutes`) };
}

function breakRule(value: unknown, path: string): StudyMethodFileBreak {
  if (typeof value === "string") {
    if (value !== "none") fail(path, `Unknown break "${value}"`);
    return { kind: "none" };
  }
  const entry = object(value, path);
  if (entry.flowtime !== undefined) {
    return { kind: "flowtime", scheme: oneOf(entry.flowtime, FLOWTIME_BREAK_SCHEMES, `${path}.flowtime`) };
  }
  return { kind: "minutes", minutes: number(entry.minutes, `${path}.minutes`) };
}

function method(value: unknown, path: string): StudyMethodFileMethod {
  const entry = object(value, path);
  return {
    kind: oneOf(entry.kind, STUDY_METHOD_KINDS, `${path}.kind`),
    focus: focus(entry.focus, `${path}.focus`),
    break: breakRule(entry.break, `${path}.break`),
    ...(entry.longBreak === undefined ? {} : { longBreak: longBreak(entry.longBreak, `${path}.longBreak`) }),
    ...(entry.review === undefined ? {} : { review: number(object(entry.review, `${path}.review`).minutes, `${path}.review.minutes`) }),
    ...(entry.questionCount === undefined ? {} : { questionCount: integer(entry.questionCount, `${path}.questionCount`) }),
    name: string(entry.name, `${path}.name`),
    tagline: string(entry.tagline, `${path}.tagline`),
    howTo: string(entry.howTo, `${path}.howTo`),
    evidence: string(entry.evidence, `${path}.evidence`),
    ...(entry.evidenceLevel === undefined
      ? {}
      : { evidenceLevel: oneOf(entry.evidenceLevel, STUDY_EVIDENCE_LEVELS, `${path}.evidenceLevel`) }),
  };
}

function isWhole(value: number): boolean {
  return Number.isInteger(value);
}

/**
 * Parses and checks a file: its schema version, one method per kind,
 * positive lengths and counts, a label per evidence level, and stepper
 * ranges that hold their defaults. Throws `StudyMethodFileError`.
 */
export function decodeStudyMethodFile(json: unknown): StudyMethodFile {
  const root = object(json, "file");
  const schema = string(root.schema, "schema");
  if (schema !== STUDY_METHOD_SCHEMA_NAME) {
    throw new StudyMethodFileError(`Unsupported schema "${schema}"; expected "${STUDY_METHOD_SCHEMA_NAME}"`);
  }
  const phase = object(root.phaseMinutes, "phaseMinutes");
  const phaseMinutes = { min: number(phase.min, "phaseMinutes.min"), max: number(phase.max, "phaseMinutes.max") };
  const levels = object(root.evidenceLevels, "evidenceLevels");
  for (const key of Object.keys(levels)) oneOf(key, STUDY_EVIDENCE_LEVELS, `evidenceLevels.${key}`);
  const evidenceLevels = {} as Record<StudyEvidenceLevel, string>;
  for (const level of STUDY_EVIDENCE_LEVELS) {
    if (levels[level] === undefined) fail("evidenceLevels", `no label for "${level}"`);
    evidenceLevels[level] = string(levels[level], `evidenceLevels.${level}`);
  }
  const sprint = object(root.ankiSprint, "ankiSprint");
  const ankiSprint = {
    breakAfterCards: integer(sprint.breakAfterCards, "ankiSprint.breakAfterCards"),
    breakAfterMinutes: number(sprint.breakAfterMinutes, "ankiSprint.breakAfterMinutes"),
  };
  const timerEntry = object(root.timer, "timer");
  const presets = timerEntry.presetMinutes;
  if (!Array.isArray(presets)) fail("timer.presetMinutes", "expected an array");
  const timer = {
    minMinutes: integer(timerEntry.minMinutes, "timer.minMinutes"),
    maxMinutes: integer(timerEntry.maxMinutes, "timer.maxMinutes"),
    presetMinutes: presets.map((value, index) => integer(value, `timer.presetMinutes[${index}]`)),
  };
  const customEntry = object(root.custom, "custom");
  const fieldsEntry = object(customEntry.fields, "custom.fields");
  const fields = {} as Record<CustomRhythmField, StudyMethodFileStepper>;
  for (const field of CUSTOM_RHYTHM_FIELDS) {
    if (fieldsEntry[field] === undefined) fail("custom.fields", `no field "${field}"`);
    fields[field] = stepper(fieldsEntry[field], `custom.fields.${field}`);
  }
  const custom = { longBreak: longBreak(customEntry.longBreak, "custom.longBreak"), fields };
  const methodList = root.methods;
  if (!Array.isArray(methodList)) fail("methods", "expected an array");
  const methods = methodList.map((entry, index) => method(entry, `methods[${index}]`));
  const file: StudyMethodFile = {
    schema,
    phaseMinutes,
    footnote: string(root.footnote, "footnote"),
    evidenceLevels,
    ankiSprint,
    timer,
    custom,
    methods,
  };
  check(file);
  return file;
}

function ensure(condition: boolean, path: string, reason: string): void {
  if (!condition) fail(path, reason);
}

function check(file: StudyMethodFile): void {
  ensure(file.phaseMinutes.min > 0 && file.phaseMinutes.min < file.phaseMinutes.max, "phaseMinutes", "min must be above 0 and below max");
  ensure(file.ankiSprint.breakAfterCards > 0, "ankiSprint.breakAfterCards", "must be above 0");
  ensure(file.ankiSprint.breakAfterMinutes > 0, "ankiSprint.breakAfterMinutes", "must be above 0");
  const timer = file.timer;
  ensure(timer.minMinutes > 0 && timer.minMinutes <= timer.maxMinutes, "timer", "minMinutes must be 1...maxMinutes");
  timer.presetMinutes.forEach((minutes, index) => {
    ensure(minutes >= timer.minMinutes && minutes <= timer.maxMinutes, `timer.presetMinutes[${index}]`, "outside the timer range");
  });
  for (const field of CUSTOM_RHYTHM_FIELDS) {
    const stepper = file.custom.fields[field];
    ensure(
      stepper.min > 0 && stepper.min <= stepper.max && stepper.step > 0,
      `custom.fields.${field}`,
      "needs 0 < min <= max and a positive step",
    );
  }

  const seen = new Set<StudyMethodKind>();
  file.methods.forEach((entry, index) => {
    const path = `methods[${index}]`;
    if (seen.has(entry.kind)) throw new StudyMethodFileError(`Method "${entry.kind}" is defined twice`);
    seen.add(entry.kind);
    const lengths: [string, number | undefined][] = [
      ["focus", entry.focus.kind === "minutes" ? entry.focus.minutes : undefined],
      ["break", entry.break.kind === "minutes" ? entry.break.minutes : undefined],
      ["longBreak", entry.longBreak?.minutes],
      ["review", entry.review],
    ];
    for (const [name, minutes] of lengths) {
      if (minutes === undefined) continue;
      ensure(minutes >= file.phaseMinutes.min && minutes <= file.phaseMinutes.max, `${path}.${name}.minutes`, "outside phaseMinutes");
    }
    if (entry.focus.kind === "cards") ensure(entry.focus.cards > 0, `${path}.focus.cards`, "must be above 0");
    if (entry.longBreak !== undefined) ensure(entry.longBreak.every >= 2, `${path}.longBreak.every`, "must be 2 or more");
    if (entry.questionCount !== undefined) ensure(entry.questionCount > 0, `${path}.questionCount`, "must be above 0");
  });
  for (const kind of STUDY_METHOD_KINDS) {
    if (!seen.has(kind)) throw new StudyMethodFileError(`methods: no method "${kind}"`);
  }
  checkDefaults(file);
}

/* The Timer and Custom methods start the steppers, so their lengths must be values the steppers can show. */
function checkDefaults(file: StudyMethodFile): void {
  const timerEntry = file.methods.find((entry) => entry.kind === "timer");
  const timerOk =
    timerEntry !== undefined &&
    timerEntry.focus.kind === "minutes" &&
    timerEntry.break.kind === "none" &&
    isWhole(timerEntry.focus.minutes) &&
    timerEntry.focus.minutes >= file.timer.minMinutes &&
    timerEntry.focus.minutes <= file.timer.maxMinutes;
  if (!timerOk) fail("methods.timer", "needs whole focus minutes in the timer range and break \"none\"");

  const fits = (value: number, field: CustomRhythmField): boolean => {
    const stepper = file.custom.fields[field];
    return isWhole(value) && value >= stepper.min && value <= stepper.max;
  };
  const customEntry = file.methods.find((entry) => entry.kind === "custom");
  const customOk =
    customEntry !== undefined &&
    customEntry.focus.kind === "minutes" &&
    customEntry.break.kind === "minutes" &&
    customEntry.longBreak === undefined &&
    customEntry.review === undefined &&
    customEntry.questionCount === undefined &&
    fits(customEntry.focus.minutes, "focus") &&
    fits(customEntry.break.minutes, "shortBreak") &&
    fits(file.custom.longBreak.minutes, "longBreak") &&
    fits(file.custom.longBreak.every, "longBreakEvery");
  if (!customOk) {
    fail("methods.custom", "needs focus and break minutes inside custom.fields, and no long break, review or questions");
  }
}
