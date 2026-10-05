import Foundation

/// The kits a user can choose from: the ones that ship in `Kits/Bundled`
/// plus any they imported.
public struct KitLibrary: Equatable, Sendable {
    /// Bundled kit ids in picker order. Each is a `<id>.json` in `Kits/Bundled`.
    public static var bundledIDs: [String] { bundled.kits.map(\.id) }
    /// The kit used when the user (or edition) hasn't picked one: the four
    /// essential tabs, with everything else in Settings' module library.
    public static let defaultKitID = "essentials"
    /// Bundled kits that no longer ship, and the kit that replaced each.
    /// Settings saved on one move to its replacement (`SettingsSchema`), and
    /// the user's tabs stay as they were. Never reuse a retired id.
    public static let retiredKitIDs: [String: String] = [
        "productivity": "essentials",
        "student": "essentials",
    ]

    public private(set) var kits: [KitManifest]

    /// Kits with a duplicate id are dropped; the first one wins.
    public init(_ kits: [KitManifest]) {
        var seen = Set<String>()
        self.kits = kits.filter { seen.insert($0.id).inserted }
    }

    /// The kits that ship with the app: every JSON file in `Kits/Bundled`,
    /// ordered by `pickerOrder` and then id, so shipping a kit is adding its
    /// file. Bundled files are covered by tests, so one failing to load is a
    /// packaging bug; it is skipped rather than crashing the app.
    public static let bundled = KitLibrary(
        bundledFileURLs
            .compactMap { try? load(from: $0) }
            .sorted { ($0.pickerOrder ?? .max, $0.id) < ($1.pickerOrder ?? .max, $1.id) }
    )

    /// Every kit file in `Kits/Bundled`, in file-name order.
    static var bundledFileURLs: [URL] {
        (KitResources.bundle?.urls(forResourcesWithExtension: "json", subdirectory: "Bundled") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Loads one bundled kit by id.
    public static func loadBundled(_ id: String) throws -> KitManifest {
        guard let url = KitResources.bundle?.url(forResource: id, withExtension: "json", subdirectory: "Bundled") else {
            throw KitError.malformed("no bundled kit \"\(id)\"")
        }
        return try load(from: url)
    }

    /// Reads a kit file, e.g. one the user imports.
    public static func load(from url: URL) throws -> KitManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw KitError.malformed("can't read \(url.lastPathComponent)")
        }
        return try KitManifest.decode(from: data)
    }

    public subscript(id: String) -> KitManifest? {
        kits.first { $0.id == id }
    }

    /// The kit with `id`, or the default kit if it's gone (say, an imported
    /// kit was removed), or the first kit as a last resort.
    public func kit(_ id: String?) -> KitManifest? {
        id.flatMap { self[$0] } ?? self[Self.defaultKitID] ?? kits.first
    }

    /// Adds or replaces a kit (matched by id), keeping its position if it
    /// was already present.
    public mutating func upsert(_ kit: KitManifest) {
        if let index = kits.firstIndex(where: { $0.id == kit.id }) {
            kits[index] = kit
        } else {
            kits.append(kit)
        }
    }
}
