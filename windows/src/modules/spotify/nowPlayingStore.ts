/*
 * Port of SpotifyController for Windows: Now Playing's state and controls
 * over the system media session. The host sends a snapshot on every change
 * while watched, and watching is on only while someone can see the result:
 * the panel, or the closed pill's music preview (the ticker says so through
 * `closedPreview.watchedKinds`). Nothing is read before `start()`. Which
 * session the panel follows, the extrapolated position and the modes a
 * click asked for but the player has not shown yet are the core's
 * (MediaSourceTracker, PlaybackClock, PendingMediaModes); this store feeds
 * them, sends the commands and republishes. With `TABBI_DEMO=1` it shows the
 * demo track and never talks to the host.
 */

import type { ModuleContext } from "../../app/context";
import { Store } from "../../app/store";
import type { MediaCommand, MediaSessionSnapshot } from "../../core/nowPlaying/mediaSession";
import {
  addingPending,
  applyPending,
  DEMO_PLAYBACK,
  NOTHING_PLAYING,
  type NowPlayingPlayback,
  pendingIsActive,
  type PendingMediaModes,
  PENDING_SETTLE_TIME,
  PlaybackClock,
  type RepeatMode,
  repeatModeAfter,
  seeking,
  settingRepeat,
  settingShuffle,
  togglingPlayPause,
} from "../../core/nowPlaying/nowPlayingPlayback";
import {
  controlsFor,
  MediaSourceTracker,
  type NowPlayingControls,
  type NowPlayingSourceID,
  type NowPlayingStatus,
  playerDisplayName,
  sessionRepeatMode,
  statusIsPlaying,
} from "../../core/nowPlaying/nowPlayingSource";
import { TICKER_KINDS } from "../../core/ticker/tickerKind";
import type { MediaSnapshot } from "../../host/host";
import { hostAction, sessionsFromHost } from "./hostMedia";

export interface NowPlayingState {
  /** What the panel shows; the playback position is extrapolated while the panel ticks. */
  readonly status: NowPlayingStatus;
  /** The app `status` belongs to (its SourceAppUserModelId); undefined while no session exists. */
  readonly source: NowPlayingSourceID | undefined;
  /** The controls the source's app accepts; every control off while nothing is connected. */
  readonly controls: NowPlayingControls;
  /** Music is playing, so the closed pill shows the music wings. */
  readonly isPlaying: boolean;
}

/** The panel states a snapshot run renders beyond the demo track playing. */
export const NOW_PLAYING_SNAPSHOT_STATES = ["paused", "idle", "empty"] as const;

/** The demo's app: its name and badge read "Spotify", as the Mac's demo names a real player. */
export const DEMO_SOURCE: NowPlayingSourceID = "Spotify.exe";

/**
 * The Mac's demo track without what a Windows session cannot offer (a
 * player volume, whether the track is liked), so the demo shows no control
 * a real session would lack.
 */
export const WINDOWS_DEMO_PLAYBACK: NowPlayingPlayback = {
  state: DEMO_PLAYBACK.state,
  position: DEMO_PLAYBACK.position,
  isShuffling: DEMO_PLAYBACK.isShuffling,
  repeatMode: DEMO_PLAYBACK.repeatMode,
  ...(DEMO_PLAYBACK.track
    ? {
        track: {
          id: DEMO_PLAYBACK.track.id,
          title: DEMO_PLAYBACK.track.title,
          artist: DEMO_PLAYBACK.track.artist,
          album: DEMO_PLAYBACK.track.album,
          duration: DEMO_PLAYBACK.track.duration,
        },
      }
    : {}),
};

export const NO_CONTROLS: NowPlayingControls = { playPause: false, next: false, previous: false, seek: false, shuffle: false, repeat: false };
/** What the demo's session accepts: everything a Windows session can, which is never seeking. */
export const DEMO_CONTROLS: NowPlayingControls = { playPause: true, next: true, previous: true, seek: false, shuffle: true, repeat: true };

/** The repeat modes a session that repeats steps through, in the order its button goes. */
export const REPEAT_ORDER: readonly RepeatMode[] = ["off", "all", "one"];

export class NowPlayingStore extends Store<NowPlayingState> {
  private readonly tracker = new MediaSourceTracker();
  /** Per app, so a snapshot of one never re-anchors another's position. */
  private readonly clocks = new Map<NowPlayingSourceID, PlaybackClock>();
  private readonly sessions = new Map<NowPlayingSourceID, MediaSessionSnapshot>();
  /** Shuffle and repeat changes the player may not show yet. */
  private readonly pendingModes = new Map<NowPlayingSourceID, PendingMediaModes>();
  /** Bumped by every snapshot and command, so a slow read never overwrites a newer state. */
  private generation = 0;
  private isStarted = false;
  private isPanelVisible = false;
  /** The ticker can show the music preview, so the pill needs to know what plays. */
  private tickerWatches = false;
  private stopWatching: (() => void) | undefined;
  private tickTimer: ReturnType<typeof setInterval> | undefined;
  /** What a snapshot run shows instead of the demo. */
  private snapshotOverride: { source: NowPlayingSourceID | undefined; status: NowPlayingStatus } | undefined;
  private readonly stops: (() => void)[] = [];

  constructor(private readonly context: ModuleContext) {
    super({ status: { kind: "notRunning" }, source: undefined, controls: NO_CONTROLS, isPlaying: false });
    if (context.isDemo) {
      this.record(DEMO_SOURCE, { kind: "connected", playback: WINDOWS_DEMO_PLAYBACK });
      return;
    }
    const watched = context.closedPreview.watchedKinds;
    const follow = () => {
      this.tickerWatches = watched.get().has(TICKER_KINDS.nowPlaying);
      this.updateWatch();
    };
    this.stops.push(watched.subscribe(follow));
    follow();
  }

  /** The name of the app the panel follows, for the empty state and tooltips. */
  get sourceName(): string {
    return playerDisplayName(this.state.source ?? DEMO_SOURCE);
  }

  /** Whether the host is being watched right now. */
  get isWatching(): boolean {
    return this.stopWatching !== undefined;
  }

  /** Follows the media session from now on (while the panel or the pill can show it). */
  start(): void {
    if (this.isStarted) return;
    this.isStarted = true;
    this.updateWatch();
  }

  /** Stops following and lets go of the session, so the pill's music wings go away with the tab. */
  stop(): void {
    if (!this.isStarted) return;
    this.isStarted = false;
    this.updateWatch();
  }

  /** Stops following the ticker too; for a window going away. */
  dispose(): void {
    this.stop();
    for (const stop of this.stops) stop();
    this.stops.length = 0;
  }

  /** Call from the panel's mount and unmount: the position ticks and the host is watched only while it can be seen. */
  setPanelVisible(visible: boolean): void {
    if (visible === this.isPanelVisible) return;
    this.isPanelVisible = visible;
    this.updateWatch();
    this.updateTimers();
  }

  /** One snapshot from the host; also how tests drive the store. */
  applySnapshot(media: MediaSnapshot | null): void {
    this.generation += 1;
    const now = this.context.now();
    const snapshot = sessionsFromHost(media, now);
    this.sessions.clear();
    for (const session of snapshot.sessions) this.sessions.set(session.sourceAppId, session);
    this.tracker.apply(snapshot);
    this.clocks.clear();
    for (const source of this.sessions.keys()) {
      const status = this.tracker.statusOf(source);
      if (status.kind !== "connected") continue;
      const pending = this.pendingModes.get(source);
      this.clocks.set(source, new PlaybackClock(pending ? applyPending(pending, status.playback, now) : status.playback, now));
    }
    this.publish();
  }

  // Commands

  playPause(): void {
    const playback = this.currentPlayback();
    if (!playback?.track || !this.state.controls.playPause) return;
    this.applyOptimistic(togglingPlayPause(playback));
    this.send({ kind: "playPause" });
  }

  next(): void {
    if (this.state.source === undefined || !this.state.controls.next) return;
    if (this.context.isDemo) this.applyOptimistic(seeking(WINDOWS_DEMO_PLAYBACK, 0));
    this.send({ kind: "next" });
  }

  previous(): void {
    if (this.state.source === undefined || !this.state.controls.previous) return;
    if (this.context.isDemo) this.applyOptimistic(seeking(WINDOWS_DEMO_PLAYBACK, 0));
    this.send({ kind: "previous" });
  }

  /** Turns shuffle on or off in the active app. */
  toggleShuffle(): void {
    const playback = this.currentPlayback();
    if (!playback?.track || !this.state.controls.shuffle) return;
    const isOn = !playback.isShuffling;
    this.expectModes({ shuffle: isOn });
    this.applyOptimistic(settingShuffle(playback, isOn));
    this.sendModeChange({ kind: "setShuffle", isOn });
  }

  /** Steps the active app's repeat mode: off, all, then one. */
  cycleRepeat(): void {
    const playback = this.currentPlayback();
    if (!playback?.track || !this.state.controls.repeat) return;
    const mode = repeatModeAfter(playback.repeatMode, REPEAT_ORDER);
    this.expectModes({ repeatMode: mode });
    this.applyOptimistic(settingRepeat(playback, mode));
    this.sendModeChange({ kind: "setRepeat", mode: sessionRepeatMode(mode) });
  }

  // Snapshots

  /** Shows `state` in the panel for a snapshot run: the demo track paused, an app with nothing loaded, or no session at all. */
  showSnapshotState(state: string): void {
    switch (state) {
      case "paused":
        this.snapshotOverride = { source: DEMO_SOURCE, status: { kind: "connected", playback: { ...WINDOWS_DEMO_PLAYBACK, state: "paused" } } };
        break;
      case "idle":
        this.snapshotOverride = { source: DEMO_SOURCE, status: { kind: "connected", playback: NOTHING_PLAYING } };
        break;
      case "empty":
        this.snapshotOverride = { source: undefined, status: { kind: "notRunning" } };
        break;
      default:
        this.snapshotOverride = undefined;
    }
    this.publish();
  }

  // Watching

  /** The host is watched while the module runs and the panel or the pill can show the result; never in demo runs. */
  private updateWatch(): void {
    const wanted = this.isStarted && !this.context.isDemo && (this.isPanelVisible || this.tickerWatches);
    if (wanted === this.isWatching) return;
    if (!wanted) {
      this.stopWatching?.();
      this.stopWatching = undefined;
      this.release();
      return;
    }
    const host = this.context.host;
    const unsubscribe = host.onMedia((media) => this.applySnapshot(media));
    const fail = (error: unknown) => this.context.logger.error("media watch failed", error);
    void host.mediaWatch(true).catch(fail);
    this.stopWatching = () => {
      unsubscribe();
      void host.mediaWatch(false).catch(fail);
    };
    this.refresh();
  }

  /** Reads the session now; a reply older than a later snapshot or command is dropped. */
  private refresh(): void {
    if (!this.isWatching) return;
    const current = ++this.generation;
    void this.context.host
      .mediaSnapshot()
      .then((media) => {
        if (current !== this.generation) return;
        this.applySnapshot(media);
      })
      .catch((error: unknown) => this.context.logger.error("media snapshot failed", error));
  }

  /** Forgets every session without reading, superseding any read still in flight. */
  private release(): void {
    this.generation += 1;
    this.sessions.clear();
    this.clocks.clear();
    this.pendingModes.clear();
    this.tracker.apply({ sessions: [], capturedAt: this.context.now() });
    this.publish();
  }

  // Sending

  private send(command: MediaCommand): void {
    if (this.context.isDemo) return;
    const action = hostAction(command);
    if (this.state.source === undefined || action === undefined) return;
    this.generation += 1;
    void this.context.host
      .mediaControl(action)
      .catch((error: unknown) => this.context.logger.error("media control failed", error))
      .then(() => this.refresh());
  }

  /**
   * Sends a shuffle or repeat change, then reads the session again once it
   * has settled, so the buttons end on the player's real state (Spotify
   * applies these a moment after the command returns).
   */
  private sendModeChange(command: MediaCommand): void {
    this.send(command);
    if (this.context.isDemo) return;
    const source = this.state.source;
    if (source === undefined) return;
    setTimeout(
      () => {
        const pending = this.pendingModes.get(source);
        if (pending === undefined || pendingIsActive(pending, this.context.now())) return;
        this.pendingModes.delete(source);
        this.refresh();
      },
      (PENDING_SETTLE_TIME + 0.1) * 1000,
    );
  }

  private expectModes(request: { shuffle?: boolean; repeatMode?: RepeatMode }): void {
    const source = this.state.source;
    if (source === undefined) return;
    const now = this.context.now();
    this.pendingModes.set(source, addingPending(this.pendingModes.get(source) ?? { deadline: now }, request, now));
  }

  private applyOptimistic(playback: NowPlayingPlayback): void {
    const source = this.state.source;
    if (source === undefined) return;
    this.generation += 1;
    this.record(source, { kind: "connected", playback });
  }

  /** The followed app's last known playback with its position extrapolated to now. */
  private currentPlayback(): NowPlayingPlayback | undefined {
    const source = this.state.source;
    if (source === undefined) return undefined;
    const status = this.latestStatus(source);
    return status.kind === "connected" ? status.playback : undefined;
  }

  /** Stores `source`'s status, re-anchoring its position clock, and republishes whichever app the tracker now selects. */
  private record(source: NowPlayingSourceID, status: NowPlayingStatus): void {
    const now = this.context.now();
    if (status.kind === "connected") this.clocks.set(source, new PlaybackClock(status.playback, now));
    else this.clocks.delete(source);
    this.tracker.update(source, status, now);
    this.publish();
  }

  private latestStatus(source: NowPlayingSourceID): NowPlayingStatus {
    const clock = this.clocks.get(source);
    if (clock) return { kind: "connected", playback: clock.playback(this.context.now()) };
    return this.tracker.statusOf(source);
  }

  private controlsOf(source: NowPlayingSourceID | undefined): NowPlayingControls {
    if (source === undefined) return NO_CONTROLS;
    if (this.context.isDemo) return DEMO_CONTROLS;
    const session = this.sessions.get(source);
    return session ? controlsFor(session) : NO_CONTROLS;
  }

  private publish(): void {
    const override = this.snapshotOverride;
    const source = override ? override.source : this.tracker.selected;
    const status = override ? override.status : source === undefined ? this.tracker.status : this.latestStatus(source);
    const controls = override ? (override.status.kind === "connected" && override.status.playback.track ? DEMO_CONTROLS : NO_CONTROLS) : this.controlsOf(source);
    this.setState({
      status: samePlayback(this.state.status, status) ? this.state.status : status,
      source,
      controls: sameControls(this.state.controls, controls) ? this.state.controls : controls,
      isPlaying: statusIsPlaying(status),
    });
    this.updateTimers();
  }

  // Timers

  /** The position ticks once a second only while the panel can be seen and a track plays; never in a snapshot. */
  private updateTimers(): void {
    const tick = this.isPanelVisible && this.state.isPlaying && !this.context.isSnapshot && this.snapshotOverride === undefined;
    if (tick && this.tickTimer === undefined) {
      this.tickTimer = setInterval(() => this.tick(), 1000);
    } else if (!tick && this.tickTimer !== undefined) {
      clearInterval(this.tickTimer);
      this.tickTimer = undefined;
    }
  }

  private tick(): void {
    const source = this.state.source;
    const clock = source === undefined ? undefined : this.clocks.get(source);
    if (clock === undefined) return;
    const status: NowPlayingStatus = { kind: "connected", playback: clock.playback(this.context.now()) };
    if (!samePlayback(this.state.status, status)) this.setState({ status });
  }
}

function samePlayback(a: NowPlayingStatus, b: NowPlayingStatus): boolean {
  if (a.kind !== b.kind) return false;
  if (a.kind !== "connected" || b.kind !== "connected") return true;
  const x = a.playback;
  const y = b.playback;
  return (
    x.state === y.state &&
    x.position === y.position &&
    x.isShuffling === y.isShuffling &&
    x.repeatMode === y.repeatMode &&
    x.volume === y.volume &&
    x.track?.id === y.track?.id &&
    x.track?.title === y.track?.title &&
    x.track?.artist === y.track?.artist &&
    x.track?.album === y.track?.album &&
    x.track?.duration === y.track?.duration &&
    x.track?.isFavorite === y.track?.isFavorite &&
    x.track?.artwork?.base64 === y.track?.artwork?.base64
  );
}

function sameControls(a: NowPlayingControls, b: NowPlayingControls): boolean {
  return a.playPause === b.playPause && a.next === b.next && a.previous === b.previous && a.seek === b.seek && a.shuffle === b.shuffle && a.repeat === b.repeat;
}
