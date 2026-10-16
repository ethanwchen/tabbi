import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { allAINetworkAccess } from "../../core/ai/aiProviderID";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { placeholderPanel } from "../placeholderPanel";

/*
 * Port of ScheduleModule: the day on a timeline with the free time in
 * between. Its calendar is the ICS feeds Today reads, so on Windows it asks
 * for no Calendars permission.
 */
export const SCHEDULE_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.schedule,
    title: "Schedule",
    symbol: "calendar.day.timeline.left",
    category: MODULE_CATEGORIES.productivity,
    accent: { red: 1.0, green: 0.5, blue: 0.42 },
    /* Refine asks the AI the user picks. */
    network: allAINetworkAccess(),
  },
  {
    title: () => tr("Schedule"),
    summary: () => tr("Your day on a timeline, with the free time in between."),
  },
);

export const ScheduleModule = defineModule(SCHEDULE_DESCRIPTOR, () => ({
  Panel: placeholderPanel(SCHEDULE_DESCRIPTOR),
}));
