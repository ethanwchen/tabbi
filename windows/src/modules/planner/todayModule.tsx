import { lazyView } from "../../app/lazyView";
import { localizedDescriptor } from "../../app/descriptor";
import type { ModuleContext } from "../../app/context";
import { defineModule } from "../../app/module";
import { derived } from "../../app/store";
import { requestTab } from "../../app/tabSelection";
import { allAINetworkAccess } from "../../core/ai/aiProviderID";
import { kitStarterTasks } from "../../core/kits/kitApplication";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS, type ModuleID } from "../../core/modules/moduleId";
import { ONBOARDING_SETUP_STEPS } from "../../core/onboarding/onboardingSetupStep";
import { PlannerDay, providedTaskFromItem, type PlannerItem } from "../../core/planner/plannerDay";
import { plannerDayKeyOf } from "../../core/planner/plannerDayKey";
import { todayPlanSettingsFromKit, TODAY_PLAN_KIT_SCHEMA } from "../../core/planner/todayPlanSettings";
import { moduleProvision, type ModuleProvision } from "../../core/providers/moduleProvision";
import type { ProvidedAction } from "../../core/providers/progressItem";
import type { UpcomingEvent } from "../../core/planner/upcomingEvent";
import type { FocusTimer } from "../../core/focus/focusTimer";
import { settingsCleanedName } from "../../core/settings/appSettings";
import { TICKER_KINDS } from "../../core/ticker/tickerKind";
import { calendarSource } from "./calendarServices";
import { DayPlanStore } from "./dayPlanStore";
import { DayReviewStore } from "./dayReviewStore";
import { FocusCardActions } from "./focusCardActions";
import { plannedBlocks } from "./plannedBlocks";
import { PlannerStore } from "./plannerStore";
import { UpNextStore } from "./upNextStore";
import "./planner.css";

/* The views load on first use; the store and descriptor stay eager. */
const TodayCalendarSetupView = lazyView(() => import("./TodayCalendarSetupView"), "TodayCalendarSetupView");
const TodayPanel = lazyView(() => import("./TodayPanel"), "TodayPanel");

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

/**
 * The snapshot harness's states: each day the stepper reaches, the plan
 * and review in every phase, the fresh day, the evening (Wrap up leads),
 * and the calendar card without a feed or on a free day.
 */
export const TODAY_SNAPSHOT_STATES = [
  "yesterday",
  "tomorrow",
  "empty",
  "evening",
  "plan",
  "plan-refining",
  "planning",
  "plan-failed",
  "plan-tomorrow",
  "review",
  "review-loading",
  "no-calendar",
  "free-day",
] as const;

/** Builds Today's stores over the shared calendar, focus timer and kept blocks. */
export function createTodayStores(context: ModuleContext) {
  const planSettings = todayPlanSettingsFromKit(context.activeKit?.defaults);
  const planned = plannedBlocks(context);
  const upNext = new UpNextStore(context, calendarSource(context), planned);
  const plan = new DayPlanStore(context, upNext, planned, planSettings);
  const review = new DayReviewStore(context);
  const store = new PlannerStore(context, { upNext, plan, review }, planSettings);
  const focus = new FocusCardActions(context);
  return { store, focus, upNext };
}

export const TodayModule = defineModule(
  TODAY_DESCRIPTOR,
  (context) => {
    const { store, focus, upNext } = createTodayStores(context);
    const stops: (() => void)[] = [];
    /* The starter tasks the last kit switch added, which undoing it takes back. */
    let starterTasksAdded: PlannerItem[] = [];
    /* A pinned hour for the "evening" and plan snapshots; undefined follows the clock. */
    let eveningOverride: boolean | undefined = context.isSnapshot ? false : undefined;

    const followSettings = () => {
      const settings = context.settings.current;
      store.setFocusClockOwner(context.settings.catalog.focusClockOwner(settings.modules));
      store.setFocusTabOn(settings.modules.isEnabled(MODULE_IDS.focus));
      store.setDisplayName(settingsCleanedName(settings));
      store.setPlanSettings(todayPlanSettingsFromKit(context.activeKit?.defaults));
    };
    followSettings();
    stops.push(context.settings.settings.subscribe(followSettings));
    stops.push(store.followSharedWork());
    stops.push(
      context.kitApplied((application) => {
        /* Also when re-applying the same kit, which may have been re-imported. */
        store.setPlanSettings(todayPlanSettingsFromKit(application.kit.defaults));
        switch (application.kind) {
          case "switched":
            starterTasksAdded = store.addStarterTasks(kitStarterTasks(application.kit, application.answers));
            break;
          case "undo":
            store.takeBackStarterTasks(starterTasksAdded);
            starterTasksAdded = [];
            break;
          case "reset":
            break;
        }
      }),
    );

    let stopPreview: (() => void) | undefined;
    const openModule = (id: ModuleID, action?: ProvidedAction) => requestTab(context, id, action);
    const openConnections = () => {
      void context.host.openSettings("connections").catch((error: unknown) => context.logger.error("could not open Settings", error));
    };

    function Panel() {
      return <TodayPanel context={context} store={store} focus={focus} openModule={openModule} openConnections={openConnections} eveningOverride={eveningOverride} />;
    }

    /** The checklist, today's calendar events, and the focus timer. Kept while none of the three changed, so the hub hears real changes only. */
    let lastProvision: { day: PlannerDay; events: readonly UpcomingEvent[]; timer: FocusTimer; provision: ModuleProvision } | undefined;
    const provision = derived([store, upNext, focus.service], (): ModuleProvision => {
      const day = store.state.day;
      const events = upNext.state.events;
      const timer = focus.service.state.timer;
      if (lastProvision !== undefined && lastProvision.day === day && lastProvision.events === events && lastProvision.timer === timer) {
        return lastProvision.provision;
      }
      const next = moduleProvision({
        tasks: day.items.map((item) => providedTaskFromItem(item, context.id)),
        events,
        focus: timer.provided(context.id),
      });
      lastProvision = { day, events, timer, provision: next };
      return next;
    });

    return {
      store,
      Panel,
      provision,
      setupView: (step) =>
        step.id === ONBOARDING_SETUP_STEPS.calendar.id ? () => <TodayCalendarSetupView context={context} store={store} openConnections={openConnections} /> : undefined,
      start: () => {
        /* Keep the calendar reloading while the closed island can show the next meeting. */
        const watched = context.closedPreview.watchedKinds;
        const follow = () => upNext.setPreviewWatching(watched.get().has(TICKER_KINDS.meeting));
        follow();
        stopPreview = watched.subscribe(follow);
      },
      stop: () => {
        stopPreview?.();
        stopPreview = undefined;
        upNext.setPreviewWatching(false);
      },
      showSnapshotState: async (state: string) => {
        /* Demo snapshots pin the hour, as the Mac's TABBI_PLANNER_PREVIEW does: daytime unless the state is the evening. */
        eveningOverride = state === "evening";
        switch (state) {
          case "yesterday":
            return store.showForSnapshot("yesterday");
          case "tomorrow":
            return store.showForSnapshot("tomorrow");
          case "plan-tomorrow":
            return store.showForSnapshot("tomorrow", true);
          case "empty":
            store.showDayForSnapshot(new PlannerDay(plannerDayKeyOf(context.now(), context.timeZone())));
            return;
          case "plan":
            return store.showForSnapshot("today", true);
          case "plan-refining":
            await store.showForSnapshot("today", true);
            store.plan.showPhaseForSnapshot("refining");
            return;
          case "planning":
            store.show("today");
            store.plan.showPhaseForSnapshot("planning");
            return;
          case "plan-failed":
            store.show("today");
            store.plan.showPhaseForSnapshot("failed");
            return;
          case "review":
          case "review-loading": {
            store.show("today");
            const study = store.state.planSettings.planMode === "study";
            store.review.showForSnapshot(store.state.day, {
              loading: state === "review-loading",
              study,
              sampleDay: store.state.planSettings.sampleDay,
              progress: study ? store.state.sharedProgress : [],
            });
            return;
          }
          case "no-calendar":
            store.show("today");
            upNext.showForSnapshot("noCalendar");
            return;
          case "free-day":
            store.show("today");
            upNext.showForSnapshot("freeDay");
            return;
          default:
            store.show("today");
        }
      },
      dispose: () => {
        for (const stop of stops) stop();
      },
    };
  },
  { snapshotStates: TODAY_SNAPSHOT_STATES },
);
