import Foundation

/// The AppleScript used to read Spotify's state, and the parser for its output.
///
/// Fields are joined with the ASCII unit separator (U+001F) instead of a
/// printable delimiter, so titles containing `|`, tabs, quotes, or newlines
/// can't break the record apart.
public enum SpotifyScript {
    public static let bundleIdentifier = "com.spotify.client"
    public static let fieldSeparator: Character = "\u{1F}"

    /// Returns `stopped`, or every field below separated by U+001F:
    /// state, id, name, artist, album, artwork url, duration (ms),
    /// position (s), shuffling, repeating, sound volume (0 ... 100).
    public static let readState = """
    tell application id "\(bundleIdentifier)"
        set sep to character id 31
        set ps to (player state as text)
        if ps is "stopped" then return ps
        set t to current track
        return ps & sep & (id of t) & sep & (name of t) & sep & (artist of t) & sep & ¬
            (album of t) & sep & (artwork url of t) & sep & (duration of t) & sep & ¬
            (player position) & sep & shuffling & sep & repeating & sep & sound volume
    end tell
    """

    public static let playPause = command("playpause")
    public static let nextTrack = command("next track")
    public static let previousTrack = command("previous track")

    /// Jumps to `seconds` into the current track. Uses a dot decimal so the
    /// script compiles regardless of the user's locale.
    public static func seek(to seconds: TimeInterval) -> String {
        let value = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), max(seconds, 0))
        return command("set player position to \(value)")
    }

    private static func command(_ body: String) -> String {
        "tell application id \"\(bundleIdentifier)\" to \(body)"
    }

    /// Parses the output of `readState`. Returns nil for unrecognized output.
    public static func parse(_ output: String) -> SpotifyPlayback? {
        let fields = output.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            .map(String.init)
        guard let first = fields.first,
              let state = SpotifyPlayerState(rawValue: first.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }

        if fields.count == 1 {
            guard state == .stopped else { return nil }
            return SpotifyPlayback(state: .stopped, track: nil, position: 0,
                                   isShuffling: false, isRepeating: false)
        }
        guard fields.count == 11 else { return nil }

        let artwork = fields[5].trimmingCharacters(in: .whitespacesAndNewlines)
        let track = SpotifyTrack(
            id: fields[1],
            title: fields[2],
            artist: fields[3],
            album: fields[4],
            artworkURL: artwork.isEmpty ? nil : URL(string: artwork),
            duration: (number(fields[6]) ?? 0) / 1000
        )
        var playback = SpotifyPlayback(
            state: state, track: track, position: 0,
            isShuffling: fields[8].trimmingCharacters(in: .whitespaces) == "true",
            isRepeating: fields[9].trimmingCharacters(in: .whitespaces) == "true",
            volume: MediaVolume.parse(fields[10])
        )
        playback.position = playback.clampedPosition(number(fields[7]) ?? 0)
        return playback
    }

    /// AppleScript formats reals with the user's decimal separator
    /// (`12,5` in many locales) and sometimes in exponent form (`1.0E-3`).
    private static func number(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}

/// Why a Spotify AppleScript call failed, from its `NSAppleScript` error number.
public enum SpotifyScriptError: Error, Equatable, Sendable {
    /// -1743: the user denied (or hasn't granted) Automation access.
    case permissionDenied
    /// -600 / -609: Spotify quit between the running check and the call.
    case notRunning
    case other(code: Int)

    public init(code: Int) {
        switch code {
        case -1743: self = .permissionDenied
        case -600, -609: self = .notRunning
        default: self = .other(code: code)
        }
    }
}
