import type { Seconds } from "../time";
import { SPRINT_BREAK_INTERVAL, type StudyMethod } from "../studyMethods/studyMethod";
import { intervalDuration, type DateInterval } from "./dateInterval";
import {
  MAXIMUM_BLOCKS,
  MINIMUM_BLOCK_MINUTES,
  floorSlot,
  nextSlot,
  planBlock,
  type DayPlanContext,
  type PlanBlock,
} from "./dayPlan";
import { normalizedTitle } from "./plannerDay";
import { progressRemaining, type ProgressItem } from "./providedWork";
import { roundHalfAwayFromZero } from "./upcomingEvent";

/** Typical time to answer one Anki card, in seconds. */
export const DEFAULT_SECONDS_PER_CARD: Seconds = 10;
/** Longest review a plan schedules, in minutes; a bigger queue is planned up to this. */
export const MAXIMUM_REVIEW_MINUTES = 120;

/** Port of StudyReviewWork: a review goal Plan my day fits in, such as "Anki reviews" for 30 minutes. */
export interface StudyReviewWork {
  readonly title: string;
  /** Planned length; the study day planner clamps it to a sensible block. */
  readonly minutes: number;
}

/**
 * Port of ProgressItem.reviewWork: review work for what's left of a goal at
 * `secondsPerUnit` each, rounded up to five minutes, at most the longest
 * review. Undefined when the goal is already met.
 */
export function reviewWork(item: ProgressItem, secondsPerUnit: Seconds = DEFAULT_SECONDS_PER_CARD): StudyReviewWork | undefined {
  const remaining = progressRemaining(item);
  if (!(remaining > 0)) return undefined;
  const seconds = Number.isNaN(secondsPerUnit) ? DEFAULT_SECONDS_PER_CARD : Math.max(secondsPerUnit, 1);
  const minutes = Math.min(Math.ceil((remaining * seconds) / 60 / 5) * 5, MAXIMUM_REVIEW_MINUTES);
  return { title: item.title, minutes: Math.trunc(minutes) };
}

/** Port of StudyDayPreferences: how the user likes their study day laid out. */
export interface StudyDayPreferences {
  /** Length of one study block, 15 to 120 minutes. */
  readonly studyMinutes: number;
  /** Rest after a block before the next one starts. */
  readonly breakMinutes: number;
  /** A longer rest replacing every `longBreakEvery`-th break, if any. */
  readonly longBreakMinutes?: number;
  readonly longBreakEvery?: number;
  /** Schedule reviews in the first free time; false puts them last. */
  readonly reviewsFirst: boolean;
  /** Free time kept clear right before and after a calendar event. */
  readonly eventBufferMinutes: number;
  /** Title for study blocks once every open task has one. */
  readonly studyTitle: string;
}

/** Builds preferences with the Swift initializer's defaults and clamps. */
export function studyDayPreferences(input: Partial<StudyDayPreferences> = {}): StudyDayPreferences {
  const preferences: { -readonly [Key in keyof StudyDayPreferences]: StudyDayPreferences[Key] } = {
    studyMinutes: Math.min(Math.max(input.studyMinutes ?? 25, MINIMUM_BLOCK_MINUTES), MAXIMUM_REVIEW_MINUTES),
    breakMinutes: Math.max(input.breakMinutes ?? 5, 0),
    reviewsFirst: input.reviewsFirst ?? true,
    eventBufferMinutes: Math.max(input.eventBufferMinutes ?? 10, 0),
    studyTitle: normalizedTitle(input.studyTitle ?? "Study block") ?? "Study block",
  };
  if (input.longBreakMinutes !== undefined) preferences.longBreakMinutes = Math.max(input.longBreakMinutes, 0);
  if (input.longBreakEvery !== undefined) preferences.longBreakEvery = Math.max(input.longBreakEvery, 2);
  return preferences;
}

/**
 * Block and break lengths from the user's study method, so a planned block
 * matches what the timer runs. Methods without a fixed length get a
 * plannable stand-in: Flowtime 45 min with its matching break, an Anki
 * sprint the sprint's break interval, and a question block its questions
 * plus the review of their explanations.
 */
export function studyDayPreferencesForMethod(
  method: StudyMethod,
  options: { reviewsFirst?: boolean; eventBufferMinutes?: number; studyTitle?: string } = {},
): StudyDayPreferences {
  const minutes = (seconds: Seconds) => roundHalfAwayFromZero(seconds / 60);
  let focus: Seconds;
  switch (method.focus.kind) {
    case "duration":
      focus = method.focus.seconds + (method.review ?? 0);
      break;
    case "openEnded":
      focus = 45 * 60;
      break;
    case "cards":
      focus = SPRINT_BREAK_INTERVAL;
      break;
  }
  return studyDayPreferences({
    studyMinutes: minutes(focus),
    breakMinutes: minutes(method.duration("shortBreak", focus) ?? 5 * 60),
    ...(method.longBreak === undefined
      ? {}
      : { longBreakMinutes: minutes(method.longBreak.duration), longBreakEvery: method.longBreak.every }),
    reviewsFirst: options.reviewsFirst ?? true,
    eventBufferMinutes: options.eventBufferMinutes ?? 10,
    studyTitle: options.studyTitle ?? "Study block",
  });
}

/** Port of StudyDayPlan: the blocks to offer, plus the breaks left between them. */
export interface StudyDayPlan {
  readonly blocks: readonly PlanBlock[];
  readonly breaks: readonly DateInterval[];
}

/**
 * Port of StudyDayPlanner.plan: plans a study day without the AI, review
 * blocks, study blocks of the method's length and breaks, fitted around
 * calendar events. Deterministic, so it is instant and works offline.
 */
export function planStudyDay(
  context: DayPlanContext,
  reviews: readonly StudyReviewWork[],
  preferences: StudyDayPreferences = studyDayPreferences(),
): StudyDayPlan {
  const minute = 60;
  const minimum = MINIMUM_BLOCK_MINUTES * minute;
  let free = bufferedGaps(context, preferences.eventBufferMinutes * minute);
  const placed: { block: PlanBlock; rest: Seconds }[] = [];
  let studyCount = 0;

  const restAfterStudy = (): Seconds => {
    const every = preferences.longBreakEvery;
    const long = preferences.longBreakMinutes;
    if (every !== undefined && long !== undefined && studyCount % every === 0) return long * minute;
    return preferences.breakMinutes * minute;
  };

  /* Takes `interval` plus the rest that follows it out of `free`; the rest runs to the next five-minute mark. */
  const reserve = (taken0: DateInterval, rest: Seconds) => {
    const taken = { start: taken0.start, end: nextSlot(taken0.end + rest) };
    free = free.flatMap((gap) => {
      if (!(taken.start < gap.end && gap.start < taken.end)) return [gap];
      const pieces: DateInterval[] = [];
      if (gap.start < taken.start) pieces.push({ start: gap.start, end: taken.start });
      if (taken.end < gap.end) pieces.push({ start: taken.end, end: gap.end });
      return pieces.filter((piece) => intervalDuration(piece) >= minimum);
    });
  };

  /*
   * Reviews: one block each when a gap fits it whole (the earliest such
   * gap, or the latest when reviews go last); otherwise split over
   * consecutive gaps from that end of the day, no piece shorter than a block.
   */
  const reviewRest = preferences.breakMinutes * minute;
  for (const work of reviews) {
    const title = normalizedTitle(work.title);
    if (title === undefined) continue;
    let remaining = Math.min(Math.max(work.minutes, MINIMUM_BLOCK_MINUTES), MAXIMUM_REVIEW_MINUTES) * minute;
    const fits = (gap: DateInterval) => intervalDuration(gap) >= remaining;
    const whole = preferences.reviewsFirst ? free.find(fits) : free.findLast(fits);
    while (remaining > 0 && placed.length < MAXIMUM_BLOCKS) {
      const gap = whole ?? (preferences.reviewsFirst ? free[0] : free.at(-1));
      if (gap === undefined) break;
      const length = Math.max(Math.min(remaining, intervalDuration(gap)), minimum);
      const span = preferences.reviewsFirst
        ? { start: gap.start, end: gap.start + length }
        : { start: gap.end - length, end: gap.end };
      placed.push({ block: planBlock({ start: span.start, end: span.end, title, kind: "reviews" }), rest: reviewRest });
      /* A late review block still needs its rest before it, not after. */
      if (preferences.reviewsFirst) reserve(span, reviewRest);
      else reserve({ start: span.start - reviewRest, end: span.end }, 0);
      remaining -= length;
      if (whole !== undefined) break;
    }
  }

  /* Study: exact method-length blocks, earliest first, each followed by its break; open tasks name the first ones. */
  const length = preferences.studyMinutes * minute;
  const tasks = [...context.tasks];
  while (placed.length < MAXIMUM_BLOCKS) {
    const gap = free.find((candidate) => intervalDuration(candidate) >= length);
    if (gap === undefined) break;
    const span = { start: gap.start, end: gap.start + length };
    const task = tasks.shift();
    studyCount += 1;
    const rest = restAfterStudy();
    const title = (task === undefined ? undefined : normalizedTitle(task.title)) ?? preferences.studyTitle;
    placed.push({
      block: planBlock({ start: span.start, end: span.end, title, linkedTaskID: task?.id, kind: "study" }),
      rest,
    });
    reserve(span, rest);
  }

  const ordered = [...placed].sort((a, b) => a.block.start - b.block.start);
  const busy = context.events.filter((event) => !event.isAllDay && event.end > event.start);
  const breaks: DateInterval[] = [];
  for (let index = 0; index + 1 < ordered.length; index++) {
    const previous = ordered[index];
    const next = ordered[index + 1];
    if (previous === undefined || next === undefined) continue;
    if (!(previous.rest > 0) || !(next.block.start > previous.block.end)) continue;
    const rest = {
      start: previous.block.end,
      end: Math.min(next.block.start, nextSlot(previous.block.end + previous.rest)),
    };
    const interrupted = busy.some((event) => event.start < next.block.start && event.end > previous.block.end);
    if (!interrupted) breaks.push(rest);
  }
  return { blocks: ordered.map((entry) => entry.block), breaks };
}

/**
 * The context's gaps with `buffer` kept clear after any event that ended
 * within it (including one ending around now) and before the event that
 * closes a gap; the edge at the day's end stays put. Both edges land on the
 * slot grid, so every block starts on a slot mark.
 */
export function bufferedGaps(context: DayPlanContext, buffer: Seconds): DateInterval[] {
  const minimum = MINIMUM_BLOCK_MINUTES * 60;
  const ends = context.events.filter((event) => !event.isAllDay && event.end > event.start).map((event) => event.end);
  const result: DateInterval[] = [];
  for (const gap of context.gaps) {
    const earlier = ends.filter((end) => end <= gap.start);
    const start = earlier.length > 0 ? Math.max(gap.start, nextSlot(Math.max(...earlier) + buffer)) : gap.start;
    const edge = gap.end < context.dayEnd ? gap.end - buffer : gap.end;
    const end = floorSlot(edge);
    if (end - start >= minimum) result.push({ start, end });
  }
  return result;
}
