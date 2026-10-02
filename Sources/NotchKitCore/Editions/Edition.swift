import Foundation

/// A branded build of the same NotchDeck binary, such as StudyNotch.
///
/// An edition only changes identity and first-run defaults: the app name,
/// bundle id, which kit is preselected, and where its files live. Every
/// edition contains every module, so a StudyNotch user can still switch to
/// the Productivity kit. `scripts/bundle.sh <edition>` writes the edition's
/// id into Info.plist (`NotchDeckEdition`); the app reads it back at launch
/// with `Edition.resolve(infoDictionary:)`.
public struct Edition: Sendable, Hashable, Identifiable {
    /// Stable lowercase id, used by `bundle.sh` and `--edition`.
    public let id: String
    /// User-facing app name, e.g. in Settings and tooltips.
    public let name: String
    /// CFBundleIdentifier of the packaged app.
    public let bundleIdentifier: String
    /// The kit a fresh install starts with, and falls back to.
    public let defaultKitID: String

    public init(id: String, name: String, bundleIdentifier: String, defaultKitID: String) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.defaultKitID = defaultKitID
    }

    /// The Info.plist key that names a packaged app's edition.
    public static let infoKey = "NotchDeckEdition"

    /// The classic NotchDeck app with the Productivity kit.
    public static let notchDeck = Edition(
        id: "notchdeck", name: "NotchDeck",
        bundleIdentifier: "dev.notchdeck.NotchDeck", defaultKitID: KitLibrary.defaultKitID
    )

    /// The study edition, preselecting the Medicine kit.
    public static let studyNotch = Edition(
        id: "studynotch", name: "StudyNotch",
        bundleIdentifier: "dev.notchdeck.StudyNotch", defaultKitID: "medicine"
    )

    /// Every edition `bundle.sh` can build; the first is the default.
    public static let builtIn: [Edition] = [.notchDeck, .studyNotch]

    /// The built-in edition with this id (case-insensitive), if any.
    public static func named(_ id: String) -> Edition? {
        let key = id.lowercased()
        return builtIn.first { $0.id == key }
    }

    /// The edition a running app belongs to, from its Info.plist. Builds
    /// without the key (or with an unknown id), such as `swift run`, are
    /// the default edition, so development keeps behaving like NotchDeck.
    public static func resolve(infoDictionary: [String: Any]?) -> Edition {
        (infoDictionary?[infoKey] as? String).flatMap(named) ?? .notchDeck
    }
}
