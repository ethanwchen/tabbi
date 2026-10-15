import { describe, expect, it } from "vitest";
import { instantOf } from "../../../src/core/calendar/zonedCalendar";
import { BUNDLED_KITS } from "../../../src/core/kits/bundledKits";
import { kitDefaults } from "../../../src/core/kits/kitManifest";
import type { JSONValue } from "../../../src/core/persistence/json";
import { DayPlanContext } from "../../../src/core/planner/dayPlan";
import type { ProgressItem } from "../../../src/core/planner/providedWork";
import { todayPlanSettings, todayPlanSettingsFromKit, todayStudyPlan } from "../../../src/core/planner/todayPlanSettings";
import { upcomingEvent } from "../../../src/core/planner/upcomingEvent";
import { StudyMethod } from "../../../src/core/studyMethods/studyMethod";
import { StudyMethodMenu } from "../../../src/core/studyMethods/studyMethodMenu";

/* Port of TodayPlanSettingsTests: reading the kit and the study-aware plan. */

const LA = "America/Los_Angeles";

function at(hour: number, minute = 0): number {
  return instantOf({ year: 2026, month: 10, day: 1, hour, minute }, LA);
}

function kit(planner: Record<string, JSONValue> | undefined, studyMethod?: string) {
  const sections: Record<string, JSONValue> = planner === undefined ? {} : { planner };
  if (studyMethod !== undefined) sections.study = { method: studyMethod };
  return kitDefaults({ moduleSettings: sections });
}

describe("TodayPlanSettings from a kit", () => {
  it("plans on device for kits without a section", () => {
    expect(todayPlanSettingsFromKit(undefined)).toEqual(todayPlanSettings());
    expect(todayPlanSettingsFromKit(kitDefaults()).planMode).toBe("local");
  });

  it("reads every key", () => {
    const settings = todayPlanSettingsFromKit(
      kit(
        {
          planMode: "study",
          reviewsFirst: false,
          eventBufferMinutes: 15,
          studyBlockTitle: "  Shelf prep  ",
          secondsPerCard: 6,
          upNextEvents: "lectures and labs",
          dayEndHour: 21,
          sampleDay: "medicine",
        },
        "fiftyTwoSeventeen",
      ),
    );
    expect(settings.planMode).toBe("study");
    expect(settings.studyMethod).toBe(StudyMethod.fiftyTwoSeventeen);
    expect(settings.reviewsFirst).toBe(false);
    expect(settings.eventBufferMinutes).toBe(15);
    expect(settings.studyBlockTitle).toBe("Shelf prep");
    expect(settings.secondsPerCard).toBe(6);
    expect(settings.upNextEvents).toBe("lectures and labs");
    expect(settings.dayEndHour).toBe(21);
    expect(settings.sampleDay).toBe("medicine");
  });

  it("falls back to defaults for bad values", () => {
    const settings = todayPlanSettingsFromKit(
      kit(
        {
          planMode: "astrology",
          reviewsFirst: "yes",
          eventBufferMinutes: -5,
          studyBlockTitle: "   ",
          secondsPerCard: 0,
          upNextEvents: " ",
          dayEndHour: 30,
          sampleDay: "pirate",
        },
        "nope",
      ),
    );
    const defaults = todayPlanSettings();
    expect(settings.planMode).toBe("local");
    expect(settings.studyMethod).toBe(defaults.studyMethod);
    expect(settings.reviewsFirst).toBe(true);
    expect(settings.eventBufferMinutes).toBe(0);
    expect(settings.studyBlockTitle).toBe("Study block");
    expect(settings.secondsPerCard).toBe(1);
    expect(settings.upNextEvents).toBe("meetings and calls");
    /* Past 10 pm clamps to the latest end. */
    expect(settings.dayEndHour).toBe(22);
    expect(todayPlanSettingsFromKit(kit({ dayEndHour: "late" })).dayEndHour).toBe(18);
    expect(settings.sampleDay).toBe("work");
  });

  it("clamps out-of-range numbers", () => {
    const huge = todayPlanSettingsFromKit(kit({ eventBufferMinutes: 1e20, dayEndHour: -1e30 }));
    expect(huge.eventBufferMinutes).toBe(240);
    expect(huge.dayEndHour).toBe(0);
  });

  it("plans study days for the medicine kit", () => {
    const medicine = BUNDLED_KITS.get("medicine");
    expect(medicine).toBeDefined();
    const settings = todayPlanSettingsFromKit(medicine?.defaults);
    expect(settings.planMode).toBe("study");
    expect(settings.studyMethod?.kind).toBe(StudyMethodMenu.fromKit(medicine?.defaults.moduleSettings.study).startingKind);
    expect(settings.reviewsFirst).toBe(true);
    /* Study days run into the evening. */
    expect(settings.dayEndHour).toBe(21);
    /* The demo shows a med student's day. */
    expect(settings.sampleDay).toBe("medicine");
  });
});

describe("TodayPlanSettings planning", () => {
  it("turns unfinished goals into review blocks", () => {
    const settings = todayPlanSettings({
      planMode: "study",
      studyMethod: StudyMethod.fiftyTwoSeventeen,
      studyBlockTitle: "Shelf prep",
      secondsPerCard: 10,
    });
    const context = new DayPlanContext({ now: at(8), events: [], tasks: [], timeZone: LA });
    const goal = (id: string, title: string, completed: number, target: number): ProgressItem => ({
      id,
      source: "anki",
      title,
      completed,
      target,
      unit: "cards",
      waitsForStart: false,
    });
    const plan = todayStudyPlan(settings, context, [goal("reviews", "Anki reviews", 50, 230), goal("done", "New cards", 20, 20)]);

    /* 180 cards at 10 s is 30 min, first thing; the finished goal gets no block. */
    const reviews = plan.blocks.filter((block) => block.kind === "reviews");
    expect(reviews.map((block) => block.title)).toEqual(["Anki reviews"]);
    expect(reviews[0]?.start).toBe(at(8));
    expect(reviews[0]?.end).toBe(at(8, 30));

    const study = plan.blocks.filter((block) => block.kind === "study");
    expect(study.length).toBeGreaterThan(0);
    expect(study.every((block) => block.end - block.start === 52 * 60)).toBe(true);
    expect(study.every((block) => block.title === "Shelf prep")).toBe(true);
    for (let index = 1; index < plan.blocks.length; index++) {
      expect(plan.blocks[index - 1]?.end ?? 0).toBeLessThanOrEqual(plan.blocks[index]?.start ?? 0);
    }
  });

  it("keeps the buffer around events", () => {
    const settings = todayPlanSettings({ planMode: "study", eventBufferMinutes: 15 });
    const lecture = upcomingEvent({ id: "lecture", title: "Lecture", start: at(10), end: at(12) });
    const context = new DayPlanContext({ now: at(8), events: [lecture], tasks: [], timeZone: LA });
    const plan = todayStudyPlan(settings, context, []);
    expect(plan.blocks.length).toBeGreaterThan(0);
    for (const block of plan.blocks) expect(block.end <= at(9, 45) || block.start >= at(12, 15)).toBe(true);
  });
});
