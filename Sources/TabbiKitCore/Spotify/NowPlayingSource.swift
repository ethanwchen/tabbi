import Foundation

/// A player the Now Playing panel can follow: a music app, or the SoundCloud
/// web player in a browser tab.
///
/// `MediaSource` stays the list of music apps (Focus plays its playlists
/// there); SoundCloud is only shown and controlled, so it lives here. Every
/// command goes through the matching script builder, so the controller never
/// needs to know which kind of player it is talking to.
public enum NowPlayingSource: Hashable, Sendable {
    case app(MediaSource)
    case soundCloud(SoundCloudBrowser)

    public static let spotify = NowPlayingSource.app(.spotify)
    public static let music = NowPlayingSource.app(.music)

    /// Every player, apps first, in the order idle ties are broken.
    public static let all: [NowPlayingSource] =
        MediaSource.allCases.map(NowPlayingSource.app) + SoundCloudBrowser.allCases.map(NowPlayingSource.soundCloud)

    /// The app whose process has to run: the music app or the browser.
    public var bundleIdentifier: String {
        switch self {
        case .app(let app): app.bundleIdentifier
        case .soundCloud(let browser): browser.bundleIdentifier
        }
    }

    /// The player's name as users know it.
    public var displayName: String {
        switch self {
        case .app(let app): app.displayName
        case .soundCloud: "SoundCloud"
        }
    }

    /// The music app, or nil for SoundCloud.
    public var app: MediaSource? {
        if case .app(let app) = self { return app }
        return nil
    }

    public var readStateScript: String {
        switch self {
        case .app(let app): app.readStateScript
        case .soundCloud(let browser): SoundCloudScript.readState(in: browser)
        }
    }

    public var playPauseScript: String {
        switch self {
        case .app(let app): app.playPauseScript
        case .soundCloud(let browser): SoundCloudScript.playPause(in: browser)
        }
    }

    public var nextTrackScript: String {
        switch self {
        case .app(let app): app.nextTrackScript
        case .soundCloud(let browser): SoundCloudScript.nextTrack(in: browser)
        }
    }

    public var previousTrackScript: String {
        switch self {
        case .app(let app): app.previousTrackScript
        case .soundCloud(let browser): SoundCloudScript.previousTrack(in: browser)
        }
    }

    /// Jumps to `seconds` into `track`. SoundCloud's seek is pinned to the
    /// track, so it does nothing once another one is playing.
    public func seekScript(to seconds: TimeInterval, in track: SpotifyTrack) -> String {
        switch self {
        case .app(let app): app.seekScript(to: seconds)
        case .soundCloud(let browser): SoundCloudScript.seek(to: seconds, forTrackID: track.id, in: browser)
        }
    }

    /// The repeat modes the player can set, in the order its button steps.
    public var repeatModes: [MediaRepeatMode] {
        switch self {
        case .app(let app): app.repeatModes
        case .soundCloud: [.off, .one, .all]
        }
    }

    /// What one click on the repeat button turns `mode` into.
    public func repeatMode(after mode: MediaRepeatMode) -> MediaRepeatMode {
        let modes = repeatModes
        guard let index = modes.firstIndex(of: mode) else { return .off }
        return modes[(index + 1) % modes.count]
    }

    public func setShuffleScript(_ isOn: Bool) -> String {
        switch self {
        case .app(let app): app.setShuffleScript(isOn)
        case .soundCloud(let browser): SoundCloudScript.setShuffle(isOn, in: browser)
        }
    }

    public func setRepeatScript(_ mode: MediaRepeatMode) -> String {
        switch self {
        case .app(let app): app.setRepeatScript(mode)
        case .soundCloud(let browser): SoundCloudScript.setRepeat(mode, in: browser)
        }
    }

    /// The script that likes or unlikes `track`, or nil where the player
    /// can't (Spotify, a Music stream, SoundCloud while signed out).
    public func setFavoriteScript(_ isFavorite: Bool, for track: SpotifyTrack) -> String? {
        switch self {
        case .app(let app): return app.setFavoriteScript(isFavorite, for: track)
        case .soundCloud(let browser):
            guard track.isFavorite != nil else { return nil }
            return SoundCloudScript.setLiked(isFavorite, forTrackID: track.id, in: browser)
        }
    }

    /// Sets the player's own volume, or nil when Tabbi can't (SoundCloud
    /// reports no volume, so the panel shows no slider for it).
    public func setVolumeScript(_ volume: Int) -> String? {
        app?.setVolumeScript(volume)
    }

    /// What a successful read means. Nil for unrecognized output.
    ///
    /// A browser without a SoundCloud tab reads as not running, so the panel
    /// never follows a browser that is only showing other sites.
    func status(forRead output: String) -> SpotifyStatus? {
        switch self {
        case .app(let app):
            return app.parse(output).map(SpotifyStatus.connected)
        case .soundCloud:
            switch SoundCloudScript.parse(output) {
            case .noTab: return .notRunning
            case .javaScriptOff: return .scriptingDisabled
            case .playback(let playback): return .connected(playback)
            case nil: return nil
            }
        }
    }
}
