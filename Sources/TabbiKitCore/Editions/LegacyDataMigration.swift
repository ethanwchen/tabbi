import Foundation

/// Moves what the app saved under its old names (NotchDeck, and the retired
/// StudyNotch edition) to Tabbi's places, once, on the first launch after
/// the rename.
///
/// Without it, renaming the app would look like losing every checklist,
/// study log, pet and setting, since both the Application Support folder and
/// the `UserDefaults` domain follow the app's name and bundle id.
///
/// The move never overwrites: a file or preference Tabbi already has wins
/// (folders both sides have are merged file by file), and the first legacy source that has anything is the one adopted. Old
/// preferences are copied (the old domain is left as it was), while the old
/// folder's contents are moved, so the data lives in one place afterwards.
public struct LegacyDataMigration {
    /// Old Application Support folders, most preferred first.
    public var legacyFolders: [URL]
    /// Old `UserDefaults` domains, most preferred first.
    public var legacyDomains: [String]
    /// Where Tabbi keeps its files now.
    public var storage: EditionStorage
    /// Tabbi's preferences, which also remember that the migration ran.
    public var defaults: UserDefaults

    /// Set in `defaults` once the migration has run, so it runs only once.
    public static let doneKey = "migration.legacyAppData"

    public init(legacyFolders: [URL], legacyDomains: [String], storage: EditionStorage, defaults: UserDefaults) {
        self.legacyFolders = legacyFolders
        self.legacyDomains = legacyDomains
        self.storage = storage
        self.defaults = defaults
    }

    /// The migration for the Tabbi edition: the NotchDeck app (bundled, or
    /// run with `swift run`, whose domain is the executable name), then the
    /// StudyNotch edition.
    public static func tabbi(storage: EditionStorage = EditionStorage(edition: .tabbi),
                             defaults: UserDefaults = .standard) -> LegacyDataMigration {
        let support = storage.root.deletingLastPathComponent()
        return LegacyDataMigration(
            legacyFolders: ["NotchDeck", "StudyNotch"].map { support.appendingPathComponent($0, isDirectory: true) },
            legacyDomains: ["dev.notchdeck.NotchDeck", "NotchDeck", "dev.notchdeck.StudyNotch"],
            storage: storage,
            defaults: defaults
        )
    }

    /// What one run did.
    public struct Outcome: Equatable, Sendable {
        /// The old folder whose contents moved, if any.
        public var movedFolder: URL?
        /// The old domain whose preferences were copied, if any.
        public var copiedDomain: String?
        /// False when an earlier launch had already migrated.
        public var ran: Bool
    }

    /// Runs the migration unless it already ran. Marks it done even when
    /// there was nothing to move, so later launches skip the work; a file
    /// that cannot be moved stays where it was rather than blocking launch.
    @discardableResult
    public func runIfNeeded(fileManager: FileManager = .default) -> Outcome {
        guard !defaults.bool(forKey: Self.doneKey) else {
            return Outcome(movedFolder: nil, copiedDomain: nil, ran: false)
        }
        let domain = copyPreferences()
        let folder = moveFolder(fileManager: fileManager)
        defaults.set(true, forKey: Self.doneKey)
        return Outcome(movedFolder: folder, copiedDomain: domain, ran: true)
    }

    private func copyPreferences() -> String? {
        for domain in legacyDomains {
            guard let values = defaults.persistentDomain(forName: domain), !values.isEmpty else { continue }
            for (key, value) in values where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            return domain
        }
        return nil
    }

    private func moveFolder(fileManager: FileManager) -> URL? {
        let destination = storage.root
        for folder in legacyFolders where folder.standardizedFileURL != destination.standardizedFileURL {
            guard let items = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
                  !items.isEmpty else { continue }
            merge(items, into: destination, fileManager: fileManager)
            removeIfEmpty(folder, fileManager: fileManager)
            return folder
        }
        return nil
    }

    /// Moves each item that `destination` does not have yet. A folder both
    /// sides have is merged file by file, so a subfolder Tabbi already
    /// created (a live snapshot saves today's checklist) does not hide the
    /// old one's files.
    private func merge(_ items: [URL], into destination: URL, fileManager: FileManager) {
        try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            var targetIsFolder: ObjCBool = false
            guard fileManager.fileExists(atPath: target.path, isDirectory: &targetIsFolder) else {
                try? fileManager.moveItem(at: item, to: target)
                continue
            }
            guard targetIsFolder.boolValue,
                  let children = try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
            else { continue }
            merge(children, into: target, fileManager: fileManager)
            removeIfEmpty(item, fileManager: fileManager)
        }
    }

    /// Removes an old folder only once nothing is left behind in it.
    private func removeIfEmpty(_ folder: URL, fileManager: FileManager) {
        if (try? fileManager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? fileManager.removeItem(at: folder)
        }
    }
}
