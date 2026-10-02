import Foundation

/// A well-known lo-fi or ambient study playlist offered in Settings, so
/// focus music works without hunting for a link.
///
/// Presets are plain data: picking one just fills the playlist field with
/// its link, which the user can then edit like anything they typed.
public struct FocusPlaylistPreset: Equatable, Sendable, Identifiable {
    public let name: String
    /// Who curates it, shown as secondary text.
    public let curator: String
    /// The link written into the playlist field.
    public let link: String

    public init(name: String, curator: String, link: String) {
        self.name = name
        self.curator = curator
        self.link = link
    }

    public var id: String { link }

    /// The parsed playlist; every built-in preset parses.
    public var playlist: FocusPlaylist? { FocusPlaylist(link) }

    /// The app that plays it.
    public var source: MediaSource { playlist?.source ?? .spotify }

    /// Cozy study playlists. Edit freely: each entry only needs a name and a
    /// Spotify or Apple Music link. IDs were checked against the live pages.
    public static let all: [FocusPlaylistPreset] = [
        .init(name: "beats to relax/study to", curator: "Lofi Girl",
              link: "https://open.spotify.com/playlist/0vvXsWCC9xrXsKd4FyS8kM"),
        .init(name: "lofi beats", curator: "Spotify",
              link: "https://open.spotify.com/playlist/37i9dQZF1DWWQRwui0ExPn"),
        .init(name: "Deep Focus", curator: "Spotify",
              link: "https://open.spotify.com/playlist/37i9dQZF1DWZeKCadgRdKQ"),
        .init(name: "Peaceful Piano", curator: "Spotify",
              link: "https://open.spotify.com/playlist/37i9dQZF1DX4sWSpwq3LiO"),
        .init(name: "Study Beats", curator: "Apple Music",
              link: "https://music.apple.com/us/playlist/study-beats/pl.a4e197979fc74b2a91b3cdf869f12aa5"),
        .init(name: "Pure Focus", curator: "Apple Music",
              link: "https://music.apple.com/us/playlist/pure-focus/pl.dbd712beded846dca273d5d3259d28aa"),
    ]

    /// The preset the field's text refers to, so Settings can name it.
    /// Matches by parsed playlist, so a Spotify link with a `?si=` tracking
    /// parameter or the `spotify:` URI still counts.
    public static func matching(_ text: String, in presets: [FocusPlaylistPreset] = all) -> FocusPlaylistPreset? {
        guard let playlist = FocusPlaylist(text) else { return nil }
        return presets.first { $0.playlist == playlist }
    }
}
