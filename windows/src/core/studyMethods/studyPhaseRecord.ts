import { ACTIVITY_KINDS, ACTIVITY_METADATA, ACTIVITY_UNITS, makeActivityRecord, type ActivityRecord } from "../activity/activityRecord";
import type { ModuleID } from "../modules/moduleId";
import type { Instant, Seconds } from "../time";
import type { StudyMethodKind } from "./studyMethodFile";
import { isBreakPhase, type StudyPhaseKind } from "./studyMethod";

/** Port of StudyRunState: whether the session clock is moving. */
export type StudyRunState = "idle" | "running" | "paused";

/** Port of StudyPhaseOutcome: how a phase ended. */
export type StudyPhaseOutcome =
  /** Ran its full length or hit its card goal. */
  | "completed"
  /** The user stopped an open-ended Flowtime focus phase, its normal end. */
  | "stopped"
  /** The user ended the phase early and moved on. */
  | "skipped"
  /** The session was reset or switched to another method mid-phase. */
  | "abandoned";

/** Whether a focus phase with this outcome counts as done, for long-break cadence and the day's tally. */
export function countsAsDone(outcome: StudyPhaseOutcome): boolean {
  return outcome === "completed" || outcome === "stopped";
}

/** Port of StudyPhaseRecord: one phase that actually ran, for the session log and notifications. */
export interface StudyPhaseRecord {
  readonly method: StudyMethodKind;
  readonly phase: StudyPhaseKind;
  /** When the phase was first started. */
  readonly startedAt: Instant;
  /** Wall-clock end; for a phase that ran out while the app slept, when it really ended. */
  readonly endedAt: Instant;
  /** Time the clock was running, excluding pauses. */
  readonly activeDuration: Seconds;
  readonly outcome: StudyPhaseOutcome;
  /** Cards answered during an Anki sprint focus phase; undefined otherwise. */
  readonly cards?: number;
}

/** Phases shorter than this (a start tapped by mistake, an instant skip) are not worth logging. */
export const MINIMUM_LOGGED_DURATION: Seconds = 60;

/**
 * Port of StudyPhaseRecord.activityRecord(source:): study time (focus or
 * question review) as `focus.completed`, a break as `break.taken`, with the
 * minutes the clock ran. Undefined for phases under a minute. Sprint cards go
 * in the metadata only, since the Anki module logs the cards themselves.
 */
export function phaseActivityRecord(record: StudyPhaseRecord, source: ModuleID): ActivityRecord | undefined {
  if (!Number.isFinite(record.activeDuration) || record.activeDuration < MINIMUM_LOGGED_DURATION) return undefined;
  const metadata: Record<string, string> = {
    [ACTIVITY_METADATA.method]: record.method,
    [ACTIVITY_METADATA.outcome]: record.outcome,
    phase: record.phase,
  };
  if (record.cards !== undefined) metadata.cards = String(record.cards);
  return makeActivityRecord({
    source,
    kind: isBreakPhase(record.phase) ? ACTIVITY_KINDS.breakTaken : ACTIVITY_KINDS.focusCompleted,
    start: record.startedAt,
    end: record.endedAt,
    quantity: record.activeDuration / 60,
    unit: ACTIVITY_UNITS.minutes,
    metadata,
  });
}
