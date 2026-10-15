import { PetEconomy } from "../closet/petEconomy";
import type { Instant } from "../time";
import { addDays, dayKey, weekStart, type DayCalendar, type DayKey } from "./dayCalendar";

/*
 * Port of StudyStreak, StreakFreezeRules and StreakDay: a study streak
 * replayed day by day from the study days and the freezes bought, so it is
 * the same on every launch and needs no stored "freeze used" state.
 */

/** The rules for streak freezes, kept in one place. Port of StreakFreezeRules. */
export const StreakFreezeRules = {
  /** Free freezes per calendar week (the calendar's first weekday starts the week). */
  freePerWeek: 1,
  /** An extra freeze costs one typical study day's points (105). */
  price(): number {
    return PetEconomy.pointsPerTypicalDay();
  },
  /** The most extra freezes held at once, so a streak can never be bought outright. */
  maxHeld: 2,
} as const;

/** What happened on one day of the streak's day strip. */
export type StreakDayState = "studied" | "frozen" | "missed" | "today";

/** One day in the streak's day strip. Port of StreakDay. */
export interface StreakDay {
  readonly day: DayKey;
  readonly state: StreakDayState;
}

/**
 * A study streak. Walking from the first study day to yesterday: a study
 * day adds one; a missed day while a streak runs uses the week's free
 * freeze, then the oldest extra freeze bought before that day, or ends the
 * streak. Today is never frozen or missed: it still has time for study.
 */
export class StudyStreak {
  /** Study days in the current run, today included once studied. */
  readonly length: number;
  /** Whether today already has enough study to count. */
  readonly studiedToday: boolean;
  /** Every day a freeze protected, in the current run or earlier ones. */
  readonly frozenDays: ReadonlySet<DayKey>;
  /** Whether this week's free freeze is still unused. */
  readonly freeFreezeAvailable: boolean;
  /** Extra freezes bought and not used yet. */
  readonly extraFreezes: number;
  private readonly studied: ReadonlySet<DayKey>;
  private readonly today: DayKey;

  /**
   * @param studyDays days with enough focused study; days after today are ignored.
   * @param freezePurchases when each extra freeze was bought; a freeze protects only days after the day it was bought.
   */
  constructor(studyDays: Iterable<DayKey>, freezePurchases: Iterable<Instant>, today: Instant, calendar: DayCalendar) {
    const todayKey = dayKey(today, calendar);
    const studied = new Set([...studyDays].filter((day) => day <= todayKey));
    const purchases = [...freezePurchases].map((instant) => dayKey(instant, calendar)).sort();
    let next = 0;
    let bought = 0;
    let run = 0;
    const frozen = new Set<DayKey>();
    const freeUsedWeeks = new Set<DayKey>();
    const sorted = [...studied].sort();
    let day = sorted[0];
    if (day !== undefined) {
      while (day < todayKey) {
        /* Freezes bought before this day are now in reserve. */
        while (next < purchases.length && (purchases[next] ?? "") < day) {
          next += 1;
          bought += 1;
        }
        if (studied.has(day)) {
          run += 1;
        } else if (run > 0) {
          const week = weekStart(day, calendar);
          if (!freeUsedWeeks.has(week)) {
            freeUsedWeeks.add(week);
            frozen.add(day);
          } else if (bought > 0) {
            bought -= 1;
            frozen.add(day);
          } else {
            run = 0;
          }
        }
        day = addDays(day, 1);
      }
    }
    /* Freezes bought up to today are held, ready for the next miss. */
    while (next < purchases.length && (purchases[next] ?? "") <= todayKey) {
      next += 1;
      bought += 1;
    }
    this.studied = studied;
    this.today = todayKey;
    this.studiedToday = studied.has(todayKey);
    this.length = run + (this.studiedToday ? 1 : 0);
    this.frozenDays = frozen;
    this.freeFreezeAvailable = !freeUsedWeeks.has(weekStart(todayKey, calendar));
    this.extraFreezes = bought;
  }

  /** Whether a streak is running (today studied, or kept up to yesterday). */
  get isActive(): boolean {
    return this.length > 0;
  }

  /** Whether the streak runs but today has no study yet, the one moment a gentle reminder is worth sending. */
  get needsStudyToday(): boolean {
    return this.isActive && !this.studiedToday;
  }

  /** Whether another extra freeze can be bought. */
  get canBuyFreeze(): boolean {
    return this.extraFreezes < StreakFreezeRules.maxHeld;
  }

  /** Freezes ready for the next missed day: this week's free one, if unused, plus the extras held. */
  get freezesReady(): number {
    return (this.freeFreezeAvailable ? StreakFreezeRules.freePerWeek : 0) + this.extraFreezes;
  }

  /** The last `count` days, oldest first and ending today, each with what happened on it. */
  recentDays(count: number): StreakDay[] {
    if (!(count > 0)) return [];
    const days: StreakDay[] = [];
    for (let offset = count - 1; offset >= 0; offset--) {
      const day = addDays(this.today, -offset);
      const state: StreakDayState = this.studied.has(day)
        ? "studied"
        : this.frozenDays.has(day)
          ? "frozen"
          : day === this.today
            ? "today"
            : "missed";
      days.push({ day, state });
    }
    return days;
  }
}
