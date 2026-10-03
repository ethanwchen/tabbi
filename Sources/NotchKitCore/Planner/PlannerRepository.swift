import Foundation

/// Stores one JSON file per day (`yyyy-MM-dd.json`) in a directory.
///
/// Plain files keep the data human-readable, easy to back up, and safe to
/// edit by hand. Writes are atomic so a crash never leaves a half-written day.
/// Not thread-safe; own it from a single actor.
public final class PlannerRepository {
    public let directory: URL
    private let fileManager: FileManager

    /// The folder in an edition's storage, `Application Support/<edition>/Planner`.
    public static let folderName = "Planner"

    /// The day file format. Version 1 added the `schemaVersion` key.
    public static let schema = VersionedJSON(current: 1)

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// The edition's checklist folder.
    public convenience init(storage: EditionStorage) {
        self.init(directory: storage.folder(Self.folderName))
    }

    public func fileURL(for date: PlannerDayKey) -> URL {
        directory.appendingPathComponent("\(date.rawValue).json", isDirectory: false)
    }

    /// The saved day, or nil if none exists. Throws if the file is unreadable
    /// or corrupt, so callers never mistake bad data for an empty day and
    /// overwrite it.
    public func load(_ date: PlannerDayKey) throws -> PlannerDay? {
        let url = fileURL(for: date)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let day = try Self.schema.decode(PlannerDay.self, from: Data(contentsOf: url), using: Self.decoder)
        // The file name is authoritative; a copied file must not masquerade as another day.
        return day.date == date ? day : PlannerDay(date: date, items: day.items)
    }

    public func save(_ day: PlannerDay) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.schema.encode(day, using: Self.encoder).write(to: fileURL(for: day.date), options: .atomic)
    }

    /// Every day with a file on disk, oldest first. Unrelated files are ignored.
    public func savedDays() throws -> [PlannerDayKey] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(atPath: directory.path)
            .compactMap { name in
                guard name.hasSuffix(".json") else { return nil }
                return PlannerDayKey(rawValue: String(name.dropLast(5)))
            }
            .sorted()
    }

    /// Loads `date`, creating it on first open by carrying over unfinished
    /// items from the most recent earlier day that has a file. The new day is
    /// saved immediately so carry-over happens exactly once.
    public func open(_ date: PlannerDayKey) throws -> PlannerDay {
        if let existing = try load(date) { return existing }
        var day = PlannerDay(date: date)
        // Walk back past corrupt files rather than failing the whole day.
        for previous in try savedDays().reversed() where previous < date {
            if let source = try? load(previous) {
                day = source.carryingOver(to: date)
                break
            }
        }
        try save(day)
        return day
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
