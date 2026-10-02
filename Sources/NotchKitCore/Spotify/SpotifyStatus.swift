import Foundation

/// Everything the Now Playing panel can be showing for one player app,
/// derived from whether it is installed and running plus the result of the
/// last state read.
public enum SpotifyStatus: Equatable, Sendable {
    /// Spotify isn't installed on this Mac.
    case notInstalled
    /// Installed but not running. NotchDeck never launches it on its own.
    case notRunning
    /// Running, waiting for the first state read.
    case connecting
    /// The user denied NotchDeck's Automation access to Spotify.
    case permissionDenied
    /// Connected. A `stopped` playback means nothing is loaded.
    case connected(SpotifyPlayback)

    public var playback: SpotifyPlayback? {
        if case .connected(let playback) = self { return playback }
        return nil
    }

    /// True while a track is actually playing; drives the closed-notch
    /// live activity and the local position ticker.
    public var isPlaying: Bool { playback?.isPlaying ?? false }

    /// The next status after a state read.
    ///
    /// - Parameters:
    ///   - isRunning: Spotify's process was found (checked before every read).
    ///   - isInstalled: Only consulted when Spotify isn't running.
    ///   - read: The `source.readStateScript` result, or nil if no read was made.
    ///   - previous: The current status, kept when a read is inconclusive.
    ///   - source: Which app's output format `read` is in.
    public static func resolve(
        source: MediaSource = .spotify,
        isRunning: Bool,
        isInstalled: Bool,
        read: Result<String, SpotifyScriptError>?,
        previous: SpotifyStatus
    ) -> SpotifyStatus {
        guard isRunning else { return isInstalled ? .notRunning : .notInstalled }
        switch read {
        case nil:
            switch previous {
            case .connected, .permissionDenied, .connecting: return previous
            case .notInstalled, .notRunning: return .connecting
            }
        case .success(let output):
            if let playback = source.parse(output) { return .connected(playback) }
            // Garbled output (e.g. mid track change): keep what we had.
            return previous.playback.map(SpotifyStatus.connected) ?? .connected(.nothingPlaying)
        case .failure(.permissionDenied):
            return .permissionDenied
        case .failure(.notRunning):
            return isInstalled ? .notRunning : .notInstalled
        case .failure(.other):
            // Spotify and Music error on `current track` right after launch,
            // before anything is loaded. Treat it as nothing playing, not a failure.
            return previous.playback.map(SpotifyStatus.connected) ?? .connected(.nothingPlaying)
        }
    }
}

extension SpotifyPlayback {
    /// Spotify is running with no track loaded.
    public static let nothingPlaying = SpotifyPlayback(
        state: .stopped, track: nil, position: 0, isShuffling: false, isRepeating: false
    )

    /// Optimistic result of `playpause`, shown before Spotify confirms it.
    /// Nothing changes when no track is loaded.
    public func togglingPlayPause() -> SpotifyPlayback {
        guard track != nil else { return self }
        var copy = self
        copy.state = state == .playing ? .paused : .playing
        return copy
    }

    /// Optimistic result of seeking to `seconds`, clamped to the track.
    public func seeking(to seconds: TimeInterval) -> SpotifyPlayback {
        var copy = self
        copy.position = clampedPosition(seconds)
        return copy
    }
}

/// Extrapolates the playback position between AppleScript reads, so the
/// scrubber can tick every second without asking Spotify each time.
public struct SpotifyPlaybackClock: Equatable, Sendable {
    /// The last state confirmed by Spotify (or set optimistically).
    public private(set) var anchor: SpotifyPlayback
    public private(set) var anchorDate: Date

    public init(anchor: SpotifyPlayback, at date: Date) {
        self.anchor = anchor
        self.anchorDate = date
    }

    /// Re-anchors on a fresh snapshot.
    public mutating func sync(_ playback: SpotifyPlayback, at date: Date) {
        anchor = playback
        anchorDate = date
    }

    /// The best estimate of the playback at `date`.
    public func playback(at date: Date) -> SpotifyPlayback {
        anchor.advanced(by: date.timeIntervalSince(anchorDate))
    }
}
