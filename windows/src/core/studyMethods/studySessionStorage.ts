import { isJSONObject, type JSONObject, type JSONValue } from "../persistence/json";
import type { Instant } from "../time";
import { FLOWTIME_BREAK_SCHEMES, STUDY_PHASE_KINDS, StudyMethod, studyLongBreak, type StudyBreakRule, type StudyFocusTarget, type StudyPhaseKind } from "./studyMethod";
import { STUDY_METHOD_KINDS, type FlowtimeBreakScheme, type StudyMethodKind } from "./studyMethodFile";
import { StudySession } from "./studySession";
import type { StudyPhaseOutcome, StudyPhaseRecord } from "./studyPhaseRecord";

/*
 * Port of the Codable shapes of StudySession, StudyMethod and
 * StudyPhaseRecord, as Swift's JSONEncoder writes them: dates as seconds
 * since 2001, an enum with a payload as `{"case": {"_0": value}}` and one
 * without as `{"case": {}}`, optionals left out when nil. The Study store
 * saves the session on every change so a relaunch picks up where it was,
 * and reads it back through the session's own repairing decoder.
 */

/** Seconds from 1970 to 2001, the reference date Foundation encodes dates against by default. */
const REFERENCE_DATE_OFFSET = 978_307_200;

const PHASE_OUTCOMES: readonly StudyPhaseOutcome[] = ["completed", "stopped", "skipped", "abandoned"];

function finite(value: JSONValue | undefined, key: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new TypeError(`Invalid ${key}`);
  return value;
}

function integer(value: JSONValue | undefined, key: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) throw new TypeError(`Invalid ${key}`);
  return value;
}

function optionalNumber(value: JSONValue | undefined, key: string): number | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "number") throw new TypeError(`Invalid ${key}`);
  return value;
}

function date(value: JSONValue | undefined, key: string): Instant {
  return finite(value, key) + REFERENCE_DATE_OFFSET;
}

function optionalDate(value: JSONValue | undefined, key: string): Instant | undefined {
  const seconds = optionalNumber(value, key);
  if (seconds === undefined) return undefined;
  if (!Number.isFinite(seconds)) throw new TypeError(`Invalid ${key}`);
  return seconds + REFERENCE_DATE_OFFSET;
}

function oneOf<T extends string>(options: readonly T[], value: JSONValue | undefined, key: string): T {
  const found = options.find((option) => option === value);
  if (found === undefined) throw new TypeError(`Invalid ${key}`);
  return found;
}

/* Swift's synthesized enum encoding: `{"case": {"_0": payload}}`, or `{"case": {}}` without one. */
function enumCase(json: JSONValue | undefined, key: string): { readonly name: string; readonly payload: JSONValue | undefined } {
  if (!isJSONObject(json)) throw new TypeError(`Invalid ${key}`);
  const names = Object.keys(json);
  const name = names[0];
  if (names.length !== 1 || name === undefined) throw new TypeError(`Invalid ${key}`);
  const inner = json[name];
  if (!isJSONObject(inner)) throw new TypeError(`Invalid ${key}`);
  return { name, payload: inner._0 };
}

function encodeFocus(focus: StudyFocusTarget): JSONObject {
  switch (focus.kind) {
    case "duration":
      return { duration: { _0: focus.seconds } };
    case "openEnded":
      return { openEnded: {} };
    case "cards":
      return { cards: { _0: focus.cards } };
  }
}

function decodeFocus(json: JSONValue | undefined): StudyFocusTarget {
  const { name, payload } = enumCase(json, "focus");
  switch (name) {
    case "duration":
      return { kind: "duration", seconds: finite(payload, "focus.duration") };
    case "openEnded":
      return { kind: "openEnded" };
    case "cards":
      return { kind: "cards", cards: integer(payload, "focus.cards") };
    default:
      throw new TypeError("Invalid focus");
  }
}

function encodeBreakRule(rule: StudyBreakRule): JSONObject {
  switch (rule.kind) {
    case "fixed":
      return { fixed: { _0: rule.seconds } };
    case "proportional":
      return { proportional: { _0: rule.scheme } };
    case "none":
      return { none: {} };
  }
}

function decodeBreakRule(json: JSONValue | undefined): StudyBreakRule {
  const { name, payload } = enumCase(json, "breakRule");
  switch (name) {
    case "fixed":
      return { kind: "fixed", seconds: finite(payload, "breakRule.fixed") };
    case "proportional":
      return { kind: "proportional", scheme: oneOf<FlowtimeBreakScheme>(FLOWTIME_BREAK_SCHEMES, payload, "breakRule.proportional") };
    case "none":
      return { kind: "none" };
    default:
      throw new TypeError("Invalid breakRule");
  }
}

/** A method in the Mac's Codable shape. */
export function encodeStudyMethod(method: StudyMethod): JSONObject {
  const json: JSONObject = {
    kind: method.kind,
    focus: encodeFocus(method.focus),
    breakRule: encodeBreakRule(method.breakRule),
  };
  if (method.longBreak !== undefined) json.longBreak = { duration: method.longBreak.duration, every: method.longBreak.every };
  if (method.review !== undefined) json.review = method.review;
  if (method.questionCount !== undefined) json.questionCount = method.questionCount;
  return json;
}

/** Port of StudyMethod.init(from:): decoding goes through the clamping init. Throws on a malformed method. */
export function decodeStudyMethod(json: JSONValue | undefined): StudyMethod {
  if (!isJSONObject(json)) throw new TypeError("Invalid method");
  const kind = oneOf<StudyMethodKind>(STUDY_METHOD_KINDS, json.kind, "method.kind");
  const longBreakJSON = json.longBreak;
  const longBreak =
    longBreakJSON === undefined || longBreakJSON === null
      ? undefined
      : isJSONObject(longBreakJSON)
        ? studyLongBreak(finite(longBreakJSON.duration, "longBreak.duration"), integer(longBreakJSON.every, "longBreak.every"))
        : undefined;
  if (longBreakJSON !== undefined && longBreakJSON !== null && longBreak === undefined) throw new TypeError("Invalid longBreak");
  const review = optionalNumber(json.review, "review");
  const questionCount = optionalNumber(json.questionCount, "questionCount");
  return new StudyMethod({
    kind,
    focus: decodeFocus(json.focus),
    breakRule: decodeBreakRule(json.breakRule),
    ...(longBreak === undefined ? {} : { longBreak }),
    ...(review === undefined ? {} : { review }),
    ...(questionCount === undefined ? {} : { questionCount: Math.trunc(questionCount) }),
  });
}

export function encodeStudyPhaseRecord(record: StudyPhaseRecord): JSONObject {
  const json: JSONObject = {
    method: record.method,
    phase: record.phase,
    startedAt: record.startedAt - REFERENCE_DATE_OFFSET,
    endedAt: record.endedAt - REFERENCE_DATE_OFFSET,
    activeDuration: record.activeDuration,
    outcome: record.outcome,
  };
  if (record.cards !== undefined) json.cards = record.cards;
  return json;
}

export function decodeStudyPhaseRecord(json: JSONValue | undefined): StudyPhaseRecord {
  if (!isJSONObject(json)) throw new TypeError("Invalid record");
  const cards = optionalNumber(json.cards, "cards");
  return {
    method: oneOf<StudyMethodKind>(STUDY_METHOD_KINDS, json.method, "record.method"),
    phase: oneOf<StudyPhaseKind>(STUDY_PHASE_KINDS, json.phase, "record.phase"),
    startedAt: date(json.startedAt, "startedAt"),
    endedAt: date(json.endedAt, "endedAt"),
    activeDuration: finite(json.activeDuration, "activeDuration"),
    outcome: oneOf(PHASE_OUTCOMES, json.outcome, "outcome"),
    ...(cards === undefined ? {} : { cards: Math.trunc(cards) }),
  };
}

/** The session in the Mac's Codable shape. */
export function encodeStudySession(session: StudySession): JSONObject {
  const state = session.stored;
  const json: JSONObject = {
    method: encodeStudyMethod(state.method),
    phase: state.phase,
    completedFocusCount: state.completedFocusCount,
    cardsDone: state.cardsDone,
    log: state.log.map(encodeStudyPhaseRecord),
    banked: state.banked,
    lastFocusWorked: state.lastFocusWorked,
    lastFocusCounted: state.lastFocusCounted,
  };
  if (state.phaseDuration !== undefined) json.phaseDuration = state.phaseDuration;
  if (state.resumedAt !== undefined) json.resumedAt = state.resumedAt - REFERENCE_DATE_OFFSET;
  if (state.phaseStartedAt !== undefined) json.phaseStartedAt = state.phaseStartedAt - REFERENCE_DATE_OFFSET;
  if (state.cardBaseline !== undefined) json.cardBaseline = state.cardBaseline;
  return json;
}

/** Port of StudySession.init(from:) over JSON. Throws on a malformed document. */
export function decodeStudySession(json: JSONValue | undefined): StudySession {
  if (!isJSONObject(json)) throw new TypeError("Invalid session");
  const log = json.log;
  if (!Array.isArray(log)) throw new TypeError("Invalid log");
  if (typeof json.lastFocusCounted !== "boolean") throw new TypeError("Invalid lastFocusCounted");
  const cardBaseline = optionalNumber(json.cardBaseline, "cardBaseline");
  return StudySession.fromStored({
    method: decodeStudyMethod(json.method),
    phase: oneOf<StudyPhaseKind>(STUDY_PHASE_KINDS, json.phase, "phase"),
    phaseDuration: optionalNumber(json.phaseDuration, "phaseDuration"),
    completedFocusCount: integer(json.completedFocusCount, "completedFocusCount"),
    cardsDone: integer(json.cardsDone, "cardsDone"),
    log: log.map(decodeStudyPhaseRecord),
    banked: finite(json.banked, "banked"),
    resumedAt: optionalDate(json.resumedAt, "resumedAt"),
    phaseStartedAt: optionalDate(json.phaseStartedAt, "phaseStartedAt"),
    lastFocusWorked: finite(json.lastFocusWorked, "lastFocusWorked"),
    lastFocusCounted: json.lastFocusCounted,
    cardBaseline: cardBaseline === undefined ? undefined : Math.trunc(cardBaseline),
  });
}
