import { plannerDayKeyOf } from "../planner/plannerDayKey";
import { PetPointsRules } from "../pets/petPointsRules";
import type { StudyDayTally } from "../providers/studyDayTally";
import type { Instant } from "../time";
import type { StudyMethodKind } from "./studyMethodFile";
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
