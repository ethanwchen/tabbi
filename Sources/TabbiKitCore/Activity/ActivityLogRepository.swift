import Foundation

/// Stores the activity log as one JSON file per local day (`yyyy-MM-dd.json`)
/// in the edition's `Activity` folder.
///
/// Day files keep reads cheap (today, or the last week, never the whole
/// history) and stay readable and easy to delete by hand. Writes are atomic,
/// and a day file that can't be read is never overwritten, so a bad file
/// costs new records for that day rather than the old ones. Not
/// thread-safe; own it from a single actor.
public final class ActivityLogRepository {
    public let directory: URL
    private let calendar: Calendar
    private let fileManager: FileManager

    /// The folder in an edition's storage, `Application Support/<edition>/Activity`.
    public static let folderName = "Activity"

    /// The day file format: `{"schemaVersion": 1, "records": [...]}`.
    public static let schema = VersionedJSON(current: 1)

    public init(directory: URL, calendar: Calendar = .current, fileManager: FileManager = .default) {
        self.directory = directory
        self.calendar = calendar
        self.fileManager = fileManager
    }

    /// The edition's activity folder.
    public convenience init(storage: EditionStorage) {
        self.init(directory: storage.folder(Self.folderName))
    }

    public func fileURL(for day: PlannerDayKey) -> URL {
        directory.appendingPathComponent("\(day.rawValue).json", isDirectory: false)
    }

    /// The records of `day`, oldest first; empty when there is no file.
    /// Throws if the file is unreadable, so a caller never mistakes it for
    /// an empty day.
    public func records(on day: PlannerDayKey) throws -> [ActivityRecord] {
        let url = fileURL(for: day)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try Self.schema.decode(Document.self, from: Data(contentsOf: url), using: Self.decoder).records
    }

    /// The records of every day from `first` through `last` that can be read.
    public func records(from first: PlannerDayKey, through last: PlannerDayKey) -> [ActivityRecord] {
        savedDays()
            .filter { $0 >= first && $0 <= last }
            .flatMap { (try? records(on: $0)) ?? [] }
    }

    /// Adds records to their days' files, skipping any whose id is already
    /// there. Throws on the first day it can't write; earlier days are kept.
    public func append(_ newRecords: [ActivityRecord]) throws {
        let byDay = Dictionary(grouping: newRecords) { $0.day(calendar: calendar) }
        for day in byDay.keys.sorted() {
            var stored = try records(on: day)
            let known = Set(stored.map(\.id))
            let added = byDay[day, default: []].filter { !known.contains($0.id) }
            guard !added.isEmpty else { continue }
            stored += added
            stored.sort { $0.end < $1.end }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.schema.encode(Document(records: stored), using: Self.encoder)
                .write(to: fileURL(for: day), options: .atomic)
        }
    }

    /// Every day with a file on disk, oldest first. Unrelated files are ignored.
    public func savedDays() -> [PlannerDayKey] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .compactMap { name in
                guard name.hasSuffix(".json") else { return nil }
                return PlannerDayKey(rawValue: String(name.dropLast(5)))
            }
            .sorted()
    }

    private struct Document: Codable {
        var records: [ActivityRecord]
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
