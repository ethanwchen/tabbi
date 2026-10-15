import { describe, expect, it } from "vitest";
import type { MediaSessionSnapshot } from "../../../src/core/nowPlaying/mediaSession";
import { togglingMute, UNMUTE_FALLBACK, volumeAt, volumeLevel } from "../../../src/core/nowPlaying/mediaVolume";
import { artworkChoice, Equalizer, generatedCover, Marquee, playbackTime, remainingTime } from "../../../src/core/nowPlaying/nowPlayingFormat";
import {
  addingPending,
  applyPending,
  DEMO_PLAYBACK,
  isRepeating,
  makePlayback,
  NOTHING_PLAYING,
  type NowPlayingPlayback,
  PENDING_SETTLE_TIME,
  PlaybackClock,
  progress,
  repeatModeAfter,
  seeking,
  settingFavorite,
  settingRepeat,
  settingShuffle,
  settingVolume,
  togglingPlayPause,
} from "../../../src/core/nowPlaying/nowPlayingPlayback";
import {
  controlsFor,
  MediaSourceTracker,
  type NowPlayingStatus,
  playbackFromSession,
  playerDisplayName,
  playerNames,
  repeatCommand,
  statusIsPlaying,
} from "../../../src/core/nowPlaying/nowPlayingSource";

/* Port of the Now Playing tests (MediaModes, MediaVolume, MediaSourceTracker, SpotifyStatus's playback parts, equalizer, marquee, cover), driven by media sessions. */

const allControls = { play: true, pause: true, playPause: true, stop: true, next: true, previous: true, seek: true, shuffle: true, repeat: true };

function session(fields: Partial<MediaSessionSnapshot> = {}): MediaSessionSnapshot {
  return {
    sourceAppId: "Spotify.exe",
    title: "Midnight City",
    artist: "M83",
    albumTitle: "Hurry Up, We're Dreaming",
    playbackStatus: "playing",
    timeline: { start: 0, end: 243, position: 60, minSeek: 0, maxSeek: 243, lastUpdated: 1000 },
    shuffle: false,
    repeat: "none",
    playbackRate: 1,
    controls: allControls,
    ...fields,
  };
}

describe("media session to playback", () => {
  it("maps title, artist, album, state, modes and the timeline", () => {
    const playback = playbackFromSession(session({ shuffle: true, repeat: "list" }), 1000);
    expect(playback.state).toBe("playing");
    expect(playback.track?.title).toBe("Midnight City");
    expect(playback.track?.artist).toBe("M83");
    expect(playback.track?.album).toBe("Hurry Up, We're Dreaming");
    expect(playback.track?.duration).toBe(243);
    expect(playback.position).toBe(60);
    expect(playback.isShuffling).toBe(true);
    expect(playback.repeatMode).toBe("all");
    expect(playback.volume).toBeUndefined();
    expect(playbackFromSession(session({ repeat: "track" }), 1000).repeatMode).toBe("one");
  });

  it("carries a playing position forward from when the app last reported it", () => {
    expect(playbackFromSession(session(), 1012.5).position).toBe(72.5);
    expect(playbackFromSession(session({ playbackRate: 2 }), 1010).position).toBe(80);
    expect(playbackFromSession(session({ playbackStatus: "paused" }), 1012.5).position).toBe(60);
    expect(playbackFromSession(session(), 5000).position).toBe(243);
  });

  it("reads a stopped or empty session as nothing playing", () => {
    expect(playbackFromSession(session({ playbackStatus: "stopped" }), 1000)).toEqual(NOTHING_PLAYING);
    expect(playbackFromSession(session({ title: "  " }), 1000).track).toBeUndefined();
    expect(playbackFromSession(session({ playbackStatus: "changing" }), 1000).state).toBe("paused");
  });

  it("falls back to the album artist and has no length without a timeline", () => {
    const playback = playbackFromSession(session({ artist: "", albumArtist: "Various", timeline: undefined }), 1000);
    expect(playback.track?.artist).toBe("Various");
    expect(playback.track?.duration).toBe(0);
    expect(playback.position).toBe(0);
  });

  it("keeps the same track id for the same song", () => {
    expect(playbackFromSession(session(), 1000).track?.id).toBe(playbackFromSession(session({ playbackStatus: "paused" }), 2000).track?.id);
    expect(playbackFromSession(session(), 1000).track?.id).not.toBe(playbackFromSession(session({ title: "Wait" }), 1000).track?.id);
  });

  it("offers only the controls the app supports", () => {
    const limited = session({ controls: { ...allControls, next: false, shuffle: false }, repeat: undefined });
    expect(controlsFor(limited)).toEqual({ playPause: true, next: false, previous: true, seek: true, shuffle: false, repeat: false });
    expect(controlsFor(session({ timeline: undefined })).seek).toBe(false);
    expect(repeatCommand(session({ controls: { ...allControls, repeat: false } }), "off")).toBeUndefined();
  });

  it("steps the repeat button off, all, one", () => {
    expect(repeatCommand(session(), "off")).toEqual({ kind: "setRepeat", mode: "list" });
    expect(repeatCommand(session(), "all")).toEqual({ kind: "setRepeat", mode: "track" });
    expect(repeatCommand(session(), "one")).toEqual({ kind: "setRepeat", mode: "none" });
    expect(repeatModeAfter("one", ["off", "all"])).toBe("off");
    expect(repeatModeAfter("off", ["off", "one", "all"])).toBe("one");
  });

  it("names players as users know them", () => {
    expect(playerDisplayName("Spotify.exe")).toBe("Spotify");
    expect(playerDisplayName("SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify")).toBe("Spotify");
    expect(playerDisplayName("Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic")).toBe("Media Player");
    expect(playerDisplayName("MSEdge")).toBe("Microsoft Edge");
    expect(playerDisplayName("Chrome")).toBe("Google Chrome");
    expect(playerDisplayName("308046B0AF4A39CB")).toBe("Firefox");
    expect(playerDisplayName("C:\\Program Files\\foobar2000\\foobar2000.exe")).toBe("foobar2000");
  });
});

describe("artwork", () => {
  it("uses the thumbnail when the app published one, else a generated cover", () => {
    const withArt = playbackFromSession(session({ thumbnail: { contentType: "image/png", base64: "iVA=" } }), 1000);
    const track = withArt.track;
    if (!track) throw new Error("no track");
    expect(artworkChoice(track)).toEqual({
      kind: "thumbnail",
      thumbnail: { contentType: "image/png", base64: "iVA=" },
      dataURL: "data:image/png;base64,iVA=",
    });
    const plain = playbackFromSession(session(), 1000).track;
    if (!plain) throw new Error("no track");
    expect(artworkChoice(plain)).toEqual({ kind: "generated", cover: generatedCover(plain.id) });
  });

  it("generates a stable cover per seed with hues apart", () => {
    expect(generatedCover("spotify:track:demo")).toEqual(generatedCover("spotify:track:demo"));
    expect(generatedCover("spotify:track:a")).not.toEqual(generatedCover("spotify:track:b"));
    for (const seed of ["", "x", "spotify:local:::Song:180", "\u{1F3A7} \u66F2", "z".repeat(500)]) {
      const cover = generatedCover(seed);
      expect(cover.startHue).toBeGreaterThanOrEqual(0);
      expect(cover.startHue).toBeLessThan(1);
      expect(cover.endHue).toBeGreaterThanOrEqual(0);
      expect(cover.endHue).toBeLessThan(1);
      let gap = cover.endHue - cover.startHue;
      if (gap < 0) gap += 1;
      expect(gap).toBeGreaterThanOrEqual(50 / 360 - 1e-9);
      expect(gap).toBeLessThanOrEqual(110 / 360 + 1e-9);
    }
  });

  it("matches the Mac's FNV-1a hash", () => {
    /* FNV-1a 64 of "" is the offset basis 0xcbf29ce484222325: 14695981039346656037 % 360 = 77. */
    expect(generatedCover("").startHue).toBeCloseTo(77 / 360, 12);
  });
});

describe("playback model", () => {
  it("toggles play and pause, and seeks within the track", () => {
    expect(togglingPlayPause(DEMO_PLAYBACK).state).toBe("paused");
    expect(togglingPlayPause(togglingPlayPause(DEMO_PLAYBACK))).toEqual(DEMO_PLAYBACK);
    expect(togglingPlayPause(NOTHING_PLAYING)).toEqual(NOTHING_PLAYING);
    expect(seeking(DEMO_PLAYBACK, 30).position).toBe(30);
    expect(seeking(DEMO_PLAYBACK, -5).position).toBe(0);
    expect(seeking(DEMO_PLAYBACK, 9999).position).toBe(243.96);
    expect(progress(seeking(DEMO_PLAYBACK, 243.96 / 2))).toBeCloseTo(0.5, 9);
    expect(progress(NOTHING_PLAYING)).toBe(0);
  });

  it("extrapolates the clock only while playing", () => {
    const clock = new PlaybackClock(DEMO_PLAYBACK, 1000);
    expect(clock.playback(1003).position).toBeCloseTo(90.4, 4);
    expect(clock.playback(11_000).position).toBe(243.96);
    expect(clock.playback(995).position).toBeCloseTo(87.4, 4);
    clock.sync(togglingPlayPause(DEMO_PLAYBACK), 1000);
    expect(clock.playback(1003).position).toBeCloseTo(87.4, 4);
  });

  it("changes modes optimistically", () => {
    expect(settingShuffle(DEMO_PLAYBACK, false).isShuffling).toBe(false);
    expect(settingRepeat(DEMO_PLAYBACK, "one").repeatMode).toBe("one");
    expect(isRepeating(settingRepeat(DEMO_PLAYBACK, "one"))).toBe(true);
    expect(settingShuffle(DEMO_PLAYBACK, false).track).toEqual(DEMO_PLAYBACK.track);
    expect(settingFavorite(DEMO_PLAYBACK, false).track?.isFavorite).toBe(false);
    const unlikeable = playbackFromSession(session(), 1000);
    expect(settingFavorite(unlikeable, true)).toBe(unlikeable);
  });

  it("holds pending modes over stale reads until they settle", () => {
    const t0 = 50_000;
    const stale = settingShuffle(DEMO_PLAYBACK, false);
    const pending = addingPending({ deadline: t0 }, { shuffle: true }, t0);
    expect(applyPending(pending, stale, t0 + 0.2).isShuffling).toBe(true);
    expect(applyPending(pending, settingRepeat(stale, "all"), t0 + 0.2).repeatMode).toBe("all");
    expect(applyPending(pending, stale, t0 + PENDING_SETTLE_TIME).isShuffling).toBe(false);
    const both = addingPending(pending, { repeatMode: "one" }, t0 + 1);
    expect(both).toEqual({ shuffle: true, repeatMode: "one", deadline: t0 + 1 + PENDING_SETTLE_TIME });
    const later = addingPending(pending, { repeatMode: "all" }, t0 + 10);
    expect(later.shuffle).toBeUndefined();
    expect(later.repeatMode).toBe("all");
  });
});

describe("volume", () => {
  it("clamps and maps the slider", () => {
    expect(makePlayback({ ...NOTHING_PLAYING, volume: 300 }).volume).toBe(100);
    expect(volumeAt(0.5)).toBe(50);
    expect(volumeAt(0.644)).toBe(64);
    expect(volumeAt(-0.2)).toBe(0);
    expect(volumeAt(1.5)).toBe(100);
    expect(volumeAt(Number.NaN)).toBe(0);
  });

  it("picks the speaker glyph and restores the level before muting", () => {
    expect([0, 1, 33, 34, 66, 67, 100].map(volumeLevel)).toEqual([0, 1, 1, 2, 2, 3, 3]);
    expect(togglingMute(64, undefined)).toBe(0);
    expect(togglingMute(0, 64)).toBe(64);
    expect(togglingMute(0, undefined)).toBe(UNMUTE_FALLBACK);
    expect(togglingMute(0, 0)).toBe(UNMUTE_FALLBACK);
  });

  it("changes a known volume optimistically, and nothing without one", () => {
    expect(settingVolume(DEMO_PLAYBACK, 20).volume).toBe(20);
    expect(settingVolume(DEMO_PLAYBACK, -5).volume).toBe(0);
    expect(settingVolume(NOTHING_PLAYING, 40).volume).toBeUndefined();
  });
});

describe("MediaSourceTracker", () => {
  const t0 = 10_000;
  const playback = (state: NowPlayingPlayback["state"], id = "x"): NowPlayingStatus => ({
    kind: "connected",
    playback: { state, track: { id, title: id, artist: "", album: "", duration: 100 }, position: 0, isShuffling: false, repeatMode: "off" },
  });
  const idle: NowPlayingStatus = { kind: "connected", playback: NOTHING_PLAYING };

  it("shows nothing running with no sessions", () => {
    const tracker = new MediaSourceTracker();
    expect(tracker.status).toEqual({ kind: "notRunning" });
    tracker.update("Spotify.exe", { kind: "notRunning" }, t0);
    expect(tracker.selected).toBeUndefined();
  });

  it("lets a playing source win", () => {
    const tracker = new MediaSourceTracker();
    tracker.update("Spotify.exe", playback("paused", "s"), t0);
    tracker.update("MSEdge", playback("playing", "m"), t0);
    expect(tracker.selected).toBe("MSEdge");
    expect(tracker.status.kind === "connected" && tracker.status.playback.track?.id).toBe("m");
  });

  it("prefers the most recently started when both play", () => {
    const tracker = new MediaSourceTracker();
    tracker.update("MSEdge", playback("playing"), t0);
    tracker.update("Spotify.exe", playback("playing"), t0 + 5);
    expect(tracker.selected).toBe("Spotify.exe");
    tracker.update("MSEdge", playback("playing"), t0 + 10);
    expect(tracker.selected).toBe("Spotify.exe");
  });

  it("prefers the most recently active when both are paused", () => {
    const tracker = new MediaSourceTracker();
    tracker.update("MSEdge", playback("playing"), t0);
    tracker.update("Spotify.exe", playback("playing"), t0 + 3);
    tracker.update("Spotify.exe", playback("paused"), t0 + 4);
    expect(tracker.selected).toBe("MSEdge");
    tracker.update("MSEdge", playback("paused"), t0 + 8);
    expect(tracker.selected).toBe("MSEdge");
    expect(statusIsPlaying(tracker.status)).toBe(false);
  });

  it("breaks idle ties by a loaded track, then stays put", () => {
    const tracker = new MediaSourceTracker();
    tracker.update("Spotify.exe", idle, t0);
    tracker.update("MSEdge", playback("paused"), t0);
    expect(tracker.selected).toBe("MSEdge");
    const still = new MediaSourceTracker();
    still.update("MSEdge", idle, t0);
    expect(still.selected).toBe("MSEdge");
    still.update("Spotify.exe", idle, t0);
    expect(still.selected).toBe("MSEdge");
  });

  it("falls back to the other source when one closes", () => {
    const tracker = new MediaSourceTracker();
    tracker.update("Spotify.exe", playback("paused"), t0);
    tracker.update("MSEdge", playback("playing"), t0);
    tracker.update("MSEdge", { kind: "notRunning" }, t0 + 1);
    expect(tracker.selected).toBe("Spotify.exe");
    tracker.update("Spotify.exe", { kind: "notRunning" }, t0 + 2);
    expect(tracker.selected).toBeUndefined();
    expect(tracker.status).toEqual({ kind: "notRunning" });
  });

  it("applies whole host snapshots, dropping sessions that ended", () => {
    const tracker = new MediaSourceTracker();
    tracker.apply({ sessions: [session({ playbackStatus: "paused" }), session({ sourceAppId: "MSEdge", title: "Lecture" })], capturedAt: 1000 });
    expect(tracker.selected).toBe("MSEdge");
    tracker.apply({ sessions: [session({ playbackStatus: "paused" })], capturedAt: 1005 });
    expect(tracker.selected).toBe("Spotify.exe");
    tracker.apply({ sessions: [], capturedAt: 1010 });
    expect(tracker.status).toEqual({ kind: "notRunning" });
  });

  it("follows the session Windows calls current when nothing else decides", () => {
    const tracker = new MediaSourceTracker();
    tracker.apply({
      sessions: [session({ playbackStatus: "paused" }), session({ sourceAppId: "MSEdge", playbackStatus: "paused" })],
      currentSourceAppId: "MSEdge",
      capturedAt: 1000,
    });
    expect(tracker.selected).toBe("MSEdge");
  });
});

describe("format, marquee and equalizer", () => {
  it("formats playback times", () => {
    expect(playbackTime(0)).toBe("0:00");
    expect(playbackTime(65.9)).toBe("1:05");
    expect(playbackTime(3725)).toBe("1:02:05");
    expect(playbackTime(Number.NaN)).toBe("0:00");
    expect(remainingTime(87.4, 243.96)).toBe("-2:37");
    expect(remainingTime(300, 200)).toBe("-0:00");
  });

  it("scrolls only overflowing text, resting at the start of each cycle", () => {
    expect(Marquee.needsScrolling(200, 300)).toBe(false);
    expect(Marquee.needsScrolling(300.3, 300)).toBe(false);
    expect(Marquee.needsScrolling(320, 300)).toBe(true);
    expect(Marquee.needsScrolling(Number.NaN, 300)).toBe(false);
    expect(Marquee.offset(5, 200, 300)).toBe(0);
    expect(Marquee.offset(0, 400, 300)).toBe(0);
    expect(Marquee.offset(Marquee.pause * 0.9, 400, 300)).toBe(0);
    expect(Marquee.offset(-3, 400, 300)).toBe(0);
    expect(Marquee.offset(Marquee.pause + 1, 400, 300)).toBeLessThan(0);
  });

  it("moves exactly one text width plus the gap per cycle, smoothly and only left", () => {
    const width = 400;
    const cycle = Marquee.pause + (width + Marquee.gap) / Marquee.speed;
    expect(Marquee.offset(cycle - 0.0001, width, 300)).toBeCloseTo(-(width + Marquee.gap), 1);
    expect(Marquee.offset(cycle + 0.1, width, 300)).toBe(0);
    expect(Marquee.offset(Marquee.pause + 2, width, 300)).toBeCloseTo(Marquee.offset(cycle + Marquee.pause + 2, width, 300), 4);
    let previous = 0;
    for (let frame = 0; frame < 2000; frame++) {
      const offset = Marquee.offset(frame / 60, 520, 330);
      expect(offset).toBeLessThanOrEqual(0);
      expect(offset).toBeGreaterThanOrEqual(-(520 + Marquee.gap));
      if (offset !== 0 && previous !== 0) {
        expect(offset).toBeLessThanOrEqual(previous + 1e-9);
        expect(previous - offset).toBeLessThan(2);
      }
      previous = offset;
    }
  });

  it("keeps equalizer levels in range, deterministic and moving", () => {
    for (let step = 0; step < 2000; step++) {
      const levels = Equalizer.levels(step * 0.037);
      expect(levels).toHaveLength(Equalizer.barCount);
      for (const level of levels) {
        expect(level).toBeGreaterThanOrEqual(Equalizer.minimumLevel);
        expect(level).toBeLessThanOrEqual(1);
      }
    }
    expect(Equalizer.levels(12.34)).toEqual(Equalizer.levels(12.34));
    expect(Equalizer.levels(1)).not.toEqual(Equalizer.levels(1.2));
    expect(new Set(Equalizer.levels(1)).size).toBeGreaterThan(1);
    const samples = Array.from({ length: 1000 }, (_, i) => Equalizer.levels(i * 0.05)).flat();
    expect(Math.min(...samples)).toBeLessThan(0.35);
    expect(Math.max(...samples)).toBeGreaterThan(0.9);
  });

  it("moves smoothly between frames, even at huge times", () => {
    const frame = 1 / 30;
    for (let step = 0; step < 3000; step++) {
      const time = 812_345_678 + step * frame;
      const now = Equalizer.levels(time);
      const next = Equalizer.levels(time + frame);
      now.forEach((value, index) => expect(Math.abs(value - (next[index] ?? 0))).toBeLessThan(0.25));
    }
    for (const time of [1e12, -1e12, 1e18, 812_345_678.9]) {
      const levels = Equalizer.levels(time);
      expect(levels).toHaveLength(Equalizer.barCount);
      expect(levels.every((level) => level >= Equalizer.minimumLevel && level <= 1)).toBe(true);
    }
  });

  it("loops each bar without a seam and follows the live levels before the blend", () => {
    for (let bar = 0; bar < Equalizer.barCount; bar++) {
      const loop = Equalizer.loop(bar, 30, 30);
      expect(loop).toHaveLength(901);
      expect(Math.abs((loop[0] ?? 0) - (loop.at(-1) ?? 1))).toBeLessThan(1e-12);
      for (let i = 1; i < loop.length; i++) expect(Math.abs((loop[i] ?? 0) - (loop[i - 1] ?? 0))).toBeLessThan(0.25);
    }
    const loop = Equalizer.loop(2, 10, 30, 1);
    for (let frame = 0; frame < 270; frame += 7) expect(loop[frame]).toBe(Equalizer.levels(frame / 30)[2]);
    expect(Equalizer.loop(0)).not.toEqual(Equalizer.loop(1));
    expect(Equalizer.loop(Equalizer.barCount)).toEqual([]);
    expect(Equalizer.loop(0, 0)).toEqual([]);
    expect(Equalizer.loop(0, 30, 0)).toEqual([]);
  });

  it("rests short and visible, and falls back to resting for a bad time", () => {
    const resting = Equalizer.restingLevels();
    expect(resting).toHaveLength(Equalizer.barCount);
    expect(resting.every((level) => level >= Equalizer.minimumLevel && level < 0.4)).toBe(true);
    expect(Equalizer.levels(Number.NaN)).toEqual(Equalizer.restingLevels());
    expect(Equalizer.levels(0, 0)).toEqual([]);
  });
});

describe("player names", () => {
  it("joins names for a sentence in the user's language", () => {
    expect(playerNames(["Spotify"])).toBe("Spotify");
    expect(playerNames(["Spotify", "Media Player"])).toBe("Spotify or Media Player");
    expect(playerNames(["Spotify", "Media Player"], "de")).toBe("Spotify oder Media Player");
  });
});
