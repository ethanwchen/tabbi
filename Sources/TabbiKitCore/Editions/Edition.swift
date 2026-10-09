import Foundation

/// A branded build of the same Tabbi binary.
///
/// Tabbi ships as one edition, `tabbi`; audiences are served by kits, not
/// by separate apps. The mechanism stays for future branded builds: an
/// edition only changes identity and first-run defaults (the app name,
/// bundle id, which kit is preselected, and where its files live). An
/// edition contains every module except its `excludedModules`, so its users
/// can still switch to any kit: a kit's excluded modules are skipped.
///
/// The `appstore` edition is the Mac App Store build of Tabbi: the same app
/// and bundle id as `tabbi`, sandboxed, without the modules that need the
/// `claude` CLI and with Party off until it has moderation (docs/appstore.md).
///
/// Editions are data: each is a `<id>.json` in `Editions/BundledEditions`,
/// which the app reads through `builtIn` and `scripts/assemble.sh` reads to
/// write the packaged app's Info.plist, so a new edition is a file, not a
/// code change. `assemble.sh` writes the edition's id into Info.plist
/// (`TabbiEdition`); the app reads it back at launch with
/// `Edition.resolve(infoDictionary:)`.
public struct Edition: Sendable, Hashable, Identifiable, Decodable {
    /// Stable lowercase id, used by `bundle.sh` and `--edition`. It is also
    /// the edition file's name.
    public let id: String
    /// User-facing app name, e.g. in Settings and tooltips, and the name of
    /// the edition's Application Support folder.
    public let name: String
    /// CFBundleIdentifier of the packaged app.
    public let bundleIdentifier: String
    /// The kit a fresh install starts with, and falls back to.
    public let defaultKitID: String
    /// Optional icon file in the repository's `Resources` folder, used only
    /// by `assemble.sh`; `nil` keeps `AppIcon.icns`.
    public let icon: String?
    /// Info.plist strings that replace the base plist's, such as usage
    /// descriptions that name the app. Used only by `assemble.sh`, which
    /// also sets the name, display name, bundle id and edition id itself.
    public let infoPlist: [String: String]
    /// How the edition reaches users, which decides what it may do: a
    /// direct download updates itself and can run helper programs, an App
    /// Store build is sandboxed and can't.
    public let distribution: Distribution
    /// Modules this edition leaves out. Its catalog (`catalog(from:)`) drops
    /// them, so no tab, Settings row, onboarding step or ticker preview
    /// offers them, and kits that list them still apply cleanly. Removing an
    /// id from the file turns the module back on, as long as the build
    /// compiled it (see `ModuleList`).
    public let excludedModules: [ModuleID]

    /// Where an edition's builds are published.
    public enum Distribution: String, Sendable, Hashable, Decodable {
        /// Developer ID signed, notarized and self-updating (scripts/release.sh).
        case direct
        /// Sandboxed and submitted to the Mac App Store (scripts/release-appstore.sh).
        case appStore
    }

    public init(id: String, name: String, bundleIdentifier: String, defaultKitID: String,
                icon: String? = nil, infoPlist: [String: String] = [:],
                distribution: Distribution = .direct, excludedModules: [ModuleID] = []) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.defaultKitID = defaultKitID
        self.icon = icon
        self.infoPlist = infoPlist
        self.distribution = distribution
        self.excludedModules = excludedModules
    }

    /// Whether this is the sandboxed Mac App Store build.
    public var isAppStore: Bool { distribution == .appStore }

    /// Whether the app may run helper programs on this Mac: the `claude` CLI
    /// (Plan my day with Claude, Refine, the Wrap up summary) and Shortcuts
    /// (Do Not Disturb). A sandboxed App Store build can't, so those features
    /// are hidden there rather than failing.
    public var runsLocalTools: Bool { distribution == .direct }

    /// The modules this edition offers: `catalog` without `excludedModules`,
    /// which it remembers as unavailable so kits naming them raise no warning.
    public func catalog(from catalog: ModuleCatalog) -> ModuleCatalog {
        catalog.excluding(excludedModules)
    }

    /// The edition file format this build reads. A file with a higher
    /// `formatVersion` is skipped, since it may mean something this build
    /// can't honor.
    public static let formatVersion = 1

    /// The Info.plist key that names a packaged app's edition.
    public static let infoKey = "TabbiEdition"

    /// The id of the edition used when none is named, such as `swift run`.
    public static let defaultID = "tabbi"

    /// Tabbi with the Essentials kit. Falls back to these values if its
    /// file can't be read, so the app always has an edition to run as.
    public static let tabbi = named(defaultID) ?? Edition(
        id: defaultID, name: "Tabbi",
        bundleIdentifier: "dev.tabbi.Tabbi", defaultKitID: KitLibrary.defaultKitID
    )

    /// Every edition `bundle.sh` can build, read from `Editions/BundledEditions`:
    /// the default edition first, then the others by id. Bundled files are
    /// covered by tests, so one failing to load is a packaging bug; it is
    /// skipped rather than crashing the app.
    public static let builtIn: [Edition] = bundledFileURLs
        .compactMap { try? load(from: $0) }
        .sorted { ($0.id == defaultID ? 0 : 1, $0.id) < ($1.id == defaultID ? 0 : 1, $1.id) }

    /// Every edition file in `Editions/BundledEditions`, in file-name order.
    static var bundledFileURLs: [URL] {
        (KitResources.bundle?.urls(forResourcesWithExtension: "json", subdirectory: "BundledEditions") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The built-in edition with this id (case-insensitive), if any.
    public static func named(_ id: String) -> Edition? {
        let key = id.lowercased()
        return builtIn.first { $0.id == key }
    }

    /// The edition a running app belongs to, from its Info.plist. Builds
    /// without the key (or with an unknown id), such as `swift run`, are
    /// `fallback`, by default Tabbi, so development runs as Tabbi. The App
    /// Store build passes the App Store edition.
    public static func resolve(infoDictionary: [String: Any]?, fallback: Edition = .tabbi) -> Edition {
        (infoDictionary?[infoKey] as? String).flatMap(named) ?? fallback
    }

    /// Reads and checks one edition file.
    public static func load(from url: URL) throws -> Edition {
        let edition = try decode(from: Data(contentsOf: url))
        let fileID = url.deletingPathExtension().lastPathComponent
        guard edition.id == fileID else {
            throw EditionError.invalid("id \"\(edition.id)\" doesn't match its file name \"\(fileID)\"")
        }
        return edition
    }

    /// Decodes an edition file and checks the values `assemble.sh` and the
    /// app rely on: a lowercase slug id, a name usable as a folder name, a
    /// reverse-DNS bundle id and a plain icon file name.
    public static func decode(from data: Data) throws -> Edition {
        let edition: Edition
        do {
            edition = try JSONDecoder().decode(Edition.self, from: data)
        } catch let error as EditionError {
            throw error
        } catch {
            throw EditionError.invalid("not a valid edition file")
        }
        let slug = /[a-z0-9]+(-[a-z0-9]+)*/
        guard edition.id.wholeMatch(of: slug) != nil else {
            throw EditionError.invalid("id \"\(edition.id)\" must be lowercase letters, digits and hyphens")
        }
        let name = edition.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name == edition.name, !name.contains("/"), !name.hasPrefix(".") else {
            throw EditionError.invalid("name \"\(edition.name)\" can't be used as an app or folder name")
        }
        guard edition.bundleIdentifier.wholeMatch(of: /[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/) != nil else {
            throw EditionError.invalid("bundle id \"\(edition.bundleIdentifier)\" isn't reverse-DNS")
        }
        guard !edition.defaultKitID.isEmpty else {
            throw EditionError.invalid("defaultKitID is empty")
        }
        if let icon = edition.icon {
            guard icon.hasSuffix(".icns"), !icon.contains("/"), !icon.hasPrefix(".") else {
                throw EditionError.invalid("icon \"\(icon)\" must be an .icns file name in Resources")
            }
        }
        if let bad = edition.excludedModules.first(where: { $0.rawValue.wholeMatch(of: /[A-Za-z][A-Za-z0-9]*/) == nil }) {
            throw EditionError.invalid("excludedModules has \"\(bad)\", which isn't a module id")
        }
        let reserved: Set = ["CFBundleName", "CFBundleDisplayName", "CFBundleIdentifier", infoKey]
        if let key = edition.infoPlist.keys.sorted().first(where: reserved.contains) {
            throw EditionError.invalid("infoPlist can't set \(key); it comes from the edition's own fields")
        }
        return edition
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, name, bundleIdentifier, defaultKitID, icon, infoPlist, distribution, excludedModules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .formatVersion)
        guard (1...Self.formatVersion).contains(version) else {
            throw EditionError.unsupportedFormat(version)
        }
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            bundleIdentifier: try container.decode(String.self, forKey: .bundleIdentifier),
            defaultKitID: try container.decode(String.self, forKey: .defaultKitID),
            icon: try container.decodeIfPresent(String.self, forKey: .icon),
            infoPlist: try container.decodeIfPresent([String: String].self, forKey: .infoPlist) ?? [:],
            distribution: try container.decodeIfPresent(Distribution.self, forKey: .distribution) ?? .direct,
            excludedModules: try container.decodeIfPresent([ModuleID].self, forKey: .excludedModules) ?? []
        )
    }
}

/// Why an edition file can't be used.
public enum EditionError: Error, Equatable, Sendable {
    case invalid(String)
    /// The file needs a newer build (its `formatVersion` is higher).
    case unsupportedFormat(Int)
}
