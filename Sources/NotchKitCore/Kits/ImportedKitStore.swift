import Foundation

/// Kits the user imported, kept as one `<id>.json` file each in a folder
/// (Application Support/<edition name>/Kits in the app).
///
/// The imported file is copied byte for byte, so it stays human-editable
/// and keeps fields a newer Tabbi understands. Files that stop loading
/// (say, edited by hand into invalid JSON) are skipped, never fatal.
public struct ImportedKitStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The edition's store in the user's Application Support folder. Each
    /// edition is its own app, so StudyNotch and NotchDeck keep separate kits.
    public static func standard(for edition: Edition = .notchDeck) -> ImportedKitStore? {
        ImportedKitStore(directory: EditionStorage(edition: edition).folder("Kits"))
    }

    /// Every imported kit that still loads, by name.
    public func load() -> [KitManifest] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? KitLibrary.load(from: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Validates the kit at `url` and copies it into the store, replacing an
    /// earlier import with the same id. Ids in `reserved` (the built-in kits)
    /// are refused so an import can never shadow a kit that ships with the app,
    /// and so is a kit that `requires` a module `catalog` doesn't have.
    @discardableResult
    public func install(
        from url: URL,
        catalog: ModuleCatalog,
        reserved: Set<String> = Set(KitLibrary.bundledIDs)
    ) throws -> KitManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw KitError.malformed("can't read \(url.lastPathComponent)")
        }
        let kit = try KitManifest.decode(from: data)
        guard !reserved.contains(kit.id) else { throw KitError.reservedID(kit.id) }
        let missing = kit.missingRequirements(catalog: catalog)
        guard missing.isEmpty else { throw KitError.missingRequiredModules(missing) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: kit.id), options: .atomic)
        } catch {
            throw KitError.malformed("can't save \(url.lastPathComponent)")
        }
        return kit
    }

    /// Deletes an imported kit. Removing one that isn't there is not an error.
    public func remove(id: String) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Ids are validated slugs, so they are safe as file names.
    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }
}

public extension KitLibrary {
    /// The bundled kits followed by `imported` ones. An imported kit can't
    /// replace a bundled one: the first kit with an id wins.
    static func installed(imported: [KitManifest]) -> KitLibrary {
        KitLibrary(bundled.kits + imported)
    }

    /// True for kits that ship with the app (they can't be removed).
    static func isBundled(_ id: String) -> Bool {
        bundledIDs.contains(id)
    }
}
