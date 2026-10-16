import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { KitSettingsSchema, kitSetting } from "../../core/kits/kitSettingsSchema";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { ONBOARDING_SETUP_STEPS } from "../../core/onboarding/onboardingSetupStep";
import { DAILY_GOAL_MAX, DAILY_GOAL_MIN } from "../../core/studyMethods/studyDailyGoal";
import { STUDY_METHOD_KINDS } from "../../core/studyMethods/studyMethodFile";
import { placeholderPanel } from "../placeholderPanel";

const methodChoice = kitSetting.choice(STUDY_METHOD_KINDS);

/* Port of StudyMethodMenu.kitSettingFields plus StudyDailyGoal.kitSettingType: the methods offered, the one to start with, and the daily goal. */
export const STUDY_KIT_SCHEMA = new KitSettingsSchema({
  methods: kitSetting.list(methodChoice, STUDY_METHOD_KINDS.length),
  method: methodChoice,
  dailyGoalMinutes: kitSetting.number(DAILY_GOAL_MIN, DAILY_GOAL_MAX),
});

/* Port of StudyModule: quick countdowns and focus methods, with a clock of its own. */
export const STUDY_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.study,
    title: "Timer",
    symbol: "timer",
    category: MODULE_CATEGORIES.study,
    accent: { red: 1.0, green: 0.62, blue: 0.26 },
    ownsFocusClock: true,
    kitSettings: STUDY_KIT_SCHEMA,
    setup: [ONBOARDING_SETUP_STEPS.studyMethod],
  },
  {
    title: () => tr("Timer"),
    summary: () => tr("Quick countdowns and focus methods with sounds."),
  },
);

export const StudyModule = defineModule(STUDY_DESCRIPTOR, () => ({
  Panel: placeholderPanel(STUDY_DESCRIPTOR),
}));
