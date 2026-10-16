import { describe, expect, it } from "vitest";
import { FocusMix } from "../../../src/core/focus/focusMix";
import { FocusMixPreset, FocusMixPresets } from "../../../src/core/focus/focusMixPreset";
import { FocusSettings } from "../../../src/core/focus/focusSettings";
import {
  decodeFocusSettings,
  encodeFocusSettings,
  FOCUS_SETTINGS_KEY,
  FocusSettingsRepository,
  swiftFloatJSON,
} from "../../../src/core/focus/focusSettingsRepository";
import { InMemoryDefaults } from "../../../src/core/persistence/defaults";

/* Port of the repository and decoding cases in FocusSettingsTests, over in-memory preferences. */

describe("FocusSettingsRepository", () => {
  const settings = new FocusSettings({
    mix: new FocusMix([
      { sound: "rain", level: 1 },
      { sound: "fireplace", level: 0.4 },
    ]),
    volume: 0.7,
    playlistText: "https://open.spotify.com/playlist/37i9dQZF1DWZeKCadgRdKQ",
    doNotDisturb: true,
    onShortcut: "Work On",
    offShortcut: "Work Off",
  });

  it("loads the defaults when nothing is saved, and round-trips every field", () => {
    const defaults = new InMemoryDefaults();
    const repository = new FocusSettingsRepository(defaults);
    expect(repository.load().equals(FocusSettings.default)).toBe(true);
    repository.save(settings);
    expect(new FocusSettingsRepository(defaults).load().equals(settings)).toBe(true);
    expect(FOCUS_SETTINGS_KEY).toBe("focus.settings");
    expect(typeof defaults.get(FOCUS_SETTINGS_KEY)).toBe("string");
  });

  it("writes the Mac's Codable shape and key order, with Floats as Swift prints them", () => {
    const withPreset = settings.with({ presets: new FocusMixPresets([undefined, new FocusMixPreset("Cozy", FocusMix.single("brown"))]) });
    expect(encodeFocusSettings(withPreset)).toBe(
      `{"mix":{"layers":[{"sound":"rain","level":1},{"sound":"fireplace","level":0.4}]},` +
        `"presets":{"slots":[null,{"name":"Cozy","mix":{"layers":[{"sound":"brown","level":1}]}},null]},` +
        `"volume":0.7,"playlistText":"https:\\/\\/open.spotify.com\\/playlist\\/37i9dQZF1DWZeKCadgRdKQ",` +
        `"doNotDisturb":true,"onShortcut":"Work On","offShortcut":"Work Off"}`,
    );
  });

  it("prints a Float with the fewest digits that read back as it", () => {
    expect(swiftFloatJSON(Math.fround(0.7))).toBe(0.7);
    expect(swiftFloatJSON(Math.fround(0.123456789))).toBe(0.12345679);
    expect(swiftFloatJSON(1)).toBe(1);
    expect(swiftFloatJSON(0)).toBe(0);
  });

  it("falls back per field when decoding", () => {
    const decoded = decodeFocusSettings(`{"volume": "loud", "doNotDisturb": true, "mix": {"layers": [{"sound": "unknown", "level": 1}]}}`);
    expect(decoded?.volume).toBe(FocusSettings.default.volume);
    expect(decoded?.doNotDisturb).toBe(true);
    expect(decoded?.mix.isOff).toBe(true);
    expect(decoded?.onShortcut).toBe("Tabbi Focus On");
    expect(decodeFocusSettings(`{"volume": 1e300}`)?.volume).toBe(FocusSettings.default.volume);
  });

  it("keeps shortcut names saved before the rename", () => {
    const decoded = decodeFocusSettings(`{"doNotDisturb": true, "onShortcut": "NotchDeck Focus On", "offShortcut": "NotchDeck Focus Off"}`);
    expect(decoded?.activeOnShortcut).toBe("NotchDeck Focus On");
    expect(decoded?.activeOffShortcut).toBe("NotchDeck Focus Off");
  });

  it("loads the defaults from a damaged value", () => {
    const defaults = new InMemoryDefaults();
    for (const value of ["{", "[]", "3"]) {
      defaults.set(FOCUS_SETTINGS_KEY, value);
      expect(new FocusSettingsRepository(defaults).load().equals(FocusSettings.default)).toBe(true);
    }
    defaults.set(FOCUS_SETTINGS_KEY, 12);
    expect(new FocusSettingsRepository(defaults).load().equals(FocusSettings.default)).toBe(true);
  });
});
