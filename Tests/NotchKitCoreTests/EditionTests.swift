import XCTest
@testable import NotchKitCore

final class EditionTests: XCTestCase {
    private func studyNotch() throws -> Edition {
        try XCTUnwrap(Edition.named("studynotch"))
    }

    private func decode(_ json: String) throws -> Edition {
        try Edition.decode(from: Data(json.utf8))
    }

    private func edition(_ fields: String) -> String {
        """
        {"formatVersion": 1, "id": "lsat", "name": "LSAT Notch",
         "bundleIdentifier": "dev.notchdeck.LSAT", "defaultKitID": "student"\(fields)}
        """
    }

    func testABuildWithoutTheKeyIsNotchDeckWithTheProductivityKit() {
        let edition = Edition.resolve(infoDictionary: nil)
        XCTAssertEqual(edition, .notchDeck)
        XCTAssertEqual(edition.id, Edition.defaultID)
        XCTAssertEqual(edition.name, "NotchDeck")
        XCTAssertEqual(edition.defaultKitID, KitLibrary.defaultKitID)
        XCTAssertEqual(Edition.resolve(infoDictionary: ["CFBundleName": "NotchDeck"]), .notchDeck)
    }

    func testStudyNotchPreselectsTheMedicineKit() throws {
        let edition = Edition.resolve(infoDictionary: [Edition.infoKey: "studynotch"])
        XCTAssertEqual(edition.name, "StudyNotch")
        XCTAssertEqual(edition.bundleIdentifier, "dev.notchdeck.StudyNotch")
        XCTAssertEqual(edition.defaultKitID, "medicine")
        XCTAssertEqual(edition.infoPlist["NSCalendarsFullAccessUsageDescription"]?.hasPrefix("StudyNotch "), true)
        XCTAssertNil(edition.icon)
    }

    func testUnknownOrMistypedEditionsFallBackToNotchDeck() throws {
        XCTAssertEqual(Edition.resolve(infoDictionary: [Edition.infoKey: "lawnotch"]), .notchDeck)
        XCTAssertEqual(Edition.resolve(infoDictionary: [Edition.infoKey: 42]), .notchDeck)
        XCTAssertEqual(Edition.named("StudyNotch"), try studyNotch())
        XCTAssertNil(Edition.named(""))
    }

    func testEveryEditionFileLoadsUnderItsOwnNameAndStartsWithABundledKit() throws {
        let files = Edition.bundledFileURLs
        XCTAssertEqual(files.map { $0.deletingPathExtension().lastPathComponent }, ["notchdeck", "studynotch"])
        for file in files {
            XCTAssertNoThrow(try Edition.load(from: file), file.lastPathComponent)
        }
        XCTAssertEqual(Edition.builtIn.count, files.count, "an edition file failed to load")
        XCTAssertEqual(Edition.builtIn.first, .notchDeck)
        XCTAssertEqual(Set(Edition.builtIn.map(\.bundleIdentifier)).count, Edition.builtIn.count)
        XCTAssertEqual(Set(Edition.builtIn.map(\.name)).count, Edition.builtIn.count)
        for edition in Edition.builtIn {
            XCTAssertNotNil(KitLibrary.bundled[edition.defaultKitID], edition.id)
        }
    }

    func testANewEditionIsJustAFile() throws {
        let edition = try decode(edition(#", "icon": "LSAT.icns", "infoPlist": {"NSAppleEventsUsageDescription": "LSAT Notch plays music."}"#))
        XCTAssertEqual(edition.id, "lsat")
        XCTAssertEqual(edition.name, "LSAT Notch")
        XCTAssertEqual(edition.icon, "LSAT.icns")
        XCTAssertEqual(edition.infoPlist, ["NSAppleEventsUsageDescription": "LSAT Notch plays music."])
        XCTAssertEqual(EditionStorage(edition: edition).root.lastPathComponent, "LSAT Notch")
    }

    func testEditionFilesThatWouldBreakPackagingAreRefused() {
        let bad = [
            #"{"formatVersion": 1, "id": "Bad Id", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "student"}"#,
            #"{"formatVersion": 1, "id": "x", "name": "../X", "bundleIdentifier": "a.b", "defaultKitID": "student"}"#,
            #"{"formatVersion": 1, "id": "x", "name": " ", "bundleIdentifier": "a.b", "defaultKitID": "student"}"#,
            #"{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "nodots", "defaultKitID": "student"}"#,
            #"{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": ""}"#,
            #"{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s", "icon": "../x.icns"}"#,
            #"{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s", "infoPlist": {"CFBundleIdentifier": "c.d"}}"#,
            #"{"id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s"}"#,
            "not json",
        ]
        for json in bad {
            XCTAssertThrowsError(try decode(json), json) { error in
                guard case .invalid = error as? EditionError else {
                    return XCTFail("\(json): \(error)")
                }
            }
        }
    }

    func testAnEditionFromANewerFormatIsSkipped() {
        let json = #"{"formatVersion": 2, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s"}"#
        XCTAssertThrowsError(try decode(json)) { error in
            XCTAssertEqual(error as? EditionError, .unsupportedFormat(2))
        }
    }

    func testAFileWhoseIdDoesNotMatchItsNameIsRefused() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("law.json")
        try Data(edition("").utf8).write(to: file)
        XCTAssertThrowsError(try Edition.load(from: file))
    }

    func testAFreshStudyNotchInstallGetsTheMedicineTabs() throws {
        let suite = "EditionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = SettingsRepository(
            defaults: defaults, kits: .bundled, defaultKitID: try studyNotch().defaultKitID
        )
        let settings = repository.load()
        let medicine = try XCTUnwrap(KitLibrary.bundled["medicine"])
        XCTAssertEqual(settings.kitID, "medicine")
        XCTAssertEqual(settings.modules, medicine.layout())
    }

    func testEachEditionKeepsItsOwnImportedKits() throws {
        let notchDeck = try XCTUnwrap(ImportedKitStore.standard(for: .notchDeck))
        let studyNotch = try XCTUnwrap(ImportedKitStore.standard(for: try studyNotch()))
        XCTAssertNotEqual(notchDeck.directory, studyNotch.directory)
        XCTAssertEqual(notchDeck.directory.deletingLastPathComponent().lastPathComponent, "NotchDeck")
        XCTAssertEqual(studyNotch.directory.deletingLastPathComponent().lastPathComponent, "StudyNotch")
    }
}
