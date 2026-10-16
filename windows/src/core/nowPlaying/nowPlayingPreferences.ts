import { defaultsString, type Defaults } from "../persistence/defaults";
import { isJSONObject } from "../persistence/json";
import { VersionedJSON } from "../persistence/versionedJson";

/**
 * Port of NowPlayingPreferences: Now Playing's own preferences. SoundCloud
 * is opt-in on the Mac because reading a browser tab asks macOS for
 * Automation access; the choice is kept here so a settings document moved
 * between the two editions keeps it.
 */
export interface NowPlayingPreferences {
  /** Follow SoundCloud playing in a browser. */
  showsSoundCloud: boolean;
}

export const DEFAULT_NOW_PLAYING_PREFERENCES: Readonly<NowPlayingPreferences> = { showsSoundCloud: false };

/**
 * Whether the panel follows SoundCloud: only when it is turned on and the
 * edition may follow browsers (the Mac's `followedSources(allowsBrowsers:)`,
 * which adds the SoundCloud tabs after the music apps under this rule).
 */
export function followsSoundCloud(preferences: NowPlayingPreferences, allowsBrowsers: boolean): boolean {
  return preferences.showsSoundCloud && allowsBrowsers;
}

/** The settings key, the Mac's `nowPlaying.preferences`. */
export const NOW_PLAYING_PREFERENCES_KEY = "nowPlaying.preferences";

/** Port of NowPlayingPreferencesStorage.schema. Version 1 is the first format. */
export const NOW_PLAYING_PREFERENCES_SCHEMA = new VersionedJSON(1);

/** Reads stored preferences leniently: a value this build can't read keeps its default. */
export function decodeNowPlayingPreferences(stored: unknown): NowPlayingPreferences {
  const value = isJSONObject(stored) ? stored.showsSoundCloud : undefined;
  return { showsSoundCloud: typeof value === "boolean" ? value : DEFAULT_NOW_PLAYING_PREFERENCES.showsSoundCloud };
}

/** Reads a stored document after its migrations; throws only when `text` isn't a JSON object. */
export function decodeNowPlayingPreferencesText(text: string): NowPlayingPreferences {
  return NOW_PLAYING_PREFERENCES_SCHEMA.decode(text, decodeNowPlayingPreferences);
}

/** The document the Mac's default `JSONEncoder` writes: `{"showsSoundCloud":...,"schemaVersion":1}`. */
export function encodeNowPlayingPreferences(preferences: NowPlayingPreferences): string {
  return NOW_PLAYING_PREFERENCES_SCHEMA.encode({ showsSoundCloud: preferences.showsSoundCloud });
}

/**
 * Port of NowPlayingPreferencesStorage: the preferences as JSON text under
 * `nowPlaying.preferences`, where the Mac keeps the same document as `Data`
 * in `UserDefaults`.
 */
export class NowPlayingPreferencesStorage {
  constructor(private readonly defaults: Defaults) {}

  /** The saved preferences, or the defaults when none are saved or they can't be read. */
  load(): NowPlayingPreferences {
    const text = defaultsString(this.defaults, NOW_PLAYING_PREFERENCES_KEY);
    if (text === undefined) return { ...DEFAULT_NOW_PLAYING_PREFERENCES };
    try {
      return decodeNowPlayingPreferencesText(text);
    } catch {
      return { ...DEFAULT_NOW_PLAYING_PREFERENCES };
    }
  }

  save(preferences: NowPlayingPreferences): void {
    this.defaults.set(NOW_PLAYING_PREFERENCES_KEY, encodeNowPlayingPreferences(preferences));
  }
}
