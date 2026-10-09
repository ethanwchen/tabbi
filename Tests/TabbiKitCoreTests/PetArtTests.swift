import Foundation
@testable import TabbiKitCore
import XCTest

/// The `pets.v1` art files: they load, they are checked on the way in, and
/// the JSON Schema other clients validate them with agrees with the Swift
/// legend. That every pixel matches the old Swift art is
/// `PetGoldenFrameTests`.
final class PetArtTests: XCTestCase {
    private static let families = ["cat", "costume", "dog", "effect", "paw", "prop", "tail", "walk"]

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testEveryBundledArtFileLoads() throws {
        let urls = try XCTUnwrap(KitResources.bundle?.urls(forResourcesWithExtension: "json", subdirectory: PetArt.subdirectory))
        XCTAssertEqual(urls.map { $0.deletingPathExtension().lastPathComponent }.sorted(), Self.families)
        for url in urls {
            XCTAssertNoThrow(try PetArtFile.decode(Data(contentsOf: url)), url.lastPathComponent)
        }
    }

    func testFilesHoldTheirArt() {
        XCTAssertEqual(PetArt.cat.grid("head").width, 20)
        XCTAssertEqual(PetArt.walk.sequence("catTail").count, 2)
        XCTAssertEqual(PetArt.costume.bodyItem("superheroCape").rise, 5)
        XCTAssertEqual(PetArt.costume.bodyItem("scrubs").rise, 0, "rise defaults to 0")
        XCTAssertEqual(PetArt.costume.faceItem("eyepatch").eyeRow, 3)
        XCTAssertEqual(PetArt.costume.headItem("graduationCap").sitRow, 5)
    }

    func testGridRowsReadAsSpriteText() throws {
        let file = try PetArtFile.decode(Data("""
            {"schema": "pets.v1", "grids": {"ear": [".ee.", "ePPe", "eBBe"]}}
            """.utf8))
        XCTAssertEqual(file.grid("ear"), try SpriteGrid(".ee.\nePPe\neBBe"))
    }

    func testRejectsAnotherSchemaVersion() {
        XCTAssertThrowsError(try PetArtFile.decode(Data(#"{"schema": "pets.v2"}"#.utf8))) { error in
            XCTAssertEqual(error as? PetArtFile.LoadError, .unsupportedSchema("pets.v2"))
        }
    }

    func testNamesTheBrokenGrid() {
        let json = #"{"schema": "pets.v1", "sequences": {"tail": [["BB"], ["BB", "B"]]}}"#
        XCTAssertThrowsError(try PetArtFile.decode(Data(json.utf8))) { error in
            XCTAssertEqual(
                error as? PetArtFile.LoadError,
                .invalidGrid(name: "tail[1]", reason: SpriteGrid.ParseError.raggedRow(row: 2, expected: 2, found: 1).description)
            )
        }
    }

    /// The schema's row pattern must allow exactly the symbols `SpriteCell`
    /// reads, so a TypeScript client accepts the same art the Mac app does.
    func testSchemaRowPatternMatchesTheSpriteLegend() throws {
        let url = repoRoot.appendingPathComponent("shared/schemas/pets.v1.schema.json")
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let grid = try XCTUnwrap(defs["grid"] as? [String: Any])
        let items = try XCTUnwrap(grid["items"] as? [String: Any])
        let pattern = try XCTUnwrap(items["pattern"] as? String)
        XCTAssertTrue(pattern.hasPrefix("^[") && pattern.hasSuffix("]+$"), pattern)
        let allowed = Set(pattern.dropFirst(2).dropLast(3))

        var legend: Set<Character> = [".", " ", "x"]
        legend.formUnion(PetPaletteRole.allCases.map(\.symbol))
        legend.formUnion(PetPatternZone.allCases.map(\.symbol))
        XCTAssertEqual(allowed, legend)
        XCTAssertEqual(allowed.count, pattern.count - 5, "no symbol is listed twice")
    }
}
