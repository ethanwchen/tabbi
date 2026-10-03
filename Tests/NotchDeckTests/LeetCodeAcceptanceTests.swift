import Foundation
import XCTest
import NotchKitCore
@testable import NotchDeck

/// The platform's acceptance test: a new vertical plugs in with only its own
/// files (`LeetCodeFixture/`) plus one line in the module list. The app is
/// assembled exactly as at launch, from `ModuleList.all` with that line
/// added, and every shared surface must pick the module up.
@MainActor
final class LeetCodeAcceptanceTests: XCTestCase {
    /// `ModuleList.all` plus the one line a new module adds.
    private let moduleTypes = ModuleList.all + [LeetCodeModule.self]

    private var services: AppServices!
    private var leetCode: LeetCodeModule!

    override func setUp() async throws {
        // The modules get demo mode from their context (the environment
        // passed below), so none of them touches the user's data, the
        // calendar or the network. The variable is for the one singleton no
        // context reaches yet, `FocusController.shared`.
        setenv("NOTCHDECK_DEMO", "1", 1)
        let catalog = ModuleList.catalog(of: moduleTypes)
        let settings = SettingsStore.ephemeral(catalog: catalog)
        // Only LeetCode runs, so no real module starts background work.
        settings.settings.modules.setEnabled(LeetCodeModule.descriptor.id, true)
        for id in catalog.ids where id != LeetCodeModule.descriptor.id {
            settings.settings.modules.setEnabled(id, false)
        }
        services = AppServices(settings: settings, moduleTypes: moduleTypes,
                               environment: ["NOTCHDECK_DEMO": "1"], arguments: [])
        leetCode = try XCTUnwrap(services.modules.module(LeetCodeModule.self))
    }

    override func tearDown() async throws {
        services = nil
        leetCode = nil
        unsetenv("NOTCHDECK_DEMO")
    }

    func testTheModuleIsInTheCatalogTheTabBarAndSettingsRead() {
        let catalog = services.settings.catalog
        XCTAssertEqual(catalog.descriptor(for: "leetcode").title, "LeetCode")
        XCTAssertEqual(services.modules.catalog, catalog)
        XCTAssertEqual(services.settings.settings.modules.enabled, ["leetcode"])
        XCTAssertTrue(TickerKind.all(in: catalog).contains(.highlights(from: "leetcode")))
        XCTAssertEqual(TickerKind.highlights(from: "leetcode").title(in: catalog), "LeetCode daily")
    }

    func testTheRegistryStartsAndStopsItWithItsSwitch() {
        XCTAssertEqual(services.modules.running, ["leetcode"])
        XCTAssertTrue(leetCode.store.isRunning)
        services.settings.settings.modules.setEnabled(.planner, true)
        services.settings.settings.modules.setEnabled("leetcode", false)
        XCTAssertFalse(leetCode.store.isRunning)
    }

    func testTodayAndPlanMyDayListItsTaskAndGoal() {
        let snapshot = services.providers.snapshot
        let today = snapshot.sharedTodayItems(excluding: .planner)
        XCTAssertEqual(today.map(\.title), ["LeetCode daily", "LeetCode: Two Sum"])
        XCTAssertEqual(today.map(\.source), ["leetcode", "leetcode"])
        XCTAssertEqual(today.first?.detail, "1 problem left")
        XCTAssertEqual(snapshot.plannableWork(excluding: .planner),
                       ["LeetCode daily (1 problem left)", "LeetCode: Two Sum (about 20 min)"])
    }

    func testTheTickerShowsItsLineAndOpensTheModule() throws {
        let items = services.ticker.sources.items(at: Date(), enabled: services.settings.settings.showsPreview)
        let line = try XCTUnwrap(items.first { $0.kind == .highlights(from: "leetcode") })
        guard case .highlight(let highlight) = line else { return XCTFail("not a highlight: \(line)") }
        XCTAssertEqual(highlight.text, "1 problem left")
        XCTAssertEqual(line.module, "leetcode")
        XCTAssertTrue(items.contains { $0.kind == .progress }, "its goal also reaches the progress preview")
    }

    func testSolvingTheProblemUpdatesEverySurface() {
        leetCode.store.markSolved()
        let snapshot = services.providers.snapshot
        XCTAssertEqual(snapshot.sharedTodayItems(excluding: .planner).map(\.isDone), [true, true])
        XCTAssertEqual(snapshot.plannableWork(excluding: .planner), [])
        let items = services.ticker.sources.items(at: Date(), enabled: services.settings.settings.showsPreview)
        XCTAssertFalse(items.contains { $0.kind == .highlights(from: "leetcode") })
        let solved = leetCode.activityLog.records(on: PlannerDayKey(date: Date())).filter { $0.source == "leetcode" }
        XCTAssertEqual(solved.map(\.kind), ["problem.solved"])
    }

    func testAKitCanTurnItOnAndListItsTickerLine() throws {
        let json = """
        {
          "formatVersion": 1, "id": "tech", "name": "Tech interviews",
          "modules": ["leetcode", "planner", "focus"],
          "defaults": { "ticker": ["leetcode", "tasks", "focus"] }
        }
        """
        let kit = try KitManifest.decode(from: Data(json.utf8))
        let catalog = services.settings.catalog
        XCTAssertEqual(kit.issues(catalog: catalog), [])
        XCTAssertEqual(kit.layout(catalog: catalog).enabled, ["leetcode", .planner, .focus])
        XCTAssertEqual(kit.issues(catalog: ModuleList.catalog), [.unknownModule("leetcode"), .unknownTickerKind("leetcode")],
                       "without its list line the module is unknown")
    }

    func testAKitConfiguresItThroughItsOwnSettingsSection() throws {
        let json = """
        {
          "formatVersion": 1, "id": "tech", "name": "Tech interviews", "modules": ["leetcode"],
          "defaults": { "moduleSettings": { "leetcode": { "minutesPerProblem": 45 } } }
        }
        """
        let kit = try KitManifest.decode(from: Data(json.utf8))
        let catalog = services.settings.catalog
        XCTAssertEqual(kit.issues(catalog: catalog), [])
        services.settings.kitApplied.send(.init(kit: kit, answers: [:], addsStarterTasks: false))
        XCTAssertEqual(services.providers.snapshot.plannableWork(excluding: .planner).last,
                       "LeetCode: Two Sum (about 45 min)")

        var sloppy = kit
        sloppy.defaults.moduleSettings["leetcode"] = .object(["minutesPerProblem": .number(900), "minutes": .number(30)])
        XCTAssertEqual(sloppy.issues(catalog: catalog), [
            .unknownField("moduleSettings.leetcode.minutes"),
            .invalidModuleSetting(path: "moduleSettings.leetcode.minutesPerProblem", expected: "a number from 5 to 180"),
        ])
        XCTAssertEqual(sloppy.issues(catalog: ModuleList.catalog).last, .unknownModuleSettings("leetcode"),
                       "without its list line the section is unknown")
    }
}
