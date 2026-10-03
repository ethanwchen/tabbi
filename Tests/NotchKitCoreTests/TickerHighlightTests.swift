import XCTest
@testable import NotchKitCore

final class TickerHighlightTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func highlight(_ id: String, from source: ModuleID, priority: Int = 0, pinned: Bool = false,
                           expiresIn: TimeInterval? = nil) -> TickerHighlight {
        TickerHighlight(id: id, source: source, text: id, priority: priority, isPinned: pinned,
                        expiresAt: expiresIn.map(now.addingTimeInterval))
    }

    func testEachModuleShowsItsHighestPriorityHighlight() {
        let sources = TickerSources(highlights: [
            highlight("easy", from: "leetcode", priority: 1),
            highlight("daily", from: "leetcode", priority: 5),
            highlight("streak", from: "leetcode", priority: 5),
        ])
        XCTAssertEqual(sources.items(at: now), [.highlight(highlight("daily", from: "leetcode", priority: 5))])
    }

    func testModulesRotateByPriorityThenTabOrderBetweenProgressAndTheParty() {
        let party = ProvidedParty(pets: [
            ProvidedPartyPet(id: "me", name: "Me", pet: .starter(.cat)),
            ProvidedPartyPet(id: "sam", name: "Sam", pet: .starter(.cat)),
        ])
        let sources = TickerSources(
            tasksRemaining: 1,
            highlights: [highlight("a", from: "first"), highlight("b", from: "second", priority: 3),
                         highlight("c", from: "third")],
            party: party
        )
        XCTAssertEqual(sources.items(at: now).map(\.kind.rawValue), ["tasks", "second", "first", "third", "party"])
    }

    func testAnExpiredHighlightGivesWayAndWakesTheTicker() {
        let sources = TickerSources(highlights: [
            highlight("urgent", from: "leetcode", priority: 9, expiresIn: 600),
            highlight("calm", from: "leetcode"),
        ])
        XCTAssertEqual(sources.items(at: now).first, .highlight(highlight("urgent", from: "leetcode", priority: 9,
                                                                           expiresIn: 600)))
        XCTAssertEqual(sources.nextChange(after: now), now.addingTimeInterval(600))
        XCTAssertEqual(sources.items(at: now.addingTimeInterval(600)), [.highlight(highlight("calm", from: "leetcode"))])
    }

    func testHighlightsAreToggledPerModule() {
        let sources = TickerSources(highlights: [highlight("a", from: "leetcode", expiresIn: 60),
                                                 highlight("b", from: "chess")])
        let kinds: Set<TickerKind> = [.highlights(from: "chess")]
        XCTAssertEqual(sources.items(at: now, enabled: kinds), [.highlight(highlight("b", from: "chess"))])
        XCTAssertNil(sources.nextChange(after: now, enabled: kinds), "A hidden highlight's expiry doesn't wake")
    }

    func testAPinnedHighlightHoldsTheNotchAndOpensItsModule() {
        let item = TickerItem.highlight(highlight("contest", from: "leetcode", pinned: true))
        XCTAssertTrue(item.isPinned)
        XCTAssertEqual(item.module, "leetcode")
        XCTAssertEqual(item.kind, .highlights(from: "leetcode"))

        var rotation = TickerRotation(interval: 8)
        let music = TickerItem.nowPlaying
        _ = rotation.update(items: [music], at: now)
        XCTAssertEqual(rotation.update(items: [music, item], at: now.addingTimeInterval(30)), item)
    }

    func testSnapshotMergesHighlightsAndMusicFromEveryModule() {
        let snapshot = ProviderSnapshot([
            (module: "leetcode", provision: ModuleProvision(highlights: [highlight("daily", from: "unset"),
                                                                         highlight("daily", from: "unset")])),
            (module: .spotify, provision: ModuleProvision(isPlaying: true)),
            (module: "chess", provision: ModuleProvision(highlights: [highlight("daily", from: "unset")])),
        ])
        XCTAssertEqual(snapshot.highlights.map(\.source), ["leetcode", "chess"])
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertEqual(TickerSources(snapshot).items(at: now).map(\.kind),
                       [.nowPlaying, .highlights(from: "leetcode"), .highlights(from: "chess")])
    }

    func testEveryKindListsModulesThatDeclareHighlightsInCatalogOrder() {
        let catalog = ModuleCatalog([
            ModuleDescriptor(id: "quiet", title: "Quiet", symbol: "circle", category: .productivity,
                             accent: ModuleAccent(red: 0, green: 0, blue: 0)),
            ModuleDescriptor(id: "leetcode", title: "LeetCode", symbol: "chevron.left.forwardslash.chevron.right",
                             category: .productivity, accent: ModuleAccent(red: 1, green: 0.6, blue: 0),
                             highlightTitle: "LeetCode daily problem"),
        ])
        XCTAssertEqual(TickerKind.all(in: catalog).map(\.rawValue),
                       ["meeting", "nowPlaying", "focus", "tasks", "progress", "leetcode", "party", "pet"])
        XCTAssertEqual(TickerKind.highlights(from: "leetcode").title(in: catalog), "LeetCode daily problem")
        XCTAssertEqual(TickerKind.meeting.title(in: catalog), "Next meeting")
    }

    func testKitTickerNamesModulesByID() throws {
        let kit = try KitManifest.decode(from: Data("""
        {"formatVersion": 1, "id": "tech", "name": "Tech", "modules": [{"id": "claudeUsage"}],
         "defaults": {"ticker": ["focus", "claudeUsage", "weather"]}}
        """.utf8))
        XCTAssertEqual(kit.defaults.resolvedTicker(catalog: .builtIn), [.focus, .highlights(from: .claudeUsage)])
        XCTAssertEqual(kit.issues(), [.unknownTickerKind("weather")])
    }

    func testClaudeUsagePublishesOneHighlightPerFullWindow() {
        let reset = now.addingTimeInterval(3600)
        let highlights = ClaudeUsageHighlights.highlights(for: ClaudeRateLimitSnapshot(
            status: nil,
            fiveHour: ClaudeUsageWindow(utilization: 1.02, resetsAt: reset),
            sevenDay: ClaudeUsageWindow(utilization: 0.5, resetsAt: nil)
        ), at: now)
        XCTAssertEqual(highlights.map(\.text), ["5h 102%"])
        XCTAssertEqual(highlights.first?.tone, .danger)
        XCTAssertEqual(highlights.first?.summary, "Claude usage 5h 102%")
        XCTAssertEqual(highlights.first?.expiresAt, reset)
        XCTAssertNil(highlights.first?.symbol, "Uses the module's own symbol")
    }
}
