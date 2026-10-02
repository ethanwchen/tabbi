import Foundation

/// What the focus timer means for focus mode right now.
public enum FocusActivity: Equatable, Sendable {
    /// A focus phase is counting down: sound and Do Not Disturb on.
    case focusing
    /// Mid-session but not focusing: on a break, or the timer is paused.
    case interrupted
    /// No session: the timer is idle (reset, or the break ran out).
    case idle

    /// Reads the activity off the Today panel's timer.
    public init(_ timer: FocusTimer) {
        switch timer.runState {
        case .running: self = timer.phase == .focus ? .focusing : .interrupted
        case .paused: self = .interrupted
        case .idle: self = .idle
        }
    }
}

/// A side effect the app layer performs for focus mode.
public enum FocusSessionAction: Equatable, Sendable {
    /// Fade the generated sound in with this mix and volume.
    case startSound(FocusMix, volume: Float)
    /// Fade the generated sound out.
    case stopSound
    case runShortcut(String)
    case playPlaylist(FocusPlaylist)
    case pausePlaylist(MediaSource)
}

/// Decides what focus mode does as the timer moves between phases.
///
/// Pure and synchronous: the app layer feeds it timer changes and what the
/// music app is doing, and performs the returned actions. Its rules:
///
/// - Settings are captured when a focus phase starts, so editing them
///   mid-phase can't leave Do Not Disturb on or a playlist unpaused.
/// - The "off" shortcut only runs if the "on" shortcut ran.
/// - Never fight the user. A playlist starts only if that app isn't already
///   playing something. Once we've seen our playlist play, a manual pause
///   hands it to the user: we won't pause it at the break or restart it in
///   later focus phases until the session ends (the timer goes idle).
public struct FocusSession: Equatable, Sendable {
    /// Who controls the playlist's app during this session.
    enum PlaylistControl: Equatable, Sendable {
        /// Not started by focus mode.
        case none
        /// Asked to play; not yet seen playing. `autoPlays` is false when
        /// the script only opened the playlist for the user to start.
        case requested(MediaSource, autoPlays: Bool)
        /// Seen playing what we started; we pause it when focus ends.
        case playing(MediaSource)
        /// The user paused it. Hands off until the session ends.
        case declined
    }

    public private(set) var activity: FocusActivity = .idle
    /// Settings captured when the current focus phase started.
    public private(set) var active: FocusSettings?
    private(set) var playlist: PlaylistControl = .none
    private var shortcutRan = false

    public init() {}

    /// True while a focus phase is applying its settings.
    public var isFocusing: Bool { activity == .focusing }

    /// Moves to `activity`. `settings` are the current settings, used only
    /// when a focus phase starts. `isPlaying(source)` reports whether that
    /// music app is playing right now (false if it isn't running).
    public mutating func transition(
        to activity: FocusActivity,
        settings: FocusSettings,
        isPlaying: (MediaSource) -> Bool
    ) -> [FocusSessionAction] {
        guard activity != self.activity else { return [] }
        let wasFocusing = isFocusing
        self.activity = activity

        var actions: [FocusSessionAction] = []
        if wasFocusing { actions += endFocus() }
        if activity == .focusing { actions += startFocus(settings, isPlaying: isPlaying) }
        if activity == .idle { playlist = .none }
        return actions
    }

    /// Feeds an observed player state for `source`. A pause after we saw our
    /// playlist play is the user's choice, and we respect it from then on.
    public mutating func observe(_ state: SpotifyPlayerState, of source: MediaSource) {
        switch playlist {
        case .requested(let owned, _) where owned == source && state == .playing:
            playlist = .playing(source)
        case .playing(let owned) where owned == source && state != .playing && isFocusing:
            playlist = .declined
        default:
            break
        }
    }

    private mutating func startFocus(_ settings: FocusSettings, isPlaying: (MediaSource) -> Bool) -> [FocusSessionAction] {
        active = settings
        var actions: [FocusSessionAction] = []
        if !settings.mix.isOff {
            actions.append(.startSound(settings.mix, volume: settings.volume))
        }
        if let item = settings.playlist, playlist != .declined, !isPlaying(item.source) {
            playlist = .requested(item.source, autoPlays: FocusPlaylistScript.startsPlayback(item))
            actions.append(.playPlaylist(item))
        }
        if let name = settings.activeOnShortcut {
            shortcutRan = true
            actions.append(.runShortcut(name))
        }
        return actions
    }

    private mutating func endFocus() -> [FocusSessionAction] {
        guard let settings = active else { return [] }
        active = nil
        var actions: [FocusSessionAction] = []
        if !settings.mix.isOff { actions.append(.stopSound) }
        switch playlist {
        case .requested(let source, autoPlays: true), .playing(let source):
            actions.append(.pausePlaylist(source))
        case .requested(_, autoPlays: false), .none, .declined:
            // Never pause music we didn't see our playlist start: it may be
            // something the user chose instead.
            break
        }
        if playlist != .declined { playlist = .none }
        if shortcutRan {
            shortcutRan = false
            if let name = settings.activeOffShortcut { actions.append(.runShortcut(name)) }
        }
        return actions
    }
}
