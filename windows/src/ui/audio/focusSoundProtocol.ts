import type { SynthesizedFocusSound } from "../../core/focus/focusSound";

/*
 * What FocusSoundEngine and its AudioWorklet processors agree on. Kept apart
 * from the worklet file, which registers processors at load and so can only
 * run in the AudioWorklet scope.
 */

export const SYNTH_PROCESSOR = "tabbi-focus-synth";
export const SOFT_CLIP_PROCESSOR = "tabbi-focus-soft-clip";

/** What the engine passes a synth node in `processorOptions`. */
export interface FocusSynthOptions {
  readonly sound: SynthesizedFocusSound;
  /** The 64-bit seed as a decimal string, since the options are structured-cloned. */
  readonly seed: string;
}

/** The message that lets a synth processor end once its layer has faded out. */
export const STOP_MESSAGE = "stop";
