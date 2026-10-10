import XCTest
import TabbiKitCore

final class ConnectionKindTests: XCTestCase {
    func testListsOnlyWhatTheEnabledTabsUse() {
        XCTAssertEqual(ConnectionKind.relevant(to: [.system]), [])
        XCTAssertEqual(ConnectionKind.relevant(to: [.anki]), [.anki])
        XCTAssertEqual(ConnectionKind.relevant(to: [.spotify]), [.spotify, .music])
        XCTAssertEqual(ConnectionKind.relevant(to: [.claudeAsk, .claudeUsage]), [.claude])
        XCTAssertEqual(ConnectionKind.relevant(to: [.claudeAsk]), [])
    }

    func testClaudeShowsForAskAndTodayOnlyWhenClaudeCodeAnswers() {
        XCTAssertEqual(ConnectionKind.relevant(to: [.claudeAsk], usesClaudeCode: true), [.claude])
        XCTAssertEqual(ConnectionKind.relevant(to: [.planner], usesClaudeCode: true),
                       [.calendar, .notifications, .doNotDisturb, .claude])
        XCTAssertEqual(ConnectionKind.relevant(to: [.claudeAsk], localTools: false, usesClaudeCode: true), [])
    }

    func testKeepsRowOrderWhateverTheTabOrder() {
        let medSchool: [ModuleID] = [.party, .study, .anki, .planner, .closet]
        XCTAssertEqual(ConnectionKind.relevant(to: medSchool),
                       [.calendar, .anki, .notifications, .doNotDisturb, .party])
        XCTAssertEqual(ConnectionKind.relevant(to: medSchool.reversed()), ConnectionKind.relevant(to: medSchool))
    }

    func testTodayUsesCalendarAlertsAndFocus() {
        XCTAssertEqual(ConnectionKind.relevant(to: [.planner]), [.calendar, .notifications, .doNotDisturb])
    }

    func testABuildWithoutLocalToolsHidesClaudeAndDoNotDisturb() {
        XCTAssertEqual(ConnectionKind.relevant(to: [.planner], localTools: false), [.calendar, .notifications])
        XCTAssertEqual(ConnectionKind.relevant(to: [.claudeAsk, .claudeUsage], localTools: false), [])
        XCTAssertEqual(ConnectionKind.allCases.filter(\.needsLocalTools), [.doNotDisturb, .claude])
    }

    func testEveryRowExplainsWhatItUnlocksInPlainWords() {
        let banned = ["CLI", "API", "localhost", "port", "error", "JSON", "Automation", "\u{2014}"]
        for kind in ConnectionKind.allCases {
            XCTAssertFalse(kind.title.isEmpty)
            XCTAssertFalse(kind.symbol.isEmpty)
            XCTAssertFalse(kind.modules.isEmpty, "\(kind) serves no tab")
            XCTAssertTrue(kind.unlocks.hasSuffix("."), "\(kind) should read as a sentence")
            XCTAssertLessThanOrEqual(kind.unlocks.count, 38, "\(kind) should fit on one line beside its button")
            for term in banned {
                XCTAssertNil(kind.unlocks.range(of: "\\b\(term)\\b", options: .regularExpression),
                             "\(kind) uses \(term)")
            }
        }
    }

    func testDemoShowsMostlyConnectedWithAStepLeft() {
        let lights = ConnectionKind.allCases.map(\.demoStatus.light)
        XCTAssertFalse(lights.contains(.checking), "demo rows never wait on a check")
        XCTAssertGreaterThan(lights.filter { $0 == .connected }.count, lights.count / 2)
        XCTAssertTrue(lights.contains { $0 != .connected }, "demo shows what a step left looks like")
    }
}
