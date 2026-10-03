import XCTest
@testable import NotchKitCore

final class ImportedKitStoreTests: XCTestCase {
    private var root: URL!
    private var store: ImportedKitStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kits-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = ImportedKitStore(directory: root.appendingPathComponent("Kits", isDirectory: true))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func file(_ name: String, _ json: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(json.utf8).write(to: url)
        return url
    }

    private func kitJSON(id: String, name: String, extra: String = "") -> String {
        #"{"formatVersion": 1, "id": "\#(id)", "name": "\#(name)", "modules": ["planner"]\#(extra)}"#
    }

    func testAnEmptyOrMissingFolderHasNoKits() {
        XCTAssertEqual(store.load(), [])
    }

    func testInstalledKitsLoadBackSortedByName() throws {
        // File and id order differ from name order on purpose.
        try store.install(from: file("a.json", kitJSON(id: "tech", name: "LeetCode grind")), catalog: .builtIn)
        try store.install(from: file("b.json", kitJSON(id: "z-law", name: "Law school")), catalog: .builtIn)
        XCTAssertEqual(store.load().map(\.name), ["Law school", "LeetCode grind"])
    }

    func testInstallKeepsTheFileAsWritten() throws {
        let json = kitJSON(id: "tech", name: "Tech", extra: #", "futureField": {"x": 1}"#)
        try store.install(from: file("tech.json", json), catalog: .builtIn)
        let saved = try String(contentsOf: store.directory.appendingPathComponent("tech.json"), encoding: .utf8)
        XCTAssertEqual(saved, json)
    }

    func testReimportingAnIdReplacesTheEarlierKit() throws {
        try store.install(from: file("one.json", kitJSON(id: "tech", name: "Tech")), catalog: .builtIn)
        try store.install(from: file("two.json", kitJSON(id: "tech", name: "Tech v2")), catalog: .builtIn)
        XCTAssertEqual(store.load().map(\.name), ["Tech v2"])
    }

    func testInspectingSavesNothingAndNamesTheImportItReplaces() throws {
        let first = try store.inspect(from: file("one.json", kitJSON(id: "tech", name: "Tech", extra: #", "version": "1.2""#)),
                                      catalog: .builtIn)
        XCTAssertNil(first.replaces)
        XCTAssertFalse(first.overwritesFile)
        XCTAssertEqual(store.load(), [], "nothing is saved before the user confirms")

        try store.install(first)
        let second = try store.inspect(from: file("two.json", kitJSON(id: "tech", name: "Tech", extra: #", "version": "1.3""#)),
                                       catalog: .builtIn)
        XCTAssertEqual(second.replaces?.version, "1.2")
        XCTAssertTrue(second.overwritesFile)
        XCTAssertEqual(second.versionChange, "Tech 1.2 to 1.3")
        XCTAssertEqual(store.load().map(\.version), ["1.2"])
    }

    func testAFileThatNoLongerLoadsStillCountsAsReplaced() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: store.directory.appendingPathComponent("tech.json"))
        let candidate = try store.inspect(from: file("tech.json", kitJSON(id: "tech", name: "Tech")), catalog: .builtIn)
        XCTAssertNil(candidate.replaces)
        XCTAssertTrue(candidate.overwritesFile)
        XCTAssertNil(candidate.versionChange)
    }

    func testRestorePutsBackOrRemovesAFile() throws {
        try store.install(from: file("one.json", kitJSON(id: "tech", name: "Tech")), catalog: .builtIn)
        let saved = store.savedData(for: "tech")
        try store.install(from: file("two.json", kitJSON(id: "tech", name: "Tech v2")), catalog: .builtIn)
        try store.restore(saved, for: "tech")
        XCTAssertEqual(store.load().map(\.name), ["Tech"])
        try store.restore(nil, for: "tech")
        XCTAssertEqual(store.load(), [])
        XCTAssertNil(store.savedData(for: "tech"))
    }

    func testRefusesInvalidKitsAndBuiltInIds() throws {
        XCTAssertThrowsError(try store.install(from: file("bad.json", "{"), catalog: .builtIn)) { error in
            guard case KitError.malformed = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try store.install(from: file("med.json", kitJSON(id: "medicine", name: "Mine")), catalog: .builtIn)) { error in
            XCTAssertEqual(error as? KitError, .reservedID("medicine"))
        }
        XCTAssertThrowsError(try store.install(from: root.appendingPathComponent("missing.json"), catalog: .builtIn))
        XCTAssertEqual(store.load(), [])
    }

    func testRefusesAKitThatRequiresAModuleThisBuildLacks() throws {
        let json = kitJSON(id: "grind", name: "Grind", extra: #", "requires": {"modules": ["leetcode", "planner"]}"#)
        XCTAssertThrowsError(try store.install(from: file("grind.json", json), catalog: .builtIn)) { error in
            XCTAssertEqual(error as? KitError, .missingRequiredModules(["leetcode"]))
        }
        XCTAssertEqual(store.load(), [])
        let plain = kitJSON(id: "plain", name: "Plain", extra: #", "requires": {"modules": ["planner"]}"#)
        XCTAssertEqual(try store.install(from: file("plain.json", plain), catalog: .builtIn).requires.modules, [.planner])
    }

    func testFilesBrokenAfterImportAreSkipped() throws {
        try store.install(from: file("tech.json", kitJSON(id: "tech", name: "Tech")), catalog: .builtIn)
        try Data("not json".utf8).write(to: store.directory.appendingPathComponent("broken.json"))
        try Data("notes".utf8).write(to: store.directory.appendingPathComponent("README.txt"))
        XCTAssertEqual(store.load().map(\.id), ["tech"])
    }

    func testRemoveDeletesOnlyThatKit() throws {
        try store.install(from: file("a.json", kitJSON(id: "tech", name: "Tech")), catalog: .builtIn)
        try store.install(from: file("b.json", kitJSON(id: "law", name: "Law")), catalog: .builtIn)
        try store.remove(id: "tech")
        try store.remove(id: "tech")
        XCTAssertEqual(store.load().map(\.id), ["law"])
    }

    func testInstalledLibraryListsBundledKitsFirst() throws {
        let tech = try KitManifest.decode(from: Data(kitJSON(id: "tech", name: "Tech").utf8))
        let shadow = try KitManifest.decode(from: Data(kitJSON(id: "productivity", name: "Fake").utf8))
        let library = KitLibrary.installed(imported: [tech, shadow])
        XCTAssertEqual(library.kits.map(\.id), KitLibrary.bundledIDs + ["tech"])
        XCTAssertEqual(library["productivity"]?.name, KitLibrary.bundled["productivity"]?.name)
        XCTAssertTrue(KitLibrary.isBundled("medicine"))
        XCTAssertFalse(KitLibrary.isBundled("tech"))
    }

    func testUsesDefaultsUntilTheTabsChange() throws {
        let medicine = try XCTUnwrap(KitLibrary.bundled["medicine"])
        let productivity = try XCTUnwrap(KitLibrary.bundled["productivity"])
        var settings = AppSettings.default
        settings.apply(medicine)
        XCTAssertTrue(settings.usesDefaults(of: medicine))
        XCTAssertFalse(settings.usesDefaults(of: productivity))
        settings.modules.setEnabled(.system, true)
        XCTAssertFalse(settings.usesDefaults(of: medicine))
        settings.apply(medicine)
        XCTAssertTrue(settings.usesDefaults(of: medicine))
    }
}
