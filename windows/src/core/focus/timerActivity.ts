import type { ModuleID } from "../modules/moduleId";
import type { Instant } from "../time";
import { roundHalfAwayFromZero } from "../studyMethods/swiftMath";

/*
 * The slice of the Mac's ActivityRecord that the focus timer and the study
 * session log: a focus stretch or a break, in minutes. Kept narrow here
 * because the activity log itself (ids, the per-day file) belongs to its own
 * port; that port can take these fields as they are.
 */

/** Port of ActivityKind's shared kinds the timers log. */
export const ACTIVITY_KINDS = {
  /** A focus stretch ended (finished or stopped early, see `outcome`); the quantity is the minutes focused. */
  focusCompleted: "focus.completed",
  /** A break ended; the quantity is its minutes. */
  breakTaken: "break.taken",
} as const;

/** Port of ActivityUnit.minutes. */
export const ACTIVITY_UNIT_MINUTES = "min";

/** Port of ActivityMetadata's shared keys. */
export const ACTIVITY_METADATA = {
  /** How a focus stretch ended: completed, stopped, skipped or abandoned. */
  outcome: "outcome",
  /** The study method or timer that ran it, such as pomodoro. */
  method: "method",
} as const;

export interface TimerActivityRecord {
  readonly source: ModuleID;
  readonly kind: string;
  /** Whole seconds, like the Mac's record. */
  readonly start: Instant;
  readonly end: Instant;
  readonly quantity?: number;
  readonly unit?: string;
  readonly metadata: Readonly<Record<string, string>>;
}

/* Seconds from 1970 to 2001, where Foundation's Date counts from. */
const REFERENCE_DATE_OFFSET = 978_307_200;

/** Rounds to whole seconds the way the Mac does, on Foundation's 2001-based clock. */
function wholeSeconds(instant: Instant): Instant {
  return roundHalfAwayFromZero(instant - REFERENCE_DATE_OFFSET) + REFERENCE_DATE_OFFSET;
}

/** Port of ActivityRecord's init: whole-second start and end, and an end never before the start. */
export function makeTimerActivityRecord(fields: {
  source: ModuleID;
  kind: string;
  start: Instant;
  end?: Instant;
  quantity?: number;
  unit?: string;
  metadata?: Record<string, string>;
}): TimerActivityRecord {
  const start = wholeSeconds(fields.start);
  return {
    source: fields.source,
    kind: fields.kind,
    start,
    end: Math.max(wholeSeconds(fields.end ?? fields.start), start),
    ...(fields.quantity === undefined ? {} : { quantity: fields.quantity }),
    ...(fields.unit === undefined ? {} : { unit: fields.unit }),
    metadata: fields.metadata ?? {},
  };
}
