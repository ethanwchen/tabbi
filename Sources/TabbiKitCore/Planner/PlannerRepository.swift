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

    /// The day file format. Version 1 added the `schemaVersion` key; version
    /// 2 added `isPlannedAhead`, false for every older file because each one
    /// was created by `open` with its carry-over already taken in.
    public static let schema = VersionedJSON(current: 2, migrations: [
        .init(version: 2) { object in
            if object["isPlannedAhead"] == nil { object["isPlannedAhead"] = false }
        },
    ])

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
        return day.date == date ? day : PlannerDay(date: date, items: day.items, isPlannedAhead: day.isPlannedAhead)
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

    /// Loads `date` as today. On its first open the day takes in the
    /// unfinished items of the most recent earlier day that has a file,
    /// ahead of anything planned for it in advance, and is saved right away
    /// so carry-over happens exactly once.
    public func open(_ date: PlannerDayKey) throws -> PlannerDay {
        let (day, isNew) = try opening(date)
        if isNew { try save(day) }
        return day
    }

    /// What `open` returns, without creating or updating the day's file: a
    /// snapshot run shows today's list but must leave no trace on disk.
    public func preview(_ date: PlannerDayKey) throws -> PlannerDay {
        try opening(date).day
    }

    /// `date` as today, and whether it took in carry-over just now (so `open`
    /// saves it): a day already opened comes back as it was saved.
    private func opening(_ date: PlannerDayKey) throws -> (day: PlannerDay, isNew: Bool) {
        let existing = try load(date)
        if let existing, !existing.isPlannedAhead { return (existing, false) }
        var day = existing ?? PlannerDay(date: date)
        day.takeCarryOver(from: try mostRecentDay(before: date))
        return (day, true)
    }

    /// Loads a day other than today to look at or plan, without creating a
    /// file: yesterday's list as it was left, or tomorrow's plan so far (an
    /// empty planned-ahead day until the first task is added and saved).
    public func peek(_ date: PlannerDayKey, today: PlannerDayKey) throws -> PlannerDay {
        if let existing = try load(date) { return existing }
        return PlannerDay(date: date, isPlannedAhead: date > today)
    }

    /// The latest readable day before `date`, walking back past corrupt
    /// files rather than failing the whole day. A day planned ahead but never
    /// opened first takes in its own predecessor (in memory), so skipping it
    /// loses none of the older leftovers.
    private func mostRecentDay(before date: PlannerDayKey) throws -> PlannerDay? {
        for previous in try savedDays().reversed() where previous < date {
            guard var source = try? load(previous) else { continue }
            if source.isPlannedAhead { source.takeCarryOver(from: try mostRecentDay(before: previous)) }
            return source
        }
        return nil
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
