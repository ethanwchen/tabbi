import XCTest
@testable import TabbiKitCore

final class LegacyDataMigrationTests: XCTestCase {
    private var base: URL!
    private var suite: String!
    private var defaults: UserDefaults!
    private var legacySuites: [String] = []

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyDataMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        suite = "dev.tabbi.tests.migration.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
        for name in [suite!] + legacySuites {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
    }

    private var storage: EditionStorage {
        EditionStorage(root: base.appendingPathComponent("Tabbi", isDirectory: true))
    }

    private func folder(_ name: String) -> URL {
        base.appendingPathComponent(name, isDirectory: true)
    }

    /// A legacy domain holding `values`, removed again in tear down.
    private func legacyDomain(_ values: [String: Any]) -> String {
        let name = "dev.tabbi.tests.\(UUID().uuidString)"
        legacySuites.append(name)
        UserDefaults.standard.setPersistentDomain(values, forName: name)
        return name
    }

    private func write(_ text: String, to file: String, in folder: URL) throws {
        let url = folder.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ file: String, in folder: URL) throws -> String {
        try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
    }

    private func migration(folders: [String], domains: [String]) -> LegacyDataMigration {
        LegacyDataMigration(legacyFolders: folders.map(folder), legacyDomains: domains,
                            storage: storage, defaults: defaults)
    }

    func testMovesTheOldFolderAndCopiesThePreferences() throws {
        try write("checklist", to: "Planner/2026-10-02.json", in: folder("NotchDeck"))
        try write("pet", to: "Pet/pet.json", in: folder("NotchDeck"))
        let domain = legacyDomain(["selectedModule": "study", "study.deepFocus": true])

        let outcome = migration(folders: ["NotchDeck"], domains: [domain]).runIfNeeded()

        XCTAssertTrue(outcome.ran)
        XCTAssertEqual(outcome.movedFolder?.lastPathComponent, "NotchDeck")
        XCTAssertEqual(outcome.copiedDomain, domain)
        XCTAssertEqual(try read("Planner/2026-10-02.json", in: storage.root), "checklist")
        XCTAssertEqual(try read("pet.json", in: storage.folder("Pet")), "pet")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder("NotchDeck").path))
        XCTAssertEqual(defaults.string(forKey: "selectedModule"), "study")
        XCTAssertTrue(defaults.bool(forKey: "study.deepFocus"))
    }

    func testRunsOnlyOnce() throws {
        let migration = migration(folders: ["NotchDeck"], domains: [])
        XCTAssertTrue(migration.runIfNeeded().ran)

        try write("late", to: "Pet/pet.json", in: folder("NotchDeck"))
        let second = migration.runIfNeeded()

        XCTAssertFalse(second.ran)
        XCTAssertNil(second.movedFolder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.file("pet.json", in: "Pet").path))
    }

    func testNeverOverwritesWhatTabbiAlreadyHas() throws {
        try write("old pet", to: "Pet/pet.json", in: folder("NotchDeck"))
        try write("old kit", to: "Kits/mine.json", in: folder("NotchDeck"))
        try write("new pet", to: "Pet/pet.json", in: storage.root)
        defaults.set("today", forKey: "selectedModule")
        let domain = legacyDomain(["selectedModule": "study", "claudeUsage.limitsRecord": "record"])

        migration(folders: ["NotchDeck"], domains: [domain]).runIfNeeded()

        XCTAssertEqual(try read("Pet/pet.json", in: storage.root), "new pet")
        XCTAssertEqual(try read("Kits/mine.json", in: storage.root), "old kit")
        // The file Tabbi already had stays behind, so the old folder is kept.
        XCTAssertEqual(try read("Pet/pet.json", in: folder("NotchDeck")), "old pet")
        XCTAssertEqual(defaults.string(forKey: "selectedModule"), "today")
        XCTAssertEqual(defaults.string(forKey: "claudeUsage.limitsRecord"), "record")
    }

    func testMergesASubfolderTabbiAlreadyCreated() throws {
        try write("old day", to: "Planner/2026-10-01.json", in: folder("NotchDeck"))
        try write("old today", to: "Planner/2026-10-03.json", in: folder("NotchDeck"))
        try write("old index", to: "ClaudeUsage/Index/index.json", in: folder("NotchDeck"))
        try write("new today", to: "Planner/2026-10-03.json", in: storage.root)
        try FileManager.default.createDirectory(at: storage.folder("ClaudeUsage"), withIntermediateDirectories: true)

        migration(folders: ["NotchDeck"], domains: []).runIfNeeded()

        XCTAssertEqual(try read("Planner/2026-10-01.json", in: storage.root), "old day")
        XCTAssertEqual(try read("Planner/2026-10-03.json", in: storage.root), "new today")
        XCTAssertEqual(try read("ClaudeUsage/Index/index.json", in: storage.root), "old index")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder("NotchDeck").path), ["Planner"])
        XCTAssertEqual(try read("Planner/2026-10-03.json", in: folder("NotchDeck")), "old today")
    }

    func testAdoptsTheFirstLegacySourceThatHasData() throws {
        try write("study notch", to: "Pet/pet.json", in: folder("StudyNotch"))
        let empty = legacyDomain([:])
        let studyNotch = legacyDomain(["selectedModule": "anki"])

        let outcome = migration(folders: ["NotchDeck", "StudyNotch"], domains: [empty, studyNotch]).runIfNeeded()

        XCTAssertEqual(outcome.movedFolder?.lastPathComponent, "StudyNotch")
        XCTAssertEqual(outcome.copiedDomain, studyNotch)
        XCTAssertEqual(try read("Pet/pet.json", in: storage.root), "study notch")
        XCTAssertEqual(defaults.string(forKey: "selectedModule"), "anki")
    }

    func testAFreshInstallHasNothingToMove() {
        let outcome = migration(folders: ["NotchDeck"], domains: [legacyDomain([:])]).runIfNeeded()

        XCTAssertEqual(outcome, LegacyDataMigration.Outcome(movedFolder: nil, copiedDomain: nil, ran: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.root.path))
        XCTAssertTrue(defaults.bool(forKey: LegacyDataMigration.doneKey))
    }

    func testTabbiLooksBesideItsOwnFolder() {
        let migration = LegacyDataMigration.tabbi(storage: storage, defaults: defaults)

        XCTAssertEqual(migration.legacyFolders, [folder("NotchDeck"), folder("StudyNotch")])
        XCTAssertEqual(migration.legacyDomains.first, "dev.notchdeck.NotchDeck")
    }
}
