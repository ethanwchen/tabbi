import XCTest
@testable import TabbiKitCore

final class EditionTests: XCTestCase {
    private func decode(_ json: String) throws -> Edition {
        try Edition.decode(from: Data(json.utf8))
    }

    private func edition(_ fields: String) -> String {
        """
        {"formatVersion": 1, "id": "lsat", "name": "LSAT Notch",
         "bundleIdentifier": "dev.tabbi.LSAT", "defaultKitID": "medicine"\(fields)}
        """
    }

    func testABuildWithoutTheKeyIsTabbiWithTheProductivityKit() {
        let edition = Edition.resolve(infoDictionary: nil)
        XCTAssertEqual(edition, .tabbi)
        XCTAssertEqual(edition.id, Edition.defaultID)
        XCTAssertEqual(edition.name, "Tabbi")
        XCTAssertEqual(edition.bundleIdentifier, "dev.tabbi.Tabbi")
        XCTAssertEqual(edition.defaultKitID, KitLibrary.defaultKitID)
        XCTAssertNil(edition.icon)
        XCTAssertEqual(Edition.resolve(infoDictionary: ["CFBundleName": "Tabbi"]), .tabbi)
        XCTAssertEqual(Edition.resolve(infoDictionary: [Edition.infoKey: "tabbi"]), .tabbi)
    }

    func testUnknownOrRetiredEditionsFallBackToTabbi() throws {
        XCTAssertEqual(Edition.resolve(infoDictionary: [Edition.infoKey: "lawnotch"]), .tabbi)
        XCTAssertEqual(Edition.resolve(infoDictionary: [Edition.infoKey: "studynotch"]), .tabbi)
        XCTAssertEqual(Edition.resolve(infoDictionary: [Edition.infoKey: 42]), .tabbi)
        XCTAssertEqual(Edition.named("Tabbi"), .tabbi)
        XCTAssertNil(Edition.named(""))
    }

    func testEveryEditionFileLoadsUnderItsOwnNameAndStartsWithABundledKit() throws {
        let files = Edition.bundledFileURLs
        XCTAssertEqual(files.map { $0.deletingPathExtension().lastPathComponent }, ["appstore", "tabbi"])
        for file in files {
            XCTAssertNoThrow(try Edition.load(from: file), file.lastPathComponent)
        }
        XCTAssertEqual(Edition.builtIn.count, files.count, "an edition file failed to load")
        XCTAssertEqual(Edition.builtIn.first, .tabbi)
        // Editions on the same channel are separate apps and must not share
        // an identity; the App Store build is the same app as Tabbi.
        for distribution in [Edition.Distribution.direct, .appStore] {
            let editions = Edition.builtIn.filter { $0.distribution == distribution }
            XCTAssertEqual(Set(editions.map(\.bundleIdentifier)).count, editions.count)
            XCTAssertEqual(Set(editions.map(\.name)).count, editions.count)
        }
        for edition in Edition.builtIn {
            XCTAssertNotNil(KitLibrary.bundled[edition.defaultKitID], edition.id)
        }
    }

    func testTheDirectDownloadKeepsEveryModule() {
        XCTAssertEqual(Edition.tabbi.distribution, .direct)
        XCTAssertFalse(Edition.tabbi.isAppStore)
        XCTAssertTrue(Edition.tabbi.runsLocalTools)
        XCTAssertEqual(Edition.tabbi.excludedModules, [])
        let catalog = ModuleCatalog([.unknown(.planner), .unknown(.claudeAsk)])
        XCTAssertEqual(Edition.tabbi.catalog(from: catalog), catalog)
    }

    func testTheAppStoreEditionIsTabbiWithoutClaudeUsageAndParty() throws {
        let appStore = try XCTUnwrap(Edition.named("appstore"))
        XCTAssertTrue(appStore.isAppStore)
        XCTAssertFalse(appStore.runsLocalTools, "a sandboxed build can't run the claude CLI or Shortcuts")
        XCTAssertEqual(appStore.name, Edition.tabbi.name)
        XCTAssertEqual(appStore.bundleIdentifier, Edition.tabbi.bundleIdentifier)
        XCTAssertEqual(appStore.defaultKitID, KitLibrary.defaultKitID)
        XCTAssertEqual(Set(appStore.excludedModules), [.claudeUsage, .party])
        XCTAssertEqual(appStore.infoPlist["LSApplicationCategoryType"], "public.app-category.productivity")
        XCTAssertEqual(Edition.resolve(infoDictionary: [Edition.infoKey: "appstore"]), appStore)
    }

    func testAnAppStoreBuildWithoutAnEditionKeyRunsAsTheAppStoreEdition() throws {
        let appStore = try XCTUnwrap(Edition.named("appstore"))
        XCTAssertEqual(Edition.resolve(infoDictionary: nil, fallback: appStore), appStore)
        XCTAssertEqual(Edition.resolve(infoDictionary: [Edition.infoKey: "tabbi"], fallback: appStore), .tabbi)
    }

    func testExcludedModulesAndDistributionAreRead() throws {
        let custom = try decode(edition(#", "distribution": "appStore", "excludedModules": ["anki"]"#))
        XCTAssertEqual(custom.distribution, .appStore)
        XCTAssertEqual(custom.excludedModules, [.anki])
        let plain = try decode(edition(""))
        XCTAssertEqual(plain.distribution, .direct)
        XCTAssertEqual(plain.excludedModules, [])
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
            #"{"formatVersion": 1, "id": "Bad Id", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "medicine"}"#,
            #"{"formatVersion": 1, "id": "x", "name": "../X", "bundleIdentifier": "a.b", "defaultKitID": "medicine"}"#,
            #"{"formatVersion": 1, "id": "x", "name": " ", "bundleIdentifier": "a.b", "defaultKitID": "medicine"}"#,
            #"{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "nodots", "defaultKitID": "medicine"}"#,
            #"{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": ""}"#,
            #"{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s", "icon": "../x.icns"}"#,
            #"{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s", "infoPlist": {"CFBundleIdentifier": "c.d"}}"#,
            #"{"id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s"}"#,
            #"{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s", "distribution": "beta"}"#,
            #"{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s", "excludedModules": ["../x"]}"#,
            #"{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s", "excludedModules": "anki"}"#,
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

    func testAFreshInstallStartsWithTheEditionsKit() throws {
        let suite = "EditionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let lsat = try decode(edition(""))
        let repository = SettingsRepository(defaults: defaults, kits: .bundled, defaultKitID: lsat.defaultKitID)
        let settings = repository.load()
        let medicine = try XCTUnwrap(KitLibrary.bundled["medicine"])
        XCTAssertEqual(settings.kitID, "medicine")
        XCTAssertEqual(settings.modules, medicine.layout())
    }

    func testEachEditionKeepsItsOwnImportedKits() throws {
        let tabbi = try XCTUnwrap(ImportedKitStore.standard(for: .tabbi))
        let lsat = try XCTUnwrap(ImportedKitStore.standard(for: try decode(edition(""))))
        XCTAssertNotEqual(tabbi.directory, lsat.directory)
        XCTAssertEqual(tabbi.directory.deletingLastPathComponent().lastPathComponent, "Tabbi")
        XCTAssertEqual(lsat.directory.deletingLastPathComponent().lastPathComponent, "LSAT Notch")
    }
}
