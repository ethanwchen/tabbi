import Foundation
import TabbiKitCore

/// Where the iPhone keeps the study session, the pet and the log: three
/// versioned JSON files in Application Support/Tabbi.
///
/// - `study.json`: the session and the Custom and Timer lengths
///   (`StudyFile.schema`).
/// - `pet.json`: the pet's look and points, a `PetSave`, the same document
///   the Mac writes, so sync can carry it later unchanged.
/// - `log.json`: every phase that ran, a `StudyLog` as on the Mac.
///
/// Every write is atomic, so a kill mid-write leaves the previous file. A
/// file that exists but cannot be read is never overwritten (the Mac's
/// rule), so a newer build's data survives a downgrade.
struct StudyPersistence {
    let folder: URL

    /// Application Support/Tabbi, created on first use.
    static var standard: StudyPersistence {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return StudyPersistence(folder: base.appendingPathComponent("Tabbi", isDirectory: true))
    }

    var studyURL: URL { folder.appendingPathComponent("study.json") }
    var petURL: URL { folder.appendingPathComponent("pet.json") }
    var logURL: URL { folder.appendingPathComponent("log.json") }

    /// The study session and the lengths the user picked.
    struct StudyFile: Codable, Equatable {
        var session: StudySession
        var custom: StudyCustomRhythm
        var timer: StudyTimerLength

        /// Version 1 is the first iPhone format. Add a step for any change;
        /// never edit one that has shipped.
        static let schema = VersionedJSON(current: 1)
    }

    /// What `load()` found, including which files must not be overwritten.
    struct Loaded {
        var engine: StudyEngine
        var unreadable: Set<URL>
    }

    /// Reads all three files; a missing one starts fresh.
    func load() -> Loaded {
        var unreadable: Set<URL> = []
        func read<Value>(_ url: URL, _ decode: (Data) throws -> Value) -> Value? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            do {
                return try decode(data)
            } catch {
                unreadable.insert(url)
                return nil
            }
        }
        let study = read(studyURL) { try StudyFile.schema.decode(StudyFile.self, from: $0) }
        let save = read(petURL) { try PetSave.decode($0) }
        let log = read(logURL) { try StudyLog.schema.decode(StudyLog.self, from: $0) }
        let engine = StudyEngine(
            session: study?.session,
            closet: PetCloset(save: save ?? PetSave(profile: .starter(.cat))),
            custom: study?.custom ?? .standard,
            timer: study?.timer ?? .standard,
            log: log ?? StudyLog()
        )
        return Loaded(engine: engine, unreadable: unreadable)
    }

    /// Writes what changed between `old` and `new` (everything when `old`
    /// is nil), skipping files that could not be read at launch.
    func save(_ new: StudyEngine, replacing old: StudyEngine?, unreadable: Set<URL>) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = StudyFile(session: new.session, custom: new.custom, timer: new.timer)
        if old.map({ StudyFile(session: $0.session, custom: $0.custom, timer: $0.timer) }) != file,
           !unreadable.contains(studyURL) {
            try StudyFile.schema.encode(file).write(to: studyURL, options: .atomic)
        }
        if old?.closet.save != new.closet.save, !unreadable.contains(petURL) {
            try new.closet.save.write(to: petURL)
        }
        if old?.log != new.log, !unreadable.contains(logURL) {
            try new.log.write(to: logURL)
        }
    }

    /// Deletes every file, for a clean start in UI tests.
    func reset() {
        try? FileManager.default.removeItem(at: folder)
    }
}
