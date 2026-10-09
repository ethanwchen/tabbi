import Foundation

/// A player's repeat setting. Music offers all three; Spotify's scripting
/// only knows on and off, which map to `all` and `off`.
public enum MediaRepeatMode: String, CaseIterable, Equatable, Sendable {
    case off
    case all
    case one

    /// Parses Music's `song repeat` text. Unknown values read as off.
    public init(scriptValue text: String) {
        self = MediaRepeatMode(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .off
    }
}

extension MediaSource {
    /// The repeat modes the app's scripting can set, in the order the
    /// repeat button steps through them (the same order the apps use).
    public var repeatModes: [MediaRepeatMode] {
        switch self {
        case .spotify: [.off, .all]
        case .music: [.off, .all, .one]
        }
    }

    /// What one click on the repeat button turns `mode` into. A mode the app
    /// can't set (Spotify has no `one`) goes back to off.
    public func repeatMode(after mode: MediaRepeatMode) -> MediaRepeatMode {
        let modes = repeatModes
        guard let index = modes.firstIndex(of: mode) else { return .off }
        return modes[(index + 1) % modes.count]
    }

    /// Turns shuffle on or off in the app.
    public func setShuffleScript(_ isOn: Bool) -> String {
        switch self {
        case .spotify: command("set shuffling to \(isOn)")
        case .music: command("set shuffle enabled to \(isOn)")
        }
    }

    /// Sets the app's repeat mode. Spotify repeats the whole context for any
    /// mode other than off.
    public func setRepeatScript(_ mode: MediaRepeatMode) -> String {
        switch self {
        case .spotify: command("set repeating to \(mode != .off)")
        case .music: command("set song repeat to \(mode.rawValue)")
        }
    }

    private func command(_ body: String) -> String {
        "tell application id \"\(bundleIdentifier)\" to \(body)"
    }
}

extension SpotifyPlayback {
    /// Optimistic result of turning shuffle on or off.
    public func settingShuffle(_ isOn: Bool) -> SpotifyPlayback {
        var copy = self
        copy.isShuffling = isOn
        return copy
    }

    /// Optimistic result of changing the repeat mode.
    public func settingRepeat(_ mode: MediaRepeatMode) -> SpotifyPlayback {
        var copy = self
        copy.repeatMode = mode
        return copy
    }
}

/// Shuffle and repeat values the user just asked for, held over reads that
/// come back before the player has applied them.
///
/// Spotify applies `set shuffling` asynchronously: a read right after the
/// command still returns the old value. Without this, the button would flip
/// back for a moment and then forward again. Once `deadline` passes, reads
/// are trusted as they are, so a player that refuses a change (or a change
/// made in the app itself) still shows its real state.
public struct PendingMediaModes: Equatable, Sendable {
    public var shuffle: Bool?
    public var repeatMode: MediaRepeatMode?
    public var deadline: Date

    /// How long a requested mode outranks what the player reports.
    public static let settleTime: TimeInterval = 1.5

    public init(shuffle: Bool? = nil, repeatMode: MediaRepeatMode? = nil, deadline: Date) {
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.deadline = deadline
    }

    /// Whether a read at `date` should still show the requested values.
    public func isActive(at date: Date) -> Bool { date < deadline }

    /// `playback` as a read at `date` should show it.
    public func applied(to playback: SpotifyPlayback, at date: Date) -> SpotifyPlayback {
        guard isActive(at: date) else { return playback }
        var copy = playback
        if let shuffle { copy.isShuffling = shuffle }
        if let repeatMode { copy.repeatMode = repeatMode }
        return copy
    }

    /// Adds a request made at `date`, keeping earlier unsettled ones.
    public func adding(shuffle: Bool? = nil, repeatMode: MediaRepeatMode? = nil,
                       at date: Date) -> PendingMediaModes {
        let keep = isActive(at: date)
        return PendingMediaModes(shuffle: shuffle ?? (keep ? self.shuffle : nil),
                                 repeatMode: repeatMode ?? (keep ? self.repeatMode : nil),
                                 deadline: date + Self.settleTime)
    }
}

extension MediaSource {
    /// The script that likes or unlikes `track`, or nil when the app can't
    /// do that for it. Music favorites by script. Spotify's scripting has
    /// no like, and saving to Liked Songs needs the Web API, which means a
    /// registered client, the user's sign-in and calls to api.spotify.com,
    /// so its heart stays hidden instead.
    public func setFavoriteScript(_ isFavorite: Bool, for track: SpotifyTrack) -> String? {
        guard track.isFavorite != nil else { return nil }
        switch self {
        case .spotify: return nil
        case .music: return MusicScript.setFavorite(isFavorite, forTrackID: track.id)
        }
    }
}

extension SpotifyPlayback {
    /// Optimistic result of liking or unliking the current track.
    public func settingFavorite(_ isFavorite: Bool) -> SpotifyPlayback {
        guard track?.isFavorite != nil else { return self }
        var copy = self
        copy.track?.isFavorite = isFavorite
        return copy
    }
}
