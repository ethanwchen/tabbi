import XCTest
import TabbiKitCore
@testable import Tabbi

/// A sandboxed App Store build can't run the `claude` CLI or Shortcuts, so
/// Today, Schedule and focus mode hide what needs them instead of offering
/// buttons that can't work. The direct download keeps all of it.
@MainActor
final class AppStoreEditionFeatureTests: XCTestCase {
    private func context(_ id: ModuleID, edition: Edition) -> ModuleContext {
        ModuleContext(id: id, edition: edition, settings: SettingsStore.ephemeral(catalog: ModuleList.catalog),
                      providers: ProviderHub(), shared: SharedServices(), runMode: .demo)
    }

    private var appStore: Edition {
        get throws { try XCTUnwrap(Edition.named("appstore")) }
    }

    func testTheAppStoreEditionHidesDoNotDisturb() throws {
        let focusMode = context(.focus, edition: try appStore).focusMode
        XCTAssertFalse(focusMode.offersDoNotDisturb)
        XCTAssertTrue(focusMode.settings.doNotDisturb, "the demo settings have it on")
        XCTAssertFalse(focusMode.doNotDisturb, "but focus phases never turn it on")

        let direct = context(.focus, edition: .tabbi).focusMode
        XCTAssertTrue(direct.offersDoNotDisturb)
        XCTAssertTrue(direct.doNotDisturb)
    }

    func testTheAppStoreEditionNeverOffersToRefineAPlanWithClaude() throws {
        XCTAssertFalse(ScheduleModule(context: context(.schedule, edition: try appStore)).store.claudeFound)
        XCTAssertTrue(ScheduleModule(context: context(.schedule, edition: .tabbi)).store.claudeFound)
    }

    func testTodayPlansOnDeviceWhenAKitAsksForClaude() throws {
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog)
        let context = ModuleContext(id: .planner, edition: try appStore, settings: settings, providers: ProviderHub(),
                                    shared: SharedServices(), runMode: .demo)
        let today = TodayModule(context: context)
        let claudeKit = KitDefaults(moduleSettings: ["planner": ["planMode": .string("claude")]])
        let planSettings = TodayPlanSettings(kit: claudeKit).usable(withClaude: context.edition.runsLocalTools)
        XCTAssertEqual(planSettings.planMode, .local)
        XCTAssertFalse(today.store.plan.canRefine)
    }

    func testWrapUpShowsTheLocalSummaryAtOnceWithoutClaude() {
        let review = DayReviewStore(storage: EditionStorage(root: FileManager.default.temporaryDirectory),
                                    usesClaude: false, runMode: .demo)
        review.wrapUp(day: .sample(on: PlannerDayKey(date: Date()), kind: .work), activity: [])
        XCTAssertTrue(review.isActive)
        XCTAssertFalse(review.isSummarizing, "no shimmer waiting for Claude")
    }
}
