import type { ModuleID } from "../modules/moduleId";
import { MINIMUM_LOGGED_DURATION } from "../studyMethods/studyPhaseRecord";
import type { FocusPhaseCompletion, FocusStop, FocusTimerConfig } from "./focusTimer";
import {
  ACTIVITY_KINDS,
  ACTIVITY_METADATA,
  ACTIVITY_UNIT_MINUTES,
  makeTimerActivityRecord,
  type TimerActivityRecord,
} from "./timerActivity";

/**
 * Port of FocusPhaseCompletion.activityRecord(config:source:): a finished
 * focus stretch or a break taken, lasting the configured length and ending
 * when it ended.
 */
export function completionActivityRecord(
  completion: FocusPhaseCompletion,
  config: FocusTimerConfig,
  source: ModuleID,
): TimerActivityRecord {
  const length = config.duration(completion.phase);
  return makeTimerActivityRecord({
    source,
    kind: completion.phase === "focus" ? ACTIVITY_KINDS.focusCompleted : ACTIVITY_KINDS.breakTaken,
    start: completion.endedAt - length,
    end: completion.endedAt,
    quantity: length / 60,
    unit: ACTIVITY_UNIT_MINUTES,
    metadata: { [ACTIVITY_METADATA.method]: "pomodoro", [ACTIVITY_METADATA.outcome]: "completed" },
  });
}

/**
 * Port of FocusStop.activityRecord(source:): the minutes actually focused in
 * a phase stopped or skipped early. Undefined under a minute, like a start
 * tapped by mistake.
 */
export function stopActivityRecord(stop: FocusStop, source: ModuleID): TimerActivityRecord | undefined {
  if (!Number.isFinite(stop.focused) || stop.focused < MINIMUM_LOGGED_DURATION) return undefined;
  return makeTimerActivityRecord({
    source,
    kind: ACTIVITY_KINDS.focusCompleted,
    start: stop.endedAt - stop.focused,
    end: stop.endedAt,
    quantity: stop.focused / 60,
    unit: ACTIVITY_UNIT_MINUTES,
    metadata: { [ACTIVITY_METADATA.method]: "pomodoro", [ACTIVITY_METADATA.outcome]: stop.outcome },
  });
}

/*
 * Port of ActivityRecord.countsAsFinishedSession for the timers' records: a
 * stretch stopped or skipped early adds study time but is no finished session.
 */
function countsAsFinishedSession(record: TimerActivityRecord): boolean {
  const outcome = record.metadata[ACTIVITY_METADATA.outcome];
  return outcome === undefined || outcome === "completed" || outcome === "stopped";
}

/**
 * Port of FocusTimer.sessionsDone(in:source:): how many focus stretches
 * `source` finished among `records`, for the Focus tab's daily tally.
 */
export function focusSessionsDone(records: readonly TimerActivityRecord[], source: ModuleID): number {
  return records.filter(
    (record) => record.source === source && record.kind === ACTIVITY_KINDS.focusCompleted && countsAsFinishedSession(record),
  ).length;
}
