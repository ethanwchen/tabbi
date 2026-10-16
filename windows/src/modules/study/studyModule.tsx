import { lazyView } from "../../app/lazyView";
import type { ModuleContext } from "../../app/context";
import { localizedDescriptor } from "../../app/descriptor";
import { defineModule, type SetupStepProps } from "../../app/module";
import { derived } from "../../app/store";
import { KitSettingsSchema, kitSetting } from "../../core/kits/kitSettingsSchema";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { ONBOARDING_SETUP_STEPS } from "../../core/onboarding/onboardingSetupStep";
import { moduleProvision, type ModuleProvision } from "../../core/providers/moduleProvision";
import { ProvidedPartySession } from "../../core/providers/providedParty";
import { DAILY_GOAL_MAX, DAILY_GOAL_MIN, StudyDailyGoal } from "../../core/studyMethods/studyDailyGoal";
import { sharedStudyFocus } from "../../core/studyMethods/studyFocusShare";
import { STUDY_METHOD_KINDS, type StudyMethodKind } from "../../core/studyMethods/studyMethodFile";
import { StudyMethodMenu } from "../../core/studyMethods/studyMethodMenu";
import { studyPet } from "../closet/closetServices";
import { serviceKey } from "../../app/sharedServices";
import { hostChannel, quietChannel } from "../../app/windowChannel";
import { isEphemeral } from "../../core/modules/runMode";
import { focusMode } from "../focus/focusServices";
import { ModulePreferences } from "../focus/modulePreferences";
import { StudyStore } from "./studyStore";

/* The views load on first use; the store and descriptor stay eager. */
const StudyMethodSetupView = lazyView(() => import("./studyMethodSetupView"), "StudyMethodSetupView");
const StudyPanel = lazyView(() => import("./studyPanel"), "StudyPanel");

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

/**
 * The states the snapshot harness draws besides the running demo Pomodoro:
 * the in-island overlays, the demo paused (so the pet dozes), each method
 * whose timer looks different, and a party's shared session. The Mac's
 * `TABBI_STUDY_SNAPSHOT` values, with `-` for `:`.
 */
const STUDY_SNAPSHOT_STATES = [
  "picker",
  "sounds",
  "custom",
  "paused",
  "info-pomodoro",
  "method-timer",
  "method-flowtime",
  "method-ankiSprint",
  "method-questionBlock",
  "party",
] as const;

const STUDY_PREFERENCES = serviceKey<ModulePreferences>("study.preferences");

/** The Timer's preferences document (`Study/preferences.json`): the session, the deep focus switch and the user's lengths. */
export function studyPreferences(context: ModuleContext): ModulePreferences {
  return context.shared.resolve(STUDY_PREFERENCES, () => {
    const store = isEphemeral(context.runMode) ? undefined : context.storage.folder("Study");
    const channel = context.isSnapshot ? quietChannel : hostChannel(context.host, "study/preferences");
    return new ModulePreferences(store, channel);
  });
}

function isMethodKind(value: string): value is StudyMethodKind {
  return (STUDY_METHOD_KINDS as readonly string[]).includes(value);
}

function provisionsEqual(a: ModuleProvision, b: ModuleProvision): boolean {
  const sameFocus = a.focus === undefined || b.focus === undefined ? a.focus === b.focus : a.focus.equals(b.focus);
  const pa = a.progress[0];
  const pb = b.progress[0];
  const sameProgress = pa !== undefined && pb !== undefined && pa.completed === pb.completed && pa.target === pb.target;
  const sameStudy = a.study?.minutes === b.study?.minutes && a.study?.sessions === b.study?.sessions && a.study?.points === b.study?.points;
  return sameFocus && sameProgress && sameStudy;
}

export const StudyModule = defineModule(
  STUDY_DESCRIPTOR,
  (context) => {
    const kit = context.activeKit?.defaults;
    const mode = focusMode(context);
    const pet = studyPet(context);
    const store = new StudyStore(context, {
      menu: StudyMethodMenu.fromKit(kit),
      goal: StudyDailyGoal.fromKit(kit),
      preferences: studyPreferences(context),
      focusMode: mode,
      petProfile: pet.state.profile,
    });
    pet.subscribe(() => store.followPet(pet.state.profile));
    context.snapshot.subscribe(() => store.followSnapshot(context.snapshot.get()));
    store.followSnapshot(context.snapshot.get());
    context.kitApplied((application) => {
      const defaults = application.kit.defaults;
      /* Undo keeps the user's method when the earlier kit offers it. */
      store.use(StudyMethodMenu.fromKit(defaults), StudyDailyGoal.fromKit(defaults), application.kind !== "undo");
    });
    const onUnload = () => store.interrupt();

    function Panel() {
      return <StudyPanel store={store} focusMode={mode} context={context} accent={STUDY_DESCRIPTOR.accent} />;
    }

    function SetupView(props: SetupStepProps) {
      void props;
      return <StudyMethodSetupView store={store} />;
    }

    /*
     * Today's study minutes against the kit's daily goal, the block under
     * way as the shared focus clock (the deep focus switch rides along, so
     * the pet coach holds its idle nudges longer), and today's tally for
     * Wrap Up. Recomputed on every store change, published only when one of
     * them differs, so the closed island never redraws on a tick.
     */
    const provision = derived(
      [store],
      () => {
        const state = store.state;
        const today = store.today;
        return moduleProvision({
          progress: [state.goal.progressItem(today)],
          focus: sharedStudyFocus(state.session, MODULE_IDS.study, state.deepFocus, state.now),
          study: today,
        });
      },
      provisionsEqual,
    );

    return {
      store,
      Panel,
      provision,
      setupView: (step) => (step.id === ONBOARDING_SETUP_STEPS.studyMethod.id ? SetupView : undefined),
      start: () => {
        store.setEnabled(true);
        if (typeof window !== "undefined") window.addEventListener("beforeunload", onUnload);
      },
      stop: () => {
        store.setEnabled(false);
        if (typeof window !== "undefined") window.removeEventListener("beforeunload", onUnload);
      },
      showSnapshotState: async (state: string) => {
        await store.ready;
        const [kind, argument] = state.split("-");
        switch (kind) {
          case "picker":
          case "sounds":
          case "custom":
            store.show({ kind });
            return;
          case "paused":
            store.showDemoMethod("pomodoro", true);
            return;
          case "info":
            if (argument !== undefined && isMethodKind(argument)) store.show({ kind: "info", method: argument, from: undefined });
            return;
          case "method":
            if (argument !== undefined && isMethodKind(argument)) store.showDemoMethod(argument);
            return;
          case "party": {
            const now = context.now();
            store.showForSnapshot(new ProvidedPartySession({ method: "pomodoro", startedAt: now - 6 * 60 - 18, endsAt: now + 18 * 60 + 42, friendCount: 2, hostName: "Maya" }));
            return;
          }
        }
      },
    };
  },
  { snapshotStates: STUDY_SNAPSHOT_STATES },
);
