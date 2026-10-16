/*
 * Port of DayPlanStore: drives Plan my day. Gathers the planned day's
 * events, open tasks and review goals, plans them on device with the
 * schedule planner (or, when the kit's settings say so, asks the AI the
 * user picked, or plans study blocks), and keeps the blocks the user
 * accepts in Today (plannedBlocks.ts), since Windows has no calendar it can
 * write to. The proposal replaces the checklist inline.
 *
 * Demo runs plan around the sample calendar and never ask an AI.
 */

import { aiService } from "../../app/aiService";
import type { ModuleContext } from "../../app/context";
import { Store } from "../../app/store";
import { assistantName, type AIProviderID } from "../../core/ai/aiProviderID";
import { ankiProgressItem, demoAnkiSummary } from "../../core/anki/ankiSummary";
import { setupProvider } from "../../core/ai/aiProviderFactory";
import { currentLanguage } from "../../core/localization/tr";
import { DayPlanContext, dayPlanPrompt, dayPlanProposalBlocks, type PlanBlock } from "../../core/planner/dayPlan";
import { DayPlanProposal, sampleDayPlanProposal } from "../../core/planner/dayPlanProposal";
import type { PlannerItem } from "../../core/planner/plannerDay";
import { plannerDayKeyOf } from "../../core/planner/plannerDayKey";
import { samplePlannerDay } from "../../core/planner/plannerSampleData";
import { viewedDayPlanStart, type PlannerViewedDay } from "../../core/planner/plannerViewedDay";
import { todayStudyPlan, type TodayPlanSettings } from "../../core/planner/todayPlanSettings";
import type { ProgressItem } from "../../core/providers/progressItem";
import type { ProvidedTask } from "../../core/providers/providedTask";
import { planAnswer, refinedBlocks, refinePrompt } from "../../core/schedule/planRefinement";
import { planProposal, type ScheduleClock } from "../../core/schedule/schedulePlanner";
import { localPlan, sampleLocalPlan } from "../../core/schedule/todayLocalPlan";
import type { PlannedBlocksStore } from "./plannedBlocks";
import type { UpNextStore } from "./upNextStore";

/** Why planning stopped, phrased for the panel. */
export type DayPlanFailure =
  /** No AI can answer yet: none is picked (undefined), or the picked one still needs its key. */
  | { readonly kind: "aiNotSetUp"; readonly provider: AIProviderID | undefined }
  /** The AI, named here ("Gemini"), answered with no usable plan. */
  | { readonly kind: "aiFailed"; readonly assistant: string };

export type DayPlanPhase =
  /** The checklist shows; nothing is being planned. */
  | { readonly kind: "idle" }
  /** Working out the plan (only noticeable while waiting for the AI). */
  | { readonly kind: "planning" }
  | { readonly kind: "proposal"; readonly proposal: DayPlanProposal }
  /** Nothing fits in the day's free time (or the day is over). */
  | { readonly kind: "noFreeTime" }
  | { readonly kind: "failed"; readonly failure: DayPlanFailure };

export interface DayPlanState {
  readonly phase: DayPlanPhase;
  /** The day being planned: today, or tomorrow when planning ahead. */
  readonly target: PlannerViewedDay;
  /** True when the last Add couldn't be kept; the proposal stays. */
  readonly writeFailed: boolean;
  /** True when the on-device plan can get a second look from the AI ("Refine"). */
  readonly canRefine: boolean;
  /** Waiting for the AI's refinement; the local plan stays on screen. */
  readonly isRefining: boolean;
  /** The AI's refinement didn't come back usable; the local plan stays. */
  readonly refineFailed: boolean;
  /** The picked AI's name for the panel's copy ("Refine with Gemini"); "AI" until one is picked. */
  readonly assistant: string;
  /** Bumped with every change to the proposal object, which is edited in place. */
  readonly revision: number;
}

/** Longest wait for the AI before showing the Retry message, in seconds. */
const TIMEOUT = 60;
/** How long demo mode pretends to think. */
const DEMO_DELAY_MS = 1200;

function sameFailure(a: DayPlanFailure, b: DayPlanFailure): boolean {
  return a.kind === "aiNotSetUp" ? b.kind === "aiNotSetUp" && a.provider === b.provider : b.kind === "aiFailed" && a.assistant === b.assistant;
}

export function samePhase(a: DayPlanPhase, b: DayPlanPhase): boolean {
  if (a.kind !== b.kind) return false;
  if (a.kind === "proposal" && b.kind === "proposal") return a.proposal === b.proposal;
  if (a.kind === "failed" && b.kind === "failed") return sameFailure(a.failure, b.failure);
  return true;
}

export class DayPlanStore extends Store<DayPlanState> {
  /** The active kit's planning settings; `PlannerStore` keeps them current. */
  settings: TodayPlanSettings;
  private generation = 0;
  private lastTasks: readonly PlannerItem[] = [];
  private lastSharedWork: readonly string[] = [];
  private lastSharedTasks: readonly ProvidedTask[] = [];
  private lastProgress: readonly ProgressItem[] = [];

  constructor(
    private readonly context: ModuleContext,
    private readonly upNext: UpNextStore,
    private readonly planned: PlannedBlocksStore,
    settings: TodayPlanSettings,
  ) {
    super({
      phase: { kind: "idle" },
      target: "today",
      writeFailed: false,
      canRefine: false,
      isRefining: false,
      refineFailed: false,
      assistant: "AI",
      revision: 0,
    });
    this.settings = settings;
  }

  get isActive(): boolean {
    return this.state.phase.kind !== "idle";
  }

  get target(): PlannerViewedDay {
    return this.state.target;
  }

  private get clock(): ScheduleClock {
    return { timeZone: this.context.timeZone(), locale: currentLanguage() };
  }

  /**
   * Starts planning the rest of today (or all of tomorrow, from the start
   * of the working day) around `tasks` (unfinished ones count) and what
   * other modules share: `sharedWork` phrased for the AI, `sharedTasks`
   * with their estimates for the local planner, and `progress` as goals
   * that become review blocks.
   */
  plan(
    day: PlannerViewedDay,
    tasks: readonly PlannerItem[],
    sharedWork: readonly string[] = [],
    sharedTasks: readonly ProvidedTask[] = [],
    progress: readonly ProgressItem[] = [],
  ): void {
    if (viewedDayPlanStart(day, this.context.now(), this.context.timeZone()) === undefined) return;
    this.lastTasks = tasks;
    this.lastSharedWork = sharedWork;
    this.lastSharedTasks = sharedTasks;
    this.lastProgress = progress;
    this.invalidateRun();
    const generation = this.generation;
    this.setState({ target: day, writeFailed: false, phase: { kind: "planning" } });
    void this.checkAI();

    if (this.context.isDemo) {
      this.after(DEMO_DELAY_MS, async () => {
        const proposal = await this.sampleProposal(tasks, sharedTasks, progress);
        this.publish(generation, proposal.isSettled ? { kind: "noFreeTime" } : { kind: "proposal", proposal });
      });
      return;
    }
    void this.run().then((phase) => this.publish(generation, phase));
  }

  /** Demo only: shows the sample proposal for `day` at once, so a snapshot can render a plan without waiting. */
  async showSampleProposal(day: PlannerViewedDay, tasks: readonly PlannerItem[]): Promise<void> {
    if (!this.context.isDemo || viewedDayPlanStart(day, this.context.now(), this.context.timeZone()) === undefined) return;
    this.invalidateRun();
    this.lastTasks = tasks;
    this.setState({ target: day, canRefine: this.settings.planMode === "local" });
    /* Today's preview plans the demo Anki reviews too, as the Mac's does. */
    const progress = day === "today" ? [ankiProgressItem(demoAnkiSummary(this.context.now(), this.context.timeZone()))] : [];
    const proposal = await this.sampleProposal(tasks, [], progress);
    this.setState({ phase: { kind: "proposal", proposal } });
  }

  /** Snapshot runs only: a named phase over demo data. */
  showPhaseForSnapshot(phase: "planning" | "failed" | "refining"): void {
    this.invalidateRun();
    if (phase === "failed") {
      this.setState({ target: "today", phase: { kind: "failed", failure: { kind: "aiFailed", assistant: this.state.assistant } } });
      return;
    }
    if (phase === "planning") {
      this.setState({ target: "today", phase: { kind: "planning" } });
      return;
    }
    this.setState({ canRefine: true, isRefining: true });
  }

  retry(): void {
    this.plan(this.state.target, this.lastTasks, this.lastSharedWork, this.lastSharedTasks, this.lastProgress);
  }

  /** Asks the AI for suggestions on the local plan's blocks still on offer; whatever happens, the local plan stays usable. */
  refine(): void {
    const phase = this.state.phase;
    if (!this.state.canRefine || this.state.isRefining || phase.kind !== "proposal" || phase.proposal.refinement !== undefined) return;
    this.invalidateRun();
    const generation = this.generation;
    this.setState({ isRefining: true, refineFailed: false });
    const blocks = phase.proposal.pending;
    const finish = (refined: readonly PlanBlock[] | undefined) => {
      const current = this.state.phase;
      if (generation !== this.generation || current.kind !== "proposal") return;
      if (refined !== undefined && refined.length > 0) {
        current.proposal.refine(refined);
        this.setState({ isRefining: false, revision: this.state.revision + 1 });
      } else {
        this.setState({ isRefining: false, refineFailed: true });
      }
    };
    if (this.context.isDemo) {
      /* Demo mode never asks an AI: it agrees with the sample plan. */
      this.after(DEMO_DELAY_MS, () => finish(blocks));
      return;
    }
    void this.refinedBlocks(blocks).then(finish);
  }

  /** Discards the proposal (or stops waiting) and shows the checklist again. */
  cancel(): void {
    this.invalidateRun();
    this.setState({ writeFailed: false, phase: { kind: "idle" } });
  }

  dismiss(id: string): void {
    const phase = this.state.phase;
    if (this.state.isRefining || phase.kind !== "proposal") return;
    phase.proposal.dismiss(id);
    this.settle(phase.proposal);
  }

  /** Keeps one block in Today, or every remaining block when `id` is undefined. */
  async add(id?: string): Promise<void> {
    const phase = this.state.phase;
    if (this.state.isRefining || phase.kind !== "proposal") return;
    const proposal = phase.proposal;
    try {
      /* Re-read the calendar: meetings may have arrived since the plan was made. */
      const events = await this.upNext.planEvents(this.state.target);
      if (this.state.phase.kind !== "proposal" || this.state.phase.proposal !== proposal) return;
      await proposal.add(id === undefined ? undefined : new Set([id]), this.context.now(), events, this.planned.writer());
      this.setState({ writeFailed: false });
      this.settle(proposal);
      void this.upNext.reload();
    } catch (error) {
      this.context.logger.error("could not keep the plan's blocks", error);
      this.setState({ writeFailed: true });
    }
  }

  private settle(proposal: DayPlanProposal): void {
    this.setState({ phase: proposal.isSettled ? { kind: "idle" } : { kind: "proposal", proposal }, revision: this.state.revision + 1 });
  }

  private invalidateRun(): void {
    this.generation += 1;
    this.setState({ isRefining: false, refineFailed: false });
  }

  private publish(generation: number, phase: DayPlanPhase): void {
    if (generation !== this.generation) return;
    this.setState({ phase });
  }

  private after(ms: number, run: () => void | Promise<void>): void {
    const generation = this.generation;
    setTimeout(() => {
      if (generation === this.generation) void run();
    }, ms);
  }

  /** Learns the picked AI's name and, for a local plan, whether it can answer, so "Refine" only shows when it can work. */
  private async checkAI(): Promise<void> {
    if (this.context.isDemo) {
      this.setState({ canRefine: this.settings.planMode === "local" });
      return;
    }
    const ai = aiService(this.context);
    const state = await ai.setupState();
    const provider = setupProvider(state);
    this.setState({
      assistant: provider === undefined ? "AI" : assistantName(provider),
      canRefine: this.settings.planMode === "local" && state.kind === "ready",
    });
  }

  /** What planning `target` knows at `now`: its calendar, and where planning starts. */
  private async planContext(tasks: readonly PlannerItem[], sharedWork: readonly string[]): Promise<DayPlanContext | undefined> {
    const timeZone = this.context.timeZone();
    const target = this.state.target;
    const start = viewedDayPlanStart(target, this.context.now(), timeZone);
    if (start === undefined) return undefined;
    return new DayPlanContext({
      now: start,
      events: await this.upNext.planEvents(target),
      tasks,
      sharedWork,
      timeZone,
      dayEndHour: this.settings.dayEndHour,
      isPlanningAhead: target === "tomorrow",
    });
  }

  /** Demo mode's proposal over the demo calendar: the kit's on-device planner, or the AI's canned sample. */
  private async sampleProposal(
    tasks: readonly PlannerItem[],
    sharedTasks: readonly ProvidedTask[],
    progress: readonly ProgressItem[],
  ): Promise<DayPlanProposal> {
    const now = this.context.now();
    const target = this.state.target;
    if (target !== "today") {
      const context = await this.planContext(tasks, []);
      if (context !== undefined) {
        /* Tomorrow's samples sit at fixed hours, so it plans as it is. */
        return this.settings.planMode === "study"
          ? DayPlanProposal.fromStudyPlan(todayStudyPlan(this.settings, context, progress))
          : planProposal(localPlan(this.settings, { now: context.now, events: context.events, tasks, sharedTasks, progress }, this.clock));
      }
    }
    const events = await this.upNext.planEvents("today");
    switch (this.settings.planMode) {
      case "local":
        return planProposal(sampleLocalPlan(this.settings, { now, events, tasks, sharedTasks, progress }, this.clock));
      case "claude":
        return new DayPlanProposal(sampleDayPlanProposal(now));
      case "study": {
        const context = new DayPlanContext({ now, events, tasks, timeZone: this.context.timeZone(), dayEndHour: this.settings.dayEndHour });
        return DayPlanProposal.fromStudyPlan(todayStudyPlan(this.settings, context, progress));
      }
    }
  }

  private async run(): Promise<DayPlanPhase> {
    const context = await this.planContext(this.lastTasks, this.lastSharedWork);
    if (context === undefined || !context.hasFreeTime) return { kind: "noFreeTime" };
    switch (this.settings.planMode) {
      case "local": {
        const proposal = planProposal(
          localPlan(
            this.settings,
            { now: context.now, events: context.events, tasks: this.lastTasks, sharedTasks: this.lastSharedTasks, progress: this.lastProgress },
            this.clock,
          ),
        );
        return proposal.isSettled ? { kind: "noFreeTime" } : { kind: "proposal", proposal };
      }
      case "study": {
        const proposal = DayPlanProposal.fromStudyPlan(todayStudyPlan(this.settings, context, this.lastProgress));
        return proposal.isSettled ? { kind: "noFreeTime" } : { kind: "proposal", proposal };
      }
      case "claude":
        break;
    }
    const ai = aiService(this.context);
    const provider = await ai.readyProvider();
    if (provider === undefined) return { kind: "failed", failure: { kind: "aiNotSetUp", provider: setupProvider(await ai.setupState()) } };
    const text = await planAnswer(provider, dayPlanPrompt(context), TIMEOUT);
    let blocks: PlanBlock[] | undefined;
    try {
      blocks = text === undefined ? undefined : dayPlanProposalBlocks(text, context);
    } catch {
      blocks = undefined;
    }
    if (blocks === undefined) return { kind: "failed", failure: { kind: "aiFailed", assistant: this.state.assistant } };
    return blocks.length === 0 ? { kind: "noFreeTime" } : { kind: "proposal", proposal: new DayPlanProposal(blocks) };
  }

  /** The AI's refinement of `blocks` on the planned day's calendar as it is now, or undefined when it can't answer or its answer isn't usable. */
  private async refinedBlocks(blocks: readonly PlanBlock[]): Promise<PlanBlock[] | undefined> {
    const context = await this.planContext(this.lastTasks, this.lastSharedWork);
    const provider = await aiService(this.context).readyProvider();
    if (context === undefined || provider === undefined) return undefined;
    const text = await planAnswer(provider, refinePrompt(context, blocks), TIMEOUT);
    if (text === undefined) return undefined;
    try {
      return refinedBlocks(text, context, blocks);
    } catch {
      return undefined;
    }
  }

  /** The sample checklist Plan my day's demo previews plan, for the snapshot harness. */
  sampleTasks(): PlannerItem[] {
    const timeZone = this.context.timeZone();
    return [...samplePlannerDay(plannerDayKeyOf(this.context.now(), timeZone), this.settings.sampleDay, timeZone).items];
  }
}
