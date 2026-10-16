/*
 * Port of DayReviewStore: drives the End-of-Day Review. Shows today's
 * numbers at once, asks the AI the user picked for a short encouraging
 * summary (falling back to a local line), and saves the review when the
 * user taps Done. The review card replaces the checklist inline.
 *
 * Demo runs show the sample review and never ask an AI or touch disk.
 */

import { aiService } from "../../app/aiService";
import type { ModuleContext } from "../../app/context";
import { Store } from "../../app/store";
import type { ActivityRecord } from "../../core/activity/activityRecord";
import { answer } from "../../core/ai/aiProvider";
import { promptRequest } from "../../core/ai/aiRequest";
import { isEphemeral } from "../../core/modules/runMode";
import {
  DayReviewRepository,
  dayReviewPrompt,
  fallbackReviewSummary,
  reviewDay,
  reviewSummary,
  sampleDayReview,
  type DayReview,
} from "../../core/planner/dayReview";
import type { PlannerDay } from "../../core/planner/plannerDay";
import type { PlannerSampleDay } from "../../core/planner/todayPlanSettings";
import type { ProgressItem } from "../../core/providers/progressItem";
import { SAMPLE_STUDY_DAY_TALLY, type StudyDayTally } from "../../core/providers/studyDayTally";
import { currentLanguage } from "../../core/localization/tr";

export interface DayReviewState {
  /** The open review, or undefined while the checklist shows. */
  readonly review: DayReview | undefined;
  /** True when Done couldn't write the file; the card stays open. */
  readonly saveFailed: boolean;
}

/* The review before its summary arrives, so the card shows the shimmer. */
function withoutSummary(review: DayReview): DayReview {
  const copy: { -readonly [Key in keyof DayReview]?: DayReview[Key] } = { ...review };
  delete copy.summary;
  return copy as DayReview;
}

/** Longest wait for the AI before using the local summary, in seconds. */
const TIMEOUT = 30;
const DEMO_DELAY_MS = 1200;

export class DayReviewStore extends Store<DayReviewState> {
  private readonly repository: DayReviewRepository | undefined;
  private generation = 0;

  constructor(private readonly context: ModuleContext) {
    super({ review: undefined, saveFailed: false });
    this.repository = isEphemeral(context.runMode) ? undefined : new DayReviewRepository(context.storage.folder("Planner"));
  }

  get isActive(): boolean {
    return this.state.review !== undefined;
  }

  /** Waiting for the summary; the card shows a shimmer in its place. */
  get isSummarizing(): boolean {
    return this.state.review !== undefined && this.state.review.summary === undefined;
  }

  /**
   * Opens the review of `day` and starts writing its summary. `activity`
   * is the shared log's records of that day, and `study` and `progress`
   * are what other modules share; on a study day the demo fills in a
   * sample tally, since no demo module keeps one yet.
   */
  wrapUp(input: {
    day: PlannerDay;
    activity: readonly ActivityRecord[];
    study?: StudyDayTally | undefined;
    progress?: readonly ProgressItem[];
    isStudyDay?: boolean;
    sampleDay?: PlannerSampleDay;
  }): void {
    this.generation += 1;
    const generation = this.generation;
    const progress = input.progress ?? [];
    if (this.context.isDemo) {
      const sample = sampleDayReview(
        input.day.date,
        this.context.timeZone(),
        input.sampleDay ?? "work",
        input.study ?? (input.isStudyDay === true ? SAMPLE_STUDY_DAY_TALLY : undefined),
        progress,
      );
      this.setState({ review: withoutSummary(sample), saveFailed: false });
      setTimeout(() => this.publish(generation, sample.summary), DEMO_DELAY_MS);
      return;
    }
    const review = reviewDay(input.day, input.activity, this.context.timeZone(), input.study, progress);
    this.setState({ review, saveFailed: false });
    void this.summarize(review).then((summary) => this.publish(generation, summary ?? fallbackReviewSummary(review)));
  }

  /** Snapshot runs only: the sample review, with or without its summary. */
  showForSnapshot(day: PlannerDay, options: { readonly loading?: boolean; readonly study?: boolean; readonly sampleDay?: PlannerSampleDay; readonly progress?: readonly ProgressItem[] }): void {
    this.generation += 1;
    const sample = sampleDayReview(
      day.date,
      this.context.timeZone(),
      options.sampleDay ?? "work",
      options.study === true ? SAMPLE_STUDY_DAY_TALLY : undefined,
      options.progress ?? [],
    );
    this.setState({ review: options.loading === true ? withoutSummary(sample) : sample, saveFailed: false });
  }

  /** Saves the review and closes the card. Stays open if the file can't be written. */
  async done(): Promise<void> {
    const open = this.state.review;
    if (open === undefined) return;
    /* Done before the AI answered: keep the local line rather than nothing. */
    const review: DayReview = open.summary === undefined ? { ...open, summary: fallbackReviewSummary(open) } : open;
    const generation = this.generation;
    try {
      if (!this.context.isSnapshot) await this.repository?.save(review);
    } catch (error) {
      this.context.logger.error("could not save the review", error);
      if (generation === this.generation) this.setState({ review, saveFailed: true });
      return;
    }
    if (generation === this.generation) this.close();
  }

  /** Closes the card without saving. */
  close(): void {
    this.generation += 1;
    this.setState({ review: undefined, saveFailed: false });
  }

  private publish(generation: number, summary: string | undefined): void {
    const review = this.state.review;
    if (generation !== this.generation || review === undefined) return;
    this.setState({ review: summary === undefined ? review : { ...review, summary } });
  }

  /**
   * The AI's cleaned-up summary, or undefined when it can't answer, fails,
   * or times out. Nothing is sent before a provider is picked and set up.
   */
  private async summarize(review: DayReview): Promise<string | undefined> {
    try {
      const provider = await aiService(this.context).readyProvider();
      if (provider === undefined) return undefined;
      const text = await answer(provider, promptRequest(dayReviewPrompt(review, currentLanguage())), AbortSignal.timeout(TIMEOUT * 1000));
      return reviewSummary(text);
    } catch {
      return undefined;
    }
  }
}
