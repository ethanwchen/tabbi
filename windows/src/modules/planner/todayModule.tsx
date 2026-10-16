import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { allAINetworkAccess } from "../../core/ai/aiProviderID";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { ONBOARDING_SETUP_STEPS } from "../../core/onboarding/onboardingSetupStep";
import { TODAY_PLAN_KIT_SCHEMA } from "../../core/planner/todayPlanSettings";
import { placeholderPanel } from "../placeholderPanel";

/*
 * Port of TodayModule: the to-do list, what is up next and a day plan.
 * Windows reads calendars from ICS addresses the user adds, which needs no
 * system permission (the Mac asks for Calendars), only notifications.
 */
export const TODAY_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.planner,
    title: "Today",
    symbol: "checklist",
    category: MODULE_CATEGORIES.productivity,
    accent: { red: 0.66, green: 0.55, blue: 1.0 },
    permissions: ["notifications"],
    /* Plan my day and Wrap up ask the AI the user picks. */
    network: allAINetworkAccess(),
    kitSettings: TODAY_PLAN_KIT_SCHEMA,
    setup: [ONBOARDING_SETUP_STEPS.calendar],
  },
  {
    title: () => tr("Today"),
    summary: () => tr("Your to-do list, what is up next, and a day plan."),
  },
);

export const TodayModule = defineModule(TODAY_DESCRIPTOR, () => ({
  Panel: placeholderPanel(TODAY_DESCRIPTOR),
}));
