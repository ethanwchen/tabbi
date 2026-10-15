import { roundHalfAwayFromZero, swiftInt } from "./swiftMath";

/** Shortest and longest goal, in minutes; anything outside is clamped. */
export const DAILY_GOAL_MIN = 15;
export const DAILY_GOAL_MAX = 720;
/** Goals snap to quarter hours, matching a stepper. */
export const DAILY_GOAL_STEP = 15;
/** The progress item's id, stable so Today updates the same row. */
export const DAILY_GOAL_PROGRESS_ID = "minutes";

/**
 * Port of StudyDailyGoal: how many minutes a day the user means to study. A
 * kit sets it under `moduleSettings.study.dailyGoalMinutes`; Study shares the
 * day's minutes against it as a progress goal.
 */
export class StudyDailyGoal {
  readonly minutes: number;

  /** Clamps to 15...720 and snaps to the nearest quarter hour. */
  constructor(minutes: number) {
    const snapped = swiftInt(roundHalfAwayFromZero(minutes / DAILY_GOAL_STEP)) * DAILY_GOAL_STEP;
    this.minutes = Math.min(Math.max(snapped, DAILY_GOAL_MIN), DAILY_GOAL_MAX);
  }

  /** Two hours: used when the kit says nothing. */
  static get standard(): StudyDailyGoal {
    return new StudyDailyGoal(120);
  }

  /** The kit's goal from its Study section, or `standard` when it has none or it is not a finite number. */
  static fromKit(studySection: unknown): StudyDailyGoal {
    const value =
      typeof studySection === "object" && studySection !== null
        ? (studySection as Record<string, unknown>).dailyGoalMinutes
        : undefined;
    if (typeof value !== "number" || !Number.isFinite(value)) return StudyDailyGoal.standard;
    return new StudyDailyGoal(swiftInt(Math.min(Math.max(value, -1e6), 1e6)));
  }

  /** The goal moved by `steps` quarter hours, clamped. */
  stepped(steps: number): StudyDailyGoal {
    return new StudyDailyGoal(this.minutes + steps * DAILY_GOAL_STEP);
  }
}
