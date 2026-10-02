import Foundation

/// The AppleScript used to read Apple Music's state, and the parser for its
/// output. Uses the same U+001F-separated record format as `SpotifyScript`.
public enum MusicScript {
    public static let bundleIdentifier = "com.apple.Music"
    /// Prefix for track ids so a Music persistent ID can never collide with
    /// a Spotify URI in shared caches.
    public static let trackIDPrefix = "music:"

    /// Returns `stopped`, or every field below separated by U+001F:
    /// state, persistent id, name, artist, album, duration (s), position (s),
    /// shuffle enabled, song repeat (`off` / `one` / `all`).
    ///
    /// Radio streams and some cloud tracks report `missing value` for
    /// duration, position, artist, or album; concatenating that would turn
    /// the result into a list, so each optional field is read inside `try`
    /// with a plain-text fallback.
    public static let readState = """
    tell application id "\(bundleIdentifier)"
        set sep to character id 31
        set ps to (player state as text)
        if ps is "stopped" then return ps
        set t to current track
        set pid to ""
        set nm to ""
        set ar to ""
        set al to ""
        set d to 0
        set p to 0
        try
            set pid to (persistent ID of t) as text
        end try
        try
            set nm to (name of t) as text
        end try
        try
            set ar to (artist of t) as text
        end try
        try
            set al to (album of t) as text
        end try
        try
            set d to (duration of t) as real
        end try
        try
            set p to (player position) as real
        end try
        return ps & sep & pid & sep & nm & sep & ar & sep & al & sep & d & sep & p & sep & ¬
            (shuffle enabled as text) & sep & (song repeat as text)
    end tell
    """

    /// The current track's first artwork as raw image bytes (JPEG or PNG),
    /// or `missing value` when it has none or the track already changed.
    /// Music has no artwork URLs, so the controller reads this once per
    /// track and keeps the decoded image in memory.
    ///
    /// Returns nil for ids `parse` didn't derive from a persistent ID (e.g.
    /// streams), since the script can't confirm which track it would read.
    /// Checking the persistent ID inside the script makes the read atomic:
    /// a track change between the request and the read can never store one
    /// track's cover under another track's id.
    public static func readArtwork(forTrackID trackID: String) -> String? {
        guard trackID.hasPrefix(trackIDPrefix) else { return nil }
        let persistentID = trackID.dropFirst(trackIDPrefix.count)
        guard !persistentID.isEmpty, persistentID.allSatisfy(\.isHexDigit) else { return nil }
        return """
        tell application id "\(bundleIdentifier)"
            if (persistent ID of current track) is not "\(persistentID)" then return missing value
            if (count of artworks of current track) is 0 then return missing value
            return raw data of artwork 1 of current track
        end tell
        """
    }

    public static let playPause = command("playpause")
    public static let nextTrack = command("next track")
    public static let previousTrack = command("previous track")

    /// Jumps to `seconds` into the current track, with a locale-proof decimal.
    public static func seek(to seconds: TimeInterval) -> String {
        let value = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), max(seconds, 0))
        return command("set player position to \(value)")
    }

    private static func command(_ body: String) -> String {
        "tell application id \"\(bundleIdentifier)\" to \(body)"
    }

    /// Parses the output of `readState`. Returns nil for unrecognized output.
    public static func parse(_ output: String) -> SpotifyPlayback? {
        let fields = output.split(separator: SpotifyScript.fieldSeparator, omittingEmptySubsequences: false)
            .map(String.init)
        guard let first = fields.first,
              let state = playerState(first.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }

        if fields.count == 1 {
            guard state == .stopped else { return nil }
            return .nothingPlaying
        }
        guard fields.count == 9 else { return nil }

        let persistentID = fields[1].trimmingCharacters(in: .whitespaces)
        // Streams without a persistent ID still need a stable-ish identity
        // for the generated cover; the title is the best we have.
        let track = SpotifyTrack(
            id: trackIDPrefix + (persistentID.isEmpty ? fields[2] : persistentID),
            title: fields[2],
            artist: fields[3],
            album: fields[4],
            artworkURL: nil,
            duration: max(number(fields[5]) ?? 0, 0)
        )
        let repeatMode = fields[8].trimmingCharacters(in: .whitespacesAndNewlines)
        var playback = SpotifyPlayback(
            state: state, track: track, position: 0,
            isShuffling: fields[7].trimmingCharacters(in: .whitespaces) == "true",
            isRepeating: repeatMode == "one" || repeatMode == "all"
        )
        playback.position = playback.clampedPosition(number(fields[6]) ?? 0)
        return playback
    }

    /// Music also reports `fast forwarding` and `rewinding`; both mean the
    /// track is moving, so they read as playing.
    private static func playerState(_ text: String) -> SpotifyPlayerState? {
        switch text {
        case "playing", "fast forwarding", "rewinding": .playing
        case "paused": .paused
        case "stopped": .stopped
        default: nil
        }
    }

    /// Same locale handling as `SpotifyScript`: comma decimals and exponents.
    private static func number(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}
