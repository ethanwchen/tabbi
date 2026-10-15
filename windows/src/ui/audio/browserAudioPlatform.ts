import cafeUrl from "@mac/Focus/FocusRecordings/cafe.m4a?url";
import workletUrl from "./focusSoundWorklet.ts?worker&url";
import { FOCUS_SAMPLE_RATE } from "../../core/focus/focusRecording";
import type { FocusAudioPlatform } from "./focusSoundEngine";

/*
 * The real browser behind FocusSoundEngine: a 48 kHz Web Audio context, the
 * worklet bundled by Vite, and the cafe loop read in place from the Mac's
 * resources and served with the app, so playing it touches no network.
 */
export function browserAudioPlatform(): FocusAudioPlatform {
  return {
    createContext: () => new AudioContext({ sampleRate: FOCUS_SAMPLE_RATE, latencyHint: "playback" }),
    workletUrl,
    loadCafe: async () => {
      const response = await fetch(cafeUrl);
      if (!response.ok) throw new Error(`cafe.m4a: ${response.status}`);
      return response.arrayBuffer();
    },
    randomSeed: () => {
      /* Like the Mac's UInt64.random(in: 1...UInt64.max): any value but zero. */
      const words = crypto.getRandomValues(new BigUint64Array(1));
      return words[0] || 1n;
    },
    setTimeout: (callback, milliseconds) => window.setTimeout(callback, milliseconds),
    clearTimeout: (handle) => window.clearTimeout(typeof handle === "number" ? handle : undefined),
  };
}
