import { afterEach, describe, expect, it } from "vitest";
import type { AppServices } from "../../../src/app/appServices";
import { DEMO_PLAYBACK } from "../../../src/core/nowPlaying/nowPlayingPlayback";
import { statusPlayback } from "../../../src/core/nowPlaying/nowPlayingSource";
import type { MediaSnapshot } from "../../../src/host/host";
import { hostAction, sessionFromHost, sessionsFromHost, thumbnailFromDataURL } from "../../../src/modules/spotify/hostMedia";
import { NowPlayingModule } from "../../../src/modules/spotify/nowPlayingModule";
import { DEMO_CONTROLS, NO_CONTROLS, WINDOWS_DEMO_PLAYBACK, type NowPlayingStore } from "../../../src/modules/spotify/nowPlayingStore";
import { testApp, type TestApp } from "../../support/runtime";

/* Port of the SpotifyController tests that apply to a media session host: watching, reading, optimistic commands, the demo. */

const START = 1_790_000_000;

function media(fields: Partial<MediaSnapshot> = {}): MediaSnapshot {
  return {
    appId: "Spotify.exe",
    title: "Midnight City",
    artist: "M83",
    album: "Hurry Up, We're Dreaming",
    thumbnail: null,
    status: "playing",
    positionSeconds: 87,
    durationSeconds: 244,
    updatedAt: START * 1000,
    shuffle: false,
    repeat: "none",
    controls: { play: true, pause: true, toggle: true, next: true, previous: true, shuffle: true, repeat: true },
    ...fields,
  };
}

/** Turns the module on when the kit's layout leaves it off, as the snapshot harness does. */
function enable(app: AppServices, id: string): void {
  if (app.settings.current.modules.isEnabled(id)) return;
  app.settings.update((settings) => {
    const modules = settings.modules.clone();
    modules.add(id);
    return { ...settings, modules };
  });
}

let apps: TestApp[] = [];

async function nowPlayingApp(demo = false): Promise<TestApp & { store: NowPlayingStore }> {
  const test = await testApp({ moduleTypes: [NowPlayingModule], ...(demo ? { runMode: { isDemo: true, isSnapshot: false } } : {}) }, START);
  apps.push(test);
  enable(test.app, NowPlayingModule.descriptor.id);
  const module = test.app.modules.instance(NowPlayingModule);
  if (!module) throw new Error("Now Playing not registered");
  return { ...test, store: module.store };
}

afterEach(() => {
  for (const test of apps) test.app.dispose();
  apps = [];
});

const watchCalls = (host: TestApp["host"]) => host.calls.filter((call) => call.name === "mediaWatch").map((call) => call.args[0]);

describe("hostMedia", () => {
  it("maps the host's session onto the core's, offering no seek and no timeline for a live stream", () => {
    const session = sessionFromHost(media({ thumbnail: "data:image/jpeg;base64,/9g=", shuffle: null, repeat: "track" }));
    expect(session.sourceAppId).toBe("Spotify.exe");
    expect(session.thumbnail).toEqual({ contentType: "image/jpeg", base64: "/9g=" });
    expect(session.timeline).toEqual({ start: 0, end: 244, position: 87, minSeek: 0, maxSeek: 244, lastUpdated: START });
    expect(session.shuffle).toBeUndefined();
    expect(session.repeat).toBe("track");
    expect(session.controls).toMatchObject({ playPause: true, seek: false, stop: false, next: true });
    expect(sessionFromHost(media({ durationSeconds: 0 })).timeline).toBeUndefined();
    expect(thumbnailFromDataURL("https://example.com/cover.jpg")).toBeUndefined();
    expect(thumbnailFromDataURL(null)).toBeUndefined();
    expect(sessionsFromHost(null, START)).toEqual({ sessions: [], capturedAt: START });
    expect(sessionsFromHost(media(), START).currentSourceAppId).toBe("Spotify.exe");
  });

  it("turns core commands into host actions, except seeking", () => {
    expect(hostAction({ kind: "playPause" })).toEqual({ type: "toggle" });
    expect(hostAction({ kind: "setShuffle", isOn: true })).toEqual({ type: "shuffle", on: true });
    expect(hostAction({ kind: "setRepeat", mode: "list" })).toEqual({ type: "repeat", mode: "list" });
    expect(hostAction({ kind: "seek", position: 10 })).toBeUndefined();
  });
});

describe("NowPlayingStore", () => {
  it("watches the host only while the panel or the pill's music preview can show the result", async () => {
    const { app, host, store } = await nowPlayingApp();
    /* The island's ticker is active at launch, so the pill could show music: watched. */
    expect(store.isWatching).toBe(true);
    expect(watchCalls(host)).toEqual([true]);
    /* The island opened on another tab: nobody can see what plays. */
    app.ticker?.setActive(false);
    expect(store.isWatching).toBe(false);
    expect(watchCalls(host)).toEqual([true, false]);
    store.setPanelVisible(true);
    expect(store.isWatching).toBe(true);
    store.setPanelVisible(false);
    expect(store.isWatching).toBe(false);
    /* The module turned off: nothing is read even when the pill could show it. */
    app.ticker?.setActive(true);
    expect(store.isWatching).toBe(true);
    store.stop();
    expect(store.isWatching).toBe(false);
    expect(host.calls.some((call) => call.name === "mediaSnapshot")).toBe(true);
  });

  it("shows the host's session with its position carried forward, and shares that music plays", async () => {
    const { app, host, store, clock } = await nowPlayingApp();
    clock.now = START + 10;
    host.emitMedia(media());
    const playback = statusPlayback(store.state.status);
    expect(store.state.source).toBe("Spotify.exe");
    expect(playback?.track?.title).toBe("Midnight City");
    expect(playback?.position).toBeCloseTo(97, 6);
    expect(store.state.isPlaying).toBe(true);
    expect(store.state.controls).toEqual({ playPause: true, next: true, previous: true, seek: false, shuffle: true, repeat: true });
    expect(app.providers.snapshot.get().isPlaying).toBe(true);
    host.emitMedia(media({ status: "paused", positionSeconds: 100, updatedAt: (START + 10) * 1000 }));
    expect(statusPlayback(store.state.status)?.state).toBe("paused");
    expect(app.providers.snapshot.get().isPlaying).toBe(false);
    host.emitMedia(media({ title: "", status: "opened" }));
    expect(statusPlayback(store.state.status)?.track).toBeUndefined();
    host.emitMedia(null);
    expect(store.state.status.kind).toBe("notRunning");
    expect(store.state.controls).toEqual(NO_CONTROLS);
  });

  it("lets go of the session when nobody can see it, so the pill's wings go away", async () => {
    const { app, host, store } = await nowPlayingApp();
    host.emitMedia(media());
    expect(store.state.isPlaying).toBe(true);
    app.ticker?.setActive(false);
    expect(store.state.status.kind).toBe("notRunning");
    expect(app.providers.snapshot.get().isPlaying).toBe(false);
  });

  it("applies a command at once, sends it to the host and reads back", async () => {
    const { host, store } = await nowPlayingApp();
    host.emitMedia(media());
    const before = host.calls.length;
    store.playPause();
    expect(statusPlayback(store.state.status)?.state).toBe("paused");
    expect(host.calls.slice(before).map((call) => call.name)).toEqual(["mediaControl"]);
    expect(host.calls[before]?.args[0]).toEqual({ type: "toggle" });
    await Promise.resolve();
    await Promise.resolve();
    expect(host.calls.slice(before).map((call) => call.name)).toEqual(["mediaControl", "mediaSnapshot"]);
    store.next();
    expect(host.calls.at(-1)?.args[0]).toEqual({ type: "next" });
  });

  it("hides a control the app does not accept and ignores a click on it", async () => {
    const { host, store } = await nowPlayingApp();
    host.emitMedia(media({ controls: { play: true, pause: true, toggle: true, next: false, previous: false, shuffle: false, repeat: true }, shuffle: null }));
    expect(store.state.controls).toEqual({ playPause: true, next: false, previous: false, seek: false, shuffle: false, repeat: true });
    const before = host.calls.length;
    store.next();
    store.toggleShuffle();
    expect(host.calls.length).toBe(before);
  });

  it("keeps a requested shuffle or repeat over a read that comes back before the player applied it", async () => {
    const { host, store, clock } = await nowPlayingApp();
    host.emitMedia(media());
    store.toggleShuffle();
    expect(statusPlayback(store.state.status)?.isShuffling).toBe(true);
    expect(host.calls.at(-1)?.args[0]).toEqual({ type: "shuffle", on: true });
    store.cycleRepeat();
    expect(statusPlayback(store.state.status)?.repeatMode).toBe("all");
    expect(host.calls.at(-1)?.args[0]).toEqual({ type: "repeat", mode: "list" });
    /* A stale read within the settle time does not flip the buttons back. */
    clock.now = START + 1;
    host.emitMedia(media({ shuffle: false, repeat: "none" }));
    expect(statusPlayback(store.state.status)?.isShuffling).toBe(true);
    expect(statusPlayback(store.state.status)?.repeatMode).toBe("all");
    /* Past it, the player's word wins. */
    clock.now = START + 2;
    host.emitMedia(media({ shuffle: false, repeat: "none" }));
    expect(statusPlayback(store.state.status)?.isShuffling).toBe(false);
    expect(statusPlayback(store.state.status)?.repeatMode).toBe("off");
  });

  it("steps repeat off, all, one, off", async () => {
    const { host, store } = await nowPlayingApp();
    host.emitMedia(media({ repeat: "list" }));
    store.cycleRepeat();
    expect(host.calls.at(-1)?.args[0]).toEqual({ type: "repeat", mode: "track" });
    expect(statusPlayback(store.state.status)?.repeatMode).toBe("one");
    store.cycleRepeat();
    expect(host.calls.at(-1)?.args[0]).toEqual({ type: "repeat", mode: "none" });
    expect(statusPlayback(store.state.status)?.repeatMode).toBe("off");
  });

  it("in demo mode shows the demo track, never talks to the host, and skips back to the start", async () => {
    const { host, store, app } = await nowPlayingApp(true);
    expect(store.state.source).toBe("Spotify.exe");
    expect(store.sourceName).toBe("Spotify");
    expect(store.state.controls).toEqual(DEMO_CONTROLS);
    const playback = statusPlayback(store.state.status);
    expect(playback?.track?.title).toBe(DEMO_PLAYBACK.track?.title);
    expect(playback?.volume).toBeUndefined();
    expect(playback?.track?.isFavorite).toBeUndefined();
    expect(WINDOWS_DEMO_PLAYBACK.position).toBe(DEMO_PLAYBACK.position);
    expect(app.providers.snapshot.get().isPlaying).toBe(true);
    store.next();
    expect(statusPlayback(store.state.status)?.position).toBe(0);
    store.playPause();
    expect(statusPlayback(store.state.status)?.state).toBe("paused");
    expect(app.providers.snapshot.get().isPlaying).toBe(false);
    const mediaCalls = host.calls.filter((call) => call.name.startsWith("media"));
    expect(mediaCalls).toEqual([]);
  });

  it("renders each snapshot state", async () => {
    const { store } = await nowPlayingApp(true);
    store.showSnapshotState("paused");
    expect(statusPlayback(store.state.status)?.state).toBe("paused");
    expect(store.state.isPlaying).toBe(false);
    store.showSnapshotState("idle");
    expect(store.state.status.kind).toBe("connected");
    expect(statusPlayback(store.state.status)?.track).toBeUndefined();
    expect(store.state.source).toBe("Spotify.exe");
    store.showSnapshotState("empty");
    expect(store.state.status.kind).toBe("notRunning");
    expect(store.state.source).toBeUndefined();
    store.showSnapshotState("");
    expect(store.state.isPlaying).toBe(true);
  });
});
