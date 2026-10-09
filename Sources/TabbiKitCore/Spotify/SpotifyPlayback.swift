import Foundation

/// Spotify's `player state`.
public enum SpotifyPlayerState: String, Equatable, Sendable {
    case playing
    case paused
    case stopped
}

/// The track Spotify currently has loaded.
public struct SpotifyTrack: Equatable, Sendable {
    /// Spotify URI (`spotify:track:…`); stable identity for caching artwork.
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var artworkURL: URL?
    /// Track length in seconds (Spotify reports milliseconds). Zero when unknown.
    public var duration: TimeInterval
    /// Whether the user liked (Music: favorited) the track. Nil when the
    /// player can't say or can't like this track, so the panel hides its
    /// heart instead of showing a control that does nothing.
    public var isFavorite: Bool?

    public init(id: String, title: String, artist: String, album: String,
                artworkURL: URL?, duration: TimeInterval, isFavorite: Bool? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.duration = duration
        self.isFavorite = isFavorite
    }
}

/// A point-in-time snapshot of the Spotify player.
public struct SpotifyPlayback: Equatable, Sendable {
    public var state: SpotifyPlayerState
    /// Nil when nothing is loaded (state `stopped`).
    public var track: SpotifyTrack?
    /// Seconds into the track.
    public var position: TimeInterval
    public var isShuffling: Bool
    public var repeatMode: MediaRepeatMode
    /// The app's own volume, 0 ... 100; nil when it couldn't be read.
    public var volume: Int?

    public init(state: SpotifyPlayerState, track: SpotifyTrack?, position: TimeInterval,
                isShuffling: Bool, repeatMode: MediaRepeatMode, volume: Int? = nil) {
        self.state = state
        self.track = track
        self.position = position
        self.isShuffling = isShuffling
        self.repeatMode = repeatMode
        self.volume = volume.map(MediaVolume.clamped)
    }

    public var isPlaying: Bool { state == .playing && track != nil }

    /// Whether any repeat mode is on.
    public var isRepeating: Bool { repeatMode != .off }

    /// 0.0 ... 1.0 through the track; 0 when the duration is unknown.
    public var progress: Double {
        guard let duration = track?.duration, duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// The snapshot `elapsed` seconds later. Only a playing track moves, and
    /// the position never runs past the end. Lets the UI tick locally between
    /// (expensive) AppleScript reads.
    public func advanced(by elapsed: TimeInterval) -> SpotifyPlayback {
        guard isPlaying, elapsed > 0 else { return self }
        var copy = self
        copy.position = clampedPosition(position + elapsed)
        return copy
    }

    /// `seconds` clamped to the current track's bounds.
    public func clampedPosition(_ seconds: TimeInterval) -> TimeInterval {
        let upper = track.map { $0.duration > 0 ? $0.duration : .infinity } ?? 0
        return min(max(seconds, 0), upper)
    }
}

extension SpotifyPlayback {
    /// Sample state for `TABBI_DEMO=1` snapshots and screenshots. Has no
    /// artwork URL so demo mode never touches the network.
    public static let demo = SpotifyPlayback(
        state: .playing,
        track: SpotifyTrack(
            id: "spotify:track:demo",
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            artworkURL: nil,
            duration: 243.96
        ),
        position: 87.4,
        isShuffling: true,
        repeatMode: .off,
        volume: 64
    )
}
