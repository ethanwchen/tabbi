import Foundation

/// The update feed a release build carries in its Info.plist: the appcast
/// URL (`SUFeedURL`) and the EdDSA public key (`SUPublicEDKey`) that every
/// update archive must be signed with.
///
/// `scripts/release.sh` writes both from `packaging/updates.env`; development
/// builds (`swift run`, `scripts/bundle.sh`) have neither, so they never
/// offer to replace themselves with a release.
public struct UpdateFeed: Equatable, Sendable {
    public let url: URL
    public let publicKey: String

    /// Reads the feed from an Info.plist dictionary. Nil unless the URL is
    /// HTTPS (App Transport Security, and Sparkle, refuse anything else) and
    /// the key is a base64 Ed25519 public key (32 bytes), so a half-configured
    /// build turns updates off instead of failing at the first check.
    public init?(info: [String: Any]) {
        guard let feed = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespaces),
              let url = URL(string: feed), url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
              let key = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespaces),
              Data(base64Encoded: key)?.count == 32
        else { return nil }
        self.url = url
        self.publicKey = key
    }
}

/// Whether the updater runs in this copy of the app, and if not, why.
///
/// Sparkle cannot replace an app that runs from a disk image or from
/// Gatekeeper's read-only translocation mirror, and demo and snapshot runs
/// must touch no network, so the app asks this before it starts Sparkle and
/// shows `explanation` next to the disabled update controls.
public enum UpdatePolicy: Equatable, Sendable {
    /// Checks for updates against this feed.
    case active(UpdateFeed)
    /// Updates are off; the reason says why.
    case off(Reason)

    public enum Reason: Equatable, Sendable {
        /// A demo or snapshot run.
        case preview
        /// A build without a feed: a development build, or a release made
        /// before `packaging/updates.env` had a public key.
        case notConfigured
        /// Running from a disk image or a translocated path, which Sparkle
        /// cannot update in place.
        case notInstalled
    }

    public init(info: [String: Any], runMode: RunMode, location: InstallLocation) {
        if runMode.isEphemeral {
            self = .off(.preview)
        } else if let feed = UpdateFeed(info: info) {
            switch location {
            case .diskImage, .translocated: self = .off(.notInstalled)
            default: self = .active(feed)
            }
        } else {
            self = .off(.notConfigured)
        }
    }

    public var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    /// True for demo and snapshot runs, which show the update controls as a
    /// release build would (switched on) without starting the updater.
    public var isPreview: Bool { self == .off(.preview) }

    /// A short caption for Settings, or nil when updates run (or a preview
    /// pretends they do).
    public func explanation(appName: String) -> String? {
        switch self {
        case .active, .off(.preview): nil
        case .off(.notConfigured): "This is a development build. Release builds of \(appName) update themselves."
        case .off(.notInstalled): "Move \(appName) to your Applications folder to get updates."
        }
    }
}
