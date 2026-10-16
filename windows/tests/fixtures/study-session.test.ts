import { beforeAll, describe, expect, it } from "vitest";
import {
  StudyMethod,
  studyLongBreak,
  type FlowtimeBreakScheme,
  type StudyBreakRule,
  type StudyFocusTarget,
  type StudyMethodKind,
} from "../../src/core/studyMethods/studyMethod";
import { STUDY_METHOD_KINDS } from "../../src/core/studyMethods/studyMethodFile";
import { sharedStudyFocus, studyFocusActivity } from "../../src/core/studyMethods/studyFocusShare";
import { durationMinutes } from "../../src/core/formatting/durationFormat";
import { studyPetEvents, studyPetIsDozing } from "../../src/core/studyMethods/studyPetCue";
import { MINIMUM_LOGGED_DURATION, phaseActivityRecord, type StudyPhaseRecord } from "../../src/core/studyMethods/studyPhaseRecord";
import { StudySession } from "../../src/core/studyMethods/studySession";
import {
  studyClock,
  studyPoints,
  studyPrimaryAction,
  studyReadout,
  studyRoundLabel,
} from "../../src/core/studyMethods/studyTimerFormat";
import { switchLanguage } from "../support/catalogs";
import { loadFixture } from "../support/fixtures";
import { activityJson, providedJson } from "../support/focusGolden";
import { goldenDiff } from "../support/goldenCompare";

/*
 * Replays shared/fixtures/study-session (written by StudySessionGoldenTests
 * on the Mac): the dial, studied and points labels, and every study session
 * sequence, comparing each step's ended and taken phases, session state, Study
 * tab view, pet events, deep focus activity and shared focus clock.
 */

/** A StudyMethod in the fixture's neutral form. */
interface MethodJson {
  kind: string;
  focus: { kind: string; seconds?: number; cards?: number };
  breakRule: { kind: string; seconds?: number; scheme?: string };
  longBreak?: { duration: number; every: number };
  review?: number;
  questionCount?: number;
  rhythmLabel?: string;
}

interface Input {
  action: string;
  at: number;
  method?: MethodJson;
  count?: number;
}

interface Step {
  input: Input;
  [key: string]: unknown;
}

interface Golden {
  schema: string;
  version: number;
  minimumLoggedDuration: number;
  labels: {
    clocks: { seconds: number; text: string }[];
    studied: { minutes: number; text: string }[];
    points: { points: number; text: string }[];
  };
  sequences: { name: string; method: MethodJson; steps: Step[] }[];
}

const golden = loadFixture<Golden>("study-session/study-session.json");

/** The module id the shared clock and activity records carry. */
const SOURCE = "study";

function methodJson(method: StudyMethod): MethodJson {
  const focus = method.focus;
  const rule = method.breakRule;
  return {
    kind: method.kind,
    focus:
      focus.kind === "duration"
        ? { kind: "duration", seconds: focus.seconds }
        : focus.kind === "cards"
          ? { kind: "cards", cards: focus.cards }
          : { kind: "openEnded" },
    breakRule:
      rule.kind === "fixed"
        ? { kind: "fixed", seconds: rule.seconds }
        : rule.kind === "proportional"
          ? { kind: "proportional", scheme: rule.scheme }
          : { kind: "none" },
    ...(method.longBreak === undefined ? {} : { longBreak: { duration: method.longBreak.duration, every: method.longBreak.every } }),
    ...(method.review === undefined ? {} : { review: method.review }),
    ...(method.questionCount === undefined ? {} : { questionCount: method.questionCount }),
    rhythmLabel: method.rhythmLabel,
  };
}

/** Builds the method an input names, clamping it, the way the Swift test's `Method.method` does. */
function methodFromJson(json: MethodJson): StudyMethod {
  const focus: StudyFocusTarget =
    json.focus.kind === "duration"
      ? { kind: "duration", seconds: json.focus.seconds ?? 0 }
      : json.focus.kind === "cards"
        ? { kind: "cards", cards: json.focus.cards ?? 0 }
        : { kind: "openEnded" };
  const scheme: FlowtimeBreakScheme = json.breakRule.scheme === "fifth" ? "fifth" : "tiered";
  const breakRule: StudyBreakRule =
    json.breakRule.kind === "fixed"
      ? { kind: "fixed", seconds: json.breakRule.seconds ?? 0 }
      : json.breakRule.kind === "proportional"
        ? { kind: "proportional", scheme }
        : { kind: "none" };
  const kind: StudyMethodKind = STUDY_METHOD_KINDS.find((known) => known === json.kind) ?? "custom";
  return new StudyMethod({
    kind,
    focus,
    breakRule,
    ...(json.longBreak === undefined ? {} : { longBreak: studyLongBreak(json.longBreak.duration, json.longBreak.every) }),
    ...(json.review === undefined ? {} : { review: json.review }),
    ...(json.questionCount === undefined ? {} : { questionCount: json.questionCount }),
  });
}

function recordJson(record: StudyPhaseRecord): Record<string, unknown> {
  const activity = phaseActivityRecord(record, SOURCE);
  return {
    method: record.method,
    phase: record.phase,
    startedAt: record.startedAt,
    endedAt: record.endedAt,
    activeDuration: record.activeDuration,
    outcome: record.outcome,
    cards: record.cards,
    activity: activity === undefined ? undefined : activityJson(activity),
  };
}

function stateJson(session: StudySession, now: number): Record<string, unknown> {
  return {
    method: methodJson(session.method),
    phase: session.phase,
    run: session.runState,
    phaseDuration: session.phaseDuration,
    completedFocusCount: session.completedFocusCount,
    cardsDone: session.cardsDone,
    lastFocusWorked: session.lastFocusWorked,
    elapsed: session.elapsed(now),
    remaining: session.remaining(now),
    runningSince: session.runningSince,
    endsAt: session.endsAt,
    progress: session.progress(now),
    suggestsSprintBreak: session.suggestsSprintBreak(now),
    log: session.log.map(recordJson),
  };
}

/** Feeds `inputs` to a fresh session on `method` and records it after each one, as the Swift test does. */
function run(method: StudyMethod, inputs: Input[]): Record<string, unknown>[] {
  const session = new StudySession(method);
  return inputs.map((input) => {
    const now = input.at;
    const before = session.clone();
    let accepted: boolean | undefined;
    let ended: StudyPhaseRecord[] | undefined;
    let taken: StudyPhaseRecord[] | undefined;
    const inputMethod = (): StudyMethod => (input.method === undefined ? method : methodFromJson(input.method));
    switch (input.action) {
      case "start":
        session.start(now);
        break;
      case "pause":
        session.pause(now);
        break;
      case "skip":
        session.skip(now);
        break;
      case "stopFocus":
        accepted = session.stopFocus(now);
        break;
      case "reset":
        session.reset(now);
        break;
      case "switchMethod":
        session.switchMethod(inputMethod(), now);
        break;
      case "retune":
        accepted = session.retune(inputMethod(), now);
        break;
      case "reviewed":
        ended = session.recordReviewedToday(input.count ?? 0, now);
        break;
      case "advance":
        ended = session.advance(now);
        break;
      case "takeLog":
        taken = session.takeLog();
        break;
      default:
        throw new Error(`Unknown action ${input.action}`);
    }
    const readout = studyReadout(session, now);
    const provided = sharedStudyFocus(session, SOURCE, false, now);
    return {
      input,
      accepted,
      ended: ended?.map(recordJson),
      taken: taken?.map(recordJson),
      state: stateJson(session, now),
      view: {
        value: readout.value,
        caption: readout.caption,
        countsDown: readout.countsDown,
        round: studyRoundLabel(session),
        primaryAction: studyPrimaryAction(session),
        petDozing: studyPetIsDozing(session),
        petEvents: studyPetEvents(before, session).map((event) => event.kind),
        deepFocus: studyFocusActivity(session, true),
      },
      provided: provided === undefined ? undefined : providedJson(provided, now),
    };
  });
}

describe("study-session fixture", () => {
  beforeAll(() => switchLanguage("en"));

  it("is the version this port reads", () => {
    expect(golden.schema).toBe("tabbi.study-session.golden");
    expect(golden.version).toBe(1);
    expect(golden.minimumLoggedDuration).toBe(MINIMUM_LOGGED_DURATION);
  });

  it("matches the dial, studied and points labels", () => {
    const labels = {
      clocks: golden.labels.clocks.map(({ seconds }) => ({ seconds, text: studyClock(seconds) })),
      studied: golden.labels.studied.map(({ minutes }) => ({ minutes, text: durationMinutes(minutes) })),
      points: golden.labels.points.map(({ points }) => ({ points, text: studyPoints(points) })),
    };
    expect(goldenDiff(labels, golden.labels, "labels")).toBeUndefined();
  });

  for (const sequence of golden.sequences) {
    it(`replays ${sequence.name}`, () => {
      const replayed = run(methodFromJson(sequence.method), sequence.steps.map((step) => step.input));
      expect(replayed).toHaveLength(sequence.steps.length);
      sequence.steps.forEach((step, index) => {
        expect(goldenDiff(replayed[index], step, `${sequence.name}[${index}] (${step.input.action})`)).toBeUndefined();
      });
    });
  }
});
