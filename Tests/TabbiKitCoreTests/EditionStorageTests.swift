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
        let tabbi = EditionStorage(edition: .tabbi)
        let lsat = EditionStorage(edition: Edition(id: "lsat", name: "LSAT Notch",
                                                   bundleIdentifier: "dev.tabbi.LSAT", defaultKitID: "student"))
        XCTAssertNotEqual(tabbi.root, lsat.root)
        XCTAssertEqual(tabbi.root.lastPathComponent, "Tabbi")
        XCTAssertEqual(tabbi.folder("Planner").deletingLastPathComponent(), tabbi.root)
        XCTAssertEqual(tabbi.file("pet.json", in: "Pet").pathComponents.suffix(3), ["Tabbi", "Pet", "pet.json"])
    }

    func testTodaysFilesGoToTheEditionsFolder() throws {
        let tabbi = storage("Tabbi")
        let today = try day("2026-10-02")
        try PlannerRepository(storage: tabbi).save(PlannerDay(date: today, items: [PlannerItem(title: "Cardio deck", createdAt: Date())]))
        try DayReviewRepository(storage: tabbi).save(DayReview(date: today, done: [], carryingOver: [], focusSessions: 0, focusMinutes: 0))

        XCTAssertTrue(FileManager.default.fileExists(atPath: tabbi.file("2026-10-02.json", in: "Planner").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tabbi.file("2026-10-02.json", in: "Reviews").path))
        XCTAssertNil(try PlannerRepository(storage: storage("Other")).load(today))
        XCTAssertEqual(ClaudeUsageLogScanner.indexURL(in: tabbi), tabbi.file("scan-index.json", in: "ClaudeUsage"))
    }
}
