import Ajv2020 from "ajv/dist/2020";
import { beforeAll, describe, expect, it } from "vitest";
import bundled from "@mac/StudyMethods/study-methods.json";
import schema from "@shared/schemas/study-methods.v1.schema.json";
import {
  DEFAULT_SPRINT_CARDS,
  FLOWTIME_BREAK_SCHEMES,
  MAXIMUM_PHASE,
  MINIMUM_PHASE,
  SPRINT_BREAK_CARDS,
  SPRINT_BREAK_INTERVAL,
  STUDY_PHASE_KINDS,
  StudyMethod,
  flowtimeBreakDuration,
  type StudyPhaseKind,
} from "../../src/core/studyMethods/studyMethod";
import { decodeStudyMethodFile, STUDY_EVIDENCE_LEVELS } from "../../src/core/studyMethods/studyMethodFile";
import { StudyMethodInfo, evidenceLevelLabel, methodInfo, nameIsRhythm } from "../../src/core/studyMethods/studyMethodInfo";
import { CUSTOM_RHYTHM_FIELDS, StudyCustomRhythm, customFieldStepper } from "../../src/core/studyMethods/studyCustomRhythm";
import { StudyTimerLength, TIMER_MAX_MINUTES, TIMER_MIN_MINUTES } from "../../src/core/studyMethods/studyTimerLength";
import { installEnglishCatalog } from "../support/englishCatalog";
import { loadFixture } from "../support/fixtures";
import { goldenDiff } from "../support/goldenCompare";

/*
 * Replays shared/fixtures/study-methods (written by StudyMethodGoldenTests on
 * the Mac): every method resolved to what the timer and the picker use, the
 * Flowtime breaks, sprint goals and the Timer and Custom steppers.
 */

interface GoldenMethod {
  kind: string;
}

interface Golden {
  schema: string;
  version: number;
  methods: GoldenMethod[];
  flowtimeBreaks: { workedSeconds: number }[];
  sprintGoals: { reviewDue: number; learnDue: number }[];
  timerSteps: { minutes: number }[];
  [key: string]: unknown;
}

const golden = loadFixture<Golden>("study-methods/study-methods.json");

function method(method: StudyMethod): Record<string, unknown> {
  const info = methodInfo(method);
  const phaseSeconds: Record<string, number> = {};
  for (const phase of STUDY_PHASE_KINDS) {
    const length = method.duration(phase);
    if (length !== undefined) phaseSeconds[phase] = length;
  }
  const sequence: StudyPhaseKind[] = ["focus"];
  let completed = 1;
  while (completed <= 8) {
    const last = sequence[sequence.length - 1] ?? "focus";
    const next = method.nextPhase(last, completed);
    if (next === "focus") completed += 1;
    sequence.push(next);
  }
  const breakRule =
    method.breakRule.kind === "proportional" ? `proportional:${method.breakRule.scheme}` : method.breakRule.kind;
  return {
    kind: method.kind,
    focusTarget: method.focus.kind,
    focusSeconds: method.focus.kind === "duration" ? method.focus.seconds : undefined,
    cardGoal: method.cardGoal,
    breakRule,
    longBreakSeconds: method.longBreak?.duration,
    longBreakEvery: method.longBreak?.every,
    reviewSeconds: method.review,
    questionCount: method.questionCount,
    hasBreaks: method.hasBreaks,
    rhythmLabel: method.rhythmLabel,
    nameIsRhythm: nameIsRhythm(method),
    phaseSeconds,
    phaseSequence: sequence,
    name: info.name,
    tagline: info.tagline,
    howTo: info.howTo,
    howToSentencePrefixes: info.howToSentencePrefixes,
    evidence: info.evidence,
    evidenceLevel: info.evidenceLevel,
  };
}

function current(): Record<string, unknown> {
  const flowtimeBreaks = golden.flowtimeBreaks.map(({ workedSeconds }) => {
    const breakSeconds: Record<string, number> = {};
    for (const scheme of FLOWTIME_BREAK_SCHEMES) breakSeconds[scheme] = flowtimeBreakDuration(scheme, workedSeconds);
    return { workedSeconds, breakSeconds };
  });
  const sprintGoals = golden.sprintGoals.map(({ reviewDue, learnDue }) => ({
    reviewDue,
    learnDue,
    goal: StudyMethod.sprintGoal(reviewDue, learnDue),
  }));
  const timerSteps = golden.timerSteps.map(({ minutes }) => {
    const length = new StudyTimerLength(minutes);
    return { minutes, up: length.stepped(true).minutes, down: length.stepped(false).minutes };
  });
  const custom = StudyCustomRhythm.standard;
  const customFields: Record<string, unknown> = {};
  const customStandard: Record<string, number> = {};
  for (const field of CUSTOM_RHYTHM_FIELDS) {
    customFields[field] = customFieldStepper(field);
    customStandard[field] = custom.value(field);
  }
  const evidenceLabels: Record<string, string> = {};
  for (const level of STUDY_EVIDENCE_LEVELS) evidenceLabels[level] = evidenceLevelLabel(level);
  return {
    schema: "tabbi.study-methods.golden",
    version: 1,
    footnote: StudyMethodInfo.footnote,
    evidenceLabels,
    minimumPhaseSeconds: MINIMUM_PHASE,
    maximumPhaseSeconds: MAXIMUM_PHASE,
    defaultSprintCards: DEFAULT_SPRINT_CARDS,
    sprintBreakCards: SPRINT_BREAK_CARDS,
    sprintBreakSeconds: SPRINT_BREAK_INTERVAL,
    methods: StudyMethod.presets.map(method),
    flowtimeBreaks,
    sprintGoals,
    timerMinMinutes: TIMER_MIN_MINUTES,
    timerMaxMinutes: TIMER_MAX_MINUTES,
    timerSteps,
    timerPresetMinutes: StudyTimerLength.presets,
    timerStandardMinutes: StudyTimerLength.standard.minutes,
    customFields,
    customStandard,
    customStandardHasLongBreak: custom.hasLongBreak,
  };
}

describe("study-methods fixture", () => {
  beforeAll(installEnglishCatalog);

  it("validates study-methods.json against study-methods.v1", () => {
    const ajv = new Ajv2020({ allErrors: true });
    const validate = ajv.compile(schema);
    expect(validate(bundled), JSON.stringify(validate.errors)).toBe(true);
  });

  it("lists every method in picker order", () => {
    expect(StudyMethod.presets.map((method) => method.kind)).toEqual(golden.methods.map((method) => method.kind));
  });

  const replay = current();
  for (const key of Object.keys(golden).filter((key) => key !== "methods")) {
    it(`matches ${key}`, () => {
      expect(goldenDiff(replay[key], golden[key], key)).toBeUndefined();
    });
  }
  golden.methods.forEach((recorded, index) => {
    it(`matches method ${recorded.kind}`, () => {
      const methods = replay.methods as unknown[];
      expect(goldenDiff(methods[index], recorded, `methods[${index}]`)).toBeUndefined();
    });
  });
  it("matches as a whole", () => {
    expect(goldenDiff(replay, golden)).toBeUndefined();
  });
});

describe("study-methods.json decoding", () => {
  const copy = (): Record<string, unknown> => structuredClone(bundled) as Record<string, unknown>;

  it("decodes the bundled file", () => {
    expect(decodeStudyMethodFile(bundled).methods).toHaveLength(8);
  });

  it("refuses another schema version", () => {
    expect(() => decodeStudyMethodFile({ ...copy(), schema: "study-methods.v2" })).toThrow(/Unsupported schema/);
  });

  it("refuses a missing or duplicated method", () => {
    const file = copy();
    const methods = file.methods as unknown[];
    expect(() => decodeStudyMethodFile({ ...file, methods: methods.slice(1) })).toThrow(/no method "pomodoro"/);
    expect(() => decodeStudyMethodFile({ ...file, methods: [methods[0], ...methods] })).toThrow(/defined twice/);
  });

  it("refuses a length outside phaseMinutes", () => {
    const file = copy();
    const methods = file.methods as Record<string, unknown>[];
    const first = methods[0];
    if (first === undefined) throw new Error("no methods");
    first.focus = { minutes: 500 };
    expect(() => decodeStudyMethodFile(file)).toThrow(/methods\[0\]\.focus\.minutes: outside phaseMinutes/);
  });
});
