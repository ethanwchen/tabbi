import { describe, expect, it } from "vitest";
import {
  NOW_PLAYING_PREFERENCES_KEY,
  NOW_PLAYING_PREFERENCES_SCHEMA,
  NowPlayingPreferencesStorage,
  decodeNowPlayingPreferencesText,
  encodeNowPlayingPreferences,
  followsSoundCloud,
} from "../../../src/core/nowPlaying/nowPlayingPreferences";
import { InMemoryDefaults } from "../../../src/core/persistence/defaults";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";

/* Port of NowPlayingPreferencesTests. */

describe("NowPlayingPreferences", () => {
  it("follows SoundCloud only when turned on and browsers are allowed", () => {
    expect(followsSoundCloud({ showsSoundCloud: false }, true)).toBe(false);
    expect(followsSoundCloud({ showsSoundCloud: true }, true)).toBe(true);
    expect(followsSoundCloud({ showsSoundCloud: true }, false)).toBe(false);
  });
});

describe("NowPlayingPreferencesStorage", () => {
  it("defaults when nothing is saved", () => {
    expect(new NowPlayingPreferencesStorage(new InMemoryDefaults()).load()).toEqual({ showsSoundCloud: false });
  });

  it("keeps the saved choice across a relaunch", () => {
    const defaults = new InMemoryDefaults();
    new NowPlayingPreferencesStorage(defaults).save({ showsSoundCloud: true });
    expect(new NowPlayingPreferencesStorage(defaults).load().showsSoundCloud).toBe(true);
  });

  it("writes the Mac's versioned document under the Mac's key", () => {
    const defaults = new InMemoryDefaults();
    new NowPlayingPreferencesStorage(defaults).save({ showsSoundCloud: true });
    const text = defaults.get(NOW_PLAYING_PREFERENCES_KEY);
    expect(NOW_PLAYING_PREFERENCES_KEY).toBe("nowPlaying.preferences");
    expect(text).toBe('{"showsSoundCloud":true,"schemaVersion":1}');
    expect(VersionedJSON.version(typeof text === "string" ? text : "")).toBe(NOW_PLAYING_PREFERENCES_SCHEMA.current);
    expect(encodeNowPlayingPreferences({ showsSoundCloud: false })).toBe('{"showsSoundCloud":false,"schemaVersion":1}');
  });

  it("keeps the default for a value it can't read", () => {
    const defaults = new InMemoryDefaults({ [NOW_PLAYING_PREFERENCES_KEY]: NOW_PLAYING_PREFERENCES_SCHEMA.encode({ showsSoundCloud: "sometimes" }) });
    expect(new NowPlayingPreferencesStorage(defaults).load().showsSoundCloud).toBe(false);
    expect(decodeNowPlayingPreferencesText('{"showsSoundCloud":1}')).toEqual({ showsSoundCloud: false });
  });

  it("reads a version 0 document", () => {
    expect(decodeNowPlayingPreferencesText('{"showsSoundCloud":true}')).toEqual({ showsSoundCloud: true });
  });

  it("falls back to the defaults for an unreadable document", () => {
    for (const value of ["not json", "[true]", true]) {
      const defaults = new InMemoryDefaults({ [NOW_PLAYING_PREFERENCES_KEY]: value });
      expect(new NowPlayingPreferencesStorage(defaults).load(), String(value)).toEqual({ showsSoundCloud: false });
    }
  });
});
