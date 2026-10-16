import { tr } from "../localization/tr";

/**
 * Port of FocusSound: a focus sound, generated sample by sample or (the cafe)
 * a bundled recording played as a seamless loop. "Off" is not a case: it is
 * an empty mix, so a mix of layers covers every choice uniformly.
 */
export const FOCUS_SOUNDS = ["brown", "pink", "white", "rain", "fireplace", "cafe"] as const;
export type FocusSound = (typeof FOCUS_SOUNDS)[number];

/** Synthesized sounds, rendered by the DSP in `dsp/`; the rest are recordings. */
export type SynthesizedFocusSound = Exclude<FocusSound, "cafe">;

/** Port of FocusRecording.Name: the bundled recordings, by the sound they play. */
export type FocusRecordingName = "cafe";

export function isFocusSound(value: unknown): value is FocusSound {
  return typeof value === "string" && (FOCUS_SOUNDS as readonly string[]).includes(value);
}

export function focusSoundDisplayName(sound: FocusSound): string {
  switch (sound) {
    case "brown":
      return tr("Brown noise");
    case "pink":
      return tr("Pink noise");
    case "white":
      return tr("White noise");
    case "rain":
      return tr("Rain");
    case "fireplace":
      return tr("Fireplace");
    case "cafe":
      return tr("Cafe murmur");
  }
}

/** The bundled recording this sound plays, or undefined for a synthesized one. */
export function focusSoundRecording(sound: FocusSound): FocusRecordingName | undefined {
  return sound === "cafe" ? "cafe" : undefined;
}

/** The Mac's SF Symbol name for the sound, which the icon table maps to a Windows icon. */
export function focusSoundSymbolName(sound: FocusSound): string {
  switch (sound) {
    case "brown":
      return "water.waves";
    case "pink":
      return "wind";
    case "white":
      return "waveform";
    case "rain":
      return "cloud.rain";
    case "fireplace":
      return "flame";
    case "cafe":
      return "cup.and.saucer";
  }
}

/**
 * Gain in dB that brings this sound to `FOCUS_LOUDNESS_TARGET`.
 *
 * Every generator renders at the same RMS, but equal RMS is not equal
 * loudness: the ear is far more sensitive to white noise's treble than to
 * brown noise's rumble. Each trim comes from the sound's measured integrated
 * loudness (ITU-R BS.1770, K-weighted and gated) on the Mac
 * (`FocusLoudnessTests`), so switching sounds never jumps in level.
 */
export function loudnessTrimDecibels(sound: FocusSound): number {
  switch (sound) {
    case "brown":
      return Math.fround(2.0);
    case "pink":
      return Math.fround(-3.8);
    case "white":
      return Math.fround(-6.2);
    case "rain":
      return Math.fround(-4.2);
    case "fireplace":
      return Math.fround(2.6);
    case "cafe":
      return Math.fround(-2.8);
  }
}

/** Integrated loudness, in LUFS at full volume, that every sound is trimmed to. */
export const FOCUS_LOUDNESS_TARGET = -17;

/** `loudnessTrimDecibels` as a linear amplitude factor, in single precision like the Mac. */
export function loudnessGain(sound: FocusSound): number {
  return Math.fround(Math.pow(10, Math.fround(loudnessTrimDecibels(sound) / 20)));
}
