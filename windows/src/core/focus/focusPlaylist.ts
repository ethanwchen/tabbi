/** Port of MediaSource: the music apps a focus playlist plays in. */
export type MediaSource = "spotify" | "music";

/** Port of SpotifyPlayerState: what a music app reports about playback. */
export type PlayerState = "playing" | "paused" | "stopped";

/**
 * Port of FocusPlaylist: what the user typed into the focus playlist field,
 * understood. A Spotify link or URI, an Apple Music link, or the name of a
 * playlist in the user's library; anything that is not recognizably Spotify
 * or an Apple Music link is a library playlist name, so "Deep Work" just works.
 */
export type FocusPlaylist =
  /** A Spotify URI such as `spotify:playlist:37i9dQZF1DWZeKCadgRdKQ`. */
  | { readonly kind: "spotify"; readonly uri: string }
  /** An Apple Music catalog link (`https://music.apple.com/...`). */
  | { readonly kind: "appleMusicLink"; readonly url: string }
  /** A playlist in the user's library, by name. */
  | { readonly kind: "musicLibrary"; readonly name: string };

/** Spotify item kinds that can be played as a context. */
const SPOTIFY_KINDS = new Set(["playlist", "album", "artist", "track", "show", "episode"]);

function spotifyURI(kind: string, id: string): string | undefined {
  const lowered = kind.toLowerCase();
  if (!SPOTIFY_KINDS.has(lowered) || id.length === 0 || !/^[A-Za-z0-9]+$/.test(id)) return undefined;
  return `spotify:${lowered}:${id}`;
}

/*
 * Normalizes `spotify:<kind>:<id>` (and the legacy
 * `spotify:user:<name>:playlist:<id>` form) to `spotify:<kind>:<id>`.
 */
function spotifyURIFromURI(uri: string): string | undefined {
  const parts = uri.split(":");
  const id = parts[parts.length - 1];
  const kind = parts[parts.length - 2];
  if (parts.length < 3 || parts.length % 2 !== 1 || id === undefined || kind === undefined) return undefined;
  return spotifyURI(kind, id);
}

/* Reads `/<kind>/<id>` from a link path, skipping locale prefixes such as `/intl-de/` and legacy `/user/<name>/`. */
function spotifyURIFromPath(pathname: string): string | undefined {
  const segments = pathname
    .split("/")
    .filter((segment) => segment.length > 0)
    .map((segment) => {
      try {
        return decodeURIComponent(segment);
      } catch {
        return segment;
      }
    });
  let index = -1;
  segments.forEach((segment, position) => {
    if (SPOTIFY_KINDS.has(segment.toLowerCase())) index = position;
  });
  const kind = segments[index];
  const id = segments[index + 1];
  if (index < 0 || kind === undefined || id === undefined) return undefined;
  return spotifyURI(kind, id);
}

/* A web link with a host, as Foundation's URL(string:) reads one: scheme, "://", host. */
function webLink(input: string): URL | undefined {
  if (!/^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(input)) return undefined;
  try {
    const url = new URL(input);
    return url.hostname.length > 0 ? url : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Parses the field's text; undefined when it is blank or a malformed Spotify
 * reference (a Spotify link that cannot become a URI must not fall through
 * and be searched for as a library playlist name), or a web link to anywhere
 * else.
 */
export function parseFocusPlaylist(text: string): FocusPlaylist | undefined {
  const input = text.trim();
  if (input.length === 0) return undefined;
  if (input.toLowerCase().startsWith("spotify:")) {
    const uri = spotifyURIFromURI(input);
    return uri === undefined ? undefined : { kind: "spotify", uri };
  }
  const url = webLink(input);
  if (url !== undefined) {
    const scheme = url.protocol.toLowerCase();
    if (scheme === "https:" || scheme === "http:") {
      const host = url.hostname.toLowerCase();
      if (host === "open.spotify.com" || host === "play.spotify.com") {
        const uri = spotifyURIFromPath(url.pathname);
        return uri === undefined ? undefined : { kind: "spotify", uri };
      }
      if (host === "music.apple.com" || host === "itunes.apple.com") return { kind: "appleMusicLink", url: input };
      return undefined;
    }
  }
  return { kind: "musicLibrary", name: input };
}

/** The app that plays this playlist. */
export function playlistSource(playlist: FocusPlaylist): MediaSource {
  return playlist.kind === "spotify" ? "spotify" : "music";
}

export function playlistsEqual(a: FocusPlaylist | undefined, b: FocusPlaylist | undefined): boolean {
  if (a === undefined || b === undefined) return a === b;
  switch (a.kind) {
    case "spotify":
      return b.kind === "spotify" && a.uri === b.uri;
    case "appleMusicLink":
      return b.kind === "appleMusicLink" && a.url === b.url;
    case "musicLibrary":
      return b.kind === "musicLibrary" && a.name === b.name;
  }
}

/**
 * Port of FocusPlaylistScript.startsPlayback: whether starting the playlist
 * plays audio by itself rather than just showing it (an Apple Music catalog
 * link only opens its page).
 */
export function playlistStartsPlayback(playlist: FocusPlaylist): boolean {
  return playlist.kind !== "appleMusicLink";
}

/**
 * Port of FocusPlaylistPreset: a well-known lo-fi or ambient study playlist
 * offered in Settings. Picking one only fills the playlist field with its link.
 */
export interface FocusPlaylistPreset {
  readonly name: string;
  /** Who curates it, shown as secondary text. */
  readonly curator: string;
  /** The link written into the playlist field. */
  readonly link: string;
}

export const FOCUS_PLAYLIST_PRESETS: readonly FocusPlaylistPreset[] = [
  { name: "beats to relax/study to", curator: "Lofi Girl", link: "https://open.spotify.com/playlist/0vvXsWCC9xrXsKd4FyS8kM" },
  { name: "lofi beats", curator: "Spotify", link: "https://open.spotify.com/playlist/37i9dQZF1DWWQRwui0ExPn" },
  { name: "Deep Focus", curator: "Spotify", link: "https://open.spotify.com/playlist/37i9dQZF1DWZeKCadgRdKQ" },
  { name: "Peaceful Piano", curator: "Spotify", link: "https://open.spotify.com/playlist/37i9dQZF1DX4sWSpwq3LiO" },
  {
    name: "Study Beats",
    curator: "Apple Music",
    link: "https://music.apple.com/us/playlist/study-beats/pl.a4e197979fc74b2a91b3cdf869f12aa5",
  },
  {
    name: "Pure Focus",
    curator: "Apple Music",
    link: "https://music.apple.com/us/playlist/pure-focus/pl.dbd712beded846dca273d5d3259d28aa",
  },
];

/** The app a preset plays in. */
export function presetSource(preset: FocusPlaylistPreset): MediaSource {
  const playlist = parseFocusPlaylist(preset.link);
  return playlist === undefined ? "spotify" : playlistSource(playlist);
}

/**
 * The preset the field's text refers to, matched by parsed playlist, so a
 * Spotify link with a `?si=` tracking parameter or the `spotify:` URI still counts.
 */
export function matchingPlaylistPreset(
  text: string,
  presets: readonly FocusPlaylistPreset[] = FOCUS_PLAYLIST_PRESETS,
): FocusPlaylistPreset | undefined {
  const playlist = parseFocusPlaylist(text);
  if (playlist === undefined) return undefined;
  return presets.find((preset) => playlistsEqual(parseFocusPlaylist(preset.link), playlist));
}
