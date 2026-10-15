import { beforeAll, describe, expect, it } from "vitest";
import { intervalDuration, type DateInterval } from "../../src/core/planner/dateInterval";
import {
  DAY_PLANNER_MODEL,
  DEFAULT_DAY_END_HOUR,
  DayPlanContext,
  LATEST_DAY_END_HOUR,
  MAXIMUM_BLOCKS,
  MAXIMUM_TITLE_LENGTH,
  MINIMUM_BLOCK_MINUTES,
  blockID,
  dayPlanPrompt,
  dayPlanProposalBlocks,
  dayPlannerArguments,
  parseDayPlan,
  planBlock,
  validateDayPlan,
  type PlanBlock,
  type PlanBlockKind,
} from "../../src/core/planner/dayPlan";
import { DayPlanProposal, PLANNED_EVENT_NOTE } from "../../src/core/planner/dayPlanProposal";
import { plannerItem } from "../../src/core/planner/plannerDay";
import {
  mergedProgress,
  mergedTasks,
  plannableWork,
  type ProgressItem,
  type ProvidedTask,
} from "../../src/core/planner/providedWork";
import { DEFAULT_SECONDS_PER_CARD, MAXIMUM_REVIEW_MINUTES } from "../../src/core/planner/studyDayPlan";
import {
  planStudyPreferences,
  studyReviews,
  todayPlanSettings,
  todayStudyPlan,
  type PlanMode,
} from "../../src/core/planner/todayPlanSettings";
import { upcomingEvent, type UpcomingEvent } from "../../src/core/planner/upcomingEvent";
import { refinePrompt, refinedBlocks } from "../../src/core/schedule/planRefinement";
import { planFocusMinutes, planProposal, type ScheduledBlock } from "../../src/core/schedule/schedulePlanner";
import { WORKDAY_START_MINUTE, localPlan, localSchedulePreferences, localWork } from "../../src/core/schedule/todayLocalPlan";
import { StudyMethod } from "../../src/core/studyMethods/studyMethod";
import type { StudyMethodKind } from "../../src/core/studyMethods/studyMethodFile";
import { MODULE_IDS } from "../../src/core/modules/moduleId";
import { switchLanguage } from "../unit/localization/catalogs";
import { loadFixture } from "../support/fixtures";
import { goldenDiff } from "../support/goldenCompare";

/*
 * Replays shared/fixtures/plan-my-day (written by PlanMyDayGoldenTests on
 * the Mac): every day planned on device, as a study day and from recorded
 * AI answers, with the prompts, parsed answers and refinements, plus the
 * proposal sequences. Every wall-clock time resolves in the day's own
 * IANA zone; Vitest runs in Pacific/Chatham, so a slip to the machine
 * zone fails here.
 */

interface FixtureEvent {
  id: string;
  title: string;
  start: number;
  end: number;
  isAllDay: boolean;
}

interface FixtureBlock {
  id?: string;
  start: number;
  end: number;
  title: string;
  task?: string;
  kind: string;
}

interface DayInput {
  timeZone: string;
  now: number;
  events: FixtureEvent[];
  tasks: { id: string; title: string; isDone: boolean }[];
  provided: {
    module: string;
    tasks: { id: string; title: string; isDone: boolean; estimatedMinutes?: number }[];
    progress: { id: string; title: string; completed: number; target: number; unit: string; waitsForStart: boolean }[];
  }[];
  settings: {
    planMode: string;
    studyMethod?: string;
    reviewsFirst: boolean;
    eventBufferMinutes: number;
    studyBlockTitle: string;
    secondsPerCard: number;
    dayEndHour: number;
  };
  answers: string[];
  refineAnswers: string[];
}

interface StepInput {
  action: string;
  id?: string;
  ids?: string[];
  blocks?: FixtureBlock[];
  at?: number;
  events?: FixtureEvent[];
  writerFails?: boolean;
}

interface Golden {
  schema: string;
  version: number;
  constants: Record<string, unknown>;
  days: { name: string; input: DayInput; output: Record<string, unknown> }[];
  proposals: { name: string; blocks: FixtureBlock[]; breaks: DateInterval[]; steps: (Record<string, unknown> & { input: StepInput })[] }[];
}

const golden = loadFixture<Golden>("plan-my-day/plan-my-day.json");

/** Reasons carry clock times ("Due by 3:00"), recorded for this locale. */
const LOCALE = "en-US";

function event(input: FixtureEvent): UpcomingEvent {
  return upcomingEvent({ id: input.id, title: input.title, start: input.start, end: input.end, isAllDay: input.isAllDay });
}

function blockJson(block: PlanBlock, withID = false): Record<string, unknown> {
  return {
    id: withID ? block.id : undefined,
    start: block.start,
    end: block.end,
    title: block.title,
    task: block.linkedTaskID,
    kind: block.kind,
  };
}

function intervalJson(value: DateInterval): Record<string, unknown> {
  return { start: value.start, end: value.end };
}

function fromFixture(block: FixtureBlock): PlanBlock {
  return planBlock({
    id: blockID(block.id),
    start: block.start,
    end: block.end,
    title: block.title,
    linkedTaskID: block.task?.toUpperCase(),
    kind: block.kind as PlanBlockKind,
  });
}

function scheduledJson(entry: ScheduledBlock): Record<string, unknown> {
  return { ...blockJson(entry.block), workID: entry.workID, reason: entry.reason, part: entry.part, parts: entry.parts };
}

function outcomeJson(proposal: DayPlanProposal): Record<string, unknown> {
  return proposal.isSettled
    ? { kind: "noFreeTime" }
    : { kind: "proposal", blocks: proposal.pending.map((block) => blockJson(block)), breaks: proposal.breaks.map(intervalJson) };
}

/** Port of PlanMyDayGoldenFixture.plan: what Today hands Plan my day, planned every way. */
function planDay(input: DayInput): Record<string, unknown> {
  const clock = { timeZone: input.timeZone, locale: LOCALE };
  const now = input.now;
  const events = input.events.map(event);
  const tasks = input.tasks.map((task) => plannerItem({ id: task.id, title: task.title, isDone: task.isDone, createdAt: now }));
  const providedTasks = mergedTasks(
    input.provided.map((provided) => [
      provided.module,
      provided.tasks.map(
        (task): ProvidedTask => ({
          id: task.id,
          source: provided.module,
          title: task.title,
          isDone: task.isDone,
          ...(task.estimatedMinutes === undefined ? {} : { estimatedMinutes: task.estimatedMinutes }),
        }),
      ),
    ]),
  );
  const providedProgress = mergedProgress(
    input.provided.map((provided) => [
      provided.module,
      provided.progress.map((goal): ProgressItem => ({ ...goal, source: provided.module })),
    ]),
  );
  /* What Today passes on: other modules' work, phrased and as tasks and goals. */
  const sharedWork = plannableWork(providedProgress, providedTasks, MODULE_IDS.planner, LOCALE);
  const sharedTasks = providedTasks.filter((task) => !task.isDone && task.source !== MODULE_IDS.planner);
  const progress = providedProgress.filter((goal) => goal.source !== MODULE_IDS.planner);
  const settings = todayPlanSettings({
    planMode: input.settings.planMode as PlanMode,
    ...(input.settings.studyMethod === undefined
      ? {}
      : { studyMethod: StudyMethod.preset(input.settings.studyMethod as StudyMethodKind) }),
    reviewsFirst: input.settings.reviewsFirst,
    eventBufferMinutes: input.settings.eventBufferMinutes,
    studyBlockTitle: input.settings.studyBlockTitle,
    secondsPerCard: input.settings.secondsPerCard,
    dayEndHour: input.settings.dayEndHour,
  });
  const context = new DayPlanContext({
    now,
    events,
    tasks,
    sharedWork,
    timeZone: input.timeZone,
    dayEndHour: settings.dayEndHour,
  });

  const preferences = localSchedulePreferences(settings, now, input.timeZone);
  const plan = localPlan(settings, { now, events, tasks, sharedTasks, progress }, clock);
  const local = {
    preferences: { ...preferences },
    work: localWork(settings, tasks, sharedTasks, progress).map((work) => work.id),
    day: plan.day,
    blocks: plan.blocks.map(scheduledJson),
    breaks: plan.breaks.map(intervalJson),
    unplaced: plan.unplaced.map((entry) => ({
      workID: entry.work.id,
      title: entry.work.title,
      kind: entry.work.kind,
      minutes: entry.minutes,
      reason: entry.reason,
    })),
    focusMinutes: planFocusMinutes(plan),
  };

  const studyPlan = todayStudyPlan(settings, context, progress);
  const study = {
    preferences: { ...planStudyPreferences(settings) },
    reviews: studyReviews(settings, progress).map((work) => ({ title: work.title, minutes: work.minutes })),
    blocks: studyPlan.blocks.map((block) => blockJson(block)),
    breaks: studyPlan.breaks.map(intervalJson),
  };

  const claude = input.answers.map((answer) => {
    let parsed: PlanBlock[] | undefined;
    try {
      parsed = parseDayPlan(answer, context);
    } catch {
      parsed = undefined;
    }
    return {
      answer,
      parsed: parsed?.map((block) => blockJson(block)),
      proposal: parsed === undefined ? undefined : validateDayPlan(parsed, context).map((block) => blockJson(block)),
    };
  });

  const localBlocks = plan.blocks.map((entry) => entry.block);
  const refinements = input.refineAnswers.map((answer) => {
    let refined: PlanBlock[] | undefined;
    try {
      refined = refinedBlocks(answer, context, localBlocks);
    } catch {
      refined = undefined;
    }
    const proposal = planProposal(plan);
    if (refined !== undefined) proposal.refine(refined);
    return {
      answer,
      blocks: refined?.map((block) => blockJson(block)),
      pending: proposal.pending.map((block) => blockJson(block)),
      breaks: proposal.breaks.map(intervalJson),
      refinement: proposal.refinement,
    };
  });

  /* DayPlanStore.run: no free time ends planning before any planner runs. */
  let outcome: Record<string, unknown>;
  if (!context.hasFreeTime) {
    outcome = { kind: "noFreeTime" };
  } else if (settings.planMode === "local") {
    outcome = outcomeJson(planProposal(plan));
  } else if (settings.planMode === "study") {
    outcome = outcomeJson(DayPlanProposal.fromStudyPlan(studyPlan));
  } else {
    const answer = input.answers[0];
    let blocks: PlanBlock[] | undefined;
    try {
      blocks = answer === undefined ? undefined : dayPlanProposalBlocks(answer, context);
    } catch {
      blocks = undefined;
    }
    if (blocks === undefined) outcome = { kind: "failed" };
    else outcome = blocks.length === 0 ? { kind: "noFreeTime" } : outcomeJson(new DayPlanProposal(blocks));
  }

  return {
    sharedWork,
    dayEnd: context.dayEnd,
    gaps: context.gaps.map(intervalJson),
    taskKeys: [
      ...context.taskKeys.map(({ key, task }) => `${key}=${task.id}`),
      ...context.sharedWorkKeys.map(({ key, work }) => `${key}=${work}`),
    ],
    local,
    study,
    prompt: dayPlanPrompt(context),
    claude,
    refinePrompt: refinePrompt(context, localBlocks),
    refinements,
    outcome,
  };
}

/** Port of PlanMyDayGoldenFixture.run: a proposal through its recorded steps. */
async function runProposal(blocks: FixtureBlock[], breaks: DateInterval[], steps: StepInput[]): Promise<Record<string, unknown>[]> {
  const proposal = new DayPlanProposal(blocks.map(fromFixture), breaks);
  const results: Record<string, unknown>[] = [];
  for (const input of steps) {
    let written: Record<string, unknown>[] | undefined;
    let threw: boolean | undefined;
    if (input.action === "dismiss") {
      proposal.dismiss(blockID(input.id));
    } else if (input.action === "refine") {
      proposal.refine((input.blocks ?? []).map(fromFixture));
    } else {
      try {
        const events = await proposal.add(
          input.ids === undefined ? undefined : new Set(input.ids.map((id) => blockID(id))),
          input.at ?? 0,
          (input.events ?? []).map(event),
          {
            write() {
              if (input.writerFails === true) throw new Error("The calendar refused the events");
            },
          },
        );
        written = events.map((entry) => ({ title: entry.title, start: entry.start, end: entry.end, notes: entry.notes }));
        threw = false;
      } catch {
        threw = true;
      }
    }
    results.push({
      input,
      written,
      threw,
      pending: proposal.pending.map((block) => blockJson(block, true)),
      breaksAfter: proposal.pending.map((block) => {
        const rest = proposal.breakAfter(block);
        return rest === undefined ? null : intervalJson(rest);
      }),
      breaks: proposal.breaks.map(intervalJson),
      addedCount: proposal.addedCount,
      skippedCount: proposal.skippedCount,
      refinement: proposal.refinement,
      isSettled: proposal.isSettled,
    });
  }
  return results;
}

describe("plan-my-day golden fixture", () => {
  beforeAll(() => {
    switchLanguage("en");
  });

  it("is the version this port reads", () => {
    expect(golden.schema).toBe("tabbi.plan-my-day.golden");
    expect(golden.version).toBe(1);
    expect(golden.days.length).toBeGreaterThan(0);
    expect(golden.proposals.length).toBe(4);
  });

  it("matches the constants", () => {
    const constants = {
      minimumBlockMinutes: MINIMUM_BLOCK_MINUTES,
      maximumBlocks: MAXIMUM_BLOCKS,
      maximumTitleLength: MAXIMUM_TITLE_LENGTH,
      defaultDayEndHour: DEFAULT_DAY_END_HOUR,
      latestDayEndHour: LATEST_DAY_END_HOUR,
      workdayStartMinute: WORKDAY_START_MINUTE,
      defaultSecondsPerCard: DEFAULT_SECONDS_PER_CARD,
      maximumReviewMinutes: MAXIMUM_REVIEW_MINUTES,
      eventNote: PLANNED_EVENT_NOTE,
      claudeArguments: dayPlannerArguments(),
    };
    expect(goldenDiff(constants, golden.constants)).toBeUndefined();
    expect(dayPlannerArguments()[1]).toBe(DAY_PLANNER_MODEL);
  });

  for (const day of golden.days) {
    describe(day.name, () => {
      const output = planDay(day.input);
      for (const key of Object.keys(day.output)) {
        it(key, () => {
          expect(goldenDiff(output[key], day.output[key], `${day.name}.${key}`)).toBeUndefined();
        });
      }
      it("records nothing the port leaves out", () => {
        expect(goldenDiff(output, day.output, day.name)).toBeUndefined();
      });
    });
  }

  for (const proposal of golden.proposals) {
    it(`proposal ${proposal.name}`, async () => {
      const steps = await runProposal(
        proposal.blocks,
        proposal.breaks,
        proposal.steps.map((step) => step.input),
      );
      expect(goldenDiff(steps, proposal.steps, proposal.name)).toBeUndefined();
    });
  }

  it("keeps every proposed block at least the shortest block long", () => {
    for (const day of golden.days) {
      const outcome = day.output.outcome as { blocks?: { start: number; end: number }[] };
      for (const block of outcome.blocks ?? []) {
        expect(intervalDuration(block)).toBeGreaterThanOrEqual(MINIMUM_BLOCK_MINUTES * 60);
      }
    }
  });
});
