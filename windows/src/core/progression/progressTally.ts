import {
  ACTIVITY_KINDS,
  ACTIVITY_METADATA,
  ACTIVITY_UNITS,
  activityDay,
  countsAsFinishedSession,
  type ActivityRecord,
} from "../activity/activityRecord";
import { MODULE_IDS } from "../modules/moduleId";
import { PetPointsRules } from "../pets/petPointsRules";
import { addDays, dayKey, weekStart, type DayCalendar, type DayKey } from "../streaks/dayCalendar";
import type { Instant } from "../time";
import { STEADY_WEEK_DAYS, type ProgressTrack } from "./progressTrack";

/*
 * Port of ProgressTally.swift and GentleStreak: everything the Goals
 * section counts, read from the activity log one record at a time and kept
 * per local day, so lifetime totals and one month's totals come from the
 * same numbers. Each record counts once, by id.
 */

/** The break buddy's kinds (WaterTally on the Mac). */
const BREAK_MOVE_KIND = "break.move";
const WATER_KIND = "water.logged";
/** The Party metadata key for how many friends studied along. */
const FRIENDS_KEY = "friends";

/** A day counts toward a streak once it has this many focused minutes. */
export const MINUTES_FOR_STUDY_DAY = PetPointsRules.minimumMinutes;

/** The study methods the methods badge counts: the named ones, not a custom timer or the plain countdown. */
export const NAMED_METHODS = ["pomodoro", "fiftyTwoSeventeen", "ultradian", "flowtime", "ankiSprint", "questionBlock"] as const;
const NAMED_METHOD_IDS = new Set<string>(NAMED_METHODS);

/** One local day's counts. A record counts toward the day it ended. */
export interface TallyDay {
  focusMinutes: number;
  sessions: number;
  cards: number;
  /** Ids of the tasks checked off, so one checked twice counts once. */
  readonly taskIDs: Set<string>;
  /** Tasks checked off without an id, each counted on its own. */
  unnamedTasks: number;
  breakMoves: number;
  partySessions: number;
  water: number;
  /** Named study methods used that day. */
  readonly methods: Set<string>;
}

function emptyDay(): TallyDay {
  return {
    focusMinutes: 0,
    sessions: 0,
    cards: 0,
    taskIDs: new Set(),
    unnamedTasks: 0,
    breakMoves: 0,
    partySessions: 0,
    water: 0,
    methods: new Set(),
  };
}

export function isStudyDay(day: TallyDay): boolean {
  return day.focusMinutes >= MINUTES_FOR_STUDY_DAY;
}

function countsToward(day: TallyDay, track: ProgressTrack): boolean {
  switch (track) {
    case "focusHours":
    case "gentleStreak":
    case "steadyWeeks":
    case "monthlyQuests":
      return day.focusMinutes > 0;
    case "studyDays":
      return isStudyDay(day);
    case "sessions":
      return day.sessions > 0;
    case "cards":
      return day.cards > 0;
    case "tasks":
      return day.taskIDs.size > 0 || day.unnamedTasks > 0;
    case "breakMoves":
      return day.breakMoves > 0;
    case "party":
      return day.partySessions > 0;
    case "methods":
      return day.methods.size > 0;
    case "water":
      return day.water > 0;
  }
}

export class ProgressTally {
  readonly days = new Map<DayKey, TallyDay>();
  private readonly seen = new Set<string>();

  constructor(records: Iterable<ActivityRecord> = [], calendar?: DayCalendar) {
    if (calendar) for (const record of records) this.add(record, calendar);
  }

  /** Counts `record` once; records of other kinds are ignored. */
  add(record: ActivityRecord, calendar: DayCalendar): void {
    if (this.seen.has(record.id)) return;
    const day = activityDay(record, calendar.timeZone);
    const counts = this.days.get(day) ?? emptyDay();
    const quantity = record.quantity;
    switch (record.kind) {
      case ACTIVITY_KINDS.focusCompleted: {
        if (record.unit !== ACTIVITY_UNITS.minutes || quantity === undefined || !Number.isFinite(quantity) || !(quantity > 0)) {
          return;
        }
        counts.focusMinutes += quantity;
        if (countsAsFinishedSession(record)) counts.sessions += 1;
        const method = record.metadata[ACTIVITY_METADATA.method];
        if (method !== undefined && NAMED_METHOD_IDS.has(method)) counts.methods.add(method);
        const friends = Number.parseInt(record.metadata[FRIENDS_KEY] ?? "", 10);
        if (record.source === MODULE_IDS.party && record.metadata[ACTIVITY_METADATA.outcome] === "completed" &&
          /^[+-]?\d+$/.test(record.metadata[FRIENDS_KEY] ?? "") && friends > 0) {
          counts.partySessions += 1;
        }
        break;
      }
      case ACTIVITY_KINDS.cardsReviewed:
        if (quantity === undefined || !Number.isFinite(quantity) || !(quantity > 0)) return;
        counts.cards += quantity;
        break;
      case ACTIVITY_KINDS.taskCompleted:
        if (record.subject !== undefined) counts.taskIDs.add(record.subject);
        else counts.unnamedTasks += 1;
        break;
      case BREAK_MOVE_KIND:
        counts.breakMoves += 1;
        break;
      case WATER_KIND: {
        const glasses = quantity ?? 1;
        if (!Number.isFinite(glasses) || !(glasses > 0)) return;
        counts.water += glasses;
        break;
      }
      default:
        return;
    }
    this.seen.add(record.id);
    this.days.set(day, counts);
  }

  /** The days with enough focus to count, oldest first. */
  get studyDays(): DayKey[] {
    return [...this.days.entries()].filter(([, counts]) => isStudyDay(counts)).map(([day]) => day).sort();
  }

  /**
   * The track's count over the days `include` lets through (every day when
   * absent). The gentle streak, steady weeks and monthly quests span days,
   * so they read 0 here.
   */
  total(track: ProgressTrack, include?: (day: DayKey) => boolean): number {
    const values = [...this.days.entries()].filter(([day]) => include?.(day) ?? true).map(([, counts]) => counts);
    const sum = (pick: (day: TallyDay) => number) => values.reduce((total, day) => total + pick(day), 0);
    switch (track) {
      case "focusHours":
        return Math.trunc(sum((day) => day.focusMinutes));
      case "studyDays":
        return values.filter(isStudyDay).length;
      case "sessions":
        return sum((day) => day.sessions);
      case "cards":
        return Math.trunc(sum((day) => day.cards));
      case "tasks": {
        const named = new Set<string>();
        for (const day of values) for (const id of day.taskIDs) named.add(id);
        return named.size + sum((day) => day.unnamedTasks);
      }
      case "breakMoves":
        return sum((day) => day.breakMoves);
      case "party":
        return sum((day) => day.partySessions);
      case "methods": {
        const methods = new Set<string>();
        for (const day of values) for (const method of day.methods) methods.add(method);
        return methods.size;
      }
      case "water":
        return Math.trunc(sum((day) => day.water));
      case "gentleStreak":
      case "steadyWeeks":
      case "monthlyQuests":
        return 0;
    }
  }

  /** Monday-to-Sunday weeks (the weekly recap's) with at least STEADY_WEEK_DAYS study days. */
  steadyWeeks(): number {
    const counts = new Map<DayKey, number>();
    for (const day of this.studyDays) {
      const week = weekStart(day, { timeZone: "UTC", firstWeekday: 2 });
      counts.set(week, (counts.get(week) ?? 0) + 1);
    }
    return [...counts.values()].filter((count) => count >= STEADY_WEEK_DAYS).length;
  }

  /** The first day the user did something the track counts, or undefined when they never have. */
  firstDay(track: ProgressTrack): DayKey | undefined {
    let first: DayKey | undefined;
    for (const [day, counts] of this.days) {
      if (countsToward(counts, track) && (first === undefined || day < first)) first = day;
    }
    return first;
  }
}

/**
 * The longest run of study days, with the Streak section's freezes: a
 * missed day while a run goes on uses that week's free freeze, then the
 * oldest extra freeze bought before it, and otherwise ends the run. Today
 * counts once studied. Port of GentleStreak.longest.
 */
export function longestGentleStreak(
  studyDays: Iterable<DayKey>,
  freezePurchases: Iterable<Instant>,
  today: Instant,
  calendar: DayCalendar,
): number {
  const todayKey = dayKey(today, calendar);
  const studied = new Set([...studyDays].filter((day) => day <= todayKey));
  const sorted = [...studied].sort();
  let day = sorted[0];
  if (day === undefined) return 0;
  const purchases = [...freezePurchases].map((instant) => dayKey(instant, calendar)).sort();
  let next = 0;
  let bought = 0;
  let run = 0;
  let longest = 0;
  const freeUsedWeeks = new Set<DayKey>();
  while (day < todayKey) {
    while (next < purchases.length && (purchases[next] ?? "") < day) {
      next += 1;
      bought += 1;
    }
    if (studied.has(day)) {
      run += 1;
      longest = Math.max(longest, run);
    } else if (run > 0) {
      const week = weekStart(day, calendar);
      if (!freeUsedWeeks.has(week)) {
        freeUsedWeeks.add(week);
      } else if (bought > 0) {
        bought -= 1;
      } else {
        run = 0;
      }
    }
    day = addDays(day, 1);
  }
  if (studied.has(todayKey)) longest = Math.max(longest, run + 1);
  return longest;
}
