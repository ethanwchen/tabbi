import Combine
import XCTest
import TabbiKit
import TabbiKitCore
@testable import Tabbi

/// The recap's moment in the real app wiring: opening the notch shows the
/// newest unseen recap once, after onboarding, until Done.
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

        inputs.previewVisible(true) // closed without Done
        inputs.previewVisible(false)
        XCTAssertEqual(services.recaps.shown, shown, "Still waiting for Done")

        services.recaps.dismiss()
        XCTAssertEqual(states(), [false, true, false])
        inputs.previewVisible(true)
        inputs.previewVisible(false)
        XCTAssertNil(services.recaps.shown, "Shown only once")
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
