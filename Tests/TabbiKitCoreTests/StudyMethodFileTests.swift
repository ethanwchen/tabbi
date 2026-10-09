import Foundation
import XCTest
@testable import TabbiKitCore

/// `study-methods.json` loading: the format, the checks that stop a broken
/// file, and that the JSON Schema a TypeScript client validates with agrees
/// with the Swift types.
final class StudyMethodFileTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private var bundled: [String: Any] {
        get throws {
            let url = repoRoot.appendingPathComponent("Sources/TabbiKitCore/StudyMethods/study-methods.json")
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }
    }

    /// The bundled file with `change` applied to its JSON object.
    private func file(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var object = try bundled
        change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// The bundled file with `change` applied to the method at `index`.
    private func file(method index: Int, _ change: @escaping (inout [String: Any]) -> Void) throws -> Data {
        try file { object in
            var methods = object["methods"] as! [[String: Any]]
            change(&methods[index])
            object["methods"] = methods
        }
    }

    private func error(_ data: Data) -> StudyMethodFile.LoadError? {
        do {
            _ = try StudyMethodFile.decode(data)
            return nil
        } catch {
            return error as? StudyMethodFile.LoadError
        }
    }

    func testDecodesEveryFocusAndBreakForm() throws {
        let file = try StudyMethodFile.decode(file())
        let methods = Dictionary(uniqueKeysWithValues: file.methods.map { ($0.kind, $0.method) })
        XCTAssertEqual(methods[.pomodoro]?.focus, .duration(25 * 60))
        XCTAssertEqual(methods[.pomodoro]?.longBreak, StudyLongBreak(duration: 15 * 60, every: 4))
        XCTAssertEqual(methods[.flowtime]?.focus, .openEnded)
        XCTAssertEqual(methods[.flowtime]?.breakRule, .proportional(.tiered))
        XCTAssertEqual(methods[.ankiSprint]?.focus, .cards(100))
        XCTAssertEqual(methods[.questionBlock]?.review, 60 * 60)
        XCTAssertEqual(methods[.questionBlock]?.questionCount, 40)
        XCTAssertEqual(methods[.timer]?.breakRule, StudyBreakRule.none)
        XCTAssertNil(file.methods.first { $0.kind == .timer }?.info.evidenceLevel)
        XCTAssertEqual(file.evidenceLevels[.strong], "Well supported")

        let fifth = try StudyMethodFile.decode(self.file(method: 3) { $0["break"] = ["flowtime": "fifth"] })
        XCTAssertEqual(fifth.methods[3].method.breakRule, .proportional(.fifth))
    }

    func testRejectsBrokenFiles() throws {
        XCTAssertEqual(error(try file { $0["schema"] = "study-methods.v2" }), .unsupportedSchema("study-methods.v2"))
        XCTAssertEqual(error(try file { $0["methods"] = ($0["methods"] as! [Any]).dropLast().map { $0 } }),
                       .missingMethod(.timer))
        XCTAssertEqual(error(try file(method: 1) { $0["kind"] = "pomodoro" }), .duplicateMethod(.pomodoro))
        XCTAssertEqual(error(try file(method: 0) { $0["focus"] = ["minutes": 0.5] }),
                       .invalidValue(path: "methods[0].focus.minutes", reason: "outside phaseMinutes"))
        XCTAssertEqual(error(try file(method: 0) { $0["longBreak"] = ["minutes": 15, "every": 1] }),
                       .invalidValue(path: "methods[0].longBreak.every", reason: "must be 2 or more"))
        XCTAssertEqual(error(try file(method: 4) { $0["focus"] = ["cards": 0] }),
                       .invalidValue(path: "methods[4].focus.cards", reason: "must be above 0"))
        XCTAssertEqual(error(try file { $0["evidenceLevels"] = ["strong": "A", "mixed": "B"] }),
                       .invalidValue(path: "evidenceLevels", reason: "no label for \"weak\""))
        XCTAssertEqual(error(try file { $0["timer"] = ["minMinutes": 1, "maxMinutes": 20, "presetMinutes": [5, 25]] }),
                       .invalidValue(path: "timer.presetMinutes[1]", reason: "outside the timer range"))
        // The Timer and Custom defaults must be values their steppers can show.
        XCTAssertEqual(error(try file(method: 7) { $0["focus"] = ["minutes": 200] }),
                       .invalidValue(path: "methods.timer", reason: "needs whole focus minutes in the timer range and break \"none\""))
        XCTAssertEqual(error(try file(method: 6) { $0["focus"] = ["minutes": 3] })?.description.hasPrefix("methods.custom:"), true)
        // Unknown names and missing fields are decoding errors.
        XCTAssertThrowsError(try StudyMethodFile.decode(file(method: 0) { $0["kind"] = "tomato" }))
        XCTAssertThrowsError(try StudyMethodFile.decode(file(method: 0) { $0["focus"] = "forever" }))
        XCTAssertThrowsError(try StudyMethodFile.decode(file(method: 3) { $0["break"] = ["flowtime": "half"] }))
        XCTAssertThrowsError(try StudyMethodFile.decode(Data(#"{"schema": "study-methods.v1"}"#.utf8)))
    }

    func testBundledFileDefinesThePresets() {
        XCTAssertEqual(StudyMethod.presets.map(\.kind), StudyMethodKind.allCases)
        XCTAssertEqual(StudyMethodInfo.all.map(\.kind), StudyMethodKind.allCases)
        XCTAssertEqual(StudyMethod.preset(.ankiSprint), .ankiSprint())
        XCTAssertEqual(StudyMethod.preset(.custom), StudyCustomRhythm.standard.method)
        XCTAssertEqual(StudyMethod.preset(.timer), StudyTimerLength.standard.method)
    }

    /// The schema lists the same values as the Swift enums and custom
    /// fields, so a TypeScript client accepts exactly the files the Mac app does.
    func testSchemaMatchesSwift() throws {
        let url = repoRoot.appendingPathComponent("shared/schemas/study-methods.v1.schema.json")
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        func values(_ key: String) -> [String]? { (defs[key] as? [String: Any])?["enum"] as? [String] }
        XCTAssertEqual(values("kind"), StudyMethodKind.allCases.map(\.rawValue))
        XCTAssertEqual(values("flowtimeScheme"), FlowtimeBreakScheme.allCases.map(\.rawValue))
        XCTAssertEqual(values("evidenceLevel"), StudyEvidenceLevel.allCases.map(\.rawValue))
        let methods = try XCTUnwrap((schema["properties"] as? [String: Any])?["methods"] as? [String: Any])
        XCTAssertEqual(methods["minItems"] as? Int, StudyMethodKind.allCases.count)
        XCTAssertEqual(methods["maxItems"] as? Int, StudyMethodKind.allCases.count)
        let custom = try XCTUnwrap((schema["properties"] as? [String: Any])?["custom"] as? [String: Any])
        let fields = try XCTUnwrap(((custom["properties"] as? [String: Any])?["fields"] as? [String: Any])?["required"] as? [String])
        XCTAssertEqual(fields, StudyCustomRhythm.Field.allCases.map(\.rawValue))
    }
}
