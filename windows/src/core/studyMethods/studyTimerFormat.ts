import { tr } from "../localization/tr";
import type { Instant, Seconds } from "../time";
import type { StudyMethod, StudyPhaseKind } from "./studyMethod";
import type { StudySession } from "./studySession";
import { intDivide } from "./swiftMath";

/** Port of StudyDialReadout: what the Study tab's dial shows in its center. */
export interface StudyDialReadout {
  /** The big number: time left, time worked for open-ended focus, or cards answered, e.g. "24:13", "37". */
  readonly value: string;
  /** Small text under the value, e.g. "Focus", "of 100 cards", "Break · Paused"; empty for a running Timer. */
  readonly caption: string;
  /** Whether the value counts down (for the numeric text transition). */
  readonly countsDown: boolean;
}

/*
 * Port of StudyTimerFormat: labels for the Study tab, kept out of the view so
 * they are testable and every method reads the same way.
 */

const pad2 = (value: number): string => String(value).padStart(2, "0");

/**
 * Clock text that grows an hour field only when needed: "4:05", "52:00",
 * "1:30:00". Rounds up, so a phase never shows 0:00 while it still has a
 * fraction of a second left.
 */
export function studyClock(seconds: Seconds): string {
  const total = Number.isFinite(seconds) ? Math.ceil(Math.max(seconds, 0)) : 0;
  const hours = intDivide(total, 3600);
  const minutes = intDivide(total % 3600, 60);
  const secs = total % 60;
  if (hours > 0) return `${hours}:${pad2(minutes)}:${pad2(secs)}`;
  return `${minutes}:${pad2(secs)}`;
}

/** Phase name, e.g. "Focus", "Timer", "Sprint", "Review", "Break", "Long break". */
export function studyPhaseName(phase: StudyPhaseKind, method: StudyMethod): string {
  switch (phase) {
    case "focus":
      if (method.kind === "timer") return tr("Timer");
      return method.cardGoal === undefined ? tr("Focus") : tr("Sprint");
    case "review":
      return tr("Review");
    case "shortBreak":
      return tr("Break");
    case "longBreak":
      return tr("Long break");
  }
}

/** The dial's center for `session` at `now`. */
export function studyReadout(session: StudySession, now: Instant): StudyDialReadout {
  const phase = studyPhaseName(session.phase, session.method);
  const paused = session.runState === "paused";
  const caption = (base: string): string => (paused ? tr("%@ · Paused", base) : base);
  const remaining = session.remaining(now);

  if (session.method.kind === "timer" && remaining !== undefined) {
    return { value: studyClock(remaining), caption: paused ? tr("Paused") : "", countsDown: true };
  }
  if (remaining !== undefined) {
    return { value: studyClock(remaining), caption: caption(phase), countsDown: true };
  }
  const goal = session.method.cardGoal;
  if (goal !== undefined) {
    return { value: `${session.cardsDone}`, caption: caption(tr("of %lld cards", goal)), countsDown: false };
  }
  /* Open-ended Flowtime focus counts up. */
  return {
    value: studyClock(session.elapsed(now)),
    caption: caption(session.runState === "idle" ? tr("Flow") : tr("In flow")),
    countsDown: false,
  };
}

/**
 * Where the session stands, e.g. "Round 2 of 4" for a method with a long
 * break, "3 rounds done", or undefined before the first round finishes and
 * for the Timer, which has no rounds.
 */
export function studyRoundLabel(session: StudySession): string | undefined {
  if (!session.method.hasBreaks) return undefined;
  const done = session.completedFocusCount;
  const every = session.method.longBreak?.every;
  if (every !== undefined) {
    /* Count the round in progress; after a long break start a new set. */
    const round = session.phase === "focus" ? (done % every) + 1 : ((done - 1) % every) + 1;
    return done === 0 && session.phase !== "focus" ? undefined : tr("Round %lld of %lld", Math.max(round, 1), every);
  }
  if (done <= 0) return undefined;
  return tr("%lld rounds done", done);
}

/** Title of the primary button for the session's state. */
export function studyPrimaryAction(session: StudySession): string {
  switch (session.runState) {
    case "running":
      if (session.phase === "focus" && session.method.focus.kind === "openEnded") return tr("Take a break");
      return tr("Pause");
    case "paused":
      return tr("Resume");
    case "idle":
      switch (session.phase) {
        case "focus":
          if (session.method.kind === "timer") return tr("Start timer");
          return session.method.cardGoal === undefined ? tr("Start focus") : tr("Start sprint");
        case "review":
          return tr("Start review");
        case "shortBreak":
        case "longBreak":
          return tr("Start break");
      }
  }
}

/**
 * Time studied as a short label: "0 min", "45 min", "1h 5m". This is
 * DurationFormat.minutes on the Mac, kept here until the formatting port
 * lands so Study reads the same way.
 */
export function studyStudied(minutes: number): string {
  const value = Math.max(minutes, 0);
  if (value < 60) return tr("%lld min", value);
  const hours = intDivide(value, 60);
  const rest = value % 60;
  return rest === 0 ? tr("%lldh", hours) : tr("%lldh %lldm", hours, rest);
}

/** Points as a signed label for a day's tally: "+79 pts", "+1 pt", "0 pts". */
export function studyPoints(points: number): string {
  const value = Math.max(points, 0);
  return value === 0 ? tr("0 pts") : tr("+%lld pts", value);
}
