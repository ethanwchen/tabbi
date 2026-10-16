import { PetPointsRules } from "../pets/petPointsRules";

/**
 * Port of StudyDayTally: today's study time and rewards so far, such as a
 * study timer's log. The StudySource role of a module: Wrap Up shows it
 * without knowing which module ran the sessions.
 */
export interface StudyDayTally {
  /** Minutes studied today, finished or not. */
  readonly minutes: number;
  /** Study sessions that ran to their end today. */
  readonly sessions: number;
  /** Points earned today (see `PetPointsRules`). */
  readonly points: number;
}

export const EMPTY_STUDY_DAY_TALLY: StudyDayTally = { minutes: 0, sessions: 0, points: 0 };

/** Adds two modules' tallies (the Mac's `+`). */
export function addStudyDayTallies(lhs: StudyDayTally, rhs: StudyDayTally): StudyDayTally {
  return { minutes: lhs.minutes + rhs.minutes, sessions: lhs.sessions + rhs.sessions, points: lhs.points + rhs.points };
}

/** Demo data: three finished 50-minute blocks and an unfinished 35, with points from the real rules. */
export const SAMPLE_STUDY_DAY_TALLY: StudyDayTally = (() => {
  const blocks: readonly (readonly [number, boolean])[] = [
    [50, true],
    [50, true],
    [50, true],
    [35, false],
  ];
  return {
    minutes: blocks.reduce((sum, [minutes]) => sum + minutes, 0),
    sessions: blocks.filter(([, completed]) => completed).length,
    points: blocks.reduce((sum, [minutes, completed]) => sum + PetPointsRules.points(minutes, completed), 0),
  };
})();
