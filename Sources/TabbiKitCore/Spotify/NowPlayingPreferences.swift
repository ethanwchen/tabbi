import Foundation

/// Now Playing's own preferences.
///
/// SoundCloud is opt-in: reading a browser tab asks macOS for Automation
/// access to Safari or Chrome, which should only happen once the user has
/// asked for it.
public struct NowPlayingPreferences: Codable, Equatable, Sendable {
    /// Follow SoundCloud playing in Safari or Chrome.
    public var showsSoundCloud: Bool

    public init(showsSoundCloud: Bool = false) {
        self.showsSoundCloud = showsSoundCloud
    }

    /// Lenient: a value this build can't read keeps its default instead of
    /// losing every preference.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsSoundCloud = (try? container.decodeIfPresent(Bool.self, forKey: .showsSoundCloud)) ?? false
    }

    /// The players the panel follows. The music apps always; SoundCloud only
    /// when it is turned on and `allowsBrowsers` (the App Store edition may
    /// not script browsers, so it never follows SoundCloud).
    public func followedSources(allowsBrowsers: Bool) -> [NowPlayingSource] {
        let followsSoundCloud = showsSoundCloud && allowsBrowsers
        return NowPlayingSource.all.filter { $0.app != nil || followsSoundCloud }
    }
}

/// Where Now Playing's preferences live in `UserDefaults`, and their
/// versioned JSON format.
public struct NowPlayingPreferencesStorage {
    public static let key = "nowPlaying.preferences"
    /// Version 1 is the first format.
    public static let schema = VersionedJSON(current: 1)

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved preferences, or the defaults when none are saved or they
    /// can't be read.
    public func load() -> NowPlayingPreferences {
        defaults.data(forKey: Self.key)
            .flatMap { try? Self.schema.decode(NowPlayingPreferences.self, from: $0) } ?? NowPlayingPreferences()
    }

    public func save(_ preferences: NowPlayingPreferences) {
        if let data = try? Self.schema.encode(preferences) { defaults.set(data, forKey: Self.key) }
    }
}
