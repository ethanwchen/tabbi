/*
 * The Windows host's media session as the core's Now Playing reads it. The
 * host sends one snapshot of the session Windows calls current (a data URL
 * for the artwork, a position stamped with when the app last reported it)
 * and takes a small set of actions; the core's MediaSessionsSnapshot and
 * MediaCommand are the wider shape the panel logic was written against, so
 * this file is the one place the two meet.
 */

import type { MediaAction, MediaSnapshot } from "../../host/host";
import type { MediaCommand, MediaSessionSnapshot, MediaSessionsSnapshot, MediaThumbnail } from "../../core/nowPlaying/mediaSession";
import type { Instant } from "../../core/time";

const DATA_URL = /^data:([^;,]+);base64,(.*)$/s;

/** The host's `data:<type>;base64,...` artwork as the core's thumbnail; undefined for anything else. */
export function thumbnailFromDataURL(url: string | null): MediaThumbnail | undefined {
  if (url === null) return undefined;
  const match = DATA_URL.exec(url);
  const base64 = match?.[2];
  if (match === null || match[1] === undefined || base64 === undefined || base64.length === 0) return undefined;
  return { contentType: match[1], base64 };
}

/**
 * One host session as the core's. Windows media sessions take no seek
 * through the host, so `seek` is never offered; a session without a
 * duration (a live stream) publishes no timeline.
 */
export function sessionFromHost(media: MediaSnapshot): MediaSessionSnapshot {
  const thumbnail = thumbnailFromDataURL(media.thumbnail);
  const duration = Number.isFinite(media.durationSeconds) ? Math.max(media.durationSeconds, 0) : 0;
  const position = Number.isFinite(media.positionSeconds) ? Math.max(media.positionSeconds, 0) : 0;
  return {
    sourceAppId: media.appId,
    title: media.title,
    artist: media.artist,
    albumTitle: media.album,
    ...(thumbnail ? { thumbnail } : {}),
    playbackStatus: media.status,
    ...(duration > 0
      ? { timeline: { start: 0, end: duration, position, minSeek: 0, maxSeek: duration, lastUpdated: media.updatedAt / 1000 } }
      : {}),
    ...(media.shuffle === null ? {} : { shuffle: media.shuffle }),
    ...(media.repeat === null ? {} : { repeat: media.repeat }),
    controls: {
      play: media.controls.play,
      pause: media.controls.pause,
      playPause: media.controls.toggle,
      stop: false,
      next: media.controls.next,
      previous: media.controls.previous,
      seek: false,
      shuffle: media.controls.shuffle,
      repeat: media.controls.repeat,
    },
  };
}

/** Everything the host knows, at `capturedAt`: the one current session, or none. */
export function sessionsFromHost(media: MediaSnapshot | null, capturedAt: Instant): MediaSessionsSnapshot {
  if (media === null) return { sessions: [], capturedAt };
  return { sessions: [sessionFromHost(media)], currentSourceAppId: media.appId, capturedAt };
}

/** The host action for a core command; undefined for one the host cannot do (seeking). */
export function hostAction(command: MediaCommand): MediaAction | undefined {
  switch (command.kind) {
    case "playPause":
      return { type: "toggle" };
    case "next":
      return { type: "next" };
    case "previous":
      return { type: "previous" };
    case "setShuffle":
      return { type: "shuffle", on: command.isOn };
    case "setRepeat":
      return { type: "repeat", mode: command.mode };
    case "seek":
      return undefined;
  }
}
