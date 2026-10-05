import Foundation

/// Where one edition keeps its files: `Application Support/<edition name>/`.
///
/// Each edition is its own app, so a future branded build would keep its
/// checklist, reviews, study log, pet and kits apart from Tabbi's. Every
/// persisted file goes through `folder(_:)`, so no store hardcodes an app
/// name. Settings and other `UserDefaults` keys need nothing extra: each
/// packaged edition has its own bundle id and so its own defaults domain.
public struct EditionStorage: Sendable, Hashable {
    /// The edition's folder, e.g. `~/Library/Application Support/Tabbi`.
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The edition's folder in the user's Application Support folder.
    public init(edition: Edition) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(root: support.appendingPathComponent(edition.name, isDirectory: true))
    }

    /// A named folder inside the edition's folder, such as `Planner`. It is
    /// created by whoever writes to it first.
    public func folder(_ name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: true)
    }

    /// A file inside one of the edition's folders, such as `Pet/pet.json`.
    public func file(_ name: String, in folder: String) -> URL {
        self.folder(folder).appendingPathComponent(name, isDirectory: false)
    }
}
