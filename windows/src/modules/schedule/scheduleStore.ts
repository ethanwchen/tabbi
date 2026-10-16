/*
 * Port of ScheduleStore: yesterday and the next seven days of calendar for
 * the Schedule tab (today in the Day view, which steps back to yesterday
 * and ahead to tomorrow, and the seven days from today in the Week view),
 * read from the one calendar source Today owns (ICS feeds on Windows) plus
 * the blocks kept in Today, which show as planned blocks.
 *
 * While the panel is visible the day reloads on every minute boundary (so
 * the now line moves); while it is hidden nothing runs. Demo runs show the
 * sample week seen from 11:20 and never touch a feed.
 *
 * Plan offers the rest of today planned on device (ScheduleDraft, no AI):
 * other modules' open tasks and review goals, placed in the free time, or
 * all of tomorrow's working day when the Day view shows tomorrow. The
 * blocks show on the timeline until the user adds or skips them; added
 * ones stay in Today as planned blocks. When the AI the user picked can
 * answer, Refine offers it the day plan for suggestions; that is optional
 * and the local plan stays usable. Plan week spreads the same work over
 * the free time of the next seven days.
 */

import { aiService } from "../../app/aiService";
import type { ModuleContext } from "../../app/context";
import { Store } from "../../app/store";
import { assistantName } from "../../core/ai/aiProviderID";
import { setupProvider } from "../../core/ai/aiProviderFactory";
import type { CalendarSource } from "../../core/calendar/calendarSource";
import { addingDays, startOfDay } from "../../core/calendar/zonedCalendar";
import { currentLanguage } from "../../core/localization/tr";
import type { PlanBlock } from "../../core/planner/dayPlan";
import type { MeetingLink } from "../../core/planner/meetingLink";
import { viewedDayOffset, type PlannerViewedDay } from "../../core/planner/plannerViewedDay";
import { todayPlanSettings, type TodayPlanSettings } from "../../core/planner/todayPlanSettings";
import type { UpNextSituation } from "../../core/planner/upNextEmptyState";
import type { UpcomingEvent } from "../../core/planner/upcomingEvent";
import type { ProgressItem } from "../../core/providers/progressItem";
import type { ProvidedTask } from "../../core/providers/providedTask";
import { planAnswer, refinedBlocks, refinePrompt } from "../../core/schedule/planRefinement";
import { ScheduleDayLayout, scheduleItem, scheduleItemEvent, scheduleItemFromEvent, ScheduleWeekLayout, type ScheduleItem } from "../../core/schedule/scheduleDay";
import { ScheduleDraft } from "../../core/schedule/scheduleDraft";
import type { ScheduleClock } from "../../core/schedule/schedulePlanner";
import {
  SCHEDULE_SAMPLE_TASKS,
  SCHEDULE_SAMPLE_WEEK_TASKS,
  scheduleSampleNow,
  scheduleSampleWeekItems,
  scheduleSampleYesterdayItems,
} from "../../core/schedule/scheduleSampleData";
import { localSchedulePreferences } from "../../core/schedule/todayLocalPlan";
import type { Instant } from "../../core/time";
import { PLANNED_EVENT_NOTE } from "../../core/planner/dayPlanProposal";
import type { PlannedBlocksStore } from "../planner/plannedBlocks";

/** The two ways to look at the calendar. */
export type ScheduleMode = "day" | "week";

export interface ScheduleState {
  readonly mode: ScheduleMode;
  /** The day the Day view shows. Today unless the user stepped away; it goes back to today when the panel closes. */
  readonly viewing: PlannerViewedDay;
  /** Events and planned blocks from yesterday through the next six days, all-day ones included. */
  readonly items: readonly ScheduleItem[];
  /** The moment the now line marks; advances once a minute while visible. */
  readonly now: Instant;
  /** The item whose details show under the timeline. */
  readonly selectedID: string | undefined;
  /** The plan on offer, from Plan until every block is added or skipped. */
  readonly draft: ScheduleDraft | undefined;
  /** Bumped whenever the draft (edited in place) changes. */
  readonly revision: number;
  /** True when the last Add couldn't be kept; the draft stays. */
  readonly writeFailed: boolean;
  /** Waiting for the AI's suggestions on the day plan; Add and Skip wait too. */
  readonly isRefining: boolean;
  /** The AI's suggestions didn't come back usable; the local plan stays. */
  readonly refineFailed: boolean;
  /** Whether the picked AI could answer the last time Plan ran. */
  readonly aiReady: boolean;
  /** The picked AI's name for the panel's copy ("Refine with Gemini"). */
  readonly assistant: string;
  /** Whether any calendar feed is set up; without one the panel offers Connections. */
  readonly hasSubscriptions: boolean;
}

/** Days the store reads: the Week view's seven, the first one today. */
const DAY_COUNT = 7;
const DEMO_DELAY_MS = 1200;

export class ScheduleStore extends Store<ScheduleState> {
  /** Open tasks and goals other modules share, which Plan schedules. */
  sharedTasks: readonly ProvidedTask[] = [];
  progress: readonly ProgressItem[] = [];
  /** Review sizing, buffer and end of day, from the kit's planner section. */
  planSettings: TodayPlanSettings = todayPlanSettings();

  private isVisible = false;
  private tick: ReturnType<typeof setTimeout> | undefined;
  private generation = 0;
  private refineGeneration = 0;

  constructor(
    private readonly context: ModuleContext,
    private readonly source: CalendarSource,
    private readonly planned: PlannedBlocksStore,
  ) {
    const now = context.now();
    const timeZone = context.timeZone();
    const demo = context.isDemo;
    super({
      mode: "day",
      viewing: "today",
      items: demo ? [...scheduleSampleYesterdayItems(now, timeZone), ...scheduleSampleWeekItems(now, timeZone)] : [],
      now: demo ? scheduleSampleNow(now, timeZone) : now,
      selectedID: undefined,
      draft: undefined,
      revision: 0,
      writeFailed: false,
      isRefining: false,
      refineFailed: false,
      aiReady: demo,
      assistant: "AI",
      hasSubscriptions: demo || source.status().length > 0,
    });
  }

  private get clock(): ScheduleClock {
    return { timeZone: this.context.timeZone(), locale: currentLanguage() };
  }

  /** True when the day plan on offer can get a second look from the AI. The AI's day prompt plans from now, so a plan for tomorrow stays local. */
  get canRefine(): boolean {
    return this.state.aiReady && this.state.viewing === "today" && this.state.draft?.canRefine === true;
  }

  /** The calendar plus any blocks on offer. */
  get shownItems(): ScheduleItem[] {
    return [...this.state.items, ...(this.state.draft?.items ?? [])];
  }

  /** Midnight of the day the Day view shows. */
  get shownDay(): Instant {
    const timeZone = this.context.timeZone();
    return addingDays(startOfDay(this.state.now, timeZone), viewedDayOffset(this.state.viewing), timeZone);
  }

  /** The Day view's layout for the day shown and the current clock. Another day keeps the usual working hours, as the Week view does. */
  get dayLayout(): ScheduleDayLayout {
    const timeZone = this.context.timeZone();
    const day = this.shownDay;
    const reference = this.state.viewing === "today" ? this.state.now : day;
    return new ScheduleDayLayout(day, this.state.now, this.shownItems, timeZone, localSchedulePreferences(this.planSettings, reference, timeZone));
  }

  /** The Week view's layout: today and the six days after it. */
  get weekLayout(): ScheduleWeekLayout {
    const timeZone = this.context.timeZone();
    return new ScheduleWeekLayout(
      this.state.now,
      DAY_COUNT,
      this.shownItems,
      timeZone,
      localSchedulePreferences(this.planSettings, startOfDay(this.state.now, timeZone), timeZone),
    );
  }

  get selectedItem(): ScheduleItem | undefined {
    const id = this.state.selectedID;
    return id === undefined ? undefined : this.shownItems.find((item) => item.id === id);
  }

  /** Why there's no timeline to show (no calendar feed yet), or undefined when there is one. */
  get emptySituation(): UpNextSituation | undefined {
    return this.state.hasSubscriptions ? undefined : "unavailable";
  }

  /** Call when the panel appears and disappears. */
  setVisible(visible: boolean): void {
    if (visible === this.isVisible) return;
    this.isVisible = visible;
    if (visible) {
      void this.reload();
      this.scheduleTick();
    } else {
      this.cancelTick();
      if (!this.context.isDemo) this.setState({ selectedID: undefined });
      this.show("today");
    }
  }

  showMode(mode: ScheduleMode): void {
    this.setState({ selectedID: undefined, mode });
  }

  /** Steps the Day view to yesterday, today or tomorrow. A plan on offer belongs to the day it was made for, so it goes away. */
  show(day: PlannerViewedDay): void {
    if (day === this.state.viewing) return;
    this.discardPlan();
    this.setState({ viewing: day });
  }

  select(id: string | undefined): void {
    /* Offered blocks may change while the AI refines them. */
    if (this.state.isRefining && id !== undefined && this.state.draft?.items.some((item) => item.id === id) === true) return;
    this.setState({ selectedID: this.state.selectedID === id ? undefined : id });
  }

  /** Plans the rest of today (or all of tomorrow's working day) around the calendar and shows the blocks on the timeline. Yesterday is over, so there is nothing to plan there. */
  planDay(): void {
    if (this.state.viewing === "yesterday") return;
    this.startPlanning();
    if (!this.context.isDemo && this.state.viewing === "today") void this.checkAI();
    const demo = this.context.isDemo;
    const draft = ScheduleDraft.plan(
      this.state.viewing === "today" ? this.state.now : this.shownDay,
      this.state.items,
      demo ? SCHEDULE_SAMPLE_TASKS : this.sharedTasks,
      demo ? [] : this.progress,
      this.clock,
      this.planSettings,
    );
    this.setState({ draft, revision: this.state.revision + 1 });
  }

  /** Spreads the same work over the free time of today and the next six days, for the Week view. */
  planWeek(): void {
    this.startPlanning();
    const demo = this.context.isDemo;
    const draft = ScheduleDraft.planWeek(this.state.now, this.state.items, demo ? SCHEDULE_SAMPLE_WEEK_TASKS : this.sharedTasks, demo ? [] : this.progress, this.clock, this.planSettings, DAY_COUNT);
    this.setState({ draft, revision: this.state.revision + 1 });
  }

  /** Keeps one offered block (every one when `id` is undefined) in Today. */
  async add(id?: string): Promise<void> {
    const draft = this.state.draft;
    if (this.state.isRefining || draft === undefined) return;
    try {
      const now = this.context.isDemo ? this.state.now : this.context.now();
      const written = await draft.add(id, now, this.state.items.map(scheduleItemEvent), this.planned.writer());
      if (this.state.draft !== draft) return;
      if (this.context.isDemo) {
        /* Nothing reloads in demo mode, so show the blocks as planned here. */
        const items = [
          ...this.state.items,
          ...written.map((event) => scheduleItem({ id: `demo-added-${event.start}`, title: event.title, start: event.start, end: event.end, kind: "planned", reason: event.notes })),
        ];
        this.setState({ items });
      }
      this.setState({ writeFailed: false });
      this.settle(draft);
      if (!this.context.isDemo) void this.reload();
    } catch (error) {
      this.context.logger.error("could not keep the plan's blocks", error);
      this.setState({ writeFailed: true });
    }
  }

  /** Takes one offered block off the timeline. */
  skip(id: string): void {
    const draft = this.state.draft;
    if (this.state.isRefining || draft === undefined) return;
    draft.skip(id);
    this.settle(draft);
  }

  /** Drops the whole offer; nothing was kept. */
  discardPlan(): void {
    this.cancelRefine();
    this.setState({ selectedID: undefined, writeFailed: false, draft: undefined });
  }

  /** Asks the AI for suggestions on the day plan's blocks still on offer. Its answer is validated like any plan before it replaces them; on failure the local plan stays. */
  refine(): void {
    const draft = this.state.draft;
    if (!this.canRefine || this.state.isRefining || draft === undefined) return;
    this.cancelRefine();
    const generation = this.refineGeneration;
    this.setState({ isRefining: true, selectedID: undefined });
    const blocks = draft.proposal.pending;
    const now = this.context.isDemo ? this.state.now : this.context.now();
    const context = draft.refineContext(now, this.state.items, this.context.timeZone(), this.planSettings);
    const finish = (refined: readonly PlanBlock[] | undefined) => {
      if (generation !== this.refineGeneration || this.state.draft !== draft) return;
      if (refined !== undefined && refined.length > 0) {
        draft.refine(refined);
        this.setState({ isRefining: false, revision: this.state.revision + 1 });
      } else {
        this.setState({ isRefining: false, refineFailed: true });
      }
    };
    if (this.context.isDemo) {
      /* Demo mode never asks an AI: it agrees with the sample plan. */
      setTimeout(() => finish(blocks), DEMO_DELAY_MS);
      return;
    }
    void (async () => {
      const provider = await aiService(this.context).readyProvider();
      if (provider === undefined) return finish(undefined);
      const text = await planAnswer(provider, refinePrompt(context, blocks));
      if (text === undefined) return finish(undefined);
      try {
        finish(refinedBlocks(text, context, blocks));
      } catch {
        finish(undefined);
      }
    })();
  }

  /** Opens a video call in the default browser. */
  join(link: MeetingLink): void {
    void this.context.host.openUrl(link.url).catch((error: unknown) => this.context.logger.error("could not open the meeting link", error));
  }

  /** Snapshot runs only: the Day view on `day`, with a plan on offer when `planning`; without a calendar there is no stepper, so it stays on today. */
  showForSnapshot(day: PlannerViewedDay, planning = false): void {
    this.show(this.emptySituation === undefined ? day : "today");
    this.setState({ mode: "day", selectedID: undefined });
    if (planning && this.emptySituation === undefined) this.planDay();
    else this.discardPlan();
  }

  /** Snapshot runs only: a named preview over the demo week. */
  showPreviewForSnapshot(preview: "week" | "selected" | "plan-selected" | "plan-refining" | "plan-week" | "plan-week-selected" | "no-calendar" | "free-day"): void {
    this.discardPlan();
    switch (preview) {
      case "week":
        this.setState({ mode: "week" });
        return;
      case "selected":
        this.setState({ mode: "day", selectedID: "demo-deck" });
        return;
      case "plan-selected":
        this.planDay();
        this.setState({ selectedID: this.state.draft?.items[0]?.id });
        return;
      case "plan-refining":
        this.planDay();
        this.setState({ isRefining: true });
        return;
      case "plan-week":
        this.setState({ mode: "week" });
        this.planWeek();
        return;
      case "plan-week-selected":
        this.setState({ mode: "week" });
        this.planWeek();
        this.setState({ selectedID: this.state.draft?.items.at(-1)?.id });
        return;
      case "no-calendar":
        this.setState({ mode: "day", items: [], hasSubscriptions: false });
        return;
      case "free-day":
        this.setState({ mode: "day", items: [], hasSubscriptions: true });
        return;
    }
  }

  private startPlanning(): void {
    this.cancelRefine();
    if (!this.context.isDemo) this.setState({ now: this.context.now() });
    this.setState({ selectedID: undefined, writeFailed: false });
  }

  private cancelRefine(): void {
    this.refineGeneration += 1;
    this.setState({ isRefining: false, refineFailed: false });
  }

  /** Learns the picked AI's name and whether it can answer while the plan shows, so Refine only appears when it can work. */
  private async checkAI(): Promise<void> {
    const state = await aiService(this.context).setupState();
    const provider = setupProvider(state);
    this.setState({ aiReady: state.kind === "ready", assistant: provider === undefined ? "AI" : assistantName(provider) });
  }

  private settle(draft: ScheduleDraft): void {
    const selected = this.state.selectedID;
    const keepsSelection = selected === undefined || draft.items.some((item) => item.id === selected) || this.state.items.some((item) => item.id === selected);
    this.setState({
      selectedID: keepsSelection ? selected : undefined,
      draft: draft.isSettled ? undefined : draft,
      revision: this.state.revision + 1,
    });
  }

  /** Reads yesterday through the next six days again now. Demo data never changes. */
  async reload(): Promise<void> {
    if (this.context.isDemo) return;
    const generation = ++this.generation;
    const now = this.context.now();
    const timeZone = this.context.timeZone();
    const today = startOfDay(now, timeZone);
    const from = addingDays(today, -1, timeZone);
    const to = addingDays(today, DAY_COUNT, timeZone);
    const [calendar, kept] = await Promise.all([
      this.source.events(from, to).catch((error: unknown) => {
        this.context.logger.error("could not read the calendar", error);
        return [] as UpcomingEvent[];
      }),
      this.planned.events(from, to),
    ]);
    if (generation !== this.generation) return;
    const items: ScheduleItem[] = [
      ...calendar.map((event) => scheduleItemFromEvent(event)),
      ...kept.map((event) => ({ ...scheduleItemFromEvent(event, PLANNED_EVENT_NOTE), kind: "planned" as const })),
    ];
    const selected = this.state.selectedID;
    const shown = [...items, ...(this.state.draft?.items ?? [])];
    this.setState({
      now,
      items,
      selectedID: selected !== undefined && shown.some((item) => item.id === selected) ? selected : undefined,
      hasSubscriptions: this.source.status().length > 0,
    });
  }

  /** Fires just after the next whole minute, then reschedules itself, so the now line moves in step with the clock. */
  private scheduleTick(): void {
    this.cancelTick();
    if (this.context.isSnapshot || this.context.isDemo) return;
    const now = this.context.now();
    const wait = 60 - (now % 60) + 0.05;
    this.tick = setTimeout(() => {
      this.tick = undefined;
      if (!this.isVisible) return;
      void this.reload();
      this.scheduleTick();
    }, wait * 1000);
  }

  private cancelTick(): void {
    if (this.tick !== undefined) clearTimeout(this.tick);
    this.tick = undefined;
  }
}
