import Foundation

/// A link the app handles, from its `tabbi://` URL scheme (registered in
/// Info.plist). Links arrive from anywhere (a web page, a chat, a widget),
/// so anything that isn't exactly one of these is ignored.
public enum AppLink: Hashable, Sendable {
    /// `tabbi://open`, which the pet widget opens: shows the notch.
    case open
    /// A Party invite (`tabbi://add/<code>` or `tabbi://join/<code>`).
    case invite(PartyInvite)

    /// The host of the plain open link.
    public static let openHost = "open"

    /// The link in `url`, or `nil` if Tabbi doesn't handle it.
    public init?(url: URL) {
        if let invite = PartyInvite(url: url) {
            self = .invite(invite)
            return
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == PartyInvite.scheme,
              components.host?.lowercased() == Self.openHost,
              components.percentEncodedPath.allSatisfy({ $0 == "/" }) else { return nil }
        self = .open
    }
}
