import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// Importing a kit shows what it changes before anything is saved, and the
/// last switch, import or removal can be undone: the kit files, the tabs
/// and what modules took from the kit (Today's starter tasks, the focus
/// sound) all go back.
@MainActor
final class KitSwitchUndoTests: XCTestCase {
    private let moduleTypes: [any NotchModule.Type] = [TodayModule.self, FocusModule.self, StudyModule.self]
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kit-undo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeSettings() -> SettingsStore {
        let suite = "KitSwitchUndoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return SettingsStore(catalog: ModuleList.catalog(of: moduleTypes), defaults: defaults,
                             kitStore: ImportedKitStore(directory: root.appendingPathComponent("Kits")),
                             integratesWithSystem: false)
    }

    private func kitFile(_ json: String) throws -> URL {
        let url = root.appendingPathComponent("\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        return url
    }

    private let deepWork = #"""
    {"formatVersion": 1, "id": "deep-work", "name": "Deep Work", "version": "1.0", "modules": ["focus", "planner"],
     "starterTasks": ["Block two hours"], "defaults": {"moduleSettings": {"focus": {"sounds": [{"sound": "rain", "level": 0.5}]}}}}
    """#

    func testInspectingAnImportChangesNothingUntilItIsInstalled() throws {
        let settings = makeSettings()
        let before = settings.settings
        let candidate = try settings.inspectKit(from: kitFile(deepWork))
        XCTAssertNil(settings.kits["imported.deep-work"])
        XCTAssertEqual(settings.settings, before)

        let preview = settings.preview(of: candidate.kit)
        XCTAssertEqual(preview.tabs, [.focus, .planner])
        XCTAssertEqual(preview.starterTasks, ["Block two hours"])

        try settings.installKit(candidate, switchingWith: nil)
        XCTAssertNotNil(settings.kits["imported.deep-work"])
        XCTAssertEqual(settings.settings, before, "Add Only keeps the user's tabs")
    }

    func testUndoingAnImportRestoresTabsFilesAndModuleState() throws {
        let settings = makeSettings()
        let services = AppServices(settings: settings, moduleTypes: moduleTypes,
                                   environment: ["NOTCHDECK_DEMO": "1"], arguments: [])
        let today = try XCTUnwrap(services.modules.module(TodayModule.self)).store
        let focusMode = try XCTUnwrap(services.modules.module(FocusModule.self)).focusMode
        focusMode.settings.mix = .off
        let tasksBefore = today.day.items.map(\.title)
        let settingsBefore = settings.settings

        try settings.installKit(settings.inspectKit(from: kitFile(deepWork)), switchingWith: [:])
        XCTAssertEqual(settings.settings.kitID, "imported.deep-work")
        XCTAssertEqual(today.day.items.map(\.title), tasksBefore + ["Block two hours"])
        XCTAssertNotEqual(focusMode.settings.mix, .off)
        XCTAssertEqual(settings.lastKitSwitch?.kitName, "Deep Work")

        settings.undoKitSwitch()
        XCTAssertEqual(settings.settings, settingsBefore)
        XCTAssertNil(settings.kits["imported.deep-work"], "the import is taken back too")
        XCTAssertEqual(today.day.items.map(\.title), tasksBefore)
        XCTAssertEqual(focusMode.settings.mix, .off, "the user's focus sound comes back")
        XCTAssertNil(settings.lastKitSwitch)
    }

    func testUndoKeepsStarterTasksTheUserAlreadyWorkedOn() throws {
        let settings = makeSettings()
        let services = AppServices(settings: settings, moduleTypes: moduleTypes,
                                   environment: ["NOTCHDECK_DEMO": "1"], arguments: [])
        let today = try XCTUnwrap(services.modules.module(TodayModule.self)).store
        try settings.installKit(settings.inspectKit(from: kitFile(deepWork)), switchingWith: [:])
        let task = try XCTUnwrap(today.day.items.first { $0.title == "Block two hours" })
        today.toggle(task.id)

        settings.undoKitSwitch()
        XCTAssertTrue(today.day.items.contains { $0.id == task.id })
    }

    func testUndoingAReimportPutsTheEarlierVersionBack() throws {
        let settings = makeSettings()
        try settings.installKit(settings.inspectKit(from: kitFile(deepWork)), switchingWith: [:])
        let update = try settings.inspectKit(from: kitFile(deepWork.replacingOccurrences(of: "1.0", with: "2.0")))
        XCTAssertEqual(update.replaces?.version, "1.0")
        XCTAssertEqual(update.versionChange, "Deep Work 1.0 to 2.0")

        try settings.installKit(update, switchingWith: [:])
        XCTAssertEqual(settings.activeKit?.version, "2.0")
        settings.undoKitSwitch()
        XCTAssertEqual(settings.activeKit?.version, "1.0")
    }

    func testUndoingARemovalBringsTheKitBack() throws {
        let settings = makeSettings()
        try settings.installKit(settings.inspectKit(from: kitFile(deepWork)), switchingWith: [:])
        let imported = settings.settings
        try settings.removeActiveKit()
        XCTAssertNil(settings.kits["imported.deep-work"])
        XCTAssertEqual(settings.lastKitSwitch?.kitName, "Deep Work")

        settings.undoKitSwitch()
        XCTAssertEqual(settings.settings, imported)
        XCTAssertEqual(settings.activeKit?.id, "imported.deep-work")
    }

    func testUndoingAnAddOnlyImportTakesBackOnlyThatFile() throws {
        let settings = makeSettings()
        settings.switchKit(to: "student")
        let switched = settings.settings
        let candidate = try settings.inspectKit(from: kitFile(deepWork))
        try settings.installKit(candidate, switchingWith: nil)
        XCTAssertEqual(settings.lastKitSwitch?.kitName, "Deep Work")
        XCTAssertEqual(settings.lastKitSwitch?.switchedKit, false)

        settings.undoKitSwitch()
        XCTAssertNil(settings.kits["imported.deep-work"], "the import is taken back")
        XCTAssertEqual(settings.settings, switched, "the earlier switch to Student stays")
        XCTAssertNil(settings.lastKitSwitch)
    }

    func testUndoKeepsSettingsTheKitDoesNotSet() throws {
        let settings = makeSettings()
        let kitBefore = settings.settings.kitID
        settings.switchKit(to: "student")
        settings.settings.openOnHover.toggle()
        settings.settings.hapticsEnabled.toggle()
        settings.settings.notchPreview.interval = .long
        let changed = settings.settings

        settings.undoKitSwitch()
        XCTAssertEqual(settings.settings.kitID, kitBefore)
        XCTAssertEqual(settings.settings.openOnHover, changed.openOnHover)
        XCTAssertEqual(settings.settings.hapticsEnabled, changed.hapticsEnabled)
        XCTAssertEqual(settings.settings.notchPreview.interval, .long)
    }

    func testResetIsNotUndoable() throws {
        let settings = makeSettings()
        settings.resetToKitDefaults()
        XCTAssertNil(settings.lastKitSwitch)
        settings.switchKit(to: "student")
        XCTAssertEqual(settings.lastKitSwitch?.kitName, settings.kits["student"]?.name)
    }
}
