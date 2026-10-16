/*
 * Port of PlannerStore: today's checklist for the Today panel. Wraps
 * `PlannerRepository`, saves after every edit, and rolls over to a new day
 * (carrying unfinished items) when the calendar day changes.
 *
 * The panel can also step to yesterday (to see what was left and move it
 * to today) or tomorrow (to plan ahead). `day` is always today, which is
 * what other modules, Plan my day and Wrap up see; `shownDay` is the one on
 * screen, and the list's edits go there.
 *
 * Demo runs show the sample day and never touch disk.
 */

import type { ModuleContext } from "../../app/context";
import { Store } from "../../app/store";
import { ACTIVITY_KINDS, makeActivityRecord } from "../../core/activity/activityRecord";
import type { ModuleID } from "../../core/modules/moduleId";
import { PlannerDay, type PlannerItem } from "../../core/planner/plannerDay";
import { plannerDayKeyOf, type PlannerDayKey } from "../../core/planner/plannerDayKey";
import { PlannerRepository } from "../../core/planner/plannerRepository";
import { samplePlannerDay, samplePlannerDayFor } from "../../core/planner/plannerSampleData";
import { viewedDayIsEditable, viewedDayKey, type PlannerViewedDay } from "../../core/planner/plannerViewedDay";
import type { TodayPlanSettings } from "../../core/planner/todayPlanSettings";
import type { ProgressItem } from "../../core/providers/progressItem";
import type { ProvidedTask } from "../../core/providers/providedTask";
import { plannableWork } from "../../core/providers/sharedTodayItem";
import type { StudyDayTally } from "../../core/providers/studyDayTally";
import { currentLanguage } from "../../core/localization/tr";
import { isEphemeral } from "../../core/modules/runMode";
import type { DayPlanStore } from "./dayPlanStore";
import type { DayReviewStore } from "./dayReviewStore";
import type { UpNextStore } from "./upNextStore";

/** Port of PlannerStore.Problem: why a list can't be shown or saved. */
export type PlannerProblem =
  /** The day's file exists but can't be read; editing is disabled so it isn't overwritten. */
  | { readonly kind: "unreadable"; readonly fileName: string }
  /** The last edit is visible but didn't reach disk. */
  | { readonly kind: "saveFailed" };

export interface PlannerState {
  /** Today's list, whichever day the panel shows. */
  readonly day: PlannerDay;
  readonly problem: PlannerProblem | undefined;
  /** The day the checklist shows. Back to today when the day changes. */
  readonly viewing: PlannerViewedDay;
  /** Yesterday's or tomorrow's list while `viewing` names it. */
  readonly otherDay: PlannerDay | undefined;
  readonly otherProblem: PlannerProblem | undefined;
  /** Unfinished work other modules share, phrased for Plan my day. */
  readonly sharedWork: readonly string[];
  /** Other modules' open tasks with their estimates, for the local planner. */
  readonly sharedTasks: readonly ProvidedTask[];
  /** Other modules' goals for today, which the study planner turns into review blocks. */
  readonly sharedProgress: readonly ProgressItem[];
  /** Today's study minutes, sessions and points from the modules that keep them, for Wrap up. */
  readonly sharedStudy: StudyDayTally | undefined;
  /** How Plan my day works for the active kit. */
  readonly planSettings: TodayPlanSettings;
  /** An enabled module that runs its own focus clock; Today then shows that clock instead of the Pomodoro. */
  readonly focusClockOwner: ModuleID | undefined;
  /** Whether the Focus tab is on, so a Pomodoro started there shows in Today even while another module owns the clock. */
  readonly isFocusTabOn: boolean;
  /** The app-wide name from Settings > General, which the fresh-day message greets. */
  readonly displayName: string | undefined;
}

export function isUnreadable(problem: PlannerProblem | undefined): boolean {
  return problem?.kind === "unreadable";
}

export class PlannerStore extends Store<PlannerState> {
  readonly upNext: UpNextStore;
  readonly plan: DayPlanStore;
  readonly review: DayReviewStore;
  private readonly repository: PlannerRepository | undefined;
  /** Demo mode's yesterday and tomorrow, so edits to them last the session. */
  private readonly demoDays = new Map<PlannerDayKey, PlannerDay>();
  /** The first read of today, so edits wait for it instead of landing on an empty day. */
  private loaded: Promise<void>;

  constructor(
    private readonly context: ModuleContext,
    stores: { upNext: UpNextStore; plan: DayPlanStore; review: DayReviewStore },
    planSettings: TodayPlanSettings,
  ) {
    const today = plannerDayKeyOf(context.now(), context.timeZone());
    const ephemeral = isEphemeral(context.runMode);
    super({
      day: ephemeral ? samplePlannerDay(today, planSettings.sampleDay, context.timeZone()) : new PlannerDay(today),
      problem: undefined,
      viewing: "today",
      otherDay: undefined,
      otherProblem: undefined,
      sharedWork: [],
      sharedTasks: [],
      sharedProgress: [],
      sharedStudy: undefined,
      planSettings,
      focusClockOwner: undefined,
      isFocusTabOn: false,
      displayName: undefined,
    });
    this.upNext = stores.upNext;
    this.plan = stores.plan;
    this.review = stores.review;
    this.repository = ephemeral ? undefined : new PlannerRepository(context.storage.root());
    this.loaded = this.load(today);
  }

  /** The list on screen: today's, or the day `viewing` steps to. */
  get shownDay(): PlannerDay {
    const state = this.state;
    if (state.viewing === "today") return state.day;
    return state.otherDay ?? new PlannerDay(viewedDayKey(state.viewing, state.day.date));
  }

  get items(): readonly PlannerItem[] {
    return this.shownDay.items;
  }

  get shownProblem(): PlannerProblem | undefined {
    return this.state.viewing === "today" ? this.state.problem : this.state.otherProblem;
  }

  /** Yesterday's unfinished items that aren't on today's list yet, which the panel offers to move there. */
  get leftovers(): PlannerItem[] {
    return this.state.viewing === "yesterday" ? this.shownDay.unfinished(this.state.day) : [];
  }

  /** Whether Plan my day has anything to schedule. The study planner always does: it fills free time with study blocks. */
  get hasPlannableWork(): boolean {
    const state = this.state;
    return state.planSettings.planMode === "study" || state.day.items.some((item) => !item.isDone) || state.sharedWork.length > 0;
  }

  /** Whether Plan tomorrow has anything to schedule: tomorrow's open tasks, or study blocks for a study kit. */
  get hasPlannableTomorrow(): boolean {
    return this.state.viewing === "tomorrow" && (this.state.planSettings.planMode === "study" || this.shownDay.items.some((item) => !item.isDone));
  }

  /** Whether the shown list can change: not yesterday's, which is a record, and not while its file is unreadable. */
  get canEdit(): boolean {
    return viewedDayIsEditable(this.state.viewing) && !isUnreadable(this.shownProblem);
  }

  /** Resolves once today's list has been read. */
  get ready(): Promise<void> {
    return this.loaded;
  }

  setPlanSettings(settings: TodayPlanSettings): void {
    const previous = this.state.planSettings;
    if (previous === settings) return;
    this.setState({ planSettings: settings });
    this.plan.settings = settings;
    if (previous.sampleDay !== settings.sampleDay) this.showSampleDay(settings.sampleDay);
  }

  setFocusClockOwner(owner: ModuleID | undefined): void {
    this.setState({ focusClockOwner: owner });
  }

  setFocusTabOn(on: boolean): void {
    this.setState({ isFocusTabOn: on });
  }

  setDisplayName(name: string | undefined): void {
    this.setState({ displayName: name });
  }

  /** Keeps the shared work in step with what other modules provide, so Today reads the merged snapshot instead of any one module's store. */
  followSharedWork(): () => void {
    const snapshot = this.context.snapshot;
    const module = this.context.id;
    const sameList = <T,>(a: readonly T[], b: readonly T[]) => a.length === b.length && a.every((item, index) => item === b[index]);
    /* Lists that haven't changed keep their identity, so an unchanged snapshot never publishes a new state (which would feed the snapshot again). */
    const apply = () => {
      const current = snapshot.get();
      const state = this.state;
      const progress = current.progress.filter((item) => item.source !== module);
      const tasks = current.openTasks.filter((task) => task.source !== module);
      const work = plannableWork(current, module, currentLanguage());
      this.setState({
        sharedProgress: sameList(progress, state.sharedProgress) ? state.sharedProgress : progress,
        sharedStudy: current.study,
        sharedTasks: sameList(tasks, state.sharedTasks) ? state.sharedTasks : tasks,
        sharedWork: sameList(work, state.sharedWork) ? state.sharedWork : work,
      });
    };
    apply();
    return snapshot.subscribe(apply);
  }

  /** Demo mode only: shows the sample day of a newly applied kit. */
  private showSampleDay(kind: TodayPlanSettings["sampleDay"]): void {
    if (this.repository !== undefined) return;
    const timeZone = this.context.timeZone();
    this.setState({ day: samplePlannerDay(plannerDayKeyOf(this.context.now(), timeZone), kind, timeZone) });
    this.demoDays.clear();
    this.loadOtherDay();
  }

  /** Switches to the current calendar day if it has changed (or retries a failed load), and then shows today. Cheap to call whenever the panel appears. */
  refreshDay(): void {
    const today = plannerDayKeyOf(this.context.now(), this.context.timeZone());
    if (this.repository === undefined || (today === this.state.day.date && !isUnreadable(this.state.problem))) return;
    const isNewDay = today !== this.state.day.date;
    this.loaded = this.load(today).then(() => {
      if (isNewDay) {
        /* A plan for what was tomorrow is about the wrong day now. */
        if (this.plan.target !== "today") this.plan.cancel();
        this.setViewing("today");
      }
      this.loadOtherDay();
    });
  }

  /** Puts the panel back on today for the next time it opens. A plan for tomorrow still on offer keeps tomorrow on screen instead. */
  panelClosed(): void {
    if (this.plan.isActive && this.plan.target !== "today" && this.state.viewing === this.plan.target) {
      this.refreshDay();
      return;
    }
    this.show("today");
  }

  /** Shows `viewed` in the checklist, reading its list fresh. Plan my day and Wrap up close, since both are about today. */
  show(viewed: PlannerViewedDay): void {
    this.refreshDay();
    if (viewed !== "today" || this.plan.target !== "today") this.plan.cancel();
    if (viewed !== "today") this.review.close();
    this.setViewing(viewed);
    this.loadOtherDay();
  }

  /** Schedules today's unfinished items around the calendar. */
  planMyDay(): void {
    this.review.close();
    this.show("today");
    const state = this.state;
    this.plan.plan("today", state.day.items, state.sharedWork, state.sharedTasks, state.sharedProgress);
  }

  /** Schedules tomorrow's list around tomorrow's calendar from the start of the working day. Other modules' shared work is today's, so it stays out. */
  planTomorrow(): void {
    this.review.close();
    this.show("tomorrow");
    if (!this.canEdit) return;
    this.plan.plan("tomorrow", this.shownDay.items);
  }

  /** Opens the End-of-Day Review of today's list, the focus sessions in the activity log, and what other modules share. */
  async wrapUp(): Promise<void> {
    this.plan.cancel();
    this.show("today");
    const state = this.state;
    const activity = this.context.isDemo ? [] : await this.context.activityLog.records(state.day.date).catch(() => []);
    this.review.wrapUp({
      day: state.day,
      activity,
      study: state.sharedStudy,
      progress: state.sharedProgress,
      isStudyDay: state.planSettings.planMode === "study",
      sampleDay: state.planSettings.sampleDay,
    });
  }

  /** Adds a task; returns false for blank titles so the field can keep its text. */
  add(title: string): boolean {
    return this.edit((day) => day.add(title, this.context.now()) !== undefined);
  }

  /** Adds a kit's starter tasks that aren't on today's list yet and returns them, so undoing the kit switch can take them back. */
  addStarterTasks(titles: readonly string[]): PlannerItem[] {
    let added: PlannerItem[] = [];
    this.editToday((day) => {
      added = day.addStarterTasks(titles, this.context.now());
      return added.length > 0;
    });
    return added;
  }

  /** Removes starter tasks `addStarterTasks` returned that the user hasn't renamed or checked off since. */
  takeBackStarterTasks(added: readonly PlannerItem[]): void {
    this.editToday((day) => day.removeUntouched(added));
  }

  /** Moves yesterday's leftovers with these ids (all of them when undefined) to the end of today's list. Yesterday's file keeps them as they were. */
  moveToToday(ids?: ReadonlySet<string>): void {
    const moving = this.leftovers.filter((item) => ids?.has(item.id) ?? true);
    if (moving.length === 0) return;
    this.editToday((day) => day.adopt(moving).length > 0);
  }

  /** Checks an item off or back on. Checking one off logs `task.completed` with the item's id as the subject. */
  toggle(id: string): void {
    const changed = this.edit((day) => {
      day.toggle(id, this.context.now());
      return true;
    });
    if (!changed) return;
    const item = this.shownDay.items.find((candidate) => candidate.id === id);
    if (item === undefined || !item.isDone || item.completedAt === undefined) return;
    void this.context.activityLog.record(
      makeActivityRecord({ source: this.context.id, kind: ACTIVITY_KINDS.taskCompleted, start: item.completedAt, quantity: 1, subject: id }),
    );
  }

  rename(id: string, title: string): void {
    this.edit((day) => day.rename(id, title));
  }

  delete(id: string): void {
    this.edit((day) => {
      day.delete(id);
      return true;
    });
  }

  move(id: string, index: number): void {
    this.edit((day) => {
      day.move(id, index);
      return true;
    });
  }

  clearCompleted(): void {
    this.edit((day) => {
      day.clearCompleted();
      return true;
    });
  }

  /** Snapshot runs only: shows `viewed`, with its sample plan open when `planning`. */
  async showForSnapshot(viewed: PlannerViewedDay, planning = false): Promise<void> {
    this.show(viewed);
    if (planning) await this.plan.showSampleProposal(viewed, this.shownDay.items);
  }

  /** Snapshot runs only: today with the given list in place of the sample. */
  showDayForSnapshot(day: PlannerDay): void {
    this.setState({ day, viewing: "today", otherDay: undefined });
  }

  private setViewing(viewing: PlannerViewedDay): void {
    if (viewing === this.state.viewing) return;
    this.setState({ viewing });
    this.upNext.show(viewing);
  }

  /** Applies `change` to a copy of the shown day and publishes + saves it when it reports a change. */
  private edit(change: (day: PlannerDay) => boolean): boolean {
    /* A new day since the panel opened shows today again, so an edit never lands on a stale day. */
    this.refreshDay();
    if (!this.canEdit) return false;
    const updated = this.shownDay.copy();
    if (!change(updated)) return false;
    if (this.state.viewing === "today") this.setState({ day: updated });
    else this.setState({ otherDay: updated });
    this.save(updated);
    return true;
  }

  /** Like `edit`, but always on today's list, whichever day is shown. */
  private editToday(change: (day: PlannerDay) => boolean): boolean {
    this.refreshDay();
    if (isUnreadable(this.state.problem)) return false;
    const updated = this.state.day.copy();
    if (!change(updated)) return false;
    this.setState({ day: updated });
    this.save(updated);
    return true;
  }

  private async load(date: PlannerDayKey): Promise<void> {
    const repository = this.repository;
    if (repository === undefined) return;
    try {
      /* A snapshot run shows today's list without creating its file. */
      const day = await (this.context.isSnapshot ? repository.preview(date) : repository.open(date));
      this.setState({ day, problem: undefined });
    } catch (error) {
      this.context.logger.error("could not read the day's list", error);
      this.setState({ day: new PlannerDay(date), problem: { kind: "unreadable", fileName: `${date}.json` } });
    }
  }

  /** Reads the day `viewing` names other than today, without creating its file. */
  private loadOtherDay(): void {
    const state = this.state;
    if (state.viewing === "today") {
      this.setState({ otherDay: undefined, otherProblem: undefined });
      return;
    }
    const viewing = state.viewing;
    const date = viewedDayKey(viewing, state.day.date);
    if (this.repository === undefined) {
      const kind = state.planSettings.sampleDay;
      this.setState({
        otherDay: this.demoDays.get(date) ?? samplePlannerDayFor(viewing, state.day.date, kind, this.context.timeZone()),
        otherProblem: undefined,
      });
      return;
    }
    const repository = this.repository;
    void repository
      .peek(date, state.day.date)
      .then((day) => {
        if (this.state.viewing === viewing) this.setState({ otherDay: day, otherProblem: undefined });
      })
      .catch((error: unknown) => {
        this.context.logger.error("could not read the other day's list", error);
        if (this.state.viewing === viewing) {
          this.setState({ otherDay: new PlannerDay(date), otherProblem: { kind: "unreadable", fileName: `${date}.json` } });
        }
      });
  }

  /** Writes `updated` to its file (or demo mode's memory) and records whether that worked for the list it belongs to. */
  private save(updated: PlannerDay): void {
    const isToday = updated.date === this.state.day.date;
    if (this.repository === undefined) {
      if (!isToday) this.demoDays.set(updated.date, updated);
      return;
    }
    /* A snapshot run reads the user's lists but leaves no trace. */
    if (this.context.isSnapshot) return;
    void this.repository
      .save(updated)
      .then(() => this.setProblem(isToday, undefined))
      .catch((error: unknown) => {
        this.context.logger.error("could not save the day's list", error);
        this.setProblem(isToday, { kind: "saveFailed" });
      });
  }

  private setProblem(isToday: boolean, problem: PlannerProblem | undefined): void {
    if (isToday) this.setState({ problem });
    else this.setState({ otherProblem: problem });
  }
}
