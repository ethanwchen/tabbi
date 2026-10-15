import { describe, expect, it } from "vitest";
import { instantOf, wallTime } from "../../../src/core/calendar/zonedCalendar";
import { DayPlanContext, MAXIMUM_BLOCKS, MINIMUM_BLOCK_MINUTES } from "../../../src/core/planner/dayPlan";
import { plannerItem, type PlannerItem } from "../../../src/core/planner/plannerDay";
import type { ProgressItem } from "../../../src/core/planner/providedWork";
import {
  MAXIMUM_REVIEW_MINUTES,
  planStudyDay,
  reviewWork,
  studyDayPreferences,
  studyDayPreferencesForMethod,
  type StudyDayPlan,
  type StudyReviewWork,
} from "../../../src/core/planner/studyDayPlan";
import { upcomingEvent, type UpcomingEvent } from "../../../src/core/planner/upcomingEvent";
import { StudyMethod } from "../../../src/core/studyMethods/studyMethod";

/* Port of StudyDayPlannerTests. */

const LA = "America/Los_Angeles";

/* 2026-10-01 at hour:minute Los Angeles time. */
function at(hour: number, minute = 0): number {
  return instantOf({ year: 2026, month: 10, day: 1, hour, minute }, LA);
}

function event(id: string, start: number, end: number, allDay = false): UpcomingEvent {
  return upcomingEvent({ id, title: id, start, end, isAllDay: allDay });
}

const cardio = plannerItem({ title: "Cardio pathology", createdAt: 0 });
const pharm = plannerItem({ title: "Sketchy pharm", createdAt: 0 });
const anki: StudyReviewWork = { title: "Anki reviews", minutes: 45 };

function context(now: number, events: UpcomingEvent[] = [], tasks: PlannerItem[] = []): DayPlanContext {
  return new DayPlanContext({ now, events, tasks, timeZone: LA });
}

/* A lecture 10-12, lab 13-15 and an all-day reminder. */
const classDay = (): UpcomingEvent[] => [
  event("Lecture", at(10), at(12)),
  event("Anatomy lab", at(13), at(15)),
  event("Exam week", at(0), at(23, 59), true),
];

function expectConstraints(plan: StudyDayPlan, planContext: DayPlanContext): void {
  const blocks = plan.blocks;
  expect(blocks.length).toBeLessThanOrEqual(MAXIMUM_BLOCKS);
  for (let index = 1; index < blocks.length; index++) {
    expect(blocks[index - 1]?.end ?? 0).toBeLessThanOrEqual(blocks[index]?.start ?? 0);
  }
  for (const block of blocks) {
    expect(planContext.gaps.some((gap) => gap.start <= block.start && block.end <= gap.end), `${block.title} leaves free time`).toBe(
      true,
    );
    expect(block.start).toBeGreaterThanOrEqual(planContext.now);
    expect(block.end).toBeLessThanOrEqual(planContext.dayEnd);
  }
}

describe("StudyDayPlanner reviews", () => {
  it("puts reviews first by default", () => {
    const planContext = context(at(8), classDay());
    const plan = planStudyDay(planContext, [anki]);
    expect(plan.blocks[0]?.kind).toBe("reviews");
    expect(plan.blocks[0]?.title).toBe("Anki reviews");
    expect(plan.blocks[0]?.start).toBe(at(8));
    expect(plan.blocks[0]?.end).toBe(at(8, 45));
    expectConstraints(plan, planContext);
  });

  it("puts reviews last when the user prefers it", () => {
    const planContext = context(at(8), classDay());
    const plan = planStudyDay(planContext, [anki], studyDayPreferences({ reviewsFirst: false }));
    const reviews = plan.blocks.filter((block) => block.kind === "reviews");
    expect(reviews.length).toBe(1);
    expect(reviews[0]?.end).toBe(at(18));
    expect(reviews[0]?.start).toBe(at(17, 15));
    expect(plan.blocks[0]?.kind).toBe("study");
    expectConstraints(plan, planContext);
  });

  it("skips a gap too short for the reviews whole", () => {
    /* 8:00-8:40 is free, then a lecture; 45 min of reviews wait for later. */
    const planContext = context(at(8), [event("Lecture", at(8, 50), at(10))]);
    const plan = planStudyDay(planContext, [anki], studyDayPreferences({ eventBufferMinutes: 10 }));
    const reviews = plan.blocks.find((block) => block.kind === "reviews");
    expect(reviews?.start).toBe(at(10, 10));
    expect(reviews?.end).toBe(at(10, 55));
    /* The earlier slot still gets a study block. */
    expect(plan.blocks[0]?.kind).toBe("study");
    expect(plan.blocks[0]?.start).toBe(at(8));
    expectConstraints(plan, planContext);
  });

  it("splits reviews too long for any gap across the earliest gaps", () => {
    /* Free: 8:00-8:40 and 10:10-10:50 (buffered), then a shift until 18:00. */
    const planContext = context(at(8), [event("Lecture", at(8, 50), at(10)), event("Shift", at(11), at(18))]);
    const plan = planStudyDay(planContext, [{ title: "Anki reviews", minutes: 60 }], studyDayPreferences({ eventBufferMinutes: 10 }));
    const reviews = plan.blocks.filter((block) => block.kind === "reviews");
    expect(reviews.map((block) => block.start)).toEqual([at(8), at(10, 10)]);
    expect(reviews.map((block) => block.end)).toEqual([at(8, 40), at(10, 30)]);
    expectConstraints(plan, planContext);
  });

  it("splits late reviews from the end of the day", () => {
    /* Free: 8:00-8:40, 10:10-11:00 and 16:10-18:00; 150 min capped to 120: 110 at the end, the last 10 grows to 15. */
    const planContext = context(at(8), [event("Lecture", at(8, 50), at(10)), event("Clinic", at(11, 10), at(16))]);
    const plan = planStudyDay(
      planContext,
      [{ title: "Anki reviews", minutes: 150 }],
      studyDayPreferences({ reviewsFirst: false, eventBufferMinutes: 10 }),
    );
    const reviews = plan.blocks.filter((block) => block.kind === "reviews");
    expect(reviews.map((block) => block.start)).toEqual([at(10, 45), at(16, 10)]);
    expect(reviews.map((block) => block.end)).toEqual([at(11), at(18)]);
    expectConstraints(plan, planContext);
  });

  it("caps a long review queue and shrinks it to the biggest gap", () => {
    const plan = planStudyDay(context(at(16)), [{ title: "Anki reviews", minutes: 400 }]);
    /* Only 16:00-18:00 is left, so reviews take all of it. */
    expect(plan.blocks.map((block) => block.kind)).toEqual(["reviews"]);
    expect(plan.blocks[0]?.start).toBe(at(16));
    expect(plan.blocks[0]?.end).toBe(at(18));
  });

  it("rounds review work from progress up to five minutes", () => {
    const item: ProgressItem = {
      id: "reviews",
      source: "anki",
      title: "Anki reviews",
      completed: 112,
      target: 432,
      unit: "cards",
      waitsForStart: false,
    };
    /* 320 cards at 10 s is 53.3 min. */
    expect(reviewWork(item)).toEqual({ title: "Anki reviews", minutes: 55 });
    expect(reviewWork(item, 6)).toEqual({ title: "Anki reviews", minutes: 35 });
    expect(reviewWork({ ...item, completed: 432 })).toBeUndefined();
    /* A huge per-card time stays at the longest review. */
    expect(reviewWork(item, 1e300)?.minutes).toBe(MAXIMUM_REVIEW_MINUTES);
  });
});

describe("StudyDayPlanner study blocks", () => {
  it("makes study blocks exactly the method length with breaks between", () => {
    const planContext = context(at(8), classDay(), [cardio, pharm]);
    const plan = planStudyDay(planContext, [anki], studyDayPreferencesForMethod(StudyMethod.fiftyTwoSeventeen));
    const study = plan.blocks.filter((block) => block.kind === "study");
    expect(study.length).toBeGreaterThan(0);
    for (const block of study) expect(block.end - block.start).toBe(52 * 60);
    /*
     * Reviews 8:00-8:45; after a 17 min break no 52 min block fits before
     * the lecture's buffer at 9:50, nor in the lunch gap, so study waits
     * for the afternoon: 15:10, then 17 min off, 16:20.
     */
    expect(plan.blocks.map((block) => block.start)).toEqual([at(8), at(15, 10), at(16, 20)]);
    expect(plan.breaks).toEqual([{ start: at(16, 2), end: at(16, 20) }]);
    expectConstraints(plan, planContext);
  });

  it("names the first study blocks after open tasks, then the generic title", () => {
    const plan = planStudyDay(context(at(15), [], [cardio, pharm]), [], studyDayPreferences({ studyTitle: "Question bank" }));
    expect(plan.blocks.map((block) => block.title).slice(0, 3)).toEqual(["Cardio pathology", "Sketchy pharm", "Question bank"]);
    expect(plan.blocks[0]?.linkedTaskID).toBe(cardio.id);
    expect(plan.blocks[2]?.linkedTaskID).toBeUndefined();
  });

  it("takes a long Pomodoro break after every fourth block", () => {
    const plan = planStudyDay(context(at(14)), [], studyDayPreferencesForMethod(StudyMethod.pomodoro));
    expect(plan.blocks.length).toBe(MAXIMUM_BLOCKS);
    /* 25/5 three times, 25 then a 15 min long break, then the fifth block. */
    expect(plan.blocks.map((block) => block.start)).toEqual([at(14), at(14, 30), at(15), at(15, 30), at(16, 10)]);
    expect(plan.breaks.at(-1)).toEqual({ start: at(15, 55), end: at(16, 10) });
  });

  it("keeps a buffer around events", () => {
    const events = classDay();
    const planContext = context(at(8), events);
    const plan = planStudyDay(planContext, [anki], studyDayPreferences({ eventBufferMinutes: 10 }));
    const buffer = 10 * 60;
    for (const block of plan.blocks) {
      for (const entry of events.filter((candidate) => !candidate.isAllDay)) {
        expect(block.start < entry.end + buffer && entry.start - buffer < block.end, `${block.title} near ${entry.title}`).toBe(false);
      }
    }
    /* A break never spans an event. */
    for (const rest of plan.breaks) {
      expect(events.some((entry) => !entry.isAllDay && entry.start < rest.end && rest.start < entry.end)).toBe(false);
    }
    expectConstraints(plan, planContext);
  });

  it("buffers an event ending right around now", () => {
    /* At 9:01 the lecture ends at 9:05, so nothing starts before 9:15. */
    const planContext = context(at(9, 1), [event("Lecture", at(8), at(9, 5))]);
    const plan = planStudyDay(planContext, [anki], studyDayPreferences({ eventBufferMinutes: 10 }));
    expect(plan.blocks[0]?.start).toBe(at(9, 15));
    expectConstraints(plan, planContext);
  });

  it("starts late reviews on the slot grid", () => {
    /* The clinic at 13:57 minus a 10 min buffer is 13:47; reviews end on the slot before it, 13:45. */
    const planContext = context(at(12), [event("Clinic", at(13, 57), at(18))]);
    const plan = planStudyDay(
      planContext,
      [{ title: "Anki reviews", minutes: 25 }],
      studyDayPreferences({ reviewsFirst: false, eventBufferMinutes: 10 }),
    );
    const reviews = plan.blocks.filter((block) => block.kind === "reviews");
    expect(reviews.map((block) => block.start)).toEqual([at(13, 20)]);
    expect(reviews.map((block) => block.end)).toEqual([at(13, 45)]);
    for (const block of plan.blocks) expect(wallTime(block.start, LA).minute % 5).toBe(0);
    expectConstraints(plan, planContext);
  });

  it("plans nothing without free time", () => {
    const plan = planStudyDay(context(at(23)), [anki]);
    expect(plan.blocks).toEqual([]);
    expect(plan.breaks).toEqual([]);
  });
});

describe("StudyDayPreferences", () => {
  it("follows the study method", () => {
    const pomodoro = studyDayPreferencesForMethod(StudyMethod.pomodoro);
    expect(pomodoro.studyMinutes).toBe(25);
    expect(pomodoro.breakMinutes).toBe(5);
    expect(pomodoro.longBreakMinutes).toBe(15);
    expect(pomodoro.longBreakEvery).toBe(4);

    const questions = studyDayPreferencesForMethod(StudyMethod.questionBlock);
    expect(questions.studyMinutes).toBe(120);
    expect(questions.breakMinutes).toBe(10);

    const flow = studyDayPreferencesForMethod(StudyMethod.flowtime());
    expect(flow.studyMinutes).toBe(45);
    expect(flow.breakMinutes).toBe(8);

    expect(studyDayPreferencesForMethod(StudyMethod.ankiSprint()).studyMinutes).toBe(30);
    expect(studyDayPreferences({ studyMinutes: 3 }).studyMinutes).toBe(MINIMUM_BLOCK_MINUTES);
  });
});
