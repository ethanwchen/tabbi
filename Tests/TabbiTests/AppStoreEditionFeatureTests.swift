import XCTest
import TabbiKitCore
@testable import Tabbi

/// A sandboxed App Store build can't run command line tools or Shortcuts,
/// so focus mode hides what needs them instead of offering buttons that
/// can't work. Today's and the Schedule's AI features stay, since they
/// reach the AI through the provider the user picks (an API or Ollama there).
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

    func testBothEditionsOfferToRefineAPlanWithTheirAI() throws {
        XCTAssertTrue(ScheduleModule(context: context(.schedule, edition: try appStore)).store.aiReady)
        XCTAssertTrue(ScheduleModule(context: context(.schedule, edition: .tabbi)).store.aiReady)
        XCTAssertTrue(TodayModule(context: context(.planner, edition: try appStore)).store.plan.canRefine)
    }

    func testWrapUpShowsTheLocalSummaryAtOnceWithoutAnAI() {
        let review = DayReviewStore(storage: EditionStorage(root: FileManager.default.temporaryDirectory),
                                    ai: nil, runMode: .demo)
        review.wrapUp(day: .sample(on: PlannerDayKey(date: Date()), kind: .work), activity: [])
        XCTAssertTrue(review.isActive)
        XCTAssertFalse(review.isSummarizing, "no shimmer waiting for an AI")
    }
}
