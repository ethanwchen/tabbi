import type { Instant } from "../time";
import type { PlanRefinement } from "../schedule/planRefinement";
import { intervalDuration, longestInterval, sameInterval, type DateInterval } from "./dateInterval";
import { compareBlocks, floorSlot, MINIMUM_BLOCK_MINUTES, nextSlot, planBlock, type PlanBlock } from "./dayPlan";
import type { StudyDayPlan } from "./studyDayPlan";
import type { UpcomingEvent } from "./upcomingEvent";
import { sampleUUID } from "./uuid";

/** Port of PlannedCalendarEvent: a calendar event Plan my day is about to write. */
export interface PlannedCalendarEvent {
  readonly title: string;
  readonly start: Instant;
  readonly end: Instant;
  readonly notes: string;
}

/**
 * Port of PlanCalendarWriting: writes accepted plan blocks to the user's
 * calendar, every event or none (it throws or rejects without writing any).
 * Until Windows has a calendar it can write to, the plan stays in Today
 * through a writer that keeps the events itself.
 */
export interface PlanCalendarWriting {
  write(events: readonly PlannedCalendarEvent[]): void | Promise<void>;
}

/** Note on every event Plan my day writes, so they're easy to recognize. */
export const PLANNED_EVENT_NOTE = "Planned with Tabbi";

/**
 * Port of DayPlanProposal: the proposal shown in place of the checklist,
 * the blocks still waiting for a decision plus how many were added.
 */
export class DayPlanProposal {
  private pendingValue: PlanBlock[];
  private breaksValue: DateInterval[];
  private addedValue = 0;
  private skippedValue = 0;
  private refinementValue: PlanRefinement | undefined;

  constructor(blocks: readonly PlanBlock[], breaks: readonly DateInterval[] = []) {
    this.pendingValue = [...blocks].sort(compareBlocks);
    this.breaksValue = [...breaks];
  }

  /** A study plan's blocks with its breaks. */
  static fromStudyPlan(plan: StudyDayPlan): DayPlanProposal {
    return new DayPlanProposal(plan.blocks, plan.breaks);
  }

  /** Blocks the user hasn't accepted or dismissed yet, in time order. */
  get pending(): readonly PlanBlock[] {
    return this.pendingValue;
  }

  /** Planned rests between blocks; empty for the AI's plans. */
  get breaks(): readonly DateInterval[] {
    return this.breaksValue;
  }

  /** How many blocks have been written to the calendar. */
  get addedCount(): number {
    return this.addedValue;
  }

  /** Accepted blocks left out because they had run out or a meeting took their time. */
  get skippedCount(): number {
    return this.skippedValue;
  }

  /** What Refine did to this proposal, once it has run. */
  get refinement(): PlanRefinement | undefined {
    return this.refinementValue;
  }

  /** True once every block has been added or dismissed. */
  get isSettled(): boolean {
    return this.pendingValue.length === 0;
  }

  /**
   * The planned rest right after `block`, while the block it leads into is
   * still on offer; dismissing either side drops the break too.
   */
  breakAfter(block: PlanBlock): DateInterval | undefined {
    if (!this.pendingValue.some((pending) => pending.id === block.id)) return undefined;
    const rest = this.breaksValue.find((candidate) => candidate.start === block.end);
    if (rest === undefined || !this.pendingValue.some((pending) => pending.start === rest.end)) return undefined;
    return rest;
  }

  /** Removes a block the user doesn't want. */
  dismiss(id: string): void {
    this.pendingValue = this.pendingValue.filter((block) => block.id !== id);
  }

  /**
   * Replaces the blocks still on offer with the AI's refined `blocks`. The
   * same blocks leave the proposal as it was and record `unchanged`; an
   * empty answer changes nothing. Breaks stay only where they still sit
   * between blocks.
   */
  refine(blocks: readonly PlanBlock[]): void {
    if (blocks.length === 0) return;
    const refined = [...blocks].sort(compareBlocks);
    const sameTimes =
      refined.length === this.pendingValue.length &&
      refined.every((block, index) => {
        const pending = this.pendingValue[index];
        return pending !== undefined && sameInterval(block, pending);
      });
    const sameTitles = refined.every((block, index) => block.title === this.pendingValue[index]?.title);
    if (sameTimes && sameTitles) {
      this.refinementValue = "unchanged";
      return;
    }
    this.pendingValue = refined;
    this.breaksValue = this.breaksValue.filter(
      (rest) => refined.some((block) => block.end === rest.start) && refined.some((block) => block.start === rest.end),
    );
    this.refinementValue = "changed";
  }

  /**
   * Writes the given pending blocks (all of them when `ids` is undefined)
   * and removes them from the proposal. Each block is re-checked against
   * `now` and the calendar as it is then (`events`): trimmed to the free
   * time left or skipped, and skipped ones are counted. Nothing changes
   * when the writer fails. Returns the events written.
   */
  async add(
    ids: ReadonlySet<string> | undefined,
    now: Instant,
    events: readonly UpcomingEvent[],
    writer: PlanCalendarWriting,
  ): Promise<PlannedCalendarEvent[]> {
    const chosen = this.pendingValue.filter((block) => ids === undefined || ids.has(block.id));
    const written = plannedCalendarEvents(chosen, now, events);
    if (written.length > 0) await writer.write(written);
    const chosenIDs = new Set(chosen.map((block) => block.id));
    this.pendingValue = this.pendingValue.filter((block) => !chosenIDs.has(block.id));
    this.addedValue += written.length;
    this.skippedValue += chosen.length - written.length;
    return written;
  }
}

/**
 * Port of DayPlanner.calendarEvents: events for `blocks`, re-checked
 * against `now` and today's `events`. A block that has started begins on
 * the next five-minute mark, a block a timed event now overlaps keeps its
 * longest free piece, and one with less than the minimum left is dropped.
 */
export function plannedCalendarEvents(
  blocks: readonly PlanBlock[],
  now: Instant,
  events: readonly UpcomingEvent[],
): PlannedCalendarEvent[] {
  const minimum = MINIMUM_BLOCK_MINUTES * 60;
  const busy = events.filter((event) => !event.isAllDay && event.end > event.start);
  const result: PlannedCalendarEvent[] = [];
  for (const block of blocks) {
    const start = block.start >= now ? block.start : nextSlot(now);
    if (!(block.end > start)) continue;
    let pieces: DateInterval[] = [{ start, end: block.end }];
    for (const event of busy) {
      pieces = pieces.flatMap((piece) => {
        if (!(event.start < piece.end && piece.start < event.end)) return [piece];
        const rest: DateInterval[] = [];
        if (piece.start < event.start) rest.push({ start: piece.start, end: event.start });
        if (event.end < piece.end) rest.push({ start: event.end, end: piece.end });
        return rest;
      });
    }
    const longest = longestInterval(pieces);
    if (longest === undefined || intervalDuration(longest) < minimum) continue;
    result.push({ title: block.title, start: longest.start, end: longest.end, notes: PLANNED_EVENT_NOTE });
  }
  return result;
}

/**
 * Port of DayPlanner.sampleProposal: a realistic proposal for demo mode,
 * fitted around the sample events and checklist. Never asks the AI.
 */
export function sampleDayPlanProposal(now: Instant): PlanBlock[] {
  const slot = floorSlot(now);
  const block = (from: number, to: number, title: string, task?: number) =>
    planBlock({
      start: slot + from * 60,
      end: slot + to * 60,
      title,
      linkedTaskID: task === undefined ? undefined : sampleUUID(task),
    });
  /* Gaps around the samples: after the review (+45) and after yoga (+125). */
  return [block(50, 90, "Read chapter 4", 3), block(135, 180, "Essay: section two"), block(190, 220, "Spanish practice")];
}
