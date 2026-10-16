import type { DocumentStore } from "../persistence/documentStore";
import { isJSONObject, type JSONObject, type JSONValue } from "../persistence/json";
import { VersionedJSON } from "../persistence/versionedJson";
import { parseUUID } from "../planner/uuid";
import { plannerDayKeyOf } from "../planner/plannerDayKey";
import { PetPointsRules } from "../pets/petPointsRules";
import type { StudyDayTally } from "../providers/studyDayTally";
import type { Instant } from "../time";
import { STUDY_METHOD_KINDS, type StudyMethodKind } from "./studyMethodFile";
import { isBreakPhase } from "./studyMethod";
import { countsAsDone, type StudyPhaseRecord } from "./studyPhaseRecord";
import { swiftInt } from "./swiftMath";

/** Port of StudyLogEntry: one study stretch in the saved log, with the points it earned. */
export interface StudyLogEntry {
  readonly id: string;
  readonly method: StudyMethodKind;
  readonly startedAt: Instant;
  readonly endedAt: Instant;
  /** Whole minutes the clock ran, excluding pauses. */
  readonly minutes: number;
  /** Ran its full length, hit its card goal, or was a stopped Flowtime stretch. */
  readonly completed: boolean;
  /** Cards answered, for an Anki sprint. */
  readonly cards?: number;
  /** Points earned, fixed when logged so later rule changes never rewrite history. */
  readonly points: number;
}

/**
 * Port of StudyLogEntry.init?(_:): the entry for a phase that ran, or
 * undefined for breaks and stretches under a minute, which are not study time.
 */
export function studyLogEntry(record: StudyPhaseRecord, id: string): StudyLogEntry | undefined {
  if (isBreakPhase(record.phase) || !Number.isFinite(record.activeDuration)) return undefined;
  const minutes = swiftInt(Math.max(record.activeDuration, 0) / 60);
  if (minutes < 1) return undefined;
  const completed = countsAsDone(record.outcome);
  return {
    id,
    method: record.method,
    startedAt: record.startedAt,
    endedAt: record.endedAt,
    minutes,
    completed,
    ...(record.cards === undefined ? {} : { cards: Math.max(record.cards, 0) }),
    points: PetPointsRules.points(minutes, completed),
  };
}

/**
 * Port of StudyLog: the history of study stretches, oldest first, capped at
 * `capacity` entries. Points use the same rules the pet pays by; the log never
 * credits the pet itself, so every stretch is paid exactly once.
 */
export class StudyLog {
  /** The most entries kept; the oldest fall off first. Roughly a year of heavy daily use. */
  static readonly capacity = 3000;

  readonly entries: readonly StudyLogEntry[];

  constructor(entries: readonly StudyLogEntry[] = []) {
    this.entries = entries.slice(-StudyLog.capacity);
  }

  /**
   * Logs the study stretches among `records` and returns the new log and the
   * added entries. `makeId` names each entry (the app passes a UUID maker).
   */
  recording(records: readonly StudyPhaseRecord[], makeId: () => string): { log: StudyLog; added: StudyLogEntry[] } {
    const added = records.flatMap((record) => studyLogEntry(record, makeId()) ?? []);
    if (added.length === 0) return { log: this, added };
    return { log: new StudyLog([...this.entries, ...added]), added };
  }

  /** Totals for the stretches that ended on the calendar day of `day` in `timeZone` (an IANA name). */
  summary(day: Instant, timeZone: string): StudyDayTally {
    const target = plannerDayKeyOf(day, timeZone);
    const total = { minutes: 0, sessions: 0, points: 0 };
    for (const entry of this.entries) {
      if (plannerDayKeyOf(entry.endedAt, timeZone) !== target) continue;
      total.minutes += entry.minutes;
      total.points += entry.points;
      if (entry.completed) total.sessions += 1;
    }
    return total;
  }

  /** Every point the log has earned. */
  get totalPoints(): number {
    return this.entries.reduce((sum, entry) => sum + entry.points, 0);
  }
}

/* Persistence: the Mac's `Study/log.json`, a VersionedJSON document. */

/** Port of StudyStore.logURL(in:): the log's document name in the edition's folder. */
export const STUDY_LOG_DOCUMENT_NAME = "Study/log.json";

/** Port of StudyLog.schema: the log file format. Version 1 added the `schemaVersion` key. */
export const STUDY_LOG_SCHEMA = new VersionedJSON(1);

/** Seconds from 1970 to 2001, the reference date Foundation encodes dates against by default. */
const REFERENCE_DATE_OFFSET = 978_307_200;

function integer(value: JSONValue | undefined, key: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value)) throw new TypeError(`Invalid ${key}`);
  return value;
}

function date(value: JSONValue | undefined, key: string): Instant {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new TypeError(`Invalid ${key}`);
  return value + REFERENCE_DATE_OFFSET;
}

/**
 * Port of StudyLogEntry.init(from:): every key but `cards` is required, and
 * decoding goes through the clamping init so a hand-edited file can't carry
 * negative minutes, cards or points. Throws on a malformed entry.
 */
export function decodeStudyLogEntry(json: JSONValue | undefined): StudyLogEntry {
  if (!isJSONObject(json)) throw new TypeError("Invalid entry");
  const id = typeof json.id === "string" ? parseUUID(json.id) : undefined;
  if (id === undefined) throw new TypeError("Invalid id");
  const method = STUDY_METHOD_KINDS.find((kind) => kind === json.method);
  if (method === undefined) throw new TypeError("Invalid method");
  if (typeof json.completed !== "boolean") throw new TypeError("Invalid completed");
  const cards = json.cards === undefined || json.cards === null ? undefined : Math.max(integer(json.cards, "cards"), 0);
  return {
    id,
    method,
    startedAt: date(json.startedAt, "startedAt"),
    endedAt: date(json.endedAt, "endedAt"),
    minutes: Math.max(integer(json.minutes, "minutes"), 0),
    completed: json.completed,
    ...(cards === undefined ? {} : { cards }),
    points: Math.max(integer(json.points, "points"), 0),
  };
}

/** The entry in the Mac's Codable shape (dates as seconds since 2001, no `cards` when there are none). */
export function encodeStudyLogEntry(entry: StudyLogEntry): JSONObject {
  const json: JSONObject = {
    id: entry.id,
    method: entry.method,
    startedAt: entry.startedAt - REFERENCE_DATE_OFFSET,
    endedAt: entry.endedAt - REFERENCE_DATE_OFFSET,
    minutes: entry.minutes,
    completed: entry.completed,
    points: entry.points,
  };
  if (entry.cards !== undefined) json.cards = entry.cards;
  return json;
}

/**
 * Port of StudyLog.init(from:): `entries`, an empty log when the key is
 * missing or null. Keys it doesn't know (such as the retired `uncredited`
 * list) are ignored; one malformed entry makes the whole log unreadable.
 */
export function decodeStudyLog(document: JSONObject): StudyLog {
  const entries = document.entries;
  if (entries === undefined || entries === null) return new StudyLog();
  if (!Array.isArray(entries)) throw new TypeError("Invalid entries");
  return new StudyLog(entries.map(decodeStudyLogEntry));
}

/** Port of StudyLog.write's encoding: sorted keys, no indentation, stamped with the schema version. */
export function encodeStudyLog(log: StudyLog): string {
  return STUDY_LOG_SCHEMA.encode({ entries: log.entries.map(encodeStudyLogEntry) }, { sortedKeys: true });
}

/**
 * Port of StudyLog.load(from:): the log in document `name`, or undefined
 * when there is none yet. Rejects when it exists but can't be read, so the
 * caller can decide not to overwrite it.
 */
export async function loadStudyLog(store: DocumentStore, name: string = STUDY_LOG_DOCUMENT_NAME): Promise<StudyLog | undefined> {
  const text = await store.read(name);
  return text === undefined ? undefined : STUDY_LOG_SCHEMA.decode(text, decodeStudyLog);
}

/** Port of StudyLog.write(to:): replaces document `name` atomically. */
export async function writeStudyLog(store: DocumentStore, log: StudyLog, name: string = STUDY_LOG_DOCUMENT_NAME): Promise<void> {
  await store.write(name, encodeStudyLog(log));
}
