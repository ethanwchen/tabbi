import { lazyView } from "../../app/lazyView";
import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { derived, Observable } from "../../app/store";
import { useStore } from "../../app/useStore";
import { FocusMix } from "../../core/focus/focusMix";
import type { FocusSettings } from "../../core/focus/focusSettings";
import { FOCUS_SOUNDS } from "../../core/focus/focusSound";
import { KitSettingsSchema, kitSetting } from "../../core/kits/kitSettingsSchema";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { moduleProvision, type ModuleProvision } from "../../core/providers/moduleProvision";
import { focusMode, focusTimer } from "./focusServices";

/* The views load on first use; the store and descriptor stay eager. */
const FocusPanel = lazyView(() => import("./focusPanel"), "FocusPanel");
const FocusSettingsPane = lazyView(() => import("./focusSettingsPane"), "FocusSettingsPane");


/* Port of FocusSettings.kitSettings: a kit may set the focus sounds, up to three layers. */
export const FOCUS_KIT_SCHEMA = new KitSettingsSchema({
  sounds: kitSetting.list(
    kitSetting.object({ sound: kitSetting.choice(FOCUS_SOUNDS), level: kitSetting.number(0, 1) }),
    FocusMix.maxLayers,
  ),
});

/* Port of FocusModule: the Pomodoro that switches between focus and breaks, and the focus sounds. Off in every bundled kit: Today already embeds the same timer. */
export const FOCUS_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.focus,
    title: "Focus",
    symbol: "hourglass",
    category: MODULE_CATEGORIES.productivity,
    accent: { red: 0.3, green: 0.84, blue: 0.76 },
    permissions: ["notifications"],
    kitSettings: FOCUS_KIT_SCHEMA,
  },
  {
    title: () => tr("Focus"),
    summary: () => tr("A Pomodoro timer that switches between focus and breaks."),
  },
);

/** The mixer open, a paused session and a break, besides the running demo focus block. */
const FOCUS_SNAPSHOT_STATES = ["sounds", "paused", "break"] as const;

function provisionsEqual(a: ModuleProvision, b: ModuleProvision): boolean {
  return a.focus === undefined || b.focus === undefined ? a.focus === b.focus : a.focus.equals(b.focus);
}

export const FocusModule = defineModule(
  FOCUS_DESCRIPTOR,
  (context) => {
    const store = focusTimer(context);
    const controller = focusMode(context);
    /* Focus mode as it was before the last kit switch, for undo. */
    let settingsBeforeSwitch: FocusSettings | undefined;
    /* A kit's focus sounds, also while this tab is off, since Today and Study run focus mode too. */
    context.kitApplied((application) => {
      switch (application.kind) {
        case "switched":
          settingsBeforeSwitch = controller.settings;
          controller.applyKit(application.kit.defaults);
          break;
        case "reset":
          controller.applyKit(application.kit.defaults);
          break;
        case "undo":
          if (settingsBeforeSwitch !== undefined) controller.restore(settingsBeforeSwitch);
          else controller.applyKit(application.kit.defaults);
          settingsBeforeSwitch = undefined;
          break;
      }
    });
    /* Whether the mixer covers the timer; a snapshot state opens it before the panel draws. */
    const mixerOpen = new Observable(false);
    const onUnload = () => store.interrupt();

    function Panel() {
      const showsMixer = useStore(mixerOpen);
      return (
        <FocusPanel store={store} focusMode={controller} context={context} accent={FOCUS_DESCRIPTOR.accent} showsMixer={showsMixer} setShowsMixer={(shows) => mixerOpen.set(shows)} />
      );
    }

    function SettingsPane() {
      return <FocusSettingsPane controller={controller} />;
    }

    return {
      store,
      controller,
      Panel,
      SettingsPane,
      /* The focus timer, for the ticker and other modules; published only when the clock's state changes, never on a tick. */
      provision: derived([store], () => moduleProvision({ focus: store.state.timer.provided(MODULE_IDS.focus) }), provisionsEqual),
      /* The focus sound comes from the kit (see above), so Reset to Kit Defaults has work to do once the user changes it. */
      usesKitDefaults: (kit) => derived([controller], () => controller.settings.usesKitDefaults(kit.defaults)),
      start: () => {
        if (typeof window !== "undefined") window.addEventListener("beforeunload", onUnload);
      },
      stop: () => {
        if (typeof window !== "undefined") window.removeEventListener("beforeunload", onUnload);
      },
      showSnapshotState: async (state: string) => {
        await store.ready;
        switch (state) {
          case "sounds":
            mixerOpen.set(true);
            return;
          case "paused":
            store.pause();
            return;
          case "break":
            /* Idempotent, since React may run the harness's effect twice. */
            if (store.state.timer.phase === "focus") store.skip();
            return;
        }
      },
    };
  },
  { snapshotStates: FOCUS_SNAPSHOT_STATES },
);
