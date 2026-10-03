import Foundation

/// Where one edition keeps its files: `Application Support/<edition name>/`.
///
/// Each edition is its own app, so a Med School install keeps its checklist,
/// reviews, study log, pet and kits apart from the default app's. Every
/// persisted file goes through `folder(_:)`, so no store hardcodes an app
/// name. Settings and other `UserDefaults` keys need nothing extra: each
/// packaged edition has its own bundle id and so its own defaults domain.
public struct EditionStorage: Sendable, Hashable {
    /// The edition's folder, e.g. `~/Library/Application Support/StudyNotch`.
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

    /// Copies each named folder from `legacy` when this edition has none yet.
    ///
    /// Older builds wrote some folders (Today's checklist and reviews) to the
    /// default edition's folder whatever the edition, so a Med School user's
    /// data lives there. Copying (never moving) keeps it for both apps, and a
    /// folder that already exists here is left alone, so this runs at most
    /// once per folder and never overwrites newer data. Returns the folders
    /// it copied. Failures are skipped: the store then starts empty, as it
    /// would on a fresh install.
    @discardableResult
    public func adoptFolders(_ names: [String], from legacy: EditionStorage,
                             fileManager: FileManager = .default) -> [String] {
        guard legacy.root.standardizedFileURL != root.standardizedFileURL else { return [] }
        return names.filter { name in
            let source = legacy.folder(name)
            let destination = folder(name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  !fileManager.fileExists(atPath: destination.path) else { return false }
            do {
                try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
                try fileManager.copyItem(at: source, to: destination)
                return true
            } catch {
                return false
            }
        }
    }
}
