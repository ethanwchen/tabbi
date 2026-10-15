import type { ModuleID } from "../modules/moduleId";
import { isJSONObject, type JSONObject } from "../persistence/json";
import type { Instant } from "../time";
import { dayKeyOf, type DayKey } from "./dayKey";
import { formatISODate, parseISODate } from "./isoDate";

/**
 * Port of ActivityKind: what kind of thing happened, as an open string id
 * such as `focus.completed`, so a new module can log its own kinds without
 * a shared list to edit. Kinds several modules log are named here.
 */
export type ActivityKind = string;

export const ACTIVITY_KINDS = {
  /** A focus stretch ended (finished or stopped early, see `outcome`); the quantity is the minutes focused. */
  focusCompleted: "focus.completed",
  /** A break ended; the quantity is its minutes. */
  breakTaken: "break.taken",
  /** Flashcards were answered; the quantity is the number of cards. */
  cardsReviewed: "cards.reviewed",
  /** A task was checked off; `subject` is the task's id. */
  taskCompleted: "task.completed",
} as const satisfies Record<string, ActivityKind>;

/** Port of ActivityUnit: the unit of a record's quantity, open like ActivityKind. */
export type ActivityUnit = string;

export const ACTIVITY_UNITS = {
  minutes: "min",
  cards: "cards",
} as const satisfies Record<string, ActivityUnit>;

/** Port of ActivityMetadata: metadata keys several modules use. */
export const ACTIVITY_METADATA = {
  /** How a focus stretch ended: `completed`, `stopped`, `skipped` or `abandoned`. */
  outcome: "outcome",
  /** The study method or timer that ran it, such as `pomodoro`. */
  method: "method",
} as const;

/**
 * Port of ActivityRecord: one thing that happened, for gamification,
 * insights and the pet (a focus stretch, a break, cards reviewed, a task
 * done). The provider snapshot says what is true now; the activity log says
 * what happened. Records are only ever appended, and stay on this machine.
 */
export interface ActivityRecord {
  /** A UUID, upper case as the Mac writes it. */
  readonly id: string;
  /** The module that logged it. */
  readonly source: ModuleID;
  readonly kind: ActivityKind;
  /** Whole seconds, so a record reads back from its day file exactly as it was logged. */
  readonly start: Instant;
  /** Equal to `start` for something that happened at one moment; never before it. */
  readonly end: Instant;
  /** How much, in `unit`: minutes, cards, tasks. */
  readonly quantity?: number;
  readonly unit?: ActivityUnit;
  /** The stable id of what it was about (a task's id). */
  readonly subject?: string;
  /** Small, module-defined details, such as the study method. */
  readonly metadata: Readonly<Record<string, string>>;
}

export interface ActivityRecordInput {
  id?: string;
  source: ModuleID;
  kind: ActivityKind;
  start: Instant;
  end?: Instant;
  quantity?: number;
  unit?: ActivityUnit;
  subject?: string;
  metadata?: Readonly<Record<string, string>>;
}

/** Seconds from 1970 to 2001, the Mac's reference date, which its rounding is relative to. */
const REFERENCE_DATE_OFFSET = 978_307_200;

/** Rounds half away from zero, as Swift's `rounded()` does. */
function roundHalfAwayFromZero(value: number): number {
  return Math.sign(value) * Math.round(Math.abs(value));
}

/** `instant` rounded to whole seconds the way the Mac rounds a `Date`. */
export function wholeSeconds(instant: Instant): Instant {
  return roundHalfAwayFromZero(instant - REFERENCE_DATE_OFFSET) + REFERENCE_DATE_OFFSET;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** A new random id in the Mac's UUID form. */
export function newRecordID(): string {
  return globalThis.crypto.randomUUID().toUpperCase();
}

/** Builds a record the way ActivityRecord's initializer does: whole seconds, and an end never before the start. */
export function makeActivityRecord(input: ActivityRecordInput): ActivityRecord {
  const start = wholeSeconds(input.start);
  const end = Math.max(wholeSeconds(input.end ?? start), start);
  const record: {
    -readonly [Key in keyof ActivityRecord]: ActivityRecord[Key];
  } = {
    id: (input.id ?? newRecordID()).toUpperCase(),
    source: input.source,
    kind: input.kind,
    start,
    end,
    metadata: { ...(input.metadata ?? {}) },
  };
  if (input.quantity !== undefined) record.quantity = input.quantity;
  if (input.unit !== undefined) record.unit = input.unit;
  if (input.subject !== undefined) record.subject = input.subject;
  return record;
}

/** The local day the record counts toward, in the IANA zone `timeZone`: the day it ended. */
export function activityDay(record: ActivityRecord, timeZone: string): DayKey {
  return dayKeyOf(record.end, timeZone);
}

/** The record as the Mac encodes it: ISO 8601 dates, nil fields left out, metadata always present. */
export function encodeActivityRecord(record: ActivityRecord): JSONObject {
  const json: JSONObject = {
    id: record.id,
    source: record.source,
    kind: record.kind,
    start: formatISODate(record.start),
    end: formatISODate(record.end),
    metadata: { ...record.metadata },
  };
  if (record.quantity !== undefined) json.quantity = record.quantity;
  if (record.unit !== undefined) json.unit = record.unit;
  if (record.subject !== undefined) json.subject = record.subject;
  return json;
}

/** Reads one encoded record, as strictly as the Mac's decoder; throws on a field it can't read. */
export function decodeActivityRecord(json: unknown): ActivityRecord {
  if (!isJSONObject(json)) throw new TypeError("An activity record must be an object");
  const { id, source, kind, start, end, quantity, unit, subject, metadata } = json;
  if (typeof id !== "string" || !UUID_PATTERN.test(id)) throw new TypeError("Invalid record id");
  if (typeof source !== "string") throw new TypeError("Invalid record source");
  if (typeof kind !== "string") throw new TypeError("Invalid record kind");
  const startInstant = typeof start === "string" ? parseISODate(start) : undefined;
  if (startInstant === undefined) throw new TypeError("Invalid record start");
  let endInstant: Instant | undefined;
  if (end !== undefined && end !== null) {
    endInstant = typeof end === "string" ? parseISODate(end) : undefined;
    if (endInstant === undefined) throw new TypeError("Invalid record end");
  }
  const optional = <T>(value: unknown, check: (value: unknown) => value is T, what: string): T | undefined => {
    if (value === undefined || value === null) return undefined;
    if (!check(value)) throw new TypeError(`Invalid record ${what}`);
    return value;
  };
  const isNumber = (value: unknown): value is number => typeof value === "number";
  const isString = (value: unknown): value is string => typeof value === "string";
  let readMetadata: Record<string, string> = {};
  if (metadata !== undefined && metadata !== null) {
    if (!isJSONObject(metadata) || !Object.values(metadata).every(isString)) {
      throw new TypeError("Invalid record metadata");
    }
    readMetadata = metadata as Record<string, string>;
  }
  return makeActivityRecord({
    id,
    source,
    kind,
    start: startInstant,
    end: endInstant,
    quantity: optional(quantity, isNumber, "quantity"),
    unit: optional(unit, isString, "unit"),
    subject: optional(subject, isString, "subject"),
    metadata: readMetadata,
  });
}
