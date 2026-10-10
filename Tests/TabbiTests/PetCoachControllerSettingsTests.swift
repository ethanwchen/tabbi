import XCTest
import Combine
import TabbiKitCore
@testable import Tabbi

/// Settings › Pet Coach through `PetCoachController`: the nudges switch and
/// the distracting apps, how they are saved next to the pet, and what the
/// controller does with a save it cannot read or in demo mode.
///
/// No test focuses the timer, so the controller never samples idle time
/// or the frontmost app, and `screen` returns nil, so no overlay opens.
@MainActor
final class PetCoachControllerSettingsTests: XCTestCase {
    private var folder: URL!
    private var storage: EditionStorage { EditionStorage(root: folder) }
    private var saveURL: URL { PetCoachController.saveURL(in: storage) }
    private var screenRequests = 0
    private var observers: Set<AnyCancellable> = []

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PetCoachControllerSettingsTests-\(UUID().uuidString)", isDirectory: true)
        screenRequests = 0
    }

    override func tearDown() async throws {
        observers.removeAll()
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeController(_ runMode: RunMode = .live) -> PetCoachController {
        PetCoachController(
            storage: storage,
            runMode: runMode,
            profile: { PetProfile(name: "Waffles", breed: .corgi) },
            screen: { [weak self] in
                self?.screenRequests += 1
                return nil
            },
            pauseTimer: {},
            resumeTimer: {}
        )
    }

    private func savedOnDisk() throws -> PetCoachSave? {
        try PetCoachSave.load(from: saveURL)
    }

    /// A minimal `.app` bundle with `bundleID`, as Settings' app picker hands it over.
    private func makeApp(named name: String, bundleID: String) throws -> URL {
        let app = folder.appendingPathComponent("Apps/\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name, "CFBundlePackageType": "APPL"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    private func countChanges(of controller: PetCoachController) -> () -> Int {
        var count = 0
        controller.objectWillChange.sink { count += 1 }.store(in: &observers)
        return { count }
    }

    func testFreshInstallStartsWithNudgesOnAnkiAsFocusAndWritesNothing() throws {
        let coach = makeController()

        XCTAssertTrue(coach.nudgesOn)
        XCTAssertEqual(coach.apps, CoachAppList())
        XCTAssertEqual(coach.apps.category(of: "net.ankiweb.anki"), .focus)
        XCTAssertTrue(coach.apps.addedDistracting.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saveURL.path), "Opening the coach must not create a save")
    }

    func testSwitchingNudgesOffIsSavedAndReadBackOnTheNextLaunch() throws {
        let coach = makeController()
        let changes = countChanges(of: coach)

        coach.setNudgesOn(false)

        XCTAssertFalse(coach.nudgesOn)
        XCTAssertEqual(changes(), 1, "Settings follows the switch")
        XCTAssertEqual(try savedOnDisk()?.nudgesOn, false)
        XCTAssertFalse(makeController().nudgesOn)

        coach.setNudgesOn(true)
        XCTAssertEqual(try savedOnDisk()?.nudgesOn, true)
        XCTAssertTrue(makeController().nudgesOn)
    }

    func testSettingTheSwitchToItsCurrentValueChangesAndWritesNothing() throws {
        let coach = makeController()
        let changes = countChanges(of: coach)

        coach.setNudgesOn(true)

        XCTAssertEqual(changes(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saveURL.path))
    }

    func testTogglingASuggestedAppAddsItThenTakesItOffAndSavesEachStep() throws {
        let coach = makeController()
        let changes = countChanges(of: coach)

        coach.toggleDistracting("com.hnc.Discord")

        XCTAssertTrue(coach.apps.isDistracting("com.hnc.Discord"))
        XCTAssertTrue(coach.apps.addedDistracting.isEmpty, "A suggestion is not listed as an added app")
        XCTAssertEqual(try savedOnDisk()?.apps.isDistracting("com.hnc.Discord"), true)
        XCTAssertTrue(makeController().apps.isDistracting("com.hnc.Discord"))

        coach.toggleDistracting("com.hnc.Discord")

        XCTAssertFalse(coach.apps.isDistracting("com.hnc.Discord"))
        XCTAssertEqual(try savedOnDisk()?.apps.isDistracting("com.hnc.Discord"), false)
        XCTAssertEqual(changes(), 2)
    }

    func testTogglingAFocusAppMakesItDistracting() throws {
        let coach = makeController()

        coach.toggleDistracting("net.ankiweb.anki")

        XCTAssertEqual(coach.apps.category(of: "net.ankiweb.anki"), .distracting)
        XCTAssertEqual(makeController().apps.category(of: "net.ankiweb.anki"), .distracting)
    }

    func testAddingAPickedAppSavesItsBundleIDOnceAndListsItAsAdded() throws {
        let coach = makeController()
        let changes = countChanges(of: coach)
        let app = try makeApp(named: "Chess", bundleID: "com.Example.Chess")

        coach.addDistractingApp(at: app)

        XCTAssertEqual(coach.apps.addedDistracting, ["com.example.chess"])
        XCTAssertEqual(try savedOnDisk()?.apps.addedDistracting, ["com.example.chess"])
        XCTAssertEqual(changes(), 1)

        // Picking it again is a no-op: no change for Settings, no rewrite.
        try FileManager.default.removeItem(at: saveURL)
        coach.addDistractingApp(at: app)

        XCTAssertEqual(changes(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saveURL.path))

        // The row's remove button takes it off again.
        coach.toggleDistracting("com.example.chess")
        XCTAssertTrue(coach.apps.addedDistracting.isEmpty)
        XCTAssertEqual(try savedOnDisk()?.apps.addedDistracting, [])
    }

    func testPickingSomethingThatIsNotAnAppIsIgnored() throws {
        let coach = makeController()
        let changes = countChanges(of: coach)
        let notAnApp = folder.appendingPathComponent("Empty.app", isDirectory: true)
        try FileManager.default.createDirectory(at: notAnApp, withIntermediateDirectories: true)

        coach.addDistractingApp(at: notAnApp)
        coach.addDistractingApp(at: folder.appendingPathComponent("Missing.app"))

        XCTAssertEqual(coach.apps, CoachAppList())
        XCTAssertEqual(changes(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saveURL.path))
    }

    func testChangingSettingsKeepsTheCoachStateAlreadySaved() throws {
        var saved = PetCoachSave(apps: CoachAppList(distracting: ["com.apple.TV"]))
        let snoozeEnd = Date(timeIntervalSince1970: 1_800_000_000)
        saved.coach.snooze(until: snoozeEnd)
        try saved.write(to: saveURL)

        let coach = makeController()
        XCTAssertTrue(coach.apps.isDistracting("com.apple.TV"))

        coach.toggleDistracting("com.hnc.Discord")

        let after = try XCTUnwrap(savedOnDisk())
        XCTAssertEqual(after.coach, saved.coach, "A Settings change must not reset snooze or cooldowns")
        XCTAssertTrue(after.apps.isDistracting("com.apple.TV"))
        XCTAssertTrue(after.apps.isDistracting("com.hnc.Discord"))
    }

    func testAnUnreadableSaveRunsOnDefaultsAndIsNeverOverwritten() throws {
        try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let garbage = Data("{\"version\": 1, \"coach\": nope".utf8)
        try garbage.write(to: saveURL)

        let coach = makeController()

        XCTAssertTrue(coach.nudgesOn)
        XCTAssertEqual(coach.apps, CoachAppList())

        coach.setNudgesOn(false)
        coach.toggleDistracting("com.hnc.Discord")
        coach.addDistractingApp(at: try makeApp(named: "Chess", bundleID: "com.example.chess"))

        XCTAssertFalse(coach.nudgesOn, "Settings still works for this launch")
        XCTAssertTrue(coach.apps.isDistracting("com.hnc.Discord"))
        XCTAssertEqual(try Data(contentsOf: saveURL), garbage, "The file stays as it was, for the user to recover")
    }

    func testDemoModeShowsSampleAppsAndNeverReadsOrWritesTheSave() throws {
        try PetCoachSave(nudgesOn: false).write(to: saveURL)
        let real = try Data(contentsOf: saveURL)

        let coach = makeController(.demo)

        XCTAssertTrue(coach.nudgesOn, "Demo mode ignores the real save")
        XCTAssertTrue(coach.apps.isDistracting("com.apple.MobileSMS"))
        XCTAssertTrue(coach.apps.isDistracting("com.hnc.Discord"))
        XCTAssertEqual(coach.apps.addedDistracting, ["com.apple.news"])

        coach.setNudgesOn(false)
        coach.toggleDistracting("com.apple.news")
        coach.addDistractingApp(at: try makeApp(named: "Chess", bundleID: "com.example.chess"))

        XCTAssertEqual(coach.apps.addedDistracting, ["com.example.chess"])
        XCTAssertEqual(try Data(contentsOf: saveURL), real)
    }

    func testCelebrationsPlayOnlyWhileTheCoachIsOnAndNeverInDemoMode() {
        let award = PetStudyAward(completedSessions: 1, minutes: 25, points: 35)
        let coach = makeController()

        coach.celebrate(award)
        coach.stop()
        XCTAssertEqual(screenRequests, 0, "An award before the coach starts shows nothing")

        coach.start()
        coach.celebrate(award)
        XCTAssertEqual(screenRequests, 1, "A running coach sends the pet out, nudges on or off")

        coach.setNudgesOn(false)
        coach.celebrate(award)
        XCTAssertEqual(screenRequests, 2)

        coach.stop()
        coach.celebrate(award)
        XCTAssertEqual(screenRequests, 2, "A stopped coach stays home")

        let demo = makeController(.demo)
        demo.start()
        demo.celebrate(award)
        XCTAssertEqual(screenRequests, 2, "Demo mode never shows the pet over the desktop")
    }
}
