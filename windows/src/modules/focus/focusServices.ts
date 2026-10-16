/*
 * The focus services several modules share, declared here because Focus
 * owns them (the Mac's `context.focusTimer` and `context.focusMode`
 * extensions in Modules/Focus/): Today, Focus and the pet coach share one
 * Pomodoro (`FocusStore`), and the Pomodoro and Study's deep focus blocks
 * drive one focus mode (`FocusController`: the focus sounds, and the
 * saved focus settings). Both keep their values in the Focus module's
 * preferences document, loaded once per window and posted between windows.
 */

import type { ModuleContext } from "../../app/context";
import { serviceKey } from "../../app/sharedServices";
import { hostChannel, quietChannel } from "../../app/windowChannel";
import { isEphemeral } from "../../core/modules/runMode";
import { browserAudioPlatform } from "../../ui/audio/browserAudioPlatform";
import { FocusSoundEngine } from "../../ui/audio/focusSoundEngine";
import { FocusController } from "./focusController";
import { FocusStore } from "./focusStore";
import { ModulePreferences } from "./modulePreferences";

export { FocusController } from "./focusController";
export { FocusStore } from "./focusStore";
export type { FocusViewer } from "./focusStore";

/** The shared Pomodoro: one FocusStore that every module showing it reads and drives. */
export type FocusTimerService = FocusStore;
/** The one focus mode: the focus sounds and the saved focus settings. */
export type FocusModeService = FocusController;

const FOCUS_PREFERENCES = serviceKey<ModulePreferences>("focus.preferences");
const FOCUS_TIMER = serviceKey<FocusStore>("focus.timer");
const FOCUS_MODE = serviceKey<FocusController>("focus.mode");

/** The Focus module's preferences document (`Focus/preferences.json`), shared by the timer and focus mode. */
export function focusPreferences(context: ModuleContext): ModulePreferences {
  return context.shared.resolve(FOCUS_PREFERENCES, () => {
    const store = isEphemeral(context.runMode) ? undefined : context.storage.folder("Focus");
    /* One topic for every module's copy of the service, so the Settings window's pane reaches the island's store. */
    const channel = context.isSnapshot ? quietChannel : hostChannel(context.host, "focus/preferences");
    return new ModulePreferences(store, channel);
  });
}

/** The one shared Pomodoro. */
export function focusTimer(context: ModuleContext): FocusStore {
  return context.shared.resolve(FOCUS_TIMER, () => new FocusStore(context, focusPreferences(context), focusMode(context)));
}

/** The one focus mode (sounds, the saved focus settings). */
export function focusMode(context: ModuleContext): FocusController {
  return context.shared.resolve(FOCUS_MODE, () => {
    /* The engine is made on first use (no audio context exists until something plays), and never in a snapshot run, which plays no sound. */
    let engine: FocusSoundEngine | undefined;
    /* A snapshot run plays no sound, and a test runs where no audio context exists. */
    const silent = context.isSnapshot || typeof window === "undefined" || typeof AudioContext === "undefined";
    return new FocusController({
      isLive: !isEphemeral(context.runMode),
      preferences: focusPreferences(context),
      soundEngine: () => {
        if (silent) return undefined;
        engine ??= new FocusSoundEngine(browserAudioPlatform());
        return engine;
      },
      openLink: (url) => {
        if (typeof window !== "undefined") window.open(url, "_blank", "noopener");
      },
    });
  });
}
