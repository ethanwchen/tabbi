import Foundation

/// Kits the user imported, kept as one `<id>.json` file each in a folder
/// (Application Support/<edition name>/Kits in the app).
///
/// In the app an imported kit goes by `KitLibrary.importedID(_:)` of the id
/// its author wrote ("imported.deep-work" for "deep-work"): `load()` and
/// `inspect` hand out kits with that id, and the other methods take it. So
/// a kit that a later Tabbi ships with the same author id can never shadow
/// the user's import or change their active kit.
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
            .compactMap { try? KitLibrary.load(from: $0).importedCopy }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Reads and validates the kit at `url` without saving it, so the user
    /// can see what it changes (and which earlier import it replaces) before
    /// `install(_:)` keeps it. Ids in `reserved` (the built-in kits) are
    /// refused so an import can never shadow a kit that ships with the app,
    /// and so is a kit that `requires` a module `catalog` doesn't have.
    public func inspect(
        from url: URL,
        catalog: ModuleCatalog,
        reserved: Set<String> = Set(KitLibrary.bundledIDs)
    ) throws -> KitImportCandidate {
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
        let id = KitLibrary.importedID(kit.id)
        let saved = savedData(for: id)
        return KitImportCandidate(
            kit: kit.importedCopy, data: data, fileName: url.lastPathComponent,
            replaces: saved.flatMap { try? KitManifest.decode(from: $0).importedCopy }, overwritesFile: saved != nil
        )
    }

    /// Copies an inspected kit into the store, replacing an earlier import
    /// with the same id.
    public func install(_ candidate: KitImportCandidate) throws {
        do {
            try restore(candidate.data, for: candidate.kit.id)
        } catch {
            throw KitError.malformed("can't save \(candidate.fileName)")
        }
    }

    /// `inspect(from:catalog:reserved:)` and `install(_:)` in one step.
    @discardableResult
    public func install(
        from url: URL,
        catalog: ModuleCatalog,
        reserved: Set<String> = Set(KitLibrary.bundledIDs)
    ) throws -> KitManifest {
        let candidate = try inspect(from: url, catalog: catalog, reserved: reserved)
        try install(candidate)
        return candidate.kit
    }

    /// The stored file of the imported kit `id` (a `KitLibrary.importedID`), byte for byte, or nil
    /// when there is none. Undo keeps it to put the file back.
    public func savedData(for id: String) -> Data? {
        try? Data(contentsOf: fileURL(for: id))
    }

    /// Puts back the file `savedData(for:)` returned: writes `data` as the
    /// kit imported as `id`, or removes that kit when `data` is nil.
    public func restore(_ data: Data?, for id: String) throws {
        guard let data else { return try remove(id: id) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: id), options: .atomic)
    }

    /// Deletes an imported kit. Removing one that isn't there is not an error.
    public func remove(id: String) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// The file of the imported kit `id`, named after its author's id.
    /// Those are validated slugs, so they are safe as file names.
    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent("\(KitLibrary.authorID(of: id)).json")
    }
}

/// A kit file that passed validation but isn't saved yet: Settings shows
/// what it would change and saves it only once the user confirms.
public struct KitImportCandidate: Sendable {
    public let kit: KitManifest
    /// The file's bytes, saved as they are.
    public let data: Data
    /// The name of the file it came from, for messages.
    public let fileName: String
    /// The earlier import with the same id that saving this one replaces,
    /// so the user is asked first instead of losing it silently.
    public let replaces: KitManifest?
    /// True when a file is saved under the kit's id already, even one that
    /// no longer loads (so `replaces` is nil).
    public let overwritesFile: Bool

    public init(kit: KitManifest, data: Data, fileName: String, replaces: KitManifest? = nil, overwritesFile: Bool? = nil) {
        self.kit = kit
        self.data = data
        self.fileName = fileName
        self.replaces = replaces
        self.overwritesFile = overwritesFile ?? (replaces != nil)
    }

    /// "Deep Work 1.2 to 1.3" when both files carry a version, else nil.
    public var versionChange: String? {
        guard let old = replaces?.version, let new = kit.version, old != new else { return nil }
        return "\(kit.name) \(old) to \(new)"
    }
}

public extension KitLibrary {
    /// The bundled kits followed by `imported` ones (as `ImportedKitStore`
    /// loads them, with their `importedID`), so the two never share an id.
    static func installed(imported: [KitManifest]) -> KitLibrary {
        KitLibrary(bundled.kits + imported)
    }

    /// True for kits that ship with the app (they can't be removed).
    static func isBundled(_ id: String) -> Bool {
        bundledIDs.contains(id)
    }

    /// Begins every imported kit's id in the app. A kit's own id is a slug
    /// (`[a-z0-9-]+`) with no dot, so no bundled kit can ever have it.
    static let importedIDPrefix = "imported."

    /// The id the app gives a kit imported with `authorID`.
    static func importedID(_ authorID: String) -> String {
        isImported(authorID) ? authorID : importedIDPrefix + authorID
    }

    /// True for an id from `importedID(_:)`.
    static func isImported(_ id: String) -> Bool {
        id.hasPrefix(importedIDPrefix)
    }

    /// The id the kit's author wrote, for an id from `importedID(_:)`.
    static func authorID(of id: String) -> String {
        isImported(id) ? String(id.dropFirst(importedIDPrefix.count)) : id
    }
}

extension KitManifest {
    /// This kit as the app knows it once imported: with its `importedID`.
    var importedCopy: KitManifest {
        var kit = self
        kit.id = KitLibrary.importedID(id)
        return kit
    }
}
