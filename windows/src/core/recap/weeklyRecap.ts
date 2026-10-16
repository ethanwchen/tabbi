import {
  ACTIVITY_KINDS,
  ACTIVITY_UNITS,
  activityDay,
  activityOutcome,
  countsAsFinishedSession,
  type ActivityRecord,
} from "../activity/activityRecord";
import { tr } from "../localization/tr";
import { MODULE_IDS } from "../modules/moduleId";
import { PARTY_FRIENDS_METADATA_KEY } from "../party/partySessionTracker";
import { isJSONObject, type JSONObject } from "../persistence/json";
import { addingDaysToKey, isPlannerDayKey, type PlannerDayKey } from "../planner/plannerDayKey";
import { PetPointsRules } from "../pets/petPointsRules";
import { addingWeeks, recapWeekDays, type RecapWeek } from "./recapWeek";

/*
 * Port of WeeklyRecap and RecapCheer: what one week of study added up to,
 * built from the activity log. It reads only ActivityRecords, so it counts
 * whatever any module logged (the Pomodoro, Study, Party, Anki, Today)
 * without knowing about their stores. A recap is saved once it is built,
 * so past weeks stay browsable even after the log's day files are deleted.
 */

/** The fields a recap is made of, before clamping. */
export interface WeeklyRecapFields {
  readonly week: RecapWeek;
  readonly minutesByDay: readonly number[];
  readonly sessions: number;
  readonly cardsReviewed: number;
  readonly tasksDone: number;
  readonly points: number;
  readonly longestStreak: number;
}

/** The one warm line on a recap card. Always kind: a light or empty week gets encouragement, never a comparison that could sting. */
export type RecapCheer = "bestYet" | "moreThanLastWeek" | "firstWeek" | "steady" | "light" | "rest";

export const RECAP_CHEERS: readonly RecapCheer[] = ["bestYet", "moreThanLastWeek", "firstWeek", "steady", "light", "rest"];

/** Below an hour of focus a week reads as light, whatever came before. */
export const LIGHT_WEEK_MINUTES = 60;

/** The cheer's sentence, in the installed language. */
export function recapCheerLine(cheer: RecapCheer): string {
  switch (cheer) {
    case "bestYet":
      return tr("Your best week yet!");
    case "moreThanLastWeek":
      return tr("More focus than last week. Nice climb!");
    case "firstWeek":
      return tr("A lovely first week together.");
    case "steady":
      return tr("Another steady week. Keep it cozy.");
    case "light":
      return tr("A lighter week. Every minute counts.");
    case "rest":
      return tr("A restful week. A fresh start awaits.");
  }
}

/** Swift's `Int(String)`: an optional sign and decimal digits, nothing else. */
function parseInteger(text: string | undefined): number | undefined {
  return text !== undefined && /^[+-]?\d+$/.test(text) ? Number(text) : undefined;
}

/** Swift's `.rounded()`: half away from zero. */
function roundHalfAway(value: number): number {
  return Math.sign(value) * Math.round(Math.abs(value));
}

export class WeeklyRecap {
  readonly week: RecapWeek;
  /** Minutes focused each day, Monday first (always seven entries). */
  readonly minutesByDay: readonly number[];
  /** Focus stretches that ran to their end (`countsAsFinishedSession`). */
  readonly sessions: number;
  readonly cardsReviewed: number;
  /** Distinct tasks checked off, so one checked twice counts once. */
  readonly tasksDone: number;
  /** Study points the week's focus earned, by PetPointsRules. */
  readonly points: number;
  /** The longest run of consecutive active days in the week (see `isActive`). */
  readonly longestStreak: number;

  constructor(fields: WeeklyRecapFields) {
    this.week = fields.week;
    const days = fields.minutesByDay.slice(0, 7).map((value) => Math.max(value, 0));
    this.minutesByDay = [...days, ...Array<number>(7 - days.length).fill(0)];
    this.sessions = Math.max(fields.sessions, 0);
    this.cardsReviewed = Math.max(fields.cardsReviewed, 0);
    this.tasksDone = Math.max(fields.tasksDone, 0);
    this.points = Math.max(fields.points, 0);
    this.longestStreak = Math.min(Math.max(fields.longestStreak, 0), 7);
  }

  /**
   * Builds `week`'s recap from `records`. Records outside the week are
   * ignored, as are duplicates (same id), so a caller can pass a few days'
   * slack around it. Each record counts toward the local day it ended on in
   * `timeZone`, like the log's day files.
   */
  static fromRecords(week: RecapWeek, records: Iterable<ActivityRecord>, timeZone: string): WeeklyRecap {
    const index = new Map(recapWeekDays(week).map((day, offset) => [day, offset]));
    const minutes = Array<number>(7).fill(0);
    const cards = Array<number>(7).fill(0);
    const tasks = Array<number>(7).fill(0);
    let sessions = 0;
    let points = 0;
    let cardsReviewed = 0;
    const taskSubjects = new Set<string>();
    let anonymousTasks = 0;
    const seen = new Set<string>();
    for (const record of records) {
      const day = index.get(activityDay(record, timeZone));
      if (day === undefined || seen.has(record.id)) continue;
      seen.add(record.id);
      const quantity = record.quantity;
      switch (record.kind) {
        case ACTIVITY_KINDS.focusCompleted:
          if (record.unit !== ACTIVITY_UNITS.minutes || quantity === undefined || !Number.isFinite(quantity) || !(quantity > 0)) {
            continue;
          }
          minutes[day] = (minutes[day] ?? 0) + quantity;
          if (countsAsFinishedSession(record)) sessions += 1;
          points += WeeklyRecap.pointsFor(record, Math.trunc(quantity));
          break;
        case ACTIVITY_KINDS.cardsReviewed:
          if (quantity === undefined || !Number.isFinite(quantity) || !(quantity > 0)) continue;
          cards[day] = (cards[day] ?? 0) + Math.trunc(quantity);
          cardsReviewed += Math.trunc(quantity);
          break;
        case ACTIVITY_KINDS.taskCompleted:
          tasks[day] = (tasks[day] ?? 0) + 1;
          if (record.subject !== undefined) taskSubjects.add(record.subject);
          else anonymousTasks += 1;
          break;
        default:
          continue;
      }
    }
    const wholeMinutes = minutes.map(roundHalfAway);
    let streak = 0;
    let run = 0;
    for (let day = 0; day < 7; day++) {
      run = WeeklyRecap.isActive(wholeMinutes[day] ?? 0, cards[day] ?? 0, tasks[day] ?? 0) ? run + 1 : 0;
      streak = Math.max(streak, run);
    }
    return new WeeklyRecap({
      week,
      minutesByDay: wholeMinutes,
      sessions,
      cardsReviewed,
      tasksDone: taskSubjects.size + anonymousTasks,
      points,
      longestStreak: streak,
    });
  }

  /**
   * Points for one focus record, as the pet's ledger credited it: a Party
   * stay by `sharedPoints` with the friends who studied along, anything
   * else by `points`.
   */
  private static pointsFor(record: ActivityRecord, minutes: number): number {
    if (record.source === MODULE_IDS.party) {
      const friends = parseInteger(record.metadata[PARTY_FRIENDS_METADATA_KEY]) ?? 0;
      const outcome = activityOutcome(record);
      return PetPointsRules.sharedPoints(minutes, friends, outcome === "completed" || outcome === undefined);
    }
    return PetPointsRules.points(minutes, countsAsFinishedSession(record));
  }

  /**
   * A day counts toward the streak when it had a real focus stretch
   * (`PetPointsRules.minimumMinutes`), any cards reviewed or any task done,
   * so a day of flashcards or errands keeps it going too.
   */
  static isActive(minutes: number, cards: number, tasks: number): boolean {
    return minutes >= PetPointsRules.minimumMinutes || cards > 0 || tasks > 0;
  }

  get focusMinutes(): number {
    return this.minutesByDay.reduce((sum, value) => sum + value, 0);
  }

  /** The day with the most focus, Monday first on a tie; undefined when no day had any. */
  bestDay(): { readonly day: PlannerDayKey; readonly minutes: number } | undefined {
    const best = Math.max(...this.minutesByDay);
    if (!(best > 0)) return undefined;
    return { day: addingDaysToKey(this.week, this.minutesByDay.indexOf(best)), minutes: best };
  }

  /** Nothing at all was logged this week. */
  get isEmpty(): boolean {
    return this.focusMinutes === 0 && this.cardsReviewed === 0 && this.tasksDone === 0;
  }

  /** The warm line for this week, measured against `earlier` recaps (any order; weeks on or after this one are ignored). */
  cheer(earlier: Iterable<WeeklyRecap>): RecapCheer {
    if (this.isEmpty) return "rest";
    const before = [...earlier].filter((recap) => recap.week < this.week && !recap.isEmpty);
    const previous = before.reduce<WeeklyRecap | undefined>((latest, recap) => (!latest || recap.week > latest.week ? recap : latest), undefined);
    if (this.focusMinutes < LIGHT_WEEK_MINUTES) return "light";
    if (!previous) return "firstWeek";
    if (this.focusMinutes > Math.max(0, ...before.map((recap) => recap.focusMinutes))) return "bestYet";
    if (previous.week === addingWeeks(this.week, -1) && this.focusMinutes > previous.focusMinutes) return "moreThanLastWeek";
    return "steady";
  }

  /** Whether the two recaps hold the same numbers (Swift's synthesized `==`). */
  equals(other: WeeklyRecap): boolean {
    return (
      this.week === other.week &&
      this.minutesByDay.every((value, index) => value === other.minutesByDay[index]) &&
      this.sessions === other.sessions &&
      this.cardsReviewed === other.cardsReviewed &&
      this.tasksDone === other.tasksDone &&
      this.points === other.points &&
      this.longestStreak === other.longestStreak
    );
  }
}

/** The recap in the Mac's Codable shape: the week as its Monday's day key. */
export function encodeWeeklyRecap(recap: WeeklyRecap): JSONObject {
  return {
    week: recap.week,
    minutesByDay: [...recap.minutesByDay],
    sessions: recap.sessions,
    cardsReviewed: recap.cardsReviewed,
    tasksDone: recap.tasksDone,
    points: recap.points,
    longestStreak: recap.longestStreak,
  };
}

/** Reads a recap the Mac encoded; throws on a field it can't read, as its decoder does. */
export function decodeWeeklyRecap(json: unknown): WeeklyRecap {
  if (!isJSONObject(json)) throw new TypeError("A recap must be an object");
  const integer = (key: string): number => {
    const value = json[key];
    if (typeof value !== "number" || !Number.isInteger(value)) throw new TypeError(`Invalid recap ${key}`);
    return value;
  };
  const week = json.week;
  if (typeof week !== "string" || !isPlannerDayKey(week)) throw new TypeError("Invalid recap week");
  const minutes = json.minutesByDay;
  if (!Array.isArray(minutes) || !minutes.every((value) => typeof value === "number" && Number.isInteger(value))) {
    throw new TypeError("Invalid recap minutesByDay");
  }
  return new WeeklyRecap({
    week,
    minutesByDay: minutes as number[],
    sessions: integer("sessions"),
    cardsReviewed: integer("cardsReviewed"),
    tasksDone: integer("tasksDone"),
    points: integer("points"),
    longestStreak: integer("longestStreak"),
  });
}
