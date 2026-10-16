import type { PetStudyAward } from "../closet/petStudyCredit";
import type { PetMilestoneProgress } from "../closet/petLimited";
import { tr } from "../localization/tr";
import { REFERENCE_DATE_OFFSET } from "../pets/petUnlocks";
import { VersionedJSON } from "../persistence/versionedJson";
import type { JSONObject } from "../persistence/json";
import { addingDaysToKey, dayKeyStart, isPlannerDayKey, plannerDayKeyOf, type PlannerDayKey } from "../planner/plannerDayKey";
import { hourOf } from "../streaks/dayCalendar";
import type { StudyStreak } from "../streaks/studyStreak";
import type { Instant } from "../time";
import { randomElement, randomUnit, type RandomSource } from "./randomSource";

/*
 * Port of CatWisdom.swift: the rare lines the cat says in its speech bubble
 * right after a focus session ends. The lines are fixed copy approved by
 * the maintainer, kept in English and looked up in the catalog by that
 * text; `CatWisdomSchedule` decides when one shows. Days are local days in
 * the IANA zone passed in.
 */

/** Lines for the first completed session of an ordinary day. */
export const CAT_WISDOM_DAILY: readonly string[] = [
  "The pawn keeps moving forward. One square at a time, it can become anything it wants.",
  "Nobody sees roots growing. Then one day there's a tree.",
  "You didn't feel like it, and you did it anyway. That's the whole secret.",
  "Water carves canyons by never skipping a day.",
  "The person you're becoming is built in quiet hours like this one.",
  "Talent is a head start. Showing up is the whole race.",
  "The work no one sees is the work that changes you.",
  "You're not behind. You're on your own clock, and it only moves forward.",
  "Stars don't rush. They just keep burning.",
  "Every hour you give your future, it gives back with interest.",
  "Hard things get easy the same way paths get worn: one step, many times.",
  "Most people wait to feel ready. You just started. That's the difference.",
];

/** Lines for the first completed session after two or more days without one. */
export const CAT_WISDOM_COMEBACK: readonly string[] = [
  "Falling off isn't failing. Staying off is. And look, you're back.",
  "Cats land on their feet because they never stop turning toward the ground. Welcome back.",
];

/** The gentle line after a session stopped early that still earned points. */
export const CAT_WISDOM_EARLY_STOP = "Some is infinitely more than none. Rest. The board will be here.";

/** The line for a session completed late at night. */
export const CAT_WISDOM_LATE_NIGHT = "Sleep is part of the work. Go dream up tomorrow's moves.";

/**
 * One line from the daily pool for the weekly recap card: the same for
 * every look at the same week, and a different one week to week. Counted in
 * whole weeks from the Mac's 2001 reference date, so both apps pick the
 * same line.
 */
export function catWisdomRecapLine(weekStart: Instant, timeZone: string): string {
  const day = dayKeyStart(plannerDayKeyOf(weekStart, timeZone), timeZone);
  const weeks = Math.floor((day - REFERENCE_DATE_OFFSET) / (7 * 86_400));
  const count = CAT_WISDOM_DAILY.length;
  return CAT_WISDOM_DAILY[((weeks % count) + count) % count] ?? "";
}

/** A study milestone the cat marks with its own line, once, the first time it is reached. */
export type CatWisdomMilestone =
  | "sevenDayStreak"
  | "thirtyDayStreak"
  | "tenHours"
  | "fiftyHours"
  /** A 100-day streak or 100 hours focused, whichever comes first: the pawn reaching the last square. */
  | "lastSquare";

export const CAT_WISDOM_MILESTONES: readonly CatWisdomMilestone[] = [
  "sevenDayStreak",
  "thirtyDayStreak",
  "tenHours",
  "fiftyHours",
  "lastSquare",
];

const MILESTONE_LINES: Record<CatWisdomMilestone, string> = {
  sevenDayStreak: "Seven days. You're not trying anymore. You're becoming.",
  thirtyDayStreak: "Thirty days ago this was hard. Notice that it isn't anymore.",
  tenHours: "Ten hours of betting on yourself. Keep betting.",
  fiftyHours: "The pawn has crossed half the board. The far side is closer than it looks.",
  lastSquare: "The pawn reached the last square. Now it can move any way it wants. So can you.",
};

export function milestoneLine(milestone: CatWisdomMilestone): string {
  return MILESTONE_LINES[milestone];
}

/** Whether a user with this streak (days) and total focus (minutes) has reached the milestone. */
export function milestoneIsReached(milestone: CatWisdomMilestone, streakDays: number, focusMinutes: number): boolean {
  switch (milestone) {
    case "sevenDayStreak":
      return streakDays >= 7;
    case "thirtyDayStreak":
      return streakDays >= 30;
    case "tenHours":
      return focusMinutes >= 10 * 60;
    case "fiftyHours":
      return focusMinutes >= 50 * 60;
    case "lastSquare":
      return streakDays >= 100 || focusMinutes >= 100 * 60;
  }
}

/** Why a wisdom line showed, for tests and for the bubble's styling. */
export type CatWisdomKind =
  | { readonly type: "milestone"; readonly milestone: CatWisdomMilestone }
  | { readonly type: "comeback" }
  | { readonly type: "lateNight" }
  | { readonly type: "firstOfDay" }
  | { readonly type: "earlyStop" };

/** A line to show and why. `text` is the approved English, which the schedule and tests work with. */
export interface CatWisdomLine {
  readonly kind: CatWisdomKind;
  readonly text: string;
}

/** The line in the user's language, looked up by its English as seasonal event names are; a line the catalog lacks shows as written. */
export function wisdomDisplayText(line: CatWisdomLine): string {
  return tr(line.text);
}

/** A focus session that just ended, as the wisdom schedule sees it. */
export interface CatWisdomSession {
  /** `completed`: the focus phase ran to its end; `stoppedWithPoints`: stopped early and still earned points. */
  readonly outcome: "completed" | "stoppedWithPoints";
  /** When the session ended. */
  readonly end: Instant;
  /** When the completed session before this one ended, or undefined if there was none. */
  readonly previousCompletion?: Instant;
  /** The study streak in days, this session included. */
  readonly streakDays: number;
  /** Minutes focused in total, this session included. */
  readonly totalFocusMinutes: number;
}

/**
 * The session behind a study award the pet just credited, read from what
 * the pet already tracks: its streak and focus totals from the activity
 * log, and the last completion the coach saw.
 *
 * Undefined for an award with no session to speak of. A completed session
 * counts today toward the streak, and its minutes count toward the total
 * when today's log cannot hold them yet, so a milestone is never shown
 * early (at worst one session late, when the log is behind on a busy day).
 * `lastCompletion` undefined (a first look) falls back to the last study
 * day before today in `progress`.
 */
export function catWisdomSessionFromAward(
  award: PetStudyAward,
  end: Instant,
  lastCompletion: Instant | undefined,
  streak: StudyStreak,
  progress: PetMilestoneProgress,
  timeZone: string,
): CatWisdomSession | undefined {
  if (!(award.points > 0)) return undefined;
  const completed = award.completedSessions > 0;
  const today = plannerDayKeyOf(end, timeZone);
  const earlier = progress.studyDays.filter((day) => day < today);
  const lastDay = earlier[earlier.length - 1];
  const previous = lastCompletion ?? (lastDay === undefined ? undefined : dayKeyStart(lastDay, timeZone));
  const todayMinutes = progress.minutesByDay.get(today) ?? 0;
  /* The log already holds this session once today's minutes cover it. */
  const logged = todayMinutes >= award.minutes;
  const streakDays = streak.length + (completed && !streak.studiedToday ? 1 : 0);
  const total = Math.trunc(progress.focusMinutes) + (logged ? 0 : award.minutes);
  return {
    outcome: completed ? "completed" : "stoppedWithPoints",
    end,
    ...(previous === undefined ? {} : { previousCompletion: previous }),
    streakDays,
    totalFocusMinutes: total,
  };
}

/**
 * When the cat says a wisdom line, and which one. Persisted, so the
 * rotation and the caps survive a restart.
 *
 * Rules (the maintainer's design, with no guilt mechanics):
 * - Only right after a focus session ends; never during focus, on launch
 *   or as a notification. At most one line per calendar day.
 * - Priority: an unshown milestone, then a comeback (the first completed
 *   session after two or more days without one), then a late-night line
 *   (a session completed from 11 PM, at most once a week), then on the
 *   first completed session of the day a daily line with `ordinaryChance`.
 * - A session stopped early with points may get the early-stop line, with
 *   the same chance; it counts toward the daily cap.
 * - Each pool rotates without repeats until every line has shown.
 * - Milestones show once each. Those already reached on the first look or
 *   while the toggle is off are marked as seen silently, so turning the
 *   feature on never brings a backlog.
 */
export class CatWisdomSchedule {
  /** The chance of a daily or early-stop line on an ordinary day, about 3 to 4 lines in a week of study. */
  static readonly ordinaryChance = 0.5;
  /** Days between late-night lines. */
  static readonly lateNightGapDays = 7;
  /** Days without a completed session that make the next one a comeback. */
  static readonly comebackGapDays = 2;
  static readonly schema = new VersionedJSON(1);

  /** The day the last line showed. */
  lastShownDay: PlannerDayKey | undefined;
  /** The day the last late-night line showed. */
  lastLateNightDay: PlannerDayKey | undefined;
  /** Indices into the daily pool shown in the current rotation. */
  dailyShown: number[] = [];
  /** Indices into the comeback pool shown in the current rotation. */
  comebackShown: number[] = [];
  /** Milestones already shown or passed silently. */
  milestonesSeen = new Set<CatWisdomMilestone>();
  /** Whether milestones reached before the first look have been marked. */
  baselined = false;

  /**
   * The line to show for `session`, or undefined, updating the rotation and
   * caps when one shows. With `enabled` off it shows nothing and only marks
   * reached milestones as seen.
   */
  line(session: CatWisdomSession, timeZone: string, random: RandomSource, enabled = true): CatWisdomLine | undefined {
    const reached = CAT_WISDOM_MILESTONES.filter((milestone) =>
      milestoneIsReached(milestone, session.streakDays, session.totalFocusMinutes),
    );
    if (!enabled || !this.baselined) {
      this.baselined = true;
      for (const milestone of reached) this.milestonesSeen.add(milestone);
      if (!enabled) return undefined;
      return this.line(session, timeZone, random, true);
    }
    const today = plannerDayKeyOf(session.end, timeZone);
    if (this.lastShownDay === today) return undefined;

    let picked: CatWisdomLine | undefined;
    if (session.outcome === "stoppedWithPoints") {
      picked = randomUnit(random) < CatWisdomSchedule.ordinaryChance ? { kind: { type: "earlyStop" }, text: CAT_WISDOM_EARLY_STOP } : undefined;
    } else {
      picked = this.completedLine(session, today, reached, timeZone, random);
    }
    if (picked !== undefined) this.lastShownDay = today;
    return picked;
  }

  private completedLine(
    session: CatWisdomSession,
    today: PlannerDayKey,
    reached: readonly CatWisdomMilestone[],
    timeZone: string,
    random: RandomSource,
  ): CatWisdomLine | undefined {
    const milestone = reached.find((candidate) => !this.milestonesSeen.has(candidate));
    if (milestone !== undefined) {
      this.milestonesSeen.add(milestone);
      return { kind: { type: "milestone", milestone }, text: milestoneLine(milestone) };
    }
    const previousDay = session.previousCompletion === undefined ? undefined : plannerDayKeyOf(session.previousCompletion, timeZone);
    if (previousDay !== undefined && addingDaysToKey(previousDay, CatWisdomSchedule.comebackGapDays + 1) <= today) {
      const index = nextInRotation(CAT_WISDOM_COMEBACK.length, this.comebackShown, random);
      return { kind: { type: "comeback" }, text: CAT_WISDOM_COMEBACK[index] ?? "" };
    }
    const lastLateNight = this.lastLateNightDay;
    if (
      CatWisdomSchedule.isLateNight(session.end, timeZone) &&
      (lastLateNight === undefined || addingDaysToKey(lastLateNight, CatWisdomSchedule.lateNightGapDays) <= today)
    ) {
      this.lastLateNightDay = today;
      return { kind: { type: "lateNight" }, text: CAT_WISDOM_LATE_NIGHT };
    }
    if (previousDay === today || !(randomUnit(random) < CatWisdomSchedule.ordinaryChance)) return undefined;
    const index = nextInRotation(CAT_WISDOM_DAILY.length, this.dailyShown, random);
    return { kind: { type: "firstOfDay" }, text: CAT_WISDOM_DAILY[index] ?? "" };
  }

  /** Late night: from 11 PM to 4 AM local time. */
  static isLateNight(date: Instant, timeZone: string): boolean {
    const hour = hourOf(date, timeZone);
    return hour >= 23 || hour < 4;
  }

  /** The Mac's Codable shape (milestones sorted); `encoded` adds `schemaVersion`. */
  toJSON(): JSONObject {
    const json: JSONObject = {
      dailyShown: [...this.dailyShown],
      comebackShown: [...this.comebackShown],
      milestonesSeen: [...this.milestonesSeen].sort(),
      baselined: this.baselined,
    };
    if (this.lastShownDay !== undefined) json.lastShownDay = this.lastShownDay;
    if (this.lastLateNightDay !== undefined) json.lastLateNightDay = this.lastLateNightDay;
    return json;
  }

  /** Reads `toJSON`'s shape, defaulting every missing field the way the Mac does; unknown milestones are dropped. */
  static fromJSON(json: unknown): CatWisdomSchedule {
    if (typeof json !== "object" || json === null || Array.isArray(json)) throw new TypeError("Invalid wisdom schedule");
    const object = json as Record<string, unknown>;
    const schedule = new CatWisdomSchedule();
    schedule.lastShownDay = optionalDay(object.lastShownDay, "lastShownDay");
    schedule.lastLateNightDay = optionalDay(object.lastLateNightDay, "lastLateNightDay");
    schedule.dailyShown = integers(object.dailyShown, "dailyShown");
    schedule.comebackShown = integers(object.comebackShown, "comebackShown");
    const seen = object.milestonesSeen;
    if (seen !== undefined && seen !== null) {
      if (!Array.isArray(seen) || !seen.every((item): item is string => typeof item === "string")) throw new TypeError("Invalid milestonesSeen");
      for (const raw of seen) {
        const milestone = CAT_WISDOM_MILESTONES.find((candidate) => candidate === raw);
        if (milestone !== undefined) schedule.milestonesSeen.add(milestone);
      }
    }
    const baselined = object.baselined;
    if (baselined !== undefined && baselined !== null && typeof baselined !== "boolean") throw new TypeError("Invalid baselined");
    schedule.baselined = baselined === true;
    return schedule;
  }

  /** The schedule as its versioned JSON document. */
  encoded(): string {
    return CatWisdomSchedule.schema.encode(this.toJSON(), { pretty: true, sortedKeys: true });
  }

  /** Reads a document written by `encoded`, running any migrations. */
  static decode(text: string): CatWisdomSchedule {
    return CatWisdomSchedule.schema.decode(text, (document) => CatWisdomSchedule.fromJSON(document));
  }

  equals(other: CatWisdomSchedule): boolean {
    return JSON.stringify(this.toJSON()) === JSON.stringify(other.toJSON());
  }
}

/*
 * An index not shown in this rotation, starting a new rotation (that still
 * skips the last one shown) once every line has been used. Updates `shown`
 * in place.
 */
function nextInRotation(count: number, shown: number[], random: RandomSource): number {
  const valid = shown.filter((index) => index >= 0 && index < count);
  shown.splice(0, shown.length, ...valid);
  const all = Array.from({ length: count }, (_, index) => index);
  let candidates = all.filter((index) => !shown.includes(index));
  if (candidates.length === 0) {
    const last = shown[shown.length - 1];
    shown.splice(0, shown.length);
    candidates = all.filter((index) => index !== last || count === 1);
  }
  const index = randomElement(candidates, random);
  shown.push(index);
  return index;
}

function optionalDay(value: unknown, key: string): PlannerDayKey | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string" || !isPlannerDayKey(value)) throw new TypeError(`Invalid ${key}`);
  return value;
}

function integers(value: unknown, key: string): number[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || !value.every((item): item is number => Number.isInteger(item))) throw new TypeError(`Invalid ${key}`);
  return [...value];
}
