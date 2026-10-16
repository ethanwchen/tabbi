import { describe, expect, it } from "vitest";
import { FocusMix } from "../../../src/core/focus/focusMix";
import { FocusMixPreset, FocusMixPresets, cleanedPresetName, defaultPresetName } from "../../../src/core/focus/focusMixPreset";
import {
  FOCUS_PLAYLIST_PRESETS,
  matchingPlaylistPreset,
  parseFocusPlaylist,
  playlistSource,
  playlistStartsPlayback,
  presetSource,
} from "../../../src/core/focus/focusPlaylist";
import { FocusSettings, kitFocusMix } from "../../../src/core/focus/focusSettings";
import { kitDefaults } from "../../../src/core/kits/kitManifest";
import type { JSONObject } from "../../../src/core/persistence/json";

const focusKit = (focus: JSONObject) => kitDefaults({ moduleSettings: { focus } });
import { FOCUS_SOUNDS, loudnessGain, loudnessTrimDecibels } from "../../../src/core/focus/focusSound";

describe("FocusMix", () => {
  it("keeps unique sounds, at most three, with levels clamped", () => {
    const mix = new FocusMix([
      { sound: "rain", level: 2 },
      { sound: "rain", level: 0.3 },
      { sound: "cafe", level: -1 },
      { sound: "white", level: Number.NaN },
      { sound: "brown" },
    ]);
    expect(mix.layers).toEqual([
      { sound: "rain", level: 1 },
      { sound: "cafe", level: 0 },
      { sound: "white", level: 1 },
    ]);
    expect(mix.canAddLayer).toBe(false);
  });

  it("toggles and sets levels without exceeding the layer limit", () => {
    let mix = FocusMix.off;
    for (const sound of ["rain", "fireplace", "cafe"] as const) mix = mix.toggled(sound).mix;
    expect(mix.toggled("white").changed).toBe(false);
    mix = mix.toggled("rain").mix;
    expect(mix.contains("rain")).toBe(false);
    mix = mix.withLevel(0.25, "cafe").withLevel(0.5, "brown");
    expect(mix.level("cafe")).toBe(0.25);
    expect(mix.level("brown")).toBeUndefined();
  });

  it("scales gains so a blend is as loud as one full sound", () => {
    expect(FocusMix.single("rain").gains.get("rain")).toBe(1);
    const half = new FocusMix([
      { sound: "rain", level: 0.5 },
      { sound: "cafe", level: 0.5 },
    ]);
    expect(half.gains.get("rain")).toBe(0.5);
    const full = new FocusMix([{ sound: "rain" }, { sound: "cafe" }]).gains;
    let power = 0;
    for (const gain of full.values()) power += gain * gain;
    expect(power).toBeCloseTo(1, 6);
  });

  it("reads like the Mac's summary and round-trips through JSON", () => {
    expect(FocusMix.off.summary).toBe("Off");
    const mix = new FocusMix([{ sound: "rain" }, { sound: "fireplace", level: 0.5 }]);
    expect(mix.summary).toBe("Rain + Fireplace");
    const decoded = FocusMix.fromJSON(JSON.parse(JSON.stringify(mix)));
    expect(decoded?.equals(mix)).toBe(true);
    expect(FocusMix.fromJSON({ layers: [{ sound: "thunder", level: 1 }] })).toBeUndefined();
    expect(FocusMix.fromJSON({})?.isOff).toBe(true);
  });
});

describe("FocusSound", () => {
  it("carries the Mac's loudness trims", () => {
    const trims = Object.fromEntries(FOCUS_SOUNDS.map((sound) => [sound, loudnessTrimDecibels(sound)]));
    expect(trims).toEqual({
      brown: Math.fround(2),
      pink: Math.fround(-3.8),
      white: Math.fround(-6.2),
      rain: Math.fround(-4.2),
      fireplace: Math.fround(2.6),
      cafe: Math.fround(-2.8),
    });
    expect(loudnessGain("white")).toBeCloseTo(Math.pow(10, -6.2 / 20), 6);
  });
});

describe("FocusMixPreset", () => {
  it("names a preset after its loudest sound and how many others play", () => {
    expect(defaultPresetName(FocusMix.off)).toBe("Off");
    expect(defaultPresetName(FocusMix.single("rain"))).toBe("Rain");
    const mix = new FocusMix([
      { sound: "cafe", level: 0.4 },
      { sound: "rain", level: 0.9 },
      { sound: "fireplace", level: 0.9 },
    ]);
    expect(defaultPresetName(mix)).toBe("Rain +2");
  });

  it("trims names, cuts long ones and falls back on blank", () => {
    expect(cleanedPresetName("   ")).toBeUndefined();
    expect(cleanedPresetName("  Rainy cafe  ")).toBe("Rainy cafe");
    expect(cleanedPresetName("A very long preset name indeed")).toBe("A very long preset");
    expect(new FocusMixPreset(" ", FocusMix.single("cafe")).name).toBe("Cafe murmur");
  });

  it("keeps three fixed slots, never holding an Off mix", () => {
    const presets = new FocusMixPresets([new FocusMixPreset("x", FocusMix.off)]);
    expect(presets.slots).toHaveLength(3);
    expect(presets.isEmpty).toBe(true);
    const saved = presets.saving(FocusMix.single("rain"), 1);
    expect(saved?.slotMatching(FocusMix.single("rain"))).toBe(1);
    expect(saved?.saving(FocusMix.single("cafe"), 1)).toBeUndefined();
    expect(saved?.saving(FocusMix.off, 0)).toBeUndefined();
    expect(saved?.renaming(1, "Storm").slots[1]?.name).toBe("Storm");
    expect(saved?.renaming(1, "").slots[1]?.name).toBe("Rain");
    expect(saved?.deleting(1).isEmpty).toBe(true);
  });

  it("decodes leniently, keeping readable slots", () => {
    const decoded = FocusMixPresets.fromJSON({
      slots: [null, { name: "Fire", mix: { layers: [{ sound: "fireplace", level: 1 }] } }, { bad: true }],
    });
    expect(decoded?.slots.map((slot) => slot?.name)).toEqual([undefined, "Fire", undefined]);
  });
});

describe("FocusPlaylist", () => {
  const expected = { kind: "spotify", uri: "spotify:playlist:37i9dQZF1DWZeKCadgRdKQ" };

  it("reads Spotify links and URIs in every form", () => {
    expect(parseFocusPlaylist("spotify:playlist:37i9dQZF1DWZeKCadgRdKQ")).toEqual(expected);
    expect(parseFocusPlaylist("  https://open.spotify.com/playlist/37i9dQZF1DWZeKCadgRdKQ?si=abc123 \n")).toEqual(expected);
    expect(parseFocusPlaylist("https://open.spotify.com/intl-de/playlist/37i9dQZF1DWZeKCadgRdKQ")).toEqual(expected);
    expect(parseFocusPlaylist("spotify:user:someone:playlist:37i9dQZF1DWZeKCadgRdKQ")).toEqual(expected);
    expect(parseFocusPlaylist("https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy")).toEqual({
      kind: "spotify",
      uri: "spotify:album:4aawyAB9vmqN3uQ7FjRGTy",
    });
  });

  it("refuses malformed Spotify references and other sites", () => {
    for (const text of [
      "spotify:playlist:",
      "spotify:podcast:abc",
      "https://open.spotify.com/",
      "https://open.spotify.com/playlist/bad-id!",
      "",
      "   \n",
      "https://www.youtube.com/watch?v=jfKfPfyJRdk",
    ]) {
      expect(parseFocusPlaylist(text), text).toBeUndefined();
    }
  });

  it("reads Apple Music links and library names", () => {
    const link = "https://music.apple.com/us/playlist/pure-focus/pl.abc?l=en";
    const music = parseFocusPlaylist(link);
    expect(music).toEqual({ kind: "appleMusicLink", url: link });
    expect(music !== undefined && playlistStartsPlayback(music)).toBe(false);
    expect(parseFocusPlaylist(" Deep Work ")).toEqual({ kind: "musicLibrary", name: "Deep Work" });
    const chill = parseFocusPlaylist("Chill");
    expect(chill !== undefined && playlistSource(chill)).toBe("music");
  });

  it("matches presets by parsed playlist, and every preset parses", () => {
    for (const preset of FOCUS_PLAYLIST_PRESETS) expect(parseFocusPlaylist(preset.link), preset.name).toBeDefined();
    expect(matchingPlaylistPreset("spotify:playlist:37i9dQZF1DWZeKCadgRdKQ")?.name).toBe("Deep Focus");
    expect(matchingPlaylistPreset("Deep Focus")).toBeUndefined();
    expect(FOCUS_PLAYLIST_PRESETS.map(presetSource)).toEqual(["spotify", "spotify", "spotify", "spotify", "music", "music"]);
  });
});

describe("FocusSettings", () => {
  it("plays nothing and leaves Do Not Disturb alone by default", () => {
    expect(FocusSettings.default.hasEffect).toBe(false);
    expect(FocusSettings.default.volume).toBe(0.5);
    expect(FocusSettings.default.activeOnShortcut).toBeUndefined();
  });

  it("runs shortcuts only with Do Not Disturb on and a name set", () => {
    const settings = new FocusSettings({ doNotDisturb: true, onShortcut: "  On ", offShortcut: " " });
    expect(settings.activeOnShortcut).toBe("On");
    expect(settings.activeOffShortcut).toBeUndefined();
  });

  it("clamps the volume and decodes field by field", () => {
    expect(new FocusSettings({ volume: 3 }).volume).toBe(1);
    expect(new FocusSettings({ volume: Number.NaN }).volume).toBe(0.5);
    const decoded = FocusSettings.fromJSON({ volume: "loud", playlistText: "Chill", mix: { layers: "nope" } });
    expect(decoded.volume).toBe(0.5);
    expect(decoded.playlistText).toBe("Chill");
    expect(decoded.mix.isOff).toBe(true);
    const settings = new FocusSettings({ mix: FocusMix.single("rain"), volume: 0.25, doNotDisturb: true });
    expect(FocusSettings.fromJSON(JSON.parse(JSON.stringify(settings))).equals(settings)).toBe(true);
  });

  it("takes a kit's focus sound and nothing else", () => {
    expect(kitFocusMix(kitDefaults())).toBeUndefined();
    expect(kitFocusMix(focusKit({ sounds: [] }))?.isOff).toBe(true);
    const mix = kitFocusMix(focusKit({ sounds: [{ sound: "rain", level: 0.5 }, { sound: "thunder" }, { sound: "cafe" }] }));
    expect(mix?.layers).toEqual([
      { sound: "rain", level: 0.5 },
      { sound: "cafe", level: 1 },
    ]);
    const mine = new FocusSettings({ volume: 0.3, playlistText: "Chill" });
    const applied = mine.applyingKit(focusKit({ sounds: [{ sound: "fireplace" }] }));
    expect(applied.mix.equals(FocusMix.single("fireplace"))).toBe(true);
    expect(applied.volume).toBe(mine.volume);
    expect(applied.usesKitDefaults(focusKit({ sounds: [{ sound: "fireplace" }] }))).toBe(true);
    expect(mine.usesKitDefaults(focusKit({ sounds: [{ sound: "fireplace" }] }))).toBe(false);
    expect(mine.applyingKit(kitDefaults()).equals(mine)).toBe(true);
  });

  it("applies a saved preset by slot", () => {
    const presets = FocusMixPresets.empty.saving(FocusMix.single("cafe"), 2);
    const settings = new FocusSettings(presets === undefined ? {} : { presets });
    expect(settings.applyingPreset(2).mix.equals(FocusMix.single("cafe"))).toBe(true);
    expect(settings.applyingPreset(0)).toBe(settings);
  });
});
