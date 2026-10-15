import type { Instant } from "../time";
import { dayKey, type DayCalendar, type DayKey } from "../streaks/dayCalendar";

/*
 * The slice of the activity log (the Mac's ActivityRecord) that points,
 * milestones, streaks and the bond read. A narrow local shape: the activity
 * log port owns the full record, and any record of it fits here.
 */

/** One logged activity, as far as the pet cares. */
export interface StudyActivityRecord {
  /** Unique per record, so replaying the log counts each once. */
  readonly id: string;
  /** The module that logged it, such as `focus`, `study` or `party`. */
  readonly source: string;
  /** The open kind, such as `focus.completed`. */
  readonly kind: string;
  /** When it ended; the record belongs to that local day. */
  readonly end: Instant;
  readonly quantity?: number;
  readonly unit?: string;
  readonly metadata?: Readonly<Record<string, string>>;
}

/** Port of ActivityKind.focusCompleted. */
export const FOCUS_COMPLETED = "focus.completed";
/** Port of ActivityUnit.minutes. */
export const MINUTES_UNIT = "min";
/** Port of ActivityMetadata.outcome: how a study phase ended. */
export const OUTCOME_KEY = "outcome";
/** The Party module's id. */
export const PARTY_SOURCE = "party";

/** How a study phase ended (StudyPhaseOutcome's raw values the pet reads). */
export type StudyPhaseOutcome = "completed" | "stopped" | "skipped" | "abandoned";

export function recordOutcome(record: StudyActivityRecord): StudyPhaseOutcome | undefined {
  const raw = record.metadata?.[OUTCOME_KEY];
  return raw === "completed" || raw === "stopped" || raw === "skipped" || raw === "abandoned" ? raw : undefined;
}

/** The local day a record belongs to: the day it ended. */
export function recordDay(record: StudyActivityRecord, calendar: DayCalendar): DayKey {
  return dayKey(record.end, calendar);
}
