import XCTest
@testable import NotchKitCore

final class EditionTests: XCTestCase {
    func testABuildWithoutTheKeyIsNotchDeckWithTheProductivityKit() {
        let edition = Edition.resolve(infoDictionary: nil)
        XCTAssertEqual(edition, .notchDeck)
        XCTAssertEqual(edition.defaultKitID, KitLibrary.defaultKitID)
        XCTAssertEqual(Edition.resolve(infoDictionary: ["CFBundleName": "NotchDeck"]), .notchDeck)
    }

    func testStudyNotchPreselectsTheMedicineKit() {
        let edition = Edition.resolve(infoDictionary: [Edition.infoKey: "studynotch"])
        XCTAssertEqual(edition.name, "StudyNotch")
        XCTAssertEqual(edition.bundleIdentifier, "dev.notchdeck.StudyNotch")
        XCTAssertEqual(edition.defaultKitID, "medicine")
    }

    func testUnknownOrMistypedEditionsFallBackToNotchDeck() {
        XCTAssertEqual(Edition.resolve(infoDictionary: [Edition.infoKey: "lawnotch"]), .notchDeck)
        XCTAssertEqual(Edition.resolve(infoDictionary: [Edition.infoKey: 42]), .notchDeck)
        XCTAssertEqual(Edition.named("StudyNotch"), .studyNotch)
        XCTAssertNil(Edition.named(""))
    }

    func testEveryEditionIsUniqueAndStartsWithABundledKit() {
        XCTAssertEqual(Edition.builtIn.first, .notchDeck)
        XCTAssertEqual(Set(Edition.builtIn.map(\.id)).count, Edition.builtIn.count)
        XCTAssertEqual(Set(Edition.builtIn.map(\.bundleIdentifier)).count, Edition.builtIn.count)
        for edition in Edition.builtIn {
            XCTAssertNotNil(KitLibrary.bundled[edition.defaultKitID], edition.id)
        }
    }

    func testAFreshStudyNotchInstallGetsTheMedicineTabs() throws {
        let suite = "EditionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = SettingsRepository(
            defaults: defaults, kits: .bundled, defaultKitID: Edition.studyNotch.defaultKitID
        )
        let settings = repository.load()
        let medicine = try XCTUnwrap(KitLibrary.bundled["medicine"])
        XCTAssertEqual(settings.kitID, "medicine")
        XCTAssertEqual(settings.modules, medicine.layout())
    }

    func testEachEditionKeepsItsOwnImportedKits() throws {
        let notchDeck = try XCTUnwrap(ImportedKitStore.standard(for: .notchDeck))
        let studyNotch = try XCTUnwrap(ImportedKitStore.standard(for: .studyNotch))
        XCTAssertNotEqual(notchDeck.directory, studyNotch.directory)
        XCTAssertEqual(notchDeck.directory.deletingLastPathComponent().lastPathComponent, "NotchDeck")
        XCTAssertEqual(studyNotch.directory.deletingLastPathComponent().lastPathComponent, "StudyNotch")
    }
}
