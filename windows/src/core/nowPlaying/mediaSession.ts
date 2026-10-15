import type { Instant, Seconds } from "../time";

/*
 * The media session snapshot the Rust host sends, read from Windows'
 * GlobalSystemMediaTransportControlsSessionManager: one entry per app that
 * publishes a media session (Spotify, the Media Player app, a browser tab
 * playing audio or video). The host subscribes to the manager's change
 * events and sends a fresh snapshot on each, so nothing polls.
 *
 * Field names are camelCase JSON; the host's serde types mirror these
 * exactly. Times are seconds (fractional), instants seconds since 1970.
 */

/**
 * GlobalSystemMediaTransportControlsSessionPlaybackStatus. `changing` is a
 * track change in flight; `opened` a session with nothing started yet.
 */
export type MediaPlaybackStatus = "closed" | "opened" | "changing" | "stopped" | "playing" | "paused";

/** MediaPlaybackAutoRepeatMode: `none`, one `track`, or the whole `list`. */
export type MediaAutoRepeatMode = "none" | "track" | "list";

/** The session's timeline, as GlobalSystemMediaTransportControlsSessionTimelineProperties reports it. */
export interface MediaTimeline {
  /** Seconds; usually 0. */
  start: Seconds;
  /** Seconds; the track length when `start` is 0. */
  end: Seconds;
  /** The position at `lastUpdated`, in seconds. */
  position: Seconds;
  minSeek: Seconds;
  maxSeek: Seconds;
  /** When the app last reported `position`, seconds since 1970. Windows does not tick it while playing. */
  lastUpdated: Instant;
}

/** Which controls the app says it supports right now (GlobalSystemMediaTransportControlsSessionPlaybackControls). */
export interface MediaControls {
  play: boolean;
  pause: boolean;
  playPause: boolean;
  stop: boolean;
  next: boolean;
  previous: boolean;
  /** Seeking by position (TryChangePlaybackPositionAsync). */
  seek: boolean;
  shuffle: boolean;
  repeat: boolean;
}

/** The artwork thumbnail, read from the session's stream reference and encoded by the host. */
export interface MediaThumbnail {
  /** `image/png` or `image/jpeg`, as the stream reports it. */
  contentType: string;
  /** The image bytes, base64. */
  base64: string;
}

/** One app's media session at the moment of the snapshot. */
export interface MediaSessionSnapshot {
  /** SourceAppUserModelId, e.g. `Spotify.exe` or `Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic`. */
  sourceAppId: string;
  title: string;
  artist: string;
  albumTitle: string;
  albumArtist?: string;
  /** Present when the app published artwork. */
  thumbnail?: MediaThumbnail;
  playbackStatus: MediaPlaybackStatus;
  /** Absent when the app publishes no timeline (many browsers' live streams). */
  timeline?: MediaTimeline;
  /** Undefined when the app doesn't report shuffle. */
  shuffle?: boolean;
  /** Undefined when the app doesn't report a repeat mode. */
  repeat?: MediaAutoRepeatMode;
  /** 1 for normal speed; undefined when not reported. */
  playbackRate?: number;
  controls: MediaControls;
}

/** Everything the host knows about media sessions, sent on every change. */
export interface MediaSessionsSnapshot {
  /** Every session, in the manager's order. */
  sessions: MediaSessionSnapshot[];
  /** The `sourceAppId` Windows itself considers current (GetCurrentSession), if any. */
  currentSourceAppId?: string;
  /** When the host took the snapshot, seconds since 1970. */
  capturedAt: Instant;
}

/** The commands the panel sends back; the host calls the matching Try...Async method on the session. */
export type MediaCommand =
  | { kind: "playPause" }
  | { kind: "next" }
  | { kind: "previous" }
  | { kind: "seek"; position: Seconds }
  | { kind: "setShuffle"; isOn: boolean }
  | { kind: "setRepeat"; mode: MediaAutoRepeatMode };

/** A command for one session. */
export interface MediaSessionCommand {
  sourceAppId: string;
  command: MediaCommand;
}
