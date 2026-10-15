import type { Instant, Seconds } from "../time";
import type { MediaThumbnail } from "./mediaSession";
import { clampedVolume } from "./mediaVolume";

/** Port of SpotifyPlayerState. */
export type PlayerState = "playing" | "paused" | "stopped";

/** Port of MediaRepeatMode: a player's repeat setting. */
export type RepeatMode = "off" | "all" | "one";

/** Port of SpotifyTrack: the track a player has loaded. */
export interface NowPlayingTrack {
  /** Stable identity within the player, for caching artwork and the generated cover. */
  id: string;
  title: string;
  artist: string;
  album: string;
  /** The session's thumbnail; undefined draws a generated cover. */
  artwork?: MediaThumbnail;
  /** Length in seconds; 0 when unknown. */
  duration: Seconds;
  /** Whether the user liked the track; undefined when the player can't say, so the heart hides. */
  isFavorite?: boolean;
}

/** Port of SpotifyPlayback: a point-in-time snapshot of a player. */
export interface NowPlayingPlayback {
  state: PlayerState;
  /** Undefined when nothing is loaded. */
  track?: NowPlayingTrack;
  /** Seconds into the track. */
  position: Seconds;
  isShuffling: boolean;
  repeatMode: RepeatMode;
  /** The player's own volume, 0 to 100; undefined when it can't be read (a Windows media session has none). */
  volume?: number;
}

export function makePlayback(fields: NowPlayingPlayback): NowPlayingPlayback {
  const playback = { ...fields };
  if (playback.volume !== undefined) playback.volume = clampedVolume(playback.volume);
  else delete playback.volume;
  return playback;
}

/** A player running with no track loaded. */
export const NOTHING_PLAYING: NowPlayingPlayback = { state: "stopped", position: 0, isShuffling: false, repeatMode: "off" };

export function isPlaying(playback: NowPlayingPlayback): boolean {
  return playback.state === "playing" && playback.track !== undefined;
}

/** Whether any repeat mode is on. */
export function isRepeating(playback: NowPlayingPlayback): boolean {
  return playback.repeatMode !== "off";
}

/** 0 to 1 through the track; 0 when the duration is unknown. */
export function progress(playback: NowPlayingPlayback): number {
  const duration = playback.track?.duration ?? 0;
  if (duration <= 0) return 0;
  return Math.min(Math.max(playback.position / duration, 0), 1);
}

/** `seconds` clamped to the current track's bounds (unbounded above when the length is unknown). */
export function clampedPosition(playback: NowPlayingPlayback, seconds: Seconds): Seconds {
  const upper = playback.track ? (playback.track.duration > 0 ? playback.track.duration : Infinity) : 0;
  return Math.min(Math.max(seconds, 0), upper);
}

/** The snapshot `elapsed` seconds later. Only a playing track moves, and never past its end. */
export function advanced(playback: NowPlayingPlayback, elapsed: Seconds): NowPlayingPlayback {
  if (!isPlaying(playback) || !(elapsed > 0)) return playback;
  return { ...playback, position: clampedPosition(playback, playback.position + elapsed) };
}

/** Optimistic result of play/pause, shown before the player confirms it. Nothing changes with no track. */
export function togglingPlayPause(playback: NowPlayingPlayback): NowPlayingPlayback {
  if (!playback.track) return playback;
  return { ...playback, state: playback.state === "playing" ? "paused" : "playing" };
}

/** Optimistic result of seeking, clamped to the track. */
export function seeking(playback: NowPlayingPlayback, seconds: Seconds): NowPlayingPlayback {
  return { ...playback, position: clampedPosition(playback, seconds) };
}

export function settingShuffle(playback: NowPlayingPlayback, isOn: boolean): NowPlayingPlayback {
  return { ...playback, isShuffling: isOn };
}

export function settingRepeat(playback: NowPlayingPlayback, mode: RepeatMode): NowPlayingPlayback {
  return { ...playback, repeatMode: mode };
}

/** Optimistic result of liking a track; nothing changes when the player can't like it. */
export function settingFavorite(playback: NowPlayingPlayback, isFavorite: boolean): NowPlayingPlayback {
  if (!playback.track || playback.track.isFavorite === undefined) return playback;
  return { ...playback, track: { ...playback.track, isFavorite } };
}

/** Optimistic result of setting the volume; nothing changes when it is unknown, since there's no control. */
export function settingVolume(playback: NowPlayingPlayback, volume: number): NowPlayingPlayback {
  if (playback.volume === undefined) return playback;
  return { ...playback, volume: clampedVolume(volume) };
}

/** What one click on the repeat button turns `mode` into, stepping through `modes`; an unsupported mode goes back to off. */
export function repeatModeAfter(mode: RepeatMode, modes: readonly RepeatMode[]): RepeatMode {
  const index = modes.indexOf(mode);
  if (index < 0) return "off";
  return modes[(index + 1) % modes.length] ?? "off";
}

/**
 * Port of SpotifyPlaybackClock: extrapolates the position between reads, so
 * the scrubber ticks every second without asking the player.
 */
export class PlaybackClock {
  constructor(
    private anchorPlayback: NowPlayingPlayback,
    private anchorDate: Instant,
  ) {}

  get anchor(): NowPlayingPlayback {
    return this.anchorPlayback;
  }

  /** Re-anchors on a fresh snapshot. */
  sync(playback: NowPlayingPlayback, date: Instant): void {
    this.anchorPlayback = playback;
    this.anchorDate = date;
  }

  /** The best estimate of the playback at `date`. */
  playback(date: Instant): NowPlayingPlayback {
    return advanced(this.anchorPlayback, date - this.anchorDate);
  }
}

/**
 * Port of PendingMediaModes: shuffle and repeat values the user just asked
 * for, held over reads that come back before the player applied them, so
 * a button never flips back for a moment. Past `deadline`, reads win.
 */
export interface PendingMediaModes {
  shuffle?: boolean;
  repeatMode?: RepeatMode;
  deadline: Instant;
}

/** How long a requested mode outranks what the player reports. */
export const PENDING_SETTLE_TIME = 1.5;

export function pendingIsActive(pending: PendingMediaModes, date: Instant): boolean {
  return date < pending.deadline;
}

/** `playback` as a read at `date` should show it. */
export function applyPending(pending: PendingMediaModes, playback: NowPlayingPlayback, date: Instant): NowPlayingPlayback {
  if (!pendingIsActive(pending, date)) return playback;
  let copy = playback;
  if (pending.shuffle !== undefined) copy = settingShuffle(copy, pending.shuffle);
  if (pending.repeatMode !== undefined) copy = settingRepeat(copy, pending.repeatMode);
  return copy;
}

/** Adds a request made at `date`, keeping earlier unsettled ones. */
export function addingPending(
  pending: PendingMediaModes,
  request: { shuffle?: boolean; repeatMode?: RepeatMode },
  date: Instant,
): PendingMediaModes {
  const keep = pendingIsActive(pending, date);
  const shuffle = request.shuffle ?? (keep ? pending.shuffle : undefined);
  const repeatMode = request.repeatMode ?? (keep ? pending.repeatMode : undefined);
  return {
    ...(shuffle === undefined ? {} : { shuffle }),
    ...(repeatMode === undefined ? {} : { repeatMode }),
    deadline: date + PENDING_SETTLE_TIME,
  };
}

/** Sample state for demo runs: made-up song, no artwork (so nothing loads), a liked track, shuffle on. */
export const DEMO_PLAYBACK: NowPlayingPlayback = {
  state: "playing",
  track: {
    id: "demo:5A1D3E0C7B92F416",
    title: "Golden Hour Drive",
    artist: "Maple Avenue",
    album: "Long Way Home",
    duration: 243.96,
    isFavorite: true,
  },
  position: 87.4,
  isShuffling: true,
  repeatMode: "off",
  volume: 64,
};
