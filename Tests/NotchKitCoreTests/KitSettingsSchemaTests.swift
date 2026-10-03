import Foundation
import XCTest
@testable import NotchKitCore

final class KitSettingsSchemaTests: XCTestCase {
    private let schema = KitSettingsSchema([
        "enabled": .bool,
        "goal": .number(1...10),
        "title": .text(maxLength: 5),
        "mode": .choice(["fast", "slow"]),
        "lines": .lines(maxLength: 4, maxCount: 2),
        "nested": .object(["level": .number(0...1)]),
    ])

    private func issues(_ json: String) throws -> [KitIssue] {
        schema.issues(in: try JSONDecoder().decode(KitValue.self, from: Data(json.utf8)), at: "moduleSettings.drill")
    }

    func testValuesThatFitHaveNoIssues() throws {
        XCTAssertEqual(try issues(#"""
        {"enabled": true, "goal": 10, "title": "Hello", "mode": "slow", "lines": ["a", "b"],
         "nested": {"level": 0.5}}
        """#), [])
        XCTAssertEqual(try issues(#"{"lines": "one"}"#), [], "a single line counts as a list of one")
        XCTAssertEqual(try issues("{}"), [], "every key is optional")
    }

    func testWrongValuesAreNamedByPathInKeyOrder() throws {
        XCTAssertEqual(try issues(#"""
        {"title": "Too long", "mode": "medium", "goal": "7", "enabled": 1, "nested": {"level": 2}}
        """#), [
            .invalidModuleSetting(path: "moduleSettings.drill.enabled", expected: "true or false"),
            .invalidModuleSetting(path: "moduleSettings.drill.goal", expected: "a number from 1 to 10"),
            .invalidModuleSetting(path: "moduleSettings.drill.mode", expected: #"one of "fast", "slow""#),
            .invalidModuleSetting(path: "moduleSettings.drill.nested.level", expected: "a number from 0 to 1"),
            .invalidModuleSetting(path: "moduleSettings.drill.title", expected: "text of at most 5 characters"),
        ])
    }

    func testLinesCheckCountLengthAndType() throws {
        let expected = "a line or a list of up to 2 lines, each at most 4 characters"
        for json in [#"{"lines": ["a", "b", "c"]}"#, #"{"lines": ["a", "longer"]}"#, #"{"lines": ["a", 2]}"#,
                     #"{"lines": "longer"}"#] {
            XCTAssertEqual(try issues(json), [.invalidModuleSetting(path: "moduleSettings.drill.lines", expected: expected)],
                           json)
        }
    }

    func testUnknownKeysAreReportedAtAnyDepth() throws {
        XCTAssertEqual(try issues(#"{"gaol": 3, "nested": {"levle": 1}}"#), [
            .unknownField("moduleSettings.drill.gaol"), .unknownField("moduleSettings.drill.nested.levle"),
        ])
        XCTAssertEqual(try issues(#"["not", "an", "object"]"#),
                       [.invalidModuleSetting(path: "moduleSettings.drill", expected: "an object")])
    }

    func testKitIssuesCheckEachModulesSectionAgainstItsDescriptor() throws {
        let kit = try KitManifest.decode(from: Data(#"""
        {"formatVersion": 1, "id": "k", "name": "K", "modules": ["planner"],
         "defaults": {"moduleSettings": {
            "planner": {"planMode": "clever", "dayEndHour": 21, "reviewsFrist": true},
            "study": {"dailyGoalMinutes": 2000},
            "closet": {"coachLines": {"distraction": "Back to it?", "cheer": ["Go!"]}},
            "anki": {"anything": "goes"},
            "chess": {"elo": 1500}
         }}}
        """#.utf8))
        XCTAssertEqual(kit.issues(), [
            .unknownModuleSettings("chess"),
            .unknownField("moduleSettings.closet.coachLines.cheer"),
            .invalidModuleSetting(path: "moduleSettings.planner.planMode", expected: #"one of "claude", "study""#),
            .unknownField("moduleSettings.planner.reviewsFrist"),
            .invalidModuleSetting(path: "moduleSettings.study.dailyGoalMinutes", expected: "a number from 15 to 720"),
        ])
    }

    func testIssueDescriptionsSayWhatHappens() {
        XCTAssertEqual(KitIssue.unknownModuleSettings("chess").description,
                       #"Settings for unknown module "chess" will be ignored."#)
        XCTAssertEqual(KitIssue.invalidModuleSetting(path: "moduleSettings.study.dailyGoalMinutes",
                                                     expected: "a number from 15 to 720").description,
                       #""moduleSettings.study.dailyGoalMinutes" should be a number from 15 to 720; "#
                           + "other values are skipped or kept in range.")
    }
}
