import type { Instant } from "../time";
import { DayPlanContext, type PlanBlock } from "../planner/dayPlan";
import type { DayPlanProposal, PlanCalendarWriting, PlannedCalendarEvent } from "../planner/dayPlanProposal";
import type { ProgressItem } from "../providers/progressItem";
import type { ProvidedTask } from "../providers/providedTask";
import { todayPlanSettings, type TodayPlanSettings } from "../planner/todayPlanSettings";
import type { UpcomingEvent } from "../planner/upcomingEvent";
import type { PlanRefinement } from "./planRefinement";
import { scheduleDuration, scheduleItem, scheduleItemEvent, scheduleItemFromBlock, type ScheduleItem } from "./scheduleDay";
import { planProposal, type ScheduleClock, type SchedulePlan, type ScheduleWeekPlan, type UnplacedWork } from "./schedulePlanner";
import { localPlan, localWeekPlan } from "./todayLocalPlan";

/**
 * Port of ScheduleDraft: a day plan the Schedule offers on its timeline
 * before anything reaches the calendar, the local plan's blocks waiting
 * for Add or Skip, each with its reason, and what didn't fit. Adding and
 * skipping go through `DayPlanProposal`, so blocks are written the way
 * Plan my day writes them.
 */
export class ScheduleDraft {
  readonly plan: SchedulePlan;
  readonly proposal: DayPlanProposal;
  /** True when the plan covers the coming week rather than today. */
  readonly isWeek: boolean;
  /* The day (midnight) each block of a week plan was planned on. */
  private readonly blockDays: ReadonlyMap<string, Instant>;

  private constructor(plan: SchedulePlan, isWeek: boolean, blockDays: ReadonlyMap<string, Instant>) {
    this.plan = plan;
    this.proposal = planProposal(plan);
    this.isWeek = isWeek;
    this.blockDays = blockDays;
  }

  static fromPlan(plan: SchedulePlan): ScheduleDraft {
    return new ScheduleDraft(plan, false, new Map());
  }

  /** A week plan as one draft: every day's blocks and breaks, and what didn't fit anywhere. */
  static fromWeek(week: ScheduleWeekPlan): ScheduleDraft {
    const plan: SchedulePlan = {
      day: week.days[0]?.day ?? Number.NEGATIVE_INFINITY,
      blocks: week.days.flatMap((day) => day.blocks),
      breaks: week.days.flatMap((day) => day.breaks),
      unplaced: week.unplaced,
    };
    const days = new Map<string, Instant>();
    for (const day of week.days) {
      for (const entry of day.blocks) if (!days.has(entry.block.id)) days.set(entry.block.id, day.day);
    }
    return new ScheduleDraft(plan, true, days);
  }

  /**
   * Plans the rest of the day containing `now` around `items` (the calendar
   * as the Schedule shows it) with Today's planning settings: review goals
   * still due, then other modules' open tasks.
   */
  static plan(
    now: Instant,
    items: readonly ScheduleItem[],
    sharedTasks: readonly ProvidedTask[],
    progress: readonly ProgressItem[],
    clock: ScheduleClock,
    settings: TodayPlanSettings = todayPlanSettings(),
  ): ScheduleDraft {
    const events = items.filter((item) => item.kind !== "proposed").map(scheduleItemEvent);
    return ScheduleDraft.fromPlan(localPlan(settings, { now, events, tasks: [], sharedTasks, progress }, clock));
  }

  /** Spreads the same work over today and the `days - 1` days after it. */
  static planWeek(
    now: Instant,
    items: readonly ScheduleItem[],
    sharedTasks: readonly ProvidedTask[],
    progress: readonly ProgressItem[],
    clock: ScheduleClock,
    settings: TodayPlanSettings = todayPlanSettings(),
    days = 7,
  ): ScheduleDraft {
    const events = items.filter((item) => item.kind !== "proposed").map(scheduleItemEvent);
    return ScheduleDraft.fromWeek(localWeekPlan(settings, { now, events, tasks: [], sharedTasks, progress }, clock, days));
  }

  /** Blocks still on offer, as proposed items; blocks the AI suggested in place of local ones say so. */
  get items(): ScheduleItem[] {
    const local = new Map<string, SchedulePlan["blocks"][number]>();
    for (const entry of this.plan.blocks) if (!local.has(entry.block.id)) local.set(entry.block.id, entry);
    return this.proposal.pending.map((block) => {
      const scheduled = local.get(block.id);
      if (scheduled === undefined) {
        return scheduleItem({
          id: block.id,
          title: block.title,
          start: block.start,
          end: block.end,
          kind: "proposed",
          reason: "Suggested by Claude",
        });
      }
      const item = scheduleItemFromBlock(scheduled);
      const title = scheduled.parts > 1 ? `${item.title} (${scheduled.part} of ${scheduled.parts})` : item.title;
      return { ...item, kind: "proposed", title };
    });
  }

  /** What Refine did to this plan, once it has run. */
  get refinement(): PlanRefinement | undefined {
    return this.proposal.refinement;
  }

  /** True while a day plan still has blocks on offer and hasn't been refined; week plans span days the day prompt can't see. */
  get canRefine(): boolean {
    return !this.isWeek && this.proposal.pending.length > 0 && this.proposal.refinement === undefined;
  }

  /** The day the AI refines: the calendar as `items` show it now and the plan's work, placed or not. */
  refineContext(now: Instant, items: readonly ScheduleItem[], timeZone: string, settings: TodayPlanSettings = todayPlanSettings()): DayPlanContext {
    const work: string[] = [];
    for (const title of [...this.plan.blocks.map((entry) => entry.block.title), ...this.plan.unplaced.map((entry) => entry.work.title)]) {
      if (!work.includes(title)) work.push(title);
    }
    return new DayPlanContext({
      now,
      events: items.filter((item) => item.kind !== "proposed").map(scheduleItemEvent),
      tasks: [],
      sharedWork: work,
      timeZone,
      dayEndHour: settings.dayEndHour,
    });
  }

  /** Replaces the blocks still on offer with the AI's (see `DayPlanProposal.refine`). */
  refine(blocks: readonly PlanBlock[]): void {
    this.proposal.refine(blocks);
  }

  /** Work the plan left out, and why; a refined plan may have found room. */
  get unplaced(): readonly UnplacedWork[] {
    if (this.proposal.refinement !== "changed") return this.plan.unplaced;
    return this.plan.unplaced.filter((entry) => !this.proposal.pending.some((block) => block.title === entry.work.title));
  }

  /** True when the plan had nothing to offer in the first place. */
  get isEmpty(): boolean {
    return this.plan.blocks.length === 0;
  }

  /** True once every block has been added or skipped. */
  get isSettled(): boolean {
    return this.proposal.isSettled;
  }

  get addedCount(): number {
    return this.proposal.addedCount;
  }

  /** Minutes of focus still on offer. */
  get pendingMinutes(): number {
    return this.proposal.pending.reduce((sum, block) => sum + Math.max(Math.trunc((block.end - block.start) / 60), 0), 0);
  }

  /** One line on what the draft offers ("3 blocks, 1h 30m. 1 didn't fit"), or why there's nothing to offer. */
  get summary(): string {
    const unplaced = this.unplaced;
    if (this.isEmpty) {
      const first = unplaced[0];
      if (first !== undefined) {
        return unplaced.length === 1
          ? `${first.work.title} didn't fit: ${first.reason}`
          : `${unplaced.length} tasks didn't fit: ${first.reason}`;
      }
      return "Nothing to plan: no open tasks or reviews";
    }
    const count = this.proposal.pending.length;
    let text = `${count} ${count === 1 ? "block" : "blocks"}`;
    const days = new Set(
      this.proposal.pending.map((block) => this.blockDays.get(block.id)).filter((day): day is Instant => day !== undefined),
    ).size;
    if (days > 1) text += ` over ${days} days`;
    text += `, ${scheduleDuration(this.pendingMinutes)}`;
    if (unplaced.length > 0) text += `. ${unplaced.length} didn't fit`;
    return text;
  }

  /** A tooltip listing what didn't fit, one line each. */
  get unplacedDetail(): string | undefined {
    const unplaced = this.unplaced;
    if (unplaced.length === 0) return undefined;
    return unplaced.map((entry) => `${entry.work.title}, ${scheduleDuration(entry.minutes)}: ${entry.reason}`).join("\n");
  }

  /** Takes a block off the offer. */
  skip(id: string): void {
    const block = this.proposal.pending.find((candidate) => candidate.id === id);
    if (block !== undefined) this.proposal.dismiss(block.id);
  }

  /**
   * Writes one block (every block on offer when `id` is undefined),
   * re-checked against `now` and the calendar's `events`. Nothing changes
   * when the writer fails.
   */
  async add(
    id: string | undefined,
    now: Instant,
    events: readonly UpcomingEvent[],
    writer: PlanCalendarWriting,
  ): Promise<PlannedCalendarEvent[]> {
    if (id === undefined) return this.proposal.add(undefined, now, events, writer);
    const ids = new Set(this.proposal.pending.filter((block) => block.id === id).map((block) => block.id));
    if (ids.size === 0) return [];
    return this.proposal.add(ids, now, events, writer);
  }
}
