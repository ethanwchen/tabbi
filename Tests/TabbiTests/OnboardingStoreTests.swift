import Combine
import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// First-run setup in the notch records the picked kit, its answers and the
/// tabs once the flow passes the tab step, so the setup steps after it build
/// on the kit, and re-running it from Settings switches kits only when the
/// pick changed.
@MainActor
final class OnboardingStoreTests: XCTestCase {
    private func makeSettings(kitID: String = "essentials") -> SettingsStore {
        let suite = "OnboardingStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return SettingsStore(catalog: ModuleList.catalog, defaults: defaults, defaultKitID: kitID, kitStore: nil,
                             integratesWithSystem: false)
    }

    func testStartsOnTheNameStepThenTheKitWithTheCurrentTabs() {
        let settings = makeSettings()
        let store = OnboardingStore(settings: settings)
        XCTAssertFalse(store.isActive)
        store.start()
        XCTAssertEqual(store.flow?.stage, .name)
        store.update { $0.next() }
        XCTAssertEqual(store.flow?.stage, .kit)
        XCTAssertEqual(store.flow?.layout, settings.settings.modules)
        XCTAssertEqual(store.flow?.kit?.id, "essentials")
    }

    func testPickingAKitAppliesNothingUntilTheTabStepIsDone() throws {
        let settings = makeSettings()
        let store = OnboardingStore(settings: settings)
        store.start()
        let medicine = try XCTUnwrap(settings.kits["medicine"])
        store.update { $0.choose(medicine) }
        store.update { $0.answer("preclinical") }
        XCTAssertFalse(settings.settings.hasChosenKit)
        XCTAssertEqual(settings.settings.kitID, "essentials")

        while store.flow?.stage != .modules { store.update { $0.next() } }
        store.update { _ = $0.setEnabled(.claudeAsk, false) }
        store.update { $0.next() }

        XCTAssertTrue(settings.settings.hasChosenKit)
        XCTAssertEqual(settings.settings.kitID, "medicine")
        XCTAssertEqual(settings.settings.kitAnswers["stage"], ["preclinical"])
        XCTAssertFalse(settings.settings.modules.isEnabled(.claudeAsk))
        XCTAssertEqual(settings.settings.modules, store.flow?.layout)
        // Med School's tabs need setup steps, so the flow is still running.
        XCTAssertEqual(store.flow?.stage, .setup(OnboardingSetupStep.pet.id))
    }

    func testSkipSetupKeepsTheSuggestedKitAndEnds() {
        let settings = makeSettings()
        let store = OnboardingStore(settings: settings)
        store.start()
        store.finish()
        XCTAssertFalse(store.isActive)
        XCTAssertTrue(settings.settings.hasChosenKit)
        XCTAssertEqual(settings.settings.kitID, "essentials")
    }

    func testStartFromScratchRecordsTheSuggestedKitWithTheChosenTabs() {
        let settings = makeSettings()
        let store = OnboardingStore(settings: settings)
        store.start()
        store.update { $0.startFromScratch() }
        store.update { _ = $0.setEnabled(.focus, true) }
        store.finish()
        XCTAssertTrue(settings.settings.hasChosenKit)
        XCTAssertEqual(settings.settings.kitID, "essentials")
        XCTAssertEqual(settings.settings.modules.enabled, [ModuleList.catalog.ids[0], .focus])
    }

    func testRerunWithTheSameKitOnlyChangesTheTabs() {
        let settings = makeSettings()
        let store = OnboardingStore(settings: settings)
        store.start()
        store.finish()
        var applications: [SettingsStore.KitApplication] = []
        let sink = settings.kitApplied.sink { applications.append($0) }
        defer { sink.cancel() }

        store.start()
        store.update { _ = $0.setEnabled(.spotify, false) }
        store.finish()
        XCTAssertTrue(applications.isEmpty, "starter tasks would be added again")
        XCTAssertFalse(settings.settings.modules.isEnabled(.spotify))
        XCTAssertNil(settings.lastKitSwitch)
    }

    func testTheNameTypedDuringSetupIsTheAppWideName() {
        let settings = makeSettings()
        let store = OnboardingStore(settings: settings)
        store.start()
        // The name step's field writes the app-wide name as it is typed.
        settings.settings.displayName = "Ana"
        store.update { $0.next() }
        store.finish()
        XCTAssertEqual(settings.settings.cleanedDisplayName, "Ana")
    }

    func testRerunAsksTheNameOnlyWhileNoneIsSet() {
        let settings = makeSettings()
        let store = OnboardingStore(settings: settings)
        store.start()
        store.finish()

        store.start()
        XCTAssertEqual(store.flow?.stage, .name, "skipped the first time, so asked again")
        store.finish()

        settings.settings.displayName = "Ana"
        store.start()
        XCTAssertEqual(store.flow?.stage, .kit)
        XCTAssertFalse(store.flow?.stages.contains(.name) ?? true)
    }

    func testRerunWithAnotherKitSwitchesKitsUndoably() throws {
        let settings = makeSettings()
        let store = OnboardingStore(settings: settings)
        store.start()
        store.finish()

        store.start()
        let medicine = try XCTUnwrap(settings.kits["medicine"])
        store.update { $0.choose(medicine) }
        store.finish()
        XCTAssertEqual(settings.settings.kitID, "medicine")
        XCTAssertEqual(settings.lastKitSwitch?.kitName, "Med School")
    }
}
