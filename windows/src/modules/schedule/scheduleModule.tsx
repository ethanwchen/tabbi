import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { allAINetworkAccess } from "../../core/ai/aiProviderID";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { todayPlanSettingsFromKit } from "../../core/planner/todayPlanSettings";
import { calendarSource } from "../planner/calendarServices";
import { plannedBlocks } from "../planner/plannedBlocks";
import { SchedulePanel } from "./SchedulePanel";
import { ScheduleStore } from "./scheduleStore";
import "./schedule.css";

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

/** The snapshot harness's states: the Week view, a selected block, each plan state, the other days, and the empty states. */
export const SCHEDULE_SNAPSHOT_STATES = [
  "week",
  "selected",
  "plan",
  "plan-selected",
  "plan-refining",
  "plan-week",
  "plan-week-selected",
  "yesterday",
  "tomorrow",
  "tomorrow-plan",
  "no-calendar",
  "free-day",
] as const;

export const ScheduleModule = defineModule(
  SCHEDULE_DESCRIPTOR,
  (context) => {
    const store = new ScheduleStore(context, calendarSource(context), plannedBlocks(context));
    /* Plan uses Today's planning settings, so a kit sizes reviews and buffers the same way in both places. */
    store.planSettings = todayPlanSettingsFromKit(context.activeKit?.defaults);
    const stops = [
      context.kitApplied((application) => {
        store.planSettings = todayPlanSettingsFromKit(application.kit.defaults);
      }),
      context.snapshot.subscribe(() => {
        const snapshot = context.snapshot.get();
        store.sharedTasks = snapshot.openTasks;
        store.progress = snapshot.progress;
      }),
    ];
    const openConnections = () => {
      void context.host.openSettings("connections").catch((error: unknown) => context.logger.error("could not open Settings", error));
    };

    function Panel() {
      return <SchedulePanel context={context} store={store} openConnections={openConnections} />;
    }

    return {
      store,
      Panel,
      showSnapshotState: (state: string) => {
        switch (state) {
          case "plan":
            return store.showForSnapshot("today", true);
          case "yesterday":
            return store.showForSnapshot("yesterday");
          case "tomorrow":
            return store.showForSnapshot("tomorrow");
          case "tomorrow-plan":
            return store.showForSnapshot("tomorrow", true);
          case "week":
          case "selected":
          case "plan-selected":
          case "plan-refining":
          case "plan-week":
          case "plan-week-selected":
          case "no-calendar":
          case "free-day":
            store.showForSnapshot("today");
            store.showPreviewForSnapshot(state);
            return;
          default:
            return store.showForSnapshot("today");
        }
      },
      dispose: () => {
        for (const stop of stops) stop();
      },
    };
  },
  { snapshotStates: SCHEDULE_SNAPSHOT_STATES },
);
