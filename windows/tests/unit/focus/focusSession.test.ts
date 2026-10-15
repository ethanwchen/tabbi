import { describe, expect, it } from "vitest";
import { FocusMix } from "../../../src/core/focus/focusMix";
import type { FocusPlaylist, MediaSource } from "../../../src/core/focus/focusPlaylist";
import {
  FocusSession,
  combinedFocusActivity,
  timerFocusActivity,
  type FocusActivity,
  type FocusSessionAction,
} from "../../../src/core/focus/focusSession";
import { FocusSettings } from "../../../src/core/focus/focusSettings";
import { FocusTimer } from "../../../src/core/focus/focusTimer";

/* Ports FocusSessionTests: what focus mode does as the timer moves between phases. */

const spotify: FocusPlaylist = { kind: "spotify", uri: "spotify:playlist:abc" };
const full = new FocusSettings({
  mix: FocusMix.single("rain"),
  volume: 0.4,
  playlistText: "spotify:playlist:abc",
  doNotDisturb: true,
  onShortcut: "On",
  offShortcut: "Off",
});
const startSound: FocusSessionAction = { kind: "startSound", mix: FocusMix.single("rain"), volume: Math.fround(0.4) };
const play = (playlist: FocusPlaylist): FocusSessionAction => ({ kind: "playPlaylist", playlist });
const pause = (source: MediaSource): FocusSessionAction => ({ kind: "pausePlaylist", source });
const resume = (source: MediaSource): FocusSessionAction => ({ kind: "resumePlaylist", source });
const shortcut = (name: string): FocusSessionAction => ({ kind: "runShortcut", name });
const stopSound: FocusSessionAction = { kind: "stopSound" };

function go(session: FocusSession, activity: FocusActivity, settings = full, playing: MediaSource[] = []): FocusSessionAction[] {
  return session.transition(activity, settings, (source) => playing.includes(source));
}

const picking = (text: string): FocusSettings => full.with({ playlistText: text });
const withoutSound = (settings: FocusSettings): FocusSettings => new FocusSettings({ playlistText: settings.playlistText });

describe("FocusActivity", () => {
  it("follows the timer", () => {
    const now = 1_790_000_000;
    const timer = new FocusTimer();
    expect(timerFocusActivity(timer)).toBe("idle");
    timer.start(now);
    expect(timerFocusActivity(timer)).toBe("focusing");
    timer.pause(now);
    expect(timerFocusActivity(timer)).toBe("interrupted");
    timer.start(now);
    timer.advance(now + timer.config.focusDuration + 1);
    expect(timer.phase).toBe("rest");
    expect(timerFocusActivity(timer)).toBe("interrupted");
    timer.reset();
    expect(timerFocusActivity(timer)).toBe("idle");
  });

  it("combines timers so ending one never turns off what another needs", () => {
    expect(combinedFocusActivity([])).toBe("idle");
    expect(combinedFocusActivity(["idle", "interrupted"])).toBe("interrupted");
    expect(combinedFocusActivity(["interrupted", "focusing", "idle"])).toBe("focusing");
  });
});

describe("FocusSession", () => {
  it("starts everything with focus and undoes it at the break", () => {
    const session = new FocusSession();
    expect(go(session, "focusing")).toEqual([startSound, play(spotify), shortcut("On")]);
    expect(session.isFocusing).toBe(true);
    expect(go(session, "focusing")).toEqual([]);
    expect(go(session, "interrupted")).toEqual([stopSound, pause("spotify"), shortcut("Off")]);
    expect(go(session, "idle")).toEqual([]);
  });

  it("does nothing with default settings", () => {
    const session = new FocusSession();
    expect(go(session, "focusing", FocusSettings.default)).toEqual([]);
    expect(go(session, "idle", FocusSettings.default)).toEqual([]);
  });

  it("ends with the settings captured at the start", () => {
    const session = new FocusSession();
    go(session, "focusing");
    expect(go(session, "idle", FocusSettings.default)).toEqual([stopSound, pause("spotify"), shortcut("Off")]);
  });

  it("runs the off shortcut only if the on shortcut ran", () => {
    const session = new FocusSession();
    expect(go(session, "focusing", full.with({ onShortcut: " " }))).not.toContainEqual(shortcut("On"));
    expect(go(session, "interrupted")).not.toContainEqual(shortcut("Off"));
  });

  it("never starts a playlist over music the user is playing", () => {
    const session = new FocusSession();
    expect(go(session, "focusing", full, ["spotify"])).not.toContainEqual(play(spotify));
    expect(go(session, "interrupted")).not.toContainEqual(pause("spotify"));
  });

  it("respects a manual pause until the session ends", () => {
    const session = new FocusSession();
    go(session, "focusing");
    session.observe("playing", "spotify");
    session.observe("paused", "spotify");
    expect(go(session, "interrupted")).toEqual([stopSound, shortcut("Off")]);
    expect(go(session, "focusing")).not.toContainEqual(play(spotify));
    expect(go(session, "interrupted")).not.toContainEqual(pause("spotify"));
    go(session, "idle");
    expect(go(session, "focusing")).toContainEqual(play(spotify));
  });

  it("resumes a playlist paused at the break where it left off", () => {
    const session = new FocusSession();
    go(session, "focusing");
    session.observe("playing", "spotify");
    go(session, "interrupted");
    session.observe("paused", "spotify");
    const next = go(session, "focusing");
    expect(next).toContainEqual(resume("spotify"));
    expect(next).not.toContainEqual(play(spotify));
    session.observe("playing", "spotify");
    expect(go(session, "interrupted")).toContainEqual(pause("spotify"));
    go(session, "idle");
    expect(go(session, "focusing")).toContainEqual(play(spotify));
  });

  it("starts fresh when the user played or quit during the break", () => {
    for (const state of ["playing", "stopped"] as const) {
      const session = new FocusSession();
      go(session, "focusing");
      session.observe("playing", "spotify");
      go(session, "interrupted");
      session.observe(state, "spotify");
      expect(go(session, "focusing")).toContainEqual(play(spotify));
    }
  });

  it("plays a changed playlist rather than resuming", () => {
    const session = new FocusSession();
    go(session, "focusing");
    session.observe("playing", "spotify");
    go(session, "interrupted");
    expect(go(session, "focusing", picking("spotify:playlist:other"))).toContainEqual(
      play({ kind: "spotify", uri: "spotify:playlist:other" }),
    );
  });

  it("starts a playlist never seen playing fresh next time, and ignores other apps", () => {
    const fresh = new FocusSession();
    go(fresh, "focusing");
    go(fresh, "interrupted");
    expect(go(fresh, "focusing")).toContainEqual(play(spotify));

    const loading = new FocusSession();
    go(loading, "focusing");
    loading.observe("paused", "spotify");
    loading.observe("paused", "music");
    expect(go(loading, "interrupted")).toContainEqual(pause("spotify"));
  });

  it("pauses an Apple Music link only once seen playing", () => {
    const settings = picking("https://music.apple.com/us/playlist/focus/pl.abc");
    const session = new FocusSession();
    expect(go(session, "focusing", settings).some((action) => action.kind === "playPlaylist")).toBe(true);
    expect(go(session, "interrupted")).not.toContainEqual(pause("music"));
    go(session, "focusing", settings);
    session.observe("playing", "music");
    expect(go(session, "interrupted")).toContainEqual(pause("music"));
  });

  it("plays a pick from the mixer right away and looks after it", () => {
    const outside = new FocusSession();
    expect(outside.choosePlaylist(full)).toEqual([play(spotify)]);
    expect(go(outside, "focusing", full, ["spotify"])).not.toContainEqual(play(spotify));
    outside.observe("playing", "spotify");
    expect(go(outside, "interrupted")).toContainEqual(pause("spotify"));

    const loading = new FocusSession();
    loading.choosePlaylist(full);
    expect(go(loading, "focusing")).not.toContainEqual(play(spotify));
  });

  it("makes a pick mid-phase the phase's playlist", () => {
    const session = new FocusSession();
    go(session, "focusing", FocusSettings.default);
    const other: FocusPlaylist = { kind: "spotify", uri: "spotify:playlist:other" };
    expect(session.choosePlaylist(withoutSound(picking("spotify:playlist:other")))).toEqual([play(other)]);
    session.observe("playing", "spotify");
    expect(go(session, "interrupted")).toEqual([pause("spotify")]);
    expect(go(session, "focusing", withoutSound(picking("spotify:playlist:other")))).toEqual([resume("spotify")]);
  });

  it("plays a pick even over music the user declined, and pauses the old app when switching", () => {
    const declined = new FocusSession();
    go(declined, "focusing");
    declined.observe("playing", "spotify");
    declined.observe("paused", "spotify");
    expect(declined.choosePlaylist(picking("spotify:playlist:other"))).toEqual([
      play({ kind: "spotify", uri: "spotify:playlist:other" }),
    ]);

    const switching = new FocusSession();
    go(switching, "focusing");
    switching.observe("playing", "spotify");
    const actions = switching.choosePlaylist(picking("https://music.apple.com/us/playlist/focus/pl.abc"));
    expect(actions[0]).toEqual(pause("spotify"));
    expect(actions).toHaveLength(2);
  });

  it("turning the playlist off pauses only what focus mode started", () => {
    const ours = new FocusSession();
    ours.choosePlaylist(full);
    ours.observe("playing", "spotify");
    expect(ours.choosePlaylist(picking(""))).toEqual([pause("spotify")]);

    const theirs = new FocusSession();
    go(theirs, "focusing", full, ["spotify"]);
    expect(theirs.choosePlaylist(picking(""))).toEqual([]);
    expect(go(theirs, "interrupted")).toEqual([stopSound, shortcut("Off")]);

    const midPhase = new FocusSession();
    go(midPhase, "focusing");
    midPhase.observe("playing", "spotify");
    expect(midPhase.choosePlaylist(picking(""))).toEqual([pause("spotify")]);
    expect(go(midPhase, "interrupted")).toEqual([stopSound, shortcut("Off")]);
  });

  it("resumes the playlist paused at the break when it is picked, and hands back a paused pick", () => {
    const paused = new FocusSession();
    go(paused, "focusing");
    paused.observe("playing", "spotify");
    go(paused, "interrupted");
    expect(paused.choosePlaylist(full)).toEqual([resume("spotify")]);

    const handedBack = new FocusSession();
    handedBack.choosePlaylist(full);
    handedBack.observe("playing", "spotify");
    handedBack.observe("paused", "spotify");
    expect(handedBack.choosePlaylist(picking(""))).toEqual([]);
    handedBack.choosePlaylist(full);
    handedBack.observe("playing", "spotify");
    handedBack.observe("paused", "spotify");
    expect(go(handedBack, "focusing")).toContainEqual(play(spotify));
  });
});
