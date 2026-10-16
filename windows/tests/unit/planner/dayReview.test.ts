import { beforeAll, describe, expect, it } from "vitest";
import { ActivityLogRepository } from "../../../src/core/activity/activityLogRepository";
import { ACTIVITY_KINDS, ACTIVITY_UNITS, makeActivityRecord, type ActivityRecord } from "../../../src/core/activity/activityRecord";
import { FocusTimerConfig, type FocusPhase } from "../../../src/core/focus/focusTimer";
import { completionActivityRecord } from "../../../src/core/focus/focusTimerActivity";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import {
  DAY_REVIEW_SCHEMA,
  DayReviewRepository,
  MAXIMUM_SUMMARY_LENGTH,
  decodeDayReview,
  dayReviewArguments,
  dayReviewPrompt,
  encodeDayReview,
  fallbackReviewSummary,
  focusLogActivityRecords,
  isWrapUpTime,
  reviewDay,
  reviewIsEmpty,
  reviewStats,
  reviewSummary,
  sampleDayReview,
  type DayReview,
} from "../../../src/core/planner/dayReview";
import { PlannerDay } from "../../../src/core/planner/plannerDay";
import { dayKeyStart } from "../../../src/core/planner/plannerDayKey";
import { ProgressItem } from "../../../src/core/providers/progressItem";
import type { StudyDayTally } from "../../../src/core/providers/studyDayTally";
import { phaseActivityRecord, type StudyPhaseOutcome } from "../../../src/core/studyMethods/studyPhaseRecord";
import { PetPointsRules } from "../../../src/core/pets/petPointsRules";
import { switchLanguage } from "../../support/catalogs";

/* Port of DayReviewTests: aggregation, the prompt and summary cleanup, persistence, demo data and study stats. */

const LA = "America/Los_Angeles";
const OCT1 = "2026-10-01";

function at(hour: number, minute = 0, day = OCT1): number {
  return dayKeyStart(day, LA) + hour * 3600 + minute * 60;
}

function checklist(): PlannerDay {
  const day = new PlannerDay(OCT1);
  const ship = day.add("Ship planner beta", at(9));
  day.add("Write release notes", at(9));
  const review = day.add("Review Ana's PR", at(9));
  day.toggle(review?.id ?? "", at(10));
  day.toggle(ship?.id ?? "", at(15));
  return day;
}

/* A timer's record in the activity log's shape. */
function logged(record: ActivityRecord): ActivityRecord {
  return makeActivityRecord({ ...record });
}

function completion(phase: FocusPhase, endedAt: number): ActivityRecord {
  return logged(completionActivityRecord({ phase, endedAt }, new FocusTimerConfig(25 * 60, 5 * 60), "focus"));
}

function ankiReviews(done: number, target: number): ProgressItem {
  return new ProgressItem({ id: "reviews", source: "anki", title: "Anki reviews", completed: done, target, unit: "cards", waitsForStart: false });
}

function review(fields: Partial<DayReview> = {}): DayReview {
  return { date: OCT1, done: [], carryingOver: [], focusSessions: 0, focusMinutes: 0, progress: [], ...fields };
}

beforeAll(() => {
  switchLanguage("en");
});

describe("DayReviewer aggregation", () => {
  it("splits done and carry-over in list order", () => {
    const result = reviewDay(checklist(), [], LA);
    expect(result.date).toBe(OCT1);
    expect(result.done).toEqual(["Ship planner beta", "Review Ana's PR"]);
    expect(result.carryingOver).toEqual(["Write release notes"]);
    expect(result.focusSessions).toBe(0);
    expect(result.summary).toBeUndefined();
    expect(reviewIsEmpty(result)).toBe(false);
  });

  it("counts today's focus stretches from every timer", () => {
    const study = makeActivityRecord({
      source: "study",
      kind: ACTIVITY_KINDS.focusCompleted,
      start: at(13),
      end: at(13, 40),
      quantity: 40,
      unit: ACTIVITY_UNITS.minutes,
    });
    const activity = [
      completion("focus", at(23, 50, "2026-09-30")),
      completion("focus", at(10)),
      completion("rest", at(10, 5)),
      makeActivityRecord({ source: "anki", kind: ACTIVITY_KINDS.cardsReviewed, start: at(11), quantity: 80, unit: ACTIVITY_UNITS.cards }),
      study,
    ];
    const result = reviewDay(checklist(), activity, LA);
    /* Breaks, cards and yesterday's session don't count. */
    expect(result.focusSessions).toBe(2);
    expect(result.focusMinutes).toBe(65);
  });

  it("skips study phases that were cut short", () => {
    const phase = (outcome: StudyPhaseOutcome, start: number) => {
      const record = phaseActivityRecord(
        { method: "flowtime", phase: "focus", startedAt: at(start), endedAt: at(start, 30), activeDuration: 30 * 60, outcome },
        "study",
      );
      return record === undefined ? [] : [logged(record)];
    };
    const activity = [...phase("completed", 9), ...phase("stopped", 10), ...phase("skipped", 11), ...phase("abandoned", 12)];
    const result = reviewDay(checklist(), activity, LA);
    /* A skipped or abandoned phase isn't a finished session. */
    expect(result.focusSessions).toBe(2);
    expect(result.focusMinutes).toBe(60);
  });

  it("turns the legacy session log into Pomodoro focus records", () => {
    const records = focusLogActivityRecords([{ endedAt: at(10), duration: 25 * 60 }], "focus");
    const expected = completion("focus", at(10));
    expect(records.length).toBe(1);
    expect(records[0]?.kind).toBe(expected.kind);
    expect(records[0]?.start).toBe(expected.start);
    expect(records[0]?.end).toBe(expected.end);
    expect(records[0]?.quantity).toBe(25);
    expect(records[0]?.metadata).toEqual(expected.metadata);
    expect(reviewDay(checklist(), records, LA).focusMinutes).toBe(25);
  });

  it("adds no copies when the legacy log is moved again", async () => {
    const repository = new ActivityLogRepository(new InMemoryDocumentStore(), LA);
    const sessions = [
      { endedAt: at(10), duration: 25 * 60 },
      { endedAt: at(11), duration: 25 * 60 },
    ];
    await repository.append(focusLogActivityRecords(sessions, "focus"));
    await repository.append(focusLogActivityRecords(sessions, "focus"));
    /* A retried move skips what is already on disk. */
    expect((await repository.records(OCT1)).length).toBe(2);
  });

  it("finds an empty day empty", () => {
    expect(reviewIsEmpty(reviewDay(new PlannerDay(OCT1), [], LA))).toBe(true);
  });

  it("suggests wrapping up from 5 pm", () => {
    expect(isWrapUpTime(at(16, 59), LA)).toBe(false);
    expect(isWrapUpTime(at(17), LA)).toBe(true);
    expect(isWrapUpTime(at(23, 30), LA)).toBe(true);
  });
});

describe("DayReviewer prompt and summary", () => {
  it("lists the day in the prompt and disables tools", () => {
    const result = { ...reviewDay(checklist(), [], LA), focusSessions: 2, focusMinutes: 50 };
    const prompt = dayReviewPrompt(result);
    expect(prompt).toContain("- Ship planner beta");
    expect(prompt).toContain("- Write release notes");
    expect(prompt).toContain("Focus sessions completed: 2 (50 minutes)");
    expect(dayReviewPrompt(review())).toContain("Done today:\n- none");
    const args = dayReviewArguments();
    expect(args[args.indexOf("--tools") + 1]).toBe("");
    expect(args).toContain("--model");
  });

  it("cleans fences, quotes and line breaks", () => {
    expect(reviewSummary('  "Nice work today.\nRest well."  ')).toBe("Nice work today. Rest well.");
    expect(reviewSummary("```\nGreat focus today.\n```")).toBe("Great focus today.");
    expect(reviewSummary("“Solid progress.”")).toBe("Solid progress.");
  });

  it("keeps at most two sentences", () => {
    expect(reviewSummary("One. Two! Three? Four.")).toBe("One. Two!");
  });

  it("cuts an overlong summary at a word", () => {
    const summary = reviewSummary("wonderful ".repeat(40)) ?? "";
    expect([...summary].length).toBeLessThanOrEqual(MAXIMUM_SUMMARY_LENGTH);
    expect(summary.endsWith("wonderful…")).toBe(true);
  });

  it("gives nothing for a blank summary", () => {
    expect(reviewSummary("  \n ")).toBeUndefined();
    expect(reviewSummary('""')).toBeUndefined();
  });

  it("fits the fallback summary to the day", () => {
    const day = (done: number, left: number, focus = 0) =>
      review({
        done: Array.from({ length: done }, () => "a"),
        carryingOver: Array.from({ length: left }, () => "b"),
        focusSessions: focus,
        focusMinutes: focus * 25,
      });
    expect(fallbackReviewSummary(day(3, 0))).toBe("You cleared all 3 tasks today. Enjoy the evening.");
    expect(fallbackReviewSummary(day(1, 2))).toBe("You finished 1 task today. 2 tasks will be waiting tomorrow.");
    expect(fallbackReviewSummary(day(0, 1))).toContain("1 task ready");
    expect(fallbackReviewSummary(day(0, 0, 1))).toContain("1 focus session");
    expect(fallbackReviewSummary(day(0, 0))).toBe("A quiet day. Rest up and start fresh tomorrow.");
  });
});

describe("DayReview persistence and demo", () => {
  it("saves one file per day", async () => {
    const store = new InMemoryDocumentStore();
    const repository = new DayReviewRepository(store);
    expect(await repository.load(OCT1)).toBeUndefined();

    const saved = { ...reviewDay(checklist(), [], LA), summary: "Good day." };
    await repository.save(saved);
    expect(repository.documentName(OCT1)).toBe("Reviews/2026-10-01.json");
    expect(await new DayReviewRepository(store).load(OCT1)).toEqual(saved);

    await repository.save({ ...saved, summary: "Even better." });
    expect((await repository.load(OCT1))?.summary).toBe("Even better.");
  });

  it("makes the sample review realistic", () => {
    const sample = sampleDayReview(OCT1, LA);
    expect(sample.done.length).toBe(2);
    expect(sample.carryingOver).toEqual(["Read chapter 4"]);
    expect(sample.focusSessions).toBeGreaterThan(0);
    const summary = sample.summary ?? "";
    /* The canned summary already fits the card. */
    expect(reviewSummary(summary)).toBe(summary);
  });

  it("carries over study work in the medicine sample", () => {
    const sample = sampleDayReview(OCT1, LA, "medicine");
    expect(sample.carryingOver).toEqual(["Cardio practice questions", "Renal notes"]);
    const summary = sample.summary ?? "";
    expect(reviewSummary(summary)).toBe(summary);
    expect(summary).toContain("cardio questions");
  });
});

describe("DayReview study stats", () => {
  const tally: StudyDayTally = { minutes: 185, sessions: 3, points: 215 };

  it("keeps the study tally and shared goal counts", () => {
    const idle = new ProgressItem({
      id: "q",
      source: "anki",
      title: "Questions",
      completed: 0,
      target: 0,
      unit: "questions",
      waitsForStart: false,
    });
    const result = reviewDay(checklist(), [], LA, tally, [ankiReviews(112, 432), idle]);
    expect(result.study).toEqual(tally);
    /* A goal with nothing due and nothing done is left out. */
    expect(result.progress).toEqual([{ title: "Anki reviews", count: 112, unit: "cards" }]);
  });

  it("shows study time, sessions, cards and points", () => {
    const result = reviewDay(checklist(), [], LA, tally, [ankiReviews(112, 432)]);
    expect(reviewStats(result).map((stat) => stat.text)).toEqual(["3h 5m · 3 sessions", "112 cards", "215 pts"]);
  });

  it("falls back to focus sessions without a study tally", () => {
    const result = reviewDay(checklist(), [], LA);
    expect(reviewStats(result).map((stat) => stat.text)).toEqual(["No focus sessions today"]);
    expect(reviewStats({ ...result, focusSessions: 1, focusMinutes: 60 }).map((stat) => stat.text)).toEqual([
      "1 focus session · 1h",
    ]);
  });

  it("shows a study day with nothing logged yet", () => {
    const result = reviewDay(new PlannerDay(OCT1), [], LA, { minutes: 0, sessions: 0, points: 0 }, [ankiReviews(0, 200)]);
    expect(reviewStats(result).map((stat) => stat.text)).toEqual(["No study yet", "0 cards", "0 pts"]);
    expect(reviewIsEmpty(result)).toBe(true);
  });

  it("finds study time alone worth reviewing", () => {
    const result = reviewDay(new PlannerDay(OCT1), [], LA, { minutes: 50, sessions: 1, points: 60 });
    expect(reviewIsEmpty(result)).toBe(false);
    expect(fallbackReviewSummary(result)).toBe("You put in 50 min of study today. Rest up and start fresh tomorrow.");
  });

  it("mentions study and shared goals in the prompt only when present", () => {
    expect(dayReviewPrompt(reviewDay(checklist(), [], LA))).not.toContain("Studied");
    const prompt = dayReviewPrompt(reviewDay(checklist(), [], LA, tally, [ankiReviews(112, 432)]));
    expect(prompt).toContain("Studied: 185 minutes over 3 sessions, 215 points earned");
    expect(prompt).toContain("Anki reviews: 112 cards done");
  });

  it("still loads reviews saved before study stats", () => {
    const json = '{"date":"2026-10-01","done":["A"],"carryingOver":[],"focusSessions":1,"focusMinutes":25,"summary":"Nice."}';
    const loaded = DAY_REVIEW_SCHEMA.decode(json, decodeDayReview);
    expect(loaded.done).toEqual(["A"]);
    expect(loaded.study).toBeUndefined();
    expect(loaded.progress).toEqual([]);
    expect(loaded.summary).toBe("Nice.");
  });

  it("round-trips a study review through JSON", () => {
    const result = reviewDay(checklist(), [], LA, tally, [ankiReviews(112, 432)]);
    expect(DAY_REVIEW_SCHEMA.decode(DAY_REVIEW_SCHEMA.encode(encodeDayReview(result)), decodeDayReview)).toEqual(result);
  });

  it("follows the points rules in the sample tally", () => {
    /* StudyDayTally.sample: three finished 50-minute blocks and an unfinished 35. */
    const blocks: [number, boolean][] = [
      [50, true],
      [50, true],
      [50, true],
      [35, false],
    ];
    const sample = {
      minutes: blocks.reduce((sum, [minutes]) => sum + minutes, 0),
      sessions: blocks.filter(([, done]) => done).length,
      points: blocks.reduce((sum, [minutes, done]) => sum + PetPointsRules.points(minutes, done), 0),
    };
    expect(sample).toEqual(tally);
  });
});
