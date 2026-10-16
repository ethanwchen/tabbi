/*
 * The focus services several modules share, declared here because Focus
 * owns them (the Mac's `context.focusTimer` and `context.focusMode`
 * extensions in Modules/Focus/): Today, Focus and the pet coach share one
 * Pomodoro, and the Pomodoro and Study's deep focus blocks drive one focus
 * mode (the focus sounds). The Focus port grows these into the full
 * FocusStore and FocusController; the keys and accessors stay.
 */

import type { ModuleContext } from "../../app/context";
import { serviceKey } from "../../app/sharedServices";
import { Store } from "../../app/store";
import { FocusTimer } from "../../core/focus/focusTimer";
import { browserAudioPlatform } from "../../ui/audio/browserAudioPlatform";
import { FocusSoundEngine } from "../../ui/audio/focusSoundEngine";

/** The shared Pomodoro: one FocusTimer that every module showing it reads and drives. */
export class FocusTimerService extends Store<{ readonly timer: FocusTimer }> {
  constructor() {
    super({ timer: new FocusTimer() });
  }

  /** Changes a copy of the timer and publishes it, so readers holding the old state never see it move. */
  change(mutate: (timer: FocusTimer) => void): void {
    const next = this.state.timer.clone();
    mutate(next);
    this.changed({ timer: next });
  }
}

/**
 * The one focus mode: the focus sound engine the Pomodoro and Study's deep
 * focus blocks play through. The engine is made on first use (no audio
 * context exists until something plays), and never in a snapshot run, which
 * plays no sound.
 */
export class FocusModeService {
  private engine: FocusSoundEngine | undefined;

  constructor(private readonly silent: boolean) {}

  /** The sound engine, or undefined in a snapshot run. */
  soundEngine(): FocusSoundEngine | undefined {
    if (this.silent) return undefined;
    this.engine ??= new FocusSoundEngine(browserAudioPlatform());
    return this.engine;
  }
}

const FOCUS_TIMER = serviceKey<FocusTimerService>("focus.timer");
const FOCUS_MODE = serviceKey<FocusModeService>("focus.mode");

/** The one shared Pomodoro. */
export function focusTimer(context: ModuleContext): FocusTimerService {
  return context.shared.resolve(FOCUS_TIMER, () => new FocusTimerService());
}

/** The one focus mode (sounds). */
export function focusMode(context: ModuleContext): FocusModeService {
  return context.shared.resolve(FOCUS_MODE, () => new FocusModeService(context.isSnapshot));
}
