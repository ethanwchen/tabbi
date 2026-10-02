import Foundation

/// The AppleScript that starts a focus playlist, plus the pause command.
///
/// Scripts address apps by bundle id, like `SpotifyScript` and
/// `MusicScript`. Sending one launches the app if it isn't running, so the
/// app layer only sends `play` when a focus phase really starts.
public enum FocusPlaylistScript {
    /// Starts `playlist` from its first track.
    ///
    /// Spotify plays any URI as a context. Music plays library playlists by
    /// name. Music can't play an Apple Music catalog playlist from a script
    /// (the scripting dictionary only sees library items), so a link opens
    /// the playlist's page in Music for the user to press play; see
    /// `startsPlayback`.
    public static func play(_ playlist: FocusPlaylist) -> String {
        switch playlist {
        case .spotify(let uri):
            return tell(.spotify, "play track \(quoted(uri))")
        case .musicLibrary(let name):
            // Shuffle and repeat stay as the user set them in Music.
            return tell(.music, "play playlist \(quoted(name))")
        case .appleMusicLink(let url):
            return tell(.music, "open location \(quoted(musicURL(for: url)))")
        }
    }

    /// True when `play(_:)` starts audio by itself rather than just showing
    /// the playlist.
    public static func startsPlayback(_ playlist: FocusPlaylist) -> Bool {
        if case .appleMusicLink = playlist { return false }
        return true
    }

    /// Resumes `source` where it was paused, keeping its queue and position.
    public static func resume(_ source: MediaSource) -> String {
        tell(source, "play")
    }

    /// Pauses `source`. Unlike `playpause`, this never starts playback, so
    /// it's safe to send even if the user already paused.
    public static func pause(_ source: MediaSource) -> String {
        tell(source, "pause")
    }

    /// Wraps `text` in an AppleScript string literal, escaping backslashes
    /// and quotes so a playlist name can never break out of the string.
    public static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return "\"\(escaped)\""
    }

    /// The `music://` form of a catalog link, which Music opens itself
    /// instead of handing it to the default browser.
    static func musicURL(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = "music"
        return components.string ?? url.absoluteString
    }

    private static func tell(_ source: MediaSource, _ body: String) -> String {
        "tell application id \"\(source.bundleIdentifier)\" to \(body)"
    }
}
