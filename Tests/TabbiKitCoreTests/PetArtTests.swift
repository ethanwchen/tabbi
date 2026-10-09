import Foundation
@testable import TabbiKitCore
import XCTest

/// The `pets.v1` art and breed files: they load, they are checked on the way
/// in, and the JSON Schema other clients validate them with agrees with the
/// Swift legend, roles and zones. That every pixel and palette matches the
/// old Swift definitions is `PetGoldenFrameTests`.
final class PetArtTests: XCTestCase {
    private static let families = ["breeds", "cat", "costume", "dog", "effect", "paw", "prop", "tail", "walk"]

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

    /// The breed file defines exactly the Swift cases, in their order (the
    /// picker order), and a color for every role in the base palette.
    func testBreedFileCoversEveryCase() {
        XCTAssertEqual(PetArt.breeds.breedOrder, PetBreed.allCases)
        XCTAssertEqual(Set(PetArt.breeds.bodyShapes.keys), Set(PetBodyShape.allCases))
        XCTAssertEqual(Set(PetArt.breeds.basePalette.keys), Set(PetPaletteRole.allCases))
    }

    func testBreedsReadTheirDefinitions() throws {
        let file = try PetArtFile.decode(Data("""
            {"schema": "pets.v1",
             "bodyShapes": {"longDog": {"species": "dog"}},
             "breeds": [{"id": "dachshund", "name": "Wiener", "bodyShape": "longDog", "hasTail": false,
                         "palette": {"belly": "#C9803F"}, "pattern": {"paws": "belly"}}]}
            """.utf8))
        XCTAssertEqual(file.species(of: .longDog), .dog)
        XCTAssertEqual(file.breed(.dachshund), PetArtFile.BreedDefinition(
            name: "Wiener", bodyShape: .longDog, hasTail: false,
            palette: [.belly: PetColor(red: 0xC9, green: 0x80, blue: 0x3F)], pattern: [.paws: .belly]
        ))
        XCTAssertEqual(PetBreed.corgi.displayName, "Corgi")
        XCTAssertFalse(PetBreed.corgi.hasTail)
        XCTAssertEqual(PetBreed.corgi.species, .dog)
        XCTAssertEqual(PetBreed.calico.pattern.role(for: .patchB), .furSpot)
        XCTAssertEqual(PetBreed.calico.palette[.eye], PetPalette.base[.eye], "unset roles keep the base color")
    }

    func testNamesTheUnknownBreedValue() {
        let json = """
            {"schema": "pets.v1", "breeds": [{"id": "corgi", "name": "Corgi", "bodyShape": "pointyEaredDog",
             "hasTail": false, "palette": {"furBase": "#E88D3C"}, "pattern": {"tail": "belly"}}]}
            """
        XCTAssertThrowsError(try PetArtFile.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? PetArtFile.LoadError, .invalidValue(path: "breeds[0].pattern", value: "tail"))
        }
        let badColor = ##"{"schema": "pets.v1", "basePalette": {"eye": "#12345"}}"##
        XCTAssertThrowsError(try PetArtFile.decode(Data(badColor.utf8))) { error in
            XCTAssertEqual(error as? PetArtFile.LoadError, .invalidValue(path: "basePalette.eye", value: "#12345"))
        }
    }

    /// The schema lists the same roles and zones as the Swift enums, so a
    /// TypeScript client rejects exactly the breed files the Mac app does.
    func testSchemaRolesAndZonesMatchSwift() throws {
        let defs = try XCTUnwrap(schema()["$defs"] as? [String: Any])
        let roles = try XCTUnwrap((defs["role"] as? [String: Any])?["enum"] as? [String])
        let zones = try XCTUnwrap((defs["zone"] as? [String: Any])?["enum"] as? [String])
        XCTAssertEqual(roles, PetPaletteRole.allCases.map(\.rawValue))
        XCTAssertEqual(zones, PetPatternZone.allCases.map(\.rawValue))
        let properties = try XCTUnwrap(schema()["properties"] as? [String: Any])
        let base = try XCTUnwrap(properties["basePalette"] as? [String: Any])
        XCTAssertEqual(base["required"] as? [String], roles)
        let shapes = try XCTUnwrap(properties["bodyShapes"] as? [String: Any])
        let shape = try XCTUnwrap(shapes["additionalProperties"] as? [String: Any])
        let species = try XCTUnwrap((shape["properties"] as? [String: Any])?["species"] as? [String: Any])
        XCTAssertEqual(species["enum"] as? [String], PetSpecies.allCases.map(\.rawValue))
    }

    private func schema() throws -> [String: Any] {
        let url = repoRoot.appendingPathComponent("shared/schemas/pets.v1.schema.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// The schema's row pattern must allow exactly the symbols `SpriteCell`
    /// reads, so a TypeScript client accepts the same art the Mac app does.
    func testSchemaRowPatternMatchesTheSpriteLegend() throws {
        let defs = try XCTUnwrap(schema()["$defs"] as? [String: Any])
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
