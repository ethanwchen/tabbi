import { tr } from "../localization/tr";
import { dayKey, type DayCalendar, type DayKey } from "../streaks/dayCalendar";
import type { Instant } from "../time";
import { progressLabel, trackDisplayName, type ProgressTrack } from "./progressTrack";
import type { ProgressTally } from "./progressTally";

/*
 * Port of MonthlyQuests.swift: three small goals each calendar month,
 * optional and gentle, picked by a fixed hash of the month (FNV-1a) so the
 * Mac and Windows pick the same ones.
 */

/** A local calendar month, `yyyy-MM`, the prefix of its days' keys. Port of MonthKey. */
export type MonthKey = string;

export function monthKeyFromRaw(raw: string): MonthKey | undefined {
  const match = /^(\d{4})-(\d{2})$/.exec(raw);
  if (!match) return undefined;
  const year = Number(match[1]);
  const month = Number(match[2]);
  return year > 0 && month >= 1 && month <= 12 ? raw : undefined;
}

export function monthOfDay(day: DayKey): MonthKey {
  return day.slice(0, 7);
}

export function monthAt(instant: Instant, calendar: DayCalendar): MonthKey {
  return monthOfDay(dayKey(instant, calendar));
}

export function monthFirstDay(month: MonthKey): DayKey {
  return `${month}-01`;
}

export function monthContains(month: MonthKey, day: DayKey): boolean {
  return day.startsWith(month);
}

export function nextMonth(month: MonthKey): MonthKey {
  const [year, value] = month.split("-").map(Number);
  const y = (year ?? 1970) + ((value ?? 1) === 12 ? 1 : 0);
  const m = ((value ?? 1) % 12) + 1;
  return `${String(y).padStart(4, "0")}-${String(m).padStart(2, "0")}`;
}

/** One of a month's quests: a track and how much of it to do that month (minutes for focus). */
export interface MonthlyQuest {
  readonly track: ProgressTrack;
  readonly target: number;
}

export function questTitle(quest: MonthlyQuest): string {
  const target = quest.target;
  switch (quest.track) {
    case "focusHours":
      return tr("Focus for %lld hours", Math.trunc(target / 60));
    case "studyDays":
      return tr("Study on %lld days", target);
    case "sessions":
      return tr("Finish %lld focus sessions", target);
    case "cards":
      return tr("Review %lld flashcards", target);
    case "tasks":
      return tr("Check off %lld tasks", target);
    case "breakMoves":
      return tr("Do %lld break moves with your pet", target);
    case "party":
      return tr("Finish %lld Party sessions with friends", target);
    case "water":
      return tr("Log %lld glasses of water", target);
    default:
      return trackDisplayName(quest.track);
  }
}

/** A quest with what this month has done toward it. Port of MonthlyQuestProgress. */
export interface MonthlyQuestProgress {
  readonly quest: MonthlyQuest;
  readonly value: number;
}

export function questIsDone(progress: MonthlyQuestProgress): boolean {
  return progress.value >= progress.quest.target;
}

export function questFraction(progress: MonthlyQuestProgress): number {
  return progress.quest.target > 0 ? Math.min(1, progress.value / progress.quest.target) : 0;
}

export function questLabel(progress: MonthlyQuestProgress): string {
  return progressLabel(progress.quest.track, progress.value, progress.quest.target);
}

export const MonthlyQuests = {
  /** Each quest track and how much of it a month asks for. */
  targets: {
    focusHours: 10 * 60,
    studyDays: 10,
    sessions: 20,
    cards: 600,
    tasks: 20,
    breakMoves: 8,
    party: 2,
    water: 30,
  } as Readonly<Partial<Record<ProgressTrack, number>>>,
  /** Tracks every month can offer; one of them is always among the three. */
  core: ["focusHours", "studyDays", "sessions"] as readonly ProgressTrack[],
  /** Tracks offered once the user has done them before the month. */
  extras: ["cards", "tasks", "breakMoves", "party", "water"] as readonly ProgressTrack[],
  count: 3,

  /** 32-bit FNV-1a over the UTF-8 bytes. */
  hash(text: string): number {
    let value = 0x811c9dc5;
    for (const byte of new TextEncoder().encode(text)) {
      value ^= byte;
      value = Math.imul(value, 0x01000193) >>> 0;
    }
    return value >>> 0;
  },

  /** `month`'s quests: the core track that hashes lowest first, then the two lowest of the rest of the pool. */
  quests(month: MonthKey, tally: ProgressTally): MonthlyQuest[] {
    const start = monthFirstDay(month);
    const available = MonthlyQuests.extras.filter((track) => {
      const first = tally.firstDay(track);
      return first !== undefined && first < start;
    });
    const order = (track: ProgressTrack) => MonthlyQuests.hash(`${month}|${track}`);
    const ranked = [...MonthlyQuests.core, ...available].sort(
      (a, b) => order(a) - order(b) || (a < b ? -1 : a > b ? 1 : 0),
    );
    const first = ranked.find((track) => MonthlyQuests.core.includes(track));
    if (first === undefined) return [];
    const picked = [first, ...ranked.filter((track) => track !== first).slice(0, MonthlyQuests.count - 1)];
    return picked.map((track) => ({ track, target: MonthlyQuests.targets[track] ?? 0 }));
  },

  progress(month: MonthKey, tally: ProgressTally): MonthlyQuestProgress[] {
    return MonthlyQuests.quests(month, tally).map((quest) => ({
      quest,
      value: tally.total(quest.track, (day) => monthContains(month, day)),
    }));
  },

  isComplete(month: MonthKey, tally: ProgressTally): boolean {
    const progress = MonthlyQuests.progress(month, tally);
    return progress.length > 0 && progress.every(questIsDone);
  },

  /** Every month up to and including `today`'s whose quests the log shows finished, oldest first. */
  completedMonths(tally: ProgressTally, today: Instant, calendar: DayCalendar): MonthKey[] {
    const last = monthAt(today, calendar);
    const months = new Set([...tally.days.keys()].map(monthOfDay).filter((month) => month <= last));
    return [...months].sort().filter((month) => MonthlyQuests.isComplete(month, tally));
  },
};
