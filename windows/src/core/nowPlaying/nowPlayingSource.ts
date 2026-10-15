import type { Instant } from "../time";
import type { MediaAutoRepeatMode, MediaCommand, MediaSessionSnapshot, MediaSessionsSnapshot } from "./mediaSession";
import { clampedPosition, type NowPlayingPlayback, type PlayerState, type RepeatMode, NOTHING_PLAYING, isPlaying } from "./nowPlayingPlayback";

/*
 * How a Windows media session maps onto the Now Playing panel: the Mac's
 * players (Spotify and Music over AppleScript, SoundCloud in a browser tab)
 * become whatever app publishes a session, keyed by its app id.
 */

/** A player the panel can follow: one app's media session, by its SourceAppUserModelId. */
export type NowPlayingSourceID = string;

/** Kinds of player, for wording and the repeat button. */
export type PlayerKind = "spotify" | "mediaPlayer" | "browser" | "other";

const browsers: [RegExp, string][] = [
  [/msedge/i, "Microsoft Edge"],
  [/chrome/i, "Google Chrome"],
  [/firefox|308046B0AF4A39CB/i, "Firefox"],
  [/brave/i, "Brave"],
  [/opera/i, "Opera"],
  [/vivaldi/i, "Vivaldi"],
];

export function playerKind(sourceAppId: string): PlayerKind {
  if (/spotify/i.test(sourceAppId)) return "spotify";
  if (/ZuneMusic|ZuneVideo|Microsoft\.Media\.Player/i.test(sourceAppId)) return "mediaPlayer";
  if (browsers.some(([pattern]) => pattern.test(sourceAppId))) return "browser";
  return "other";
}

/**
 * The player's name as users know it: "Spotify", "Media Player", the
 * browser's name, or the app's executable name without `.exe`.
 */
export function playerDisplayName(sourceAppId: string): string {
  switch (playerKind(sourceAppId)) {
    case "spotify":
      return "Spotify";
    case "mediaPlayer":
      return /ZuneVideo/i.test(sourceAppId) ? "Movies & TV" : "Media Player";
    case "browser":
      return browsers.find(([pattern]) => pattern.test(sourceAppId))?.[1] ?? sourceAppId;
    case "other": {
      const packaged = sourceAppId.split("!")[0] ?? sourceAppId;
      const name = (packaged.split(/[\\/]/).at(-1) ?? packaged).replace(/\.exe$/i, "").replace(/_[a-z0-9]{13}$/i, "");
      const last = name.split(".").at(-1) ?? name;
      return last.length > 0 ? last : sourceAppId;
    }
  }
}

function repeatFromSession(mode: MediaAutoRepeatMode | undefined): RepeatMode {
  switch (mode) {
    case "track":
      return "one";
    case "list":
      return "all";
    default:
      return "off";
  }
}

/** The session's repeat mode for one of ours. */
export function sessionRepeatMode(mode: RepeatMode): MediaAutoRepeatMode {
  switch (mode) {
    case "one":
      return "track";
    case "all":
      return "list";
    case "off":
      return "none";
  }
}

/**
 * The repeat modes the player can set, in the order its button steps.
 * Every session that supports repeat takes all three; Spotify's own button
 * goes off, all, one, as the Mac's Music does.
 */
export function repeatModes(session: Pick<MediaSessionSnapshot, "controls">): RepeatMode[] {
  return session.controls.repeat ? ["off", "all", "one"] : [];
}

function stateFromSession(status: MediaSessionSnapshot["playbackStatus"]): PlayerState {
  switch (status) {
    case "playing":
      return "playing";
    case "paused":
    case "changing":
      return "paused";
    default:
      return "stopped";
  }
}

/** A stable id for the session's track: the app, title, artist and album (sessions carry no track id). */
export function trackID(session: MediaSessionSnapshot): string {
  return JSON.stringify([session.sourceAppId, session.title, session.artist, session.albumTitle]);
}

/**
 * The playback a session shows at `capturedAt`. Windows does not tick the
 * timeline while playing, so a playing position is carried forward from
 * `lastUpdated` at the session's rate. A session with no title has nothing
 * loaded.
 */
export function playbackFromSession(session: MediaSessionSnapshot, capturedAt: Instant): NowPlayingPlayback {
  const state = stateFromSession(session.playbackStatus);
  const hasTrack = session.title.trim().length > 0 && state !== "stopped";
  if (!hasTrack) return { ...NOTHING_PLAYING, isShuffling: session.shuffle ?? false, repeatMode: repeatFromSession(session.repeat) };
  const timeline = session.timeline;
  const duration = timeline ? Math.max(timeline.end - timeline.start, 0) : 0;
  const artist = session.artist.trim().length > 0 ? session.artist : (session.albumArtist ?? "");
  const track = {
    id: trackID(session),
    title: session.title,
    artist,
    album: session.albumTitle,
    duration,
    ...(session.thumbnail ? { artwork: session.thumbnail } : {}),
  };
  const playback: NowPlayingPlayback = {
    state,
    track,
    position: 0,
    isShuffling: session.shuffle ?? false,
    repeatMode: repeatFromSession(session.repeat),
  };
  if (!timeline) return playback;
  const rate = session.playbackRate !== undefined && session.playbackRate > 0 ? session.playbackRate : 1;
  const elapsed = state === "playing" ? Math.max(capturedAt - timeline.lastUpdated, 0) * rate : 0;
  return { ...playback, position: clampedPosition(playback, timeline.position - timeline.start + elapsed) };
}

/** What the panel can offer for a session: each control the app supports. */
export interface NowPlayingControls {
  playPause: boolean;
  next: boolean;
  previous: boolean;
  seek: boolean;
  shuffle: boolean;
  repeat: boolean;
}

export function controlsFor(session: MediaSessionSnapshot): NowPlayingControls {
  const c = session.controls;
  return {
    playPause: c.playPause || c.play || c.pause,
    next: c.next,
    previous: c.previous,
    seek: c.seek && (session.timeline?.end ?? 0) > (session.timeline?.start ?? 0),
    shuffle: c.shuffle && session.shuffle !== undefined,
    repeat: c.repeat && session.repeat !== undefined,
  };
}

/** The command for one click on the repeat button, or undefined when the session can't repeat. */
export function repeatCommand(session: MediaSessionSnapshot, current: RepeatMode): MediaCommand | undefined {
  const modes = repeatModes(session);
  if (modes.length === 0) return undefined;
  const index = modes.indexOf(current);
  const next = index < 0 ? "off" : (modes[(index + 1) % modes.length] ?? "off");
  return { kind: "setRepeat", mode: sessionRepeatMode(next) };
}

/**
 * Port of SpotifyStatus for a media session: what the panel shows for one
 * player. Windows reports only sessions that exist, so a player is either
 * connected or gone.
 */
export type NowPlayingStatus = { kind: "connected"; playback: NowPlayingPlayback } | { kind: "notRunning" };

export function statusPlayback(status: NowPlayingStatus): NowPlayingPlayback | undefined {
  return status.kind === "connected" ? status.playback : undefined;
}

export function statusIsPlaying(status: NowPlayingStatus): boolean {
  const playback = statusPlayback(status);
  return playback !== undefined && isPlaying(playback);
}

/**
 * Port of MediaSourceTracker: picks the one player the panel follows. A
 * playing player wins (if several play, the one that started most
 * recently); otherwise the one that was playing most recently; then one
 * with a track loaded; then the one Windows calls current; then the current
 * selection, so the panel doesn't flip between equally idle players.
 */
export class MediaSourceTracker {
  private statuses = new Map<NowPlayingSourceID, NowPlayingStatus>();
  private order: NowPlayingSourceID[] = [];
  private chosen: NowPlayingSourceID | undefined;
  private windowsCurrent: NowPlayingSourceID | undefined;
  /** When each player last went from not playing to playing. */
  private readonly playingSince = new Map<NowPlayingSourceID, Instant>();
  /** The last moment each player was known to be playing. */
  private readonly lastPlaying = new Map<NowPlayingSourceID, Instant>();

  /** The player the panel follows; undefined while no session exists. */
  get selected(): NowPlayingSourceID | undefined {
    return this.chosen;
  }

  /** What the panel shows: the selected player's status, or `notRunning` with no session at all. */
  get status(): NowPlayingStatus {
    const status = this.chosen === undefined ? undefined : this.statuses.get(this.chosen);
    return status ?? { kind: "notRunning" };
  }

  /** Records one player's newest status, observed at `date`, and reselects. */
  update(source: NowPlayingSourceID, status: NowPlayingStatus, date: Instant): void {
    const wasPlaying = statusIsPlaying(this.statuses.get(source) ?? { kind: "notRunning" });
    if (statusIsPlaying(status)) {
      if (!wasPlaying) this.playingSince.set(source, date);
      this.lastPlaying.set(source, date);
    } else if (wasPlaying) {
      /* It played right up until this observation. */
      this.lastPlaying.set(source, date);
    }
    if (!this.order.includes(source)) this.order.push(source);
    this.statuses.set(source, status);
    this.chosen = this.select();
  }

  /**
   * Applies a whole snapshot from the host: every listed session is
   * connected, every session no longer listed has gone.
   */
  apply(snapshot: MediaSessionsSnapshot): void {
    this.windowsCurrent = snapshot.currentSourceAppId;
    const listed = new Set(snapshot.sessions.map((session) => session.sourceAppId));
    for (const source of [...this.statuses.keys()]) {
      if (!listed.has(source)) this.update(source, { kind: "notRunning" }, snapshot.capturedAt);
    }
    for (const session of snapshot.sessions) {
      this.update(session.sourceAppId, { kind: "connected", playback: playbackFromSession(session, snapshot.capturedAt) }, snapshot.capturedAt);
    }
  }

  private select(): NowPlayingSourceID | undefined {
    const running = this.order.filter((source) => this.statuses.get(source)?.kind === "connected");
    const playing = running.filter((source) => statusIsPlaying(this.statuses.get(source) ?? { kind: "notRunning" }));
    if (playing.length > 0) return this.best(playing, (source) => this.playingSince.get(source));
    return this.best(running, (source) => this.lastPlaying.get(source));
  }

  /** The candidate with the newest date; ties go to the more useful status, the one Windows calls current, the selection, then order. */
  private best(candidates: NowPlayingSourceID[], date: (source: NowPlayingSourceID) => Instant | undefined): NowPlayingSourceID | undefined {
    const rank = (source: NowPlayingSourceID, index: number): number[] => [
      date(source) ?? -Infinity,
      usefulness(this.statuses.get(source)),
      source === this.windowsCurrent ? 1 : 0,
      source === this.chosen ? 1 : 0,
      -index,
    ];
    let winner: { source: NowPlayingSourceID; rank: number[] } | undefined;
    candidates.forEach((source, index) => {
      const candidate = { source, rank: rank(source, index) };
      if (!winner || compareRanks(candidate.rank, winner.rank) > 0) winner = candidate;
    });
    return winner?.source;
  }
}

function compareRanks(a: number[], b: number[]): number {
  for (let index = 0; index < a.length; index++) {
    const difference = (a[index] ?? 0) - (b[index] ?? 0);
    if (difference !== 0 && !Number.isNaN(difference)) return difference;
    if (a[index] !== b[index]) return (a[index] ?? 0) > (b[index] ?? 0) ? 1 : -1;
  }
  return 0;
}

/** How much an idle player has to show, for breaking selection ties. */
function usefulness(status: NowPlayingStatus | undefined): number {
  if (!status || status.kind !== "connected") return 0;
  return status.playback.track ? 4 : 1;
}

/**
 * Port of MediaSource.names: player names joined for a sentence in the
 * user's language ("Spotify or Media Player", "Spotify oder Media Player").
 */
export function playerNames(names: readonly string[], locale = "en-US"): string {
  return new Intl.ListFormat(locale, { type: "disjunction" }).format(names);
}
