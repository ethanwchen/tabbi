import type { Instant, Seconds } from "../time";
import { addingDays, settingTime, startOfDay } from "../calendar/zonedCalendar";
import { durationMinutes } from "../formatting/durationFormat";
import { intervalDuration, type DateInterval } from "../planner/dateInterval";
import { DayPlanProposal } from "../planner/dayPlanProposal";
import { MINIMUM_BLOCK_MINUTES, SLOT_MINUTES, floorSlot, nextSlot, planBlock, type PlanBlock, type PlanBlockKind } from "../planner/dayPlan";
import { normalizedTitle, type PlannerItem } from "../planner/plannerDay";
import type { StudyReviewWork } from "../planner/studyDayPlan";
import { studyDayPreferencesForMethod } from "../planner/studyDayPlan";
import { eventStartTime, roundHalfAwayFromZero, type UpcomingEvent } from "../planner/upcomingEvent";
import type { StudyMethod } from "../studyMethods/studyMethod";

/** Port of SchedulePriority: how much a piece of work matters. */
export type SchedulePriority = "low" | "normal" | "high";

const PRIORITY_RANK: Readonly<Record<SchedulePriority, number>> = { low: 0, normal: 1, high: 2 };

/**
 * Port of ScheduleWork: one piece of work the local planner can schedule,
 * a To-do item, another module's shared task, or a review queue.
 */
export interface ScheduleWork {
  /** Stable for the work, so blocks and overflow rows point back to it. */
  readonly id: string;
  readonly title: string;
  /** How long it takes; undefined uses the preferences' default. */
  readonly estimatedMinutes?: number;
  readonly priority: SchedulePriority;
  /** When it must be finished; such work is placed first and never after this. */
  readonly due?: Instant;
  /** The checklist item a block for this work links to, if any. */
  readonly linkedTaskID?: string;
  readonly kind: PlanBlockKind;
}

/** Builds work with the Swift initializer's defaults. */
export function scheduleWork(input: {
  id: string;
  title: string;
  estimatedMinutes?: number | undefined;
  priority?: SchedulePriority;
  due?: Instant | undefined;
  linkedTaskID?: string | undefined;
  kind?: PlanBlockKind;
}): ScheduleWork {
  const work: { -readonly [Key in keyof ScheduleWork]: ScheduleWork[Key] } = {
    id: input.id,
    title: input.title,
    priority: input.priority ?? "normal",
    kind: input.kind ?? "focus",
  };
  if (input.estimatedMinutes !== undefined) work.estimatedMinutes = input.estimatedMinutes;
  if (input.due !== undefined) work.due = input.due;
  if (input.linkedTaskID !== undefined) work.linkedTaskID = input.linkedTaskID;
  return work;
}

/** A review queue (say, Anki cards due) as plannable work. */
export function reviewScheduleWork(reviews: StudyReviewWork, id: string): ScheduleWork {
  return scheduleWork({ id, title: reviews.title, estimatedMinutes: reviews.minutes, kind: "reviews" });
}

/** An unfinished checklist item; a To-do item has no estimate of its own. */
export function taskScheduleWork(task: PlannerItem, priority: SchedulePriority = "normal"): ScheduleWork {
  return scheduleWork({ id: task.id, title: task.title, priority, linkedTaskID: task.id });
}

/** Port of SchedulePreferences: the user's planning rhythm, with an everyday default for every value. */
export interface SchedulePreferences {
  /** Working hours as minutes after midnight (9:00 to 18:00 by default). */
  readonly workdayStartMinute: number;
  readonly workdayEndMinute: number;
  /** Length assumed for work without an estimate. */
  readonly defaultTaskMinutes: number;
  /** Longest single block; longer work is split across blocks. */
  readonly maximumBlockMinutes: number;
  /** Rest after each block, and the longer one after every `longBreakEvery`-th block (none when undefined). */
  readonly breakMinutes: number;
  readonly longBreakMinutes: number;
  readonly longBreakEvery?: number;
  /** Most focus time planned in one day, reviews included. */
  readonly maximumFocusMinutes: number;
  /** Free time kept clear before and after every timed event. */
  readonly eventBufferMinutes: number;
  /** Review queues go before other work; false puts them after it. */
  readonly reviewsFirst: boolean;
}

export interface SchedulePreferencesInput {
  workdayStartMinute?: number;
  workdayEndMinute?: number;
  defaultTaskMinutes?: number;
  maximumBlockMinutes?: number;
  breakMinutes?: number;
  longBreakMinutes?: number;
  /** `null` means no long breaks; undefined keeps the default (every 4th block). */
  longBreakEvery?: number | null;
  maximumFocusMinutes?: number;
  eventBufferMinutes?: number;
  reviewsFirst?: boolean;
}

const clamp = (value: number, low: number, high: number) => Math.min(Math.max(value, low), high);

/** Builds preferences with the Swift initializer's defaults and clamps. */
export function schedulePreferences(input: SchedulePreferencesInput = {}): SchedulePreferences {
  const minimum = MINIMUM_BLOCK_MINUTES;
  const start = clamp(input.workdayStartMinute ?? 9 * 60, 0, 24 * 60 - minimum);
  const every = input.longBreakEvery === undefined ? 4 : input.longBreakEvery;
  const preferences: { -readonly [Key in keyof SchedulePreferences]: SchedulePreferences[Key] } = {
    workdayStartMinute: start,
    workdayEndMinute: clamp(input.workdayEndMinute ?? 18 * 60, start + minimum, 24 * 60),
    defaultTaskMinutes: clamp(input.defaultTaskMinutes ?? 30, minimum, 8 * 60),
    maximumBlockMinutes: clamp(input.maximumBlockMinutes ?? 90, minimum, 4 * 60),
    breakMinutes: clamp(input.breakMinutes ?? 5, 0, 60),
    longBreakMinutes: clamp(input.longBreakMinutes ?? 15, 0, 120),
    maximumFocusMinutes: clamp(input.maximumFocusMinutes ?? 6 * 60, minimum, 24 * 60),
    eventBufferMinutes: clamp(input.eventBufferMinutes ?? 10, 0, 120),
    reviewsFirst: input.reviewsFirst ?? true,
  };
  if (every !== null) preferences.longBreakEvery = Math.max(every, 2);
  return preferences;
}

/** Block and break lengths from the user's study method, so a planned block matches what the timer runs. */
export function schedulePreferencesForMethod(
  method: StudyMethod,
  input: {
    workdayStartMinute?: number;
    workdayEndMinute?: number;
    maximumFocusMinutes?: number;
    eventBufferMinutes?: number;
    reviewsFirst?: boolean;
  } = {},
): SchedulePreferences {
  const study = studyDayPreferencesForMethod(method);
  return schedulePreferences({
    ...input,
    defaultTaskMinutes: study.studyMinutes,
    maximumBlockMinutes: Math.max(study.studyMinutes, 25),
    breakMinutes: study.breakMinutes,
    longBreakMinutes: study.longBreakMinutes ?? 15,
    longBreakEvery: study.longBreakEvery ?? null,
  });
}

/** Port of ScheduledBlock: one block of a local plan and a few words on why it sits there. */
export interface ScheduledBlock {
  readonly block: PlanBlock;
  /** The `ScheduleWork.id` it works on. */
  readonly workID: string;
  readonly reason: string;
  /** Which piece of split work this is (1-based), and of how many. */
  readonly part: number;
  readonly parts: number;
}

/** Port of UnplacedWork: work the plan could not (fully) fit, and why. */
export interface UnplacedWork {
  readonly work: ScheduleWork;
  /** Minutes still unplanned. */
  readonly minutes: number;
  readonly reason: string;
}

/** Port of SchedulePlan: a day planned on device. */
export interface SchedulePlan {
  /** Midnight of the planned day. */
  readonly day: Instant;
  readonly blocks: readonly ScheduledBlock[];
  /** Rests between consecutive blocks that no event interrupts. */
  readonly breaks: readonly DateInterval[];
  readonly unplaced: readonly UnplacedWork[];
}

/** Planned focus time, in minutes. */
export function planFocusMinutes(plan: SchedulePlan): number {
  return plan.blocks.reduce((sum, entry) => sum + Math.trunc((entry.block.end - entry.block.start) / 60), 0);
}

/** The blocks as Plan my day's proposal, breaks included. */
export function planProposal(plan: SchedulePlan): DayPlanProposal {
  return new DayPlanProposal(
    plan.blocks.map((entry) => entry.block),
    plan.breaks,
  );
}

/** Port of ScheduleWeekPlan: several days planned together, and what still didn't fit by the end. */
export interface ScheduleWeekPlan {
  readonly days: readonly SchedulePlan[];
  readonly unplaced: readonly UnplacedWork[];
}

/** Where the plan runs: the IANA zone for wall-clock times and the locale for clock times in reasons. */
export interface ScheduleClock {
  readonly timeZone: string;
  readonly locale: string;
}

const MINUTE: Seconds = 60;
const SLOT: Seconds = SLOT_MINUTES * 60;

/** Work waiting for time, with how much of it is left. */
interface Pending {
  work: ScheduleWork;
  minutesLeft: number;
  placed: number;
  reason: string | undefined;
}

/**
 * Port of SchedulePlanner.planDay: plans the day containing `now` from
 * `now` on, without the AI or the network. Review queues go first (or
 * last), then time-sensitive work by due time, then by priority and list
 * order; each piece takes the earliest free time left, long work is split
 * into blocks with breaks, and what doesn't fit is listed with the reason.
 */
export function planScheduleDay(
  now: Instant,
  events: readonly UpcomingEvent[],
  work: readonly ScheduleWork[],
  clock: ScheduleClock,
  preferences: SchedulePreferences = schedulePreferences(),
): SchedulePlan {
  const day = startOfDay(now, clock.timeZone);
  const window = { start: day, end: addingDays(day, 1, clock.timeZone) };
  const pending = orderedWork(notScheduled(work, events, window), preferences);
  const plan = planOneDay(day, now, events, pending, preferences, clock);
  return {
    ...plan,
    unplaced: pending.map((entry) => ({
      work: entry.work,
      minutes: entry.minutesLeft,
      reason: entry.reason ?? "No free time left today",
    })),
  };
}

/** Port of SchedulePlanner.planWeek: spreads `work` over `days` days from the one containing `now`. */
export function planScheduleWeek(
  now: Instant,
  days: number,
  events: readonly UpcomingEvent[],
  work: readonly ScheduleWork[],
  clock: ScheduleClock,
  preferences: SchedulePreferences = schedulePreferences(),
): ScheduleWeekPlan {
  const first = startOfDay(now, clock.timeZone);
  const count = Math.max(days, 1);
  const window = { start: first, end: addingDays(first, count, clock.timeZone) };
  const pending = orderedWork(notScheduled(work, events, window), preferences);
  const plans: SchedulePlan[] = [];
  for (let offset = 0; offset < count; offset++) {
    const day = addingDays(first, offset, clock.timeZone);
    /* A reason only explains the final day's leftovers. */
    for (const entry of pending) entry.reason = undefined;
    plans.push(planOneDay(day, Math.max(now, day), events, pending, preferences, clock));
  }
  return {
    days: plans,
    unplaced: pending.map((entry) => ({
      work: entry.work,
      minutes: entry.minutesLeft,
      reason: entry.reason ?? "No free time left this week",
    })),
  };
}

/**
 * The wall-clock time `minutes` after midnight on the day containing `day`
 * (24:00 is the next midnight), so working hours keep their clock times on
 * a daylight saving change.
 */
export function clockTime(minutes: number, day: Instant, timeZone: string): Instant {
  const midnight = startOfDay(day, timeZone);
  if (minutes >= 24 * 60) return addingDays(midnight, 1, timeZone);
  const value = Math.max(minutes, 0);
  return settingTime(midnight, Math.trunc(value / 60), value % 60, 0, timeZone);
}

/**
 * Free intervals of the working day containing `day`, after `now`, with
 * every timed event and its buffer cut out, on the five-minute grid, none
 * shorter than a block.
 */
export function scheduleFreeTime(
  day: Instant,
  now: Instant,
  events: readonly UpcomingEvent[],
  timeZone: string,
  preferences: SchedulePreferences = schedulePreferences(),
): DateInterval[] {
  const start = Math.max(floorSlot(clockTime(preferences.workdayStartMinute, day, timeZone)), nextSlot(now));
  const end = floorSlot(clockTime(preferences.workdayEndMinute, day, timeZone));
  if (!(end > start)) return [];
  const buffer = preferences.eventBufferMinutes * MINUTE;
  const busy = events
    .filter((event) => !event.isAllDay && event.end > event.start)
    .map((event) => ({ start: event.start - buffer, end: event.end + buffer }));
  return subtractIntervals(busy, [{ start, end }]);
}

/* `work` without what a timed event in `window` already covers, matched by title (case and spacing aside). */
function notScheduled(work: readonly ScheduleWork[], events: readonly UpcomingEvent[], window: DateInterval): ScheduleWork[] {
  const key = (title: string) => normalizedTitle(title)?.toLowerCase();
  const booked = new Set(
    events
      .filter((event) => !event.isAllDay && event.end > event.start && event.start < window.end && event.end > window.start)
      .map((event) => key(event.title))
      .filter((title): title is string => title !== undefined),
  );
  return work.filter((entry) => {
    const title = key(entry.title);
    return title === undefined || !booked.has(title);
  });
}

/* Review queues first (or last), then work with a due time, earliest first, then the rest by priority; ties keep list order. */
function orderedWork(work: readonly ScheduleWork[], preferences: SchedulePreferences): Pending[] {
  const group = (entry: ScheduleWork) => {
    if (entry.kind === "reviews") return preferences.reviewsFirst ? 0 : 3;
    return entry.due === undefined ? 2 : 1;
  };
  const indexed = work.map((entry, offset) => ({ entry, offset })).filter(({ entry }) => normalizedTitle(entry.title) !== undefined);
  indexed.sort((lhs, rhs) => {
    const a = lhs.entry;
    const b = rhs.entry;
    if (group(a) !== group(b)) return group(a) - group(b);
    if (a.due !== b.due) return (a.due ?? Number.POSITIVE_INFINITY) - (b.due ?? Number.POSITIVE_INFINITY);
    if (a.priority !== b.priority) return PRIORITY_RANK[b.priority] - PRIORITY_RANK[a.priority];
    return lhs.offset - rhs.offset;
  });
  return indexed.map(({ entry }) => {
    const minutes = entry.estimatedMinutes ?? preferences.defaultTaskMinutes;
    /* Rounded up to the grid, and never shorter than a block. */
    const rounded = Math.trunc(Math.ceil(Math.max(minutes, MINIMUM_BLOCK_MINUTES) / 5)) * 5;
    return {
      work: { ...entry, title: normalizedTitle(entry.title) ?? entry.title },
      minutesLeft: Math.min(rounded, 24 * 60),
      placed: 0,
      reason: undefined,
    };
  });
}

/* Fills one day from `pending`, removing what it places. */
function planOneDay(
  day: Instant,
  now: Instant,
  events: readonly UpcomingEvent[],
  pending: Pending[],
  preferences: SchedulePreferences,
  clock: ScheduleClock,
): SchedulePlan {
  const minimum = MINIMUM_BLOCK_MINUTES * MINUTE;
  let free = scheduleFreeTime(day, now, events, clock.timeZone, preferences);
  const placed: { block: ScheduledBlock; rest: Seconds; entry: Pending }[] = [];
  let focusLeft = preferences.maximumFocusMinutes * MINUTE;

  const restAfter = (blockNumber: number): Seconds => {
    const every = preferences.longBreakEvery;
    if (every !== undefined && blockNumber % every === 0) return preferences.longBreakMinutes * MINUTE;
    return preferences.breakMinutes * MINUTE;
  };

  for (const entry of pending) {
    const work = entry.work;
    const deadline = work.due === undefined ? undefined : floorSlot(work.due);
    while (entry.minutesLeft > 0) {
      const left = entry.minutesLeft * MINUTE;
      if (!(focusLeft >= minimum)) {
        entry.reason = `Over your ${durationMinutes(preferences.maximumFocusMinutes)} focus limit`;
        break;
      }
      const want = Math.min(left, preferences.maximumBlockMinutes * MINUTE, floorDuration(focusLeft));
      const usable: DateInterval[] = [];
      for (const gap of free) {
        if (deadline === undefined) usable.push(gap);
        else if (gap.start < deadline) usable.push({ start: gap.start, end: Math.min(gap.end, deadline) });
      }
      const piece = pieceToPlace(want, left, usable, minimum);
      if (piece === undefined) {
        entry.reason =
          deadline === undefined ? undefined : `No free time before ${eventStartTime(deadline, clock.locale, clock.timeZone)}`;
        break;
      }
      const block = planBlock({
        start: piece.start,
        end: piece.end,
        title: work.title,
        linkedTaskID: work.linkedTaskID,
        kind: work.kind,
      });
      const rest = restAfter(placed.length + 1);
      placed.push({
        block: { block, workID: work.id, reason: scheduleReason(work, preferences, clock), part: 1, parts: 1 },
        rest,
        entry,
      });
      free = subtractIntervals([{ start: piece.start, end: nextSlot(piece.end + rest) }], free);
      entry.minutesLeft -= roundHalfAwayFromZero(intervalDuration(piece) / MINUTE);
      entry.placed += 1;
      focusLeft -= intervalDuration(piece);
    }
  }

  /* Number the pieces of split work in time order. */
  const ordered = [...placed].sort((a, b) => a.block.block.start - b.block.block.start);
  const seen = new Map<Pending, number>();
  for (let position = 0; position < ordered.length; position++) {
    const current = ordered[position];
    if (current === undefined) continue;
    const parts = current.entry.placed;
    if (parts <= 1) continue;
    const part = (seen.get(current.entry) ?? 0) + 1;
    seen.set(current.entry, part);
    ordered[position] = { ...current, block: { ...current.block, part, parts } };
  }
  const remaining = pending.filter((entry) => entry.minutesLeft > 0);
  pending.splice(0, pending.length, ...remaining);
  for (const entry of pending) entry.placed = 0;

  const busy = events.filter((event) => !event.isAllDay && event.end > event.start);
  const breaks: DateInterval[] = [];
  for (let index = 0; index + 1 < ordered.length; index++) {
    const first = ordered[index];
    const second = ordered[index + 1];
    if (first === undefined || second === undefined) continue;
    const previous = first.block.block;
    const next = second.block.block;
    if (!(first.rest > 0) || !(next.start > previous.end)) continue;
    const rest = { start: previous.end, end: Math.min(next.start, nextSlot(previous.end + first.rest)) };
    const interrupted = busy.some((event) => event.start < next.start && event.end > previous.end);
    if (!interrupted) breaks.push(rest);
  }
  return {
    day: startOfDay(day, clock.timeZone),
    blocks: ordered.map((entry) => entry.block),
    breaks,
    unplaced: [],
  };
}

/**
 * Where the next piece of work goes: the earliest gap that holds `want`
 * whole, otherwise as much as the earliest gap holds, as long as neither
 * that piece nor what remains after it is shorter than `minimum`.
 */
export function pieceToPlace(want0: Seconds, left: Seconds, usable: readonly DateInterval[], minimum: Seconds): DateInterval | undefined {
  if (!(want0 >= minimum)) return undefined;
  let want = want0;
  if (left - want > 0 && left - want < minimum && left - minimum >= minimum) want = left - minimum;
  const whole = usable.find((gap) => intervalDuration(gap) >= want);
  if (whole !== undefined) return { start: whole.start, end: whole.start + want };
  for (const gap of usable) {
    let length = floorDuration(intervalDuration(gap));
    if (left - length > 0 && left - length < minimum) length = left - minimum;
    if (length >= minimum) return { start: gap.start, end: gap.start + length };
  }
  return undefined;
}

/** A few words on why a block sits where it does. */
export function scheduleReason(work: ScheduleWork, preferences: SchedulePreferences, clock: ScheduleClock): string {
  if (work.kind === "reviews") return preferences.reviewsFirst ? "Reviews first, while you are fresh" : "Reviews after the main work";
  if (work.due !== undefined) return `Due by ${eventStartTime(work.due, clock.locale, clock.timeZone)}`;
  switch (work.priority) {
    case "high":
      return "High priority";
    case "normal":
      return "Next on your list";
    case "low":
      return "Low priority, after the rest";
  }
}

/** `intervals` with every interval in `busy` cut out (edges on the grid), dropping pieces shorter than a block. */
export function subtractIntervals(busy: readonly DateInterval[], intervals: readonly DateInterval[]): DateInterval[] {
  const minimum = MINIMUM_BLOCK_MINUTES * MINUTE;
  let free = [...intervals];
  for (const taken of busy) {
    free = free.flatMap((gap) => {
      if (!(taken.start < gap.end && gap.start < taken.end)) return [gap];
      const pieces: DateInterval[] = [];
      if (gap.start < taken.start) pieces.push({ start: gap.start, end: floorSlot(taken.start) });
      if (taken.end < gap.end) pieces.push({ start: nextSlot(taken.end), end: gap.end });
      return pieces.filter((piece) => piece.end > piece.start);
    });
  }
  return free.filter((gap) => intervalDuration(gap) >= minimum).sort((a, b) => a.start - b.start);
}

function floorDuration(duration: Seconds): Seconds {
  return Math.floor(duration / SLOT) * SLOT;
}
