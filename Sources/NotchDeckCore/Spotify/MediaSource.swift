import Foundation

/// A music app NotchDeck can read and control over AppleScript.
public enum MediaSource: String, CaseIterable, Equatable, Hashable, Sendable {
    case spotify
    case music

    public var bundleIdentifier: String {
        switch self {
        case .spotify: SpotifyScript.bundleIdentifier
        case .music: MusicScript.bundleIdentifier
        }
    }

    /// The app's name as users know it.
    public var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Music"
        }
    }

    /// Display names joined for a sentence: "Spotify", "Spotify or Music".
    /// Falls back to every known app when `sources` is empty.
    public static func names(_ sources: [MediaSource]) -> String {
        let names = (sources.isEmpty ? allCases : sources).map(\.displayName)
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " or " + last
    }

    /// The script that returns the app's state as one separated record.
    public var readStateScript: String {
        switch self {
        case .spotify: SpotifyScript.readState
        case .music: MusicScript.readState
        }
    }

    /// Parses `readStateScript` output. Nil for unrecognized output.
    public func parse(_ output: String) -> SpotifyPlayback? {
        switch self {
        case .spotify: SpotifyScript.parse(output)
        case .music: MusicScript.parse(output)
        }
    }

    public var playPauseScript: String {
        switch self {
        case .spotify: SpotifyScript.playPause
        case .music: MusicScript.playPause
        }
    }

    public var nextTrackScript: String {
        switch self {
        case .spotify: SpotifyScript.nextTrack
        case .music: MusicScript.nextTrack
        }
    }

    public var previousTrackScript: String {
        switch self {
        case .spotify: SpotifyScript.previousTrack
        case .music: MusicScript.previousTrack
        }
    }

    public func seekScript(to seconds: TimeInterval) -> String {
        switch self {
        case .spotify: SpotifyScript.seek(to: seconds)
        case .music: MusicScript.seek(to: seconds)
        }
    }

    /// Sets the app's own volume (not the system volume), 0 ... 100.
    public func setVolumeScript(_ volume: Int) -> String {
        "tell application id \"\(bundleIdentifier)\" to set sound volume to \(MediaVolume.clamped(volume))"
    }
}
