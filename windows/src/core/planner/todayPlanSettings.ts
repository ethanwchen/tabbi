import type { Seconds } from "../time";
import type { KitDefaults } from "../kits/kitManifest";
import { KitSettingsSchema, kitSetting } from "../kits/kitSettingsSchema";
import { KIT_LIMITS } from "../kits/kitValidation";
import { MODULE_IDS } from "../modules/moduleId";
import { isJSONObject, type JSONValue } from "../persistence/json";
import { StudyMethod } from "../studyMethods/studyMethod";
import { kitStartingKind } from "../studyMethods/studyMethodMenu";
import { DEFAULT_DAY_END_HOUR, LATEST_DAY_END_HOUR, type DayPlanContext } from "./dayPlan";
import { normalizedTitle } from "./plannerDay";
import type { ProgressItem } from "./providedWork";
import {
  DEFAULT_SECONDS_PER_CARD,
  planStudyDay,
  reviewWork,
  studyDayPreferencesForMethod,
  type StudyDayPlan,
  type StudyDayPreferences,
  type StudyReviewWork,
} from "./studyDayPlan";

/**
 * Port of TodayPlanSettings.PlanMode: `local` plans on device with the
 * schedule planner, `claude` asks the AI the user picked (the raw value
 * predates other providers and stays for kit files), `study` plans study
 * blocks on device.
 */
export type PlanMode = "local" | "claude" | "study";
export const PLAN_MODES: readonly PlanMode[] = ["local", "claude", "study"];

/** Port of PlannerSampleDay: which realistic day demo mode shows on Today. */
export type PlannerSampleDay = "work" | "medicine";
export const PLANNER_SAMPLE_DAYS: readonly PlannerSampleDay[] = ["work", "medicine"];

/**
 * Port of TodayPlanSettings: how Today's Plan my day works for the active
 * kit, read from the kit's `moduleSettings.planner` section. Every key is
 * optional; kits without the section plan on device.
 */
export interface TodayPlanSettings {
  readonly planMode: PlanMode;
  /** The kit's study method, whose lengths study blocks and local blocks use. */
  readonly studyMethod?: StudyMethod;
  readonly reviewsFirst: boolean;
  readonly eventBufferMinutes: number;
  /** Title for study blocks once every open task has one. */
  readonly studyBlockTitle: string;
  /** Typical time to answer one review card, for sizing review blocks. */
  readonly secondsPerCard: Seconds;
  /** What the user's calendar holds, lowercase, for Up next's empty states. */
  readonly upNextEvents: string;
  /** When planned work usually stops, 0 to 22. */
  readonly dayEndHour: number;
  /** The day demo mode shows on Today; never affects real data. */
  readonly sampleDay: PlannerSampleDay;
}

/** Builds settings with the Swift initializer's defaults and clamps. */
export function todayPlanSettings(input: Partial<TodayPlanSettings> = {}): TodayPlanSettings {
  const settings: { -readonly [Key in keyof TodayPlanSettings]: TodayPlanSettings[Key] } = {
    planMode: input.planMode ?? "local",
    reviewsFirst: input.reviewsFirst ?? true,
    eventBufferMinutes: Math.max(input.eventBufferMinutes ?? 10, 0),
    studyBlockTitle: normalizedTitle(input.studyBlockTitle ?? "Study block") ?? "Study block",
    secondsPerCard: Math.max(input.secondsPerCard ?? DEFAULT_SECONDS_PER_CARD, 1),
    upNextEvents: normalizedTitle(input.upNextEvents ?? "meetings and calls") ?? "meetings and calls",
    dayEndHour: Math.min(Math.max(input.dayEndHour ?? DEFAULT_DAY_END_HOUR, 0), LATEST_DAY_END_HOUR),
    sampleDay: input.sampleDay ?? "work",
  };
  if (input.studyMethod !== undefined) settings.studyMethod = input.studyMethod;
  return settings;
}

/* `value` rounded and clamped to 0...limit before it becomes a whole number. */
function wholeNumber(value: number, limit: number): number {
  return Math.trunc(Math.min(Math.max(Math.sign(value) * Math.round(Math.abs(value)), 0), limit));
}

/**
 * The kit's settings, leniently: values of the wrong type or unknown modes
 * fall back to the defaults rather than failing the whole kit. The study
 * method is the kit's starting one from its Study section.
 */
export function todayPlanSettingsFromKit(kit: KitDefaults | undefined): TodayPlanSettings {
  const raw: JSONValue | undefined = kit?.moduleSettings[MODULE_IDS.planner];
  const section = isJSONObject(raw) ? raw : {};
  const text = (key: string) => (typeof section[key] === "string" ? (section[key] as string) : undefined);
  const number = (key: string) => (typeof section[key] === "number" ? (section[key] as number) : undefined);
  const flag = (key: string) => (typeof section[key] === "boolean" ? (section[key] as boolean) : undefined);
  const mode = text("planMode");
  const sample = text("sampleDay");
  const kind = kitStartingKind(kit);
  const buffer = number("eventBufferMinutes");
  const endHour = number("dayEndHour");
  return todayPlanSettings({
    ...(mode !== undefined && (PLAN_MODES as readonly string[]).includes(mode) ? { planMode: mode as PlanMode } : {}),
    ...(kind === undefined ? {} : { studyMethod: StudyMethod.preset(kind) }),
    ...(flag("reviewsFirst") === undefined ? {} : { reviewsFirst: flag("reviewsFirst") }),
    ...(buffer === undefined ? {} : { eventBufferMinutes: wholeNumber(buffer, 240) }),
    ...(text("studyBlockTitle") === undefined ? {} : { studyBlockTitle: text("studyBlockTitle") }),
    ...(number("secondsPerCard") === undefined ? {} : { secondsPerCard: number("secondsPerCard") }),
    ...(text("upNextEvents") === undefined ? {} : { upNextEvents: text("upNextEvents") }),
    ...(endHour === undefined ? {} : { dayEndHour: wholeNumber(endHour, 24) }),
    ...(sample !== undefined && (PLANNER_SAMPLE_DAYS as readonly string[]).includes(sample)
      ? { sampleDay: sample as PlannerSampleDay }
      : {}),
  });
}

/** The keys `todayPlanSettingsFromKit` reads, for Today's descriptor. */
export const TODAY_PLAN_KIT_SCHEMA = new KitSettingsSchema({
  planMode: kitSetting.choice(PLAN_MODES),
  reviewsFirst: kitSetting.bool,
  eventBufferMinutes: kitSetting.number(0, 240),
  studyBlockTitle: kitSetting.text(KIT_LIMITS.maxTaskLength),
  secondsPerCard: kitSetting.number(1, 600),
  upNextEvents: kitSetting.text(KIT_LIMITS.maxNameLength),
  dayEndHour: kitSetting.number(0, LATEST_DAY_END_HOUR),
  sampleDay: kitSetting.choice(PLANNER_SAMPLE_DAYS),
});

/** Block lengths and wording for the study day planner (Pomodoro when the kit names no method). */
export function planStudyPreferences(settings: TodayPlanSettings): StudyDayPreferences {
  return studyDayPreferencesForMethod(settings.studyMethod ?? StudyMethod.pomodoro, {
    reviewsFirst: settings.reviewsFirst,
    eventBufferMinutes: settings.eventBufferMinutes,
    studyTitle: settings.studyBlockTitle,
  });
}

/** The review work the study planner sizes from shared goals, at the kit's seconds per card. */
export function studyReviews(settings: TodayPlanSettings, progress: readonly ProgressItem[]): StudyReviewWork[] {
  return progress.map((item) => reviewWork(item, settings.secondsPerCard)).filter((work) => work !== undefined);
}

/** A study-aware plan: one review block per unfinished shared goal, then study blocks and breaks. */
export function todayStudyPlan(settings: TodayPlanSettings, context: DayPlanContext, progress: readonly ProgressItem[]): StudyDayPlan {
  return planStudyDay(context, studyReviews(settings, progress), planStudyPreferences(settings));
}
