import Foundation

/// What the user typed into the focus playlist field, understood.
///
/// The field accepts a Spotify link or URI, an Apple Music link, or the name
/// of a playlist in the user's Music library. Anything that isn't recognizably
/// Spotify or an Apple Music link is treated as a library playlist name, so
/// plain names like "Deep Work" just work.
public enum FocusPlaylist: Equatable, Sendable {
    /// A Spotify URI such as `spotify:playlist:37i9dQZF1DWZeKCadgRdKQ`.
    case spotify(uri: String)
    /// An Apple Music catalog link (`https://music.apple.com/...`).
    case appleMusicLink(URL)
    /// A playlist in the user's Music library, by name.
    case musicLibrary(name: String)

    /// Spotify item kinds that can be played as a context.
    static let spotifyKinds: Set<String> = ["playlist", "album", "artist", "track", "show", "episode"]

    /// Parses the field's text; nil when it's blank or a malformed Spotify
    /// reference (a Spotify link we can't turn into a URI must not fall
    /// through and be searched for as a Music playlist name).
    public init?(_ text: String) {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        let lowered = input.lowercased()

        if lowered.hasPrefix("spotify:") {
            guard let uri = Self.spotifyURI(fromURI: input) else { return nil }
            self = .spotify(uri: uri)
        } else if let url = URL(string: input), let host = url.host?.lowercased(), Self.isWebScheme(url) {
            if host == "open.spotify.com" || host == "play.spotify.com" {
                guard let uri = Self.spotifyURI(fromPath: url.pathComponents) else { return nil }
                self = .spotify(uri: uri)
            } else if host == "music.apple.com" || host == "itunes.apple.com" {
                self = .appleMusicLink(url)
            } else {
                return nil
            }
        } else {
            self = .musicLibrary(name: input)
        }
    }

    /// The app that plays this playlist.
    public var source: MediaSource {
        switch self {
        case .spotify: .spotify
        case .appleMusicLink, .musicLibrary: .music
        }
    }

    private static func isWebScheme(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "https" || scheme == "http"
    }

    /// Normalizes `spotify:<kind>:<id>` (and the legacy
    /// `spotify:user:<name>:playlist:<id>` form) to `spotify:<kind>:<id>`.
    private static func spotifyURI(fromURI uri: String) -> String? {
        let parts = uri.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, let id = parts.last, parts.count % 2 == 1 else { return nil }
        return spotifyURI(kind: parts[parts.count - 2], id: id)
    }

    /// Reads `/<kind>/<id>` from a link path, skipping locale prefixes such
    /// as `/intl-de/` and legacy `/user/<name>/` segments.
    private static func spotifyURI(fromPath components: [String]) -> String? {
        let segments = components.filter { $0 != "/" }
        guard let index = segments.lastIndex(where: { spotifyKinds.contains($0.lowercased()) }),
              index + 1 < segments.count else { return nil }
        return spotifyURI(kind: segments[index], id: segments[index + 1])
    }

    private static func spotifyURI(kind: String, id: String) -> String? {
        let kind = kind.lowercased()
        guard spotifyKinds.contains(kind), !id.isEmpty,
              id.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) })
        else { return nil }
        return "spotify:\(kind):\(id)"
    }
}
