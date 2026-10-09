import XCTest
@testable import TabbiKitCore

final class PartyNameFilterTests: XCTestCase {
    private struct RulesFile: Decodable {
        var substitutions: [String: String]
        var ambiguous: [String: String]
        var anywhere: [String]
        var allow: [String]
        var words: [String]
    }

    private struct Cases: Decodable {
        var allowed: [String]
        var blocked: [String]
    }

    private func shared<T: Decodable>(_ file: String, as type: T.Type) throws -> T {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("backend/shared/\(file)")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    /// The app must refuse exactly what the server refuses, or a name would pass here and fail on save.
    func testRulesMatchTheServer() throws {
        let file = try shared("name-filter.json", as: RulesFile.self)
        let server = PartyNameFilter.Rules(
            substitutions: file.substitutions, ambiguous: file.ambiguous,
            anywhere: file.anywhere, allow: file.allow, words: file.words
        )
        XCTAssertEqual(PartyNameFilter.rules, server)
    }

    func testAllowsOrdinaryNames() throws {
        for name in try shared("name-filter-cases.json", as: Cases.self).allowed {
            XCTAssertTrue(PartyNameFilter.isAllowed(name), name)
        }
    }

    func testBlocksSlursAndExplicitTerms() throws {
        for name in try shared("name-filter-cases.json", as: Cases.self).blocked {
            XCTAssertFalse(PartyNameFilter.isAllowed(name), name)
        }
    }

    func testEmptyAndPunctuationOnlyNamesPass() {
        XCTAssertTrue(PartyNameFilter.isAllowed(""))
        XCTAssertTrue(PartyNameFilter.isAllowed("... !!"))
    }
}

final class PartyNameErrorTests: XCTestCase {
    func testServerNameRejectionsMapToTypedErrors() {
        XCTAssertEqual(PartyError.fromServer(code: "name_not_allowed", status: 400, retryAfter: nil), .nameNotAllowed)
        XCTAssertEqual(PartyError.fromServer(code: "pet_name_not_allowed", status: 400, retryAfter: nil), .petNameNotAllowed)
        XCTAssertFalse(PartyError.nameNotAllowed.isTransient)
        XCTAssertEqual(PartyError.petNameNotAllowed.message, "That pet name isn't allowed. Please pick another.")
    }
}
