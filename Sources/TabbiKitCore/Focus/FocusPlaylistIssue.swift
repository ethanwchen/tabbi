import Foundation

/// Why a focus playlist didn't start, so the mixer can say so and offer the
/// fix instead of a click that seems to do nothing.
public enum FocusPlaylistIssue: Equatable, Sendable {
    /// The user denied (or hasn't granted) Tabbi's Automation access to the
    /// app: macOS error -1743.
    case permissionDenied(MediaSource)
    /// The app isn't on this Mac (Spotify; Music always is).
    case notInstalled(MediaSource)
    /// Any other script failure, with its AppleScript error number.
    case failed(MediaSource, code: Int)

    /// The issue for an AppleScript error number from a script sent to `source`.
    public init(scriptError code: Int, source: MediaSource) {
        switch code {
        case -1743: self = .permissionDenied(source)
        // -10814: Launch Services can't find an app with that bundle id.
        case -10814: self = .notInstalled(source)
        default: self = .failed(source, code: code)
        }
    }

    /// The app the playlist plays in.
    public var source: MediaSource {
        switch self {
        case .permissionDenied(let source), .notInstalled(let source), .failed(let source, _): source
        }
    }
}
