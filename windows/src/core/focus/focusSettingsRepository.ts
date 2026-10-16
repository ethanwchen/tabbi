import { defaultsString, type Defaults } from "../persistence/defaults";
import { isJSONObject, stringifyJSON, type JSONObject } from "../persistence/json";
import type { FocusMix } from "./focusMix";
import { FocusSettings } from "./focusSettings";

/*
 * Port of FocusSettingsRepository: focus settings as one JSON value in the
 * preferences, under a key of their own so focus mode never touches the app
 * settings. The Mac stores them as `Data` from a plain JSONEncoder, with no
 * `schemaVersion` (they are not a VersionedJSON format); the core's
 * `Defaults` keeps that as JSON text. Decoding falls back per field, so
 * there is nothing to migrate: a missing or bad value takes its default.
 */

/** The preferences key, `FocusSettingsRepository.key` on the Mac. */
export const FOCUS_SETTINGS_KEY = "focus.settings";

/**
 * A Swift `Float` as JSONEncoder writes it: the shortest decimal that reads
 * back as the same 32-bit value (0.7, not 0.699999988079071).
 */
export function swiftFloatJSON(value: number): number {
  const single = Math.fround(value);
  for (let digits = 1; digits <= 9; digits++) {
    const candidate = Number(single.toPrecision(digits));
    if (Math.fround(candidate) === single) return candidate;
  }
  return single;
}

function encodeMix(mix: FocusMix): JSONObject {
  return { layers: mix.layers.map((layer) => ({ sound: layer.sound, level: swiftFloatJSON(layer.level) })) };
}

/** The settings in the Mac's Codable shape and key order, compact, as the default JSONEncoder writes them. */
export function encodeFocusSettings(settings: FocusSettings): string {
  return stringifyJSON({
    mix: encodeMix(settings.mix),
    presets: { slots: settings.presets.slots.map((slot) => (slot === undefined ? null : { name: slot.name, mix: encodeMix(slot.mix) })) },
    volume: swiftFloatJSON(settings.volume),
    playlistText: settings.playlistText,
    doNotDisturb: settings.doNotDisturb,
    onShortcut: settings.onShortcut,
    offShortcut: settings.offShortcut,
  });
}

/** The settings in `text`, or undefined when it isn't a JSON object (the only case the Mac's decoder refuses). */
export function decodeFocusSettings(text: string): FocusSettings | undefined {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return undefined;
  }
  return isJSONObject(parsed) ? FocusSettings.fromJSON(parsed) : undefined;
}

/** Port of FocusSettingsRepository over the core's preferences. */
export class FocusSettingsRepository {
  constructor(private readonly defaults: Defaults) {}

  /** The saved settings, or the defaults when none are saved or they can't be read. */
  load(): FocusSettings {
    const text = defaultsString(this.defaults, FOCUS_SETTINGS_KEY);
    return (text === undefined ? undefined : decodeFocusSettings(text)) ?? FocusSettings.default;
  }

  save(settings: FocusSettings): void {
    this.defaults.set(FOCUS_SETTINGS_KEY, encodeFocusSettings(settings));
  }
}
