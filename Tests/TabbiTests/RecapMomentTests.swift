import Combine
import XCTest
import TabbiKit
import TabbiKitCore
@testable import Tabbi

/// The recap's moment in the real app wiring: opening the notch shows the
/// newest unseen recap once, after onboarding, until Done or a close.
@MainActor
final class RecapMomentTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() async throws {
        cancellables = []
    }

    private func demoServices() -> AppServices {
        let types: [any NotchModule.Type] = [ClosetModule.self]
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types))
        return AppServices(settings: settings, moduleTypes: types, environment: ["TABBI_DEMO": "1"], arguments: [])
    }

    /// Follows the notch's takeover switch, as `NotchController` does.
    private func takeoverStates(_ inputs: NotchInputs) -> () -> [Bool] {
        var states: [Bool] = []
        inputs.takeover.removeDuplicates().sink { states.append($0) }.store(in: &cancellables)
        return { states }
    }

    func testOpeningTheNotchShowsTheRecapOnceUntilDone() throws {
        let services = demoServices()
        let inputs = ModuleViews.notchInputs(services: services)
        let states = takeoverStates(inputs)
        XCTAssertNil(services.recaps.shown, "Nothing shows before the notch opens")

        inputs.previewVisible(false) // the notch opened
        let shown = try XCTUnwrap(services.recaps.shown)
        XCTAssertEqual(shown.recap, RecapArchive.demo(now: Date()).recaps.first, "The newest recap")
        XCTAssertEqual(shown.cheer, .bestYet)
        XCTAssertNil(services.recaps.store.unseen, "Seen once shown")
        XCTAssertEqual(states(), [false, true])

        services.recaps.dismiss()
        XCTAssertEqual(states(), [false, true, false])
        inputs.previewVisible(true)
        inputs.previewVisible(false)
        XCTAssertNil(services.recaps.shown, "Shown only once")
    }

    func testClosingTheNotchCountsAsDoneWithTheCard() {
        let services = demoServices()
        let inputs = ModuleViews.notchInputs(services: services)
        let states = takeoverStates(inputs)

        inputs.previewVisible(false) // opened: the card shows
        XCTAssertNotNil(services.recaps.shown)
        inputs.previewVisible(true) // closed without Done
        XCTAssertNil(services.recaps.shown, "Closing ends the card")
        inputs.previewVisible(false)
        XCTAssertNil(services.recaps.shown, "The next open shows the tabs")
        XCTAssertEqual(states(), [false, true, false])
    }

    func testOnboardingComesFirstAndTheRecapWaitsForTheNextOpen() {
        let services = demoServices()
        let inputs = ModuleViews.notchInputs(services: services)
        let states = takeoverStates(inputs)
        services.onboarding.start()

        inputs.previewVisible(false)
        XCTAssertNil(services.recaps.shown, "Never interrupts setup")
        XCTAssertNotNil(services.recaps.store.unseen, "Still unseen for later")

        services.onboarding.show(nil)
        inputs.previewVisible(true)
        inputs.previewVisible(false)
        XCTAssertNotNil(services.recaps.shown)
        XCTAssertEqual(states(), [false, true, false, true], "Onboarding, then the recap")
    }

    func testTheSettingsSwitchTurnsTheRecapOff() throws {
        let services = demoServices()
        let inputs = ModuleViews.notchInputs(services: services)
        let states = takeoverStates(inputs)
        services.settings.settings.weeklyRecapEnabled = false

        inputs.previewVisible(false)
        XCTAssertNil(services.recaps.shown, "Off shows no card")
        XCTAssertNotNil(services.recaps.store.unseen, "Nor marks it seen")

        services.settings.settings.weeklyRecapEnabled = true
        inputs.previewVisible(true)
        inputs.previewVisible(false)
        XCTAssertNotNil(services.recaps.shown, "Back on, the next open shows it")

        services.settings.settings.weeklyRecapEnabled = false
        XCTAssertNil(services.recaps.shown, "Turning it off hides the card on show")
        XCTAssertEqual(states(), [false, true, false])
    }

    func testThePastRecapsListInTheClosetReopensAWeek() throws {
        let services = demoServices()
        let inputs = ModuleViews.notchInputs(services: services)
        let states = takeoverStates(inputs)
        let closet = try XCTUnwrap(services.modules.module(ClosetModule.self))
        XCTAssertTrue(closet.recaps === services.recaps.store, "The Closet lists the one shared store")

        inputs.previewVisible(false)
        services.recaps.dismiss()
        let older = try XCTUnwrap(closet.recaps.archive.recaps.last)
        closet.recaps.reopen(older)
        let shown = try XCTUnwrap(services.recaps.shown, "A past week shows again from the list")
        XCTAssertEqual(shown.recap, older)
        XCTAssertEqual(shown.cheer, closet.recaps.archive.cheer(for: older), "With the line it had then")
        services.recaps.dismiss()
        XCTAssertEqual(states(), [false, true, false, true, false])

        services.settings.settings.weeklyRecapEnabled = false
        XCTAssertFalse(closet.recaps.isEnabled, "The list hides while recaps are off")
        closet.recaps.reopen(older)
        XCTAssertNil(services.recaps.shown, "Nor opens a week")
    }

    func testNoRecapLeavesTheTabsAlone() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecapMomentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RecapStore(storage: EditionStorage(root: folder), runMode: .live,
                               activity: ActivityLog(repository: nil))
        let moment = RecapMoment(store: store)
        moment.notchOpened()
        XCTAssertNil(moment.shown, "A fresh install has no recap to show")
    }
}
