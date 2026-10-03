import XCTest
@testable import TabbiKitCore

final class EditionStorageTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditionStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func storage(_ name: String) -> EditionStorage {
        EditionStorage(root: base.appendingPathComponent(name, isDirectory: true))
    }

    private func day(_ key: String) throws -> PlannerDayKey {
        try XCTUnwrap(PlannerDayKey(rawValue: key))
    }

    func testEachEditionHasItsOwnFolders() throws {
        let notchDeck = EditionStorage(edition: .notchDeck)
        let studyNotch = EditionStorage(edition: try XCTUnwrap(Edition.named("studynotch")))
        XCTAssertNotEqual(notchDeck.root, studyNotch.root)
        XCTAssertEqual(studyNotch.root.lastPathComponent, "StudyNotch")
        XCTAssertEqual(studyNotch.folder("Planner").deletingLastPathComponent(), studyNotch.root)
        XCTAssertEqual(studyNotch.file("pet.json", in: "Pet").pathComponents.suffix(3), ["StudyNotch", "Pet", "pet.json"])
    }

    func testTodaysFilesGoToTheEditionsFolder() throws {
        let study = storage("StudyNotch")
        let today = try day("2026-10-02")
        try PlannerRepository(storage: study).save(PlannerDay(date: today, items: [PlannerItem(title: "Cardio deck", createdAt: Date())]))
        try DayReviewRepository(storage: study).save(DayReview(date: today, done: [], carryingOver: [], focusSessions: 0, focusMinutes: 0))

        XCTAssertTrue(FileManager.default.fileExists(atPath: study.file("2026-10-02.json", in: "Planner").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: study.file("2026-10-02.json", in: "Reviews").path))
        XCTAssertNil(try PlannerRepository(storage: storage("NotchDeck")).load(today))
        XCTAssertEqual(ClaudeUsageLogScanner.indexURL(in: study), study.file("scan-index.json", in: "ClaudeUsage"))
    }

    func testAdoptingCopiesLegacyFoldersOnceAndKeepsTheOriginals() throws {
        let legacy = storage("NotchDeck")
        let study = storage("StudyNotch")
        let today = try day("2026-10-02")
        try PlannerRepository(storage: legacy).save(PlannerDay(date: today, items: [PlannerItem(title: "Anatomy", createdAt: Date())]))

        XCTAssertEqual(study.adoptFolders(["Planner", "Reviews"], from: legacy), ["Planner"])
        XCTAssertEqual(try PlannerRepository(storage: study).load(today)?.items.map(\.title), ["Anatomy"])
        XCTAssertEqual(try PlannerRepository(storage: legacy).load(today)?.items.map(\.title), ["Anatomy"])

        // Later changes on either side never flow across again.
        try PlannerRepository(storage: study).save(PlannerDay(date: today, items: [PlannerItem(title: "Pharm", createdAt: Date())]))
        try PlannerRepository(storage: legacy).save(PlannerDay(date: today, items: [PlannerItem(title: "Inbox", createdAt: Date())]))
        XCTAssertEqual(study.adoptFolders(["Planner", "Reviews"], from: legacy), [])
        XCTAssertEqual(try PlannerRepository(storage: study).load(today)?.items.map(\.title), ["Pharm"])
    }

    func testAdoptingNeverOverwritesAnExistingFolder() throws {
        let legacy = storage("NotchDeck")
        let study = storage("StudyNotch")
        let today = try day("2026-10-02")
        try PlannerRepository(storage: legacy).save(PlannerDay(date: today, items: [PlannerItem(title: "Old", createdAt: Date())]))
        try FileManager.default.createDirectory(at: study.folder("Planner"), withIntermediateDirectories: true)

        XCTAssertEqual(study.adoptFolders(["Planner"], from: legacy), [])
        XCTAssertNil(try PlannerRepository(storage: study).load(today))
    }

    func testTheDefaultEditionAdoptsNothingFromItself() throws {
        let legacy = storage("NotchDeck")
        try PlannerRepository(storage: legacy).save(PlannerDay(date: try day("2026-10-02"), items: []))
        XCTAssertEqual(legacy.adoptFolders(["Planner"], from: legacy), [])
    }
}
