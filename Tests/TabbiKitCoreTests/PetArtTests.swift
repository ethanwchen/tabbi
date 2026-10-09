import Foundation
@testable import TabbiKitCore
import XCTest

/// The `pets.v1` art, breed and animation files: they load, they are checked
/// on the way in, and the JSON Schema other clients validate them with agrees
/// with the Swift legend, roles, zones and poses. That every pixel, palette
/// and frame timing matches the old Swift definitions is `PetGoldenFrameTests`.
final class PetArtTests: XCTestCase {
    private static let families = ["animations", "breeds", "cat", "costume", "dog", "effect", "paw", "prop", "tail", "walk"]

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

    func testItemsReadTheirLoopFrames() throws {
        let file = try PetArtFile.decode(Data("""
            {"schema": "pets.v1", "itemFrameDuration": 0.2,
             "headItems": {"glint": {"grid": ["YY"], "sitRow": 0, "frames": [["LY"], ["YL"]]}},
             "bodyItems": {"medal": {"cat": ["Y"], "dog": ["Y"], "longDog": ["Y"], "walk": ["Y"], "walkLong": ["Y"],
                                     "frames": [{"cat": ["L"], "dog": ["L"], "longDog": ["L"], "walk": ["L"], "walkLong": ["L"]}]}}}
            """.utf8))
        XCTAssertEqual(file.itemFrameDuration, 0.2)
        let glint = file.headItem("glint")
        XCTAssertEqual(glint.frameCount, 3)
        XCTAssertEqual((0..<4).map { glint.grid($0) }, try ["YY", "LY", "YL", "YY"].map { try SpriteGrid($0) },
                       "the still grid opens the loop, which wraps")
        let medal = file.bodyItem("medal")
        XCTAssertEqual(medal.frameCount, 2)
        XCTAssertEqual(medal.frame(1).walkLong, try SpriteGrid("L"))
        XCTAssertEqual(try PetArtFile.decode(Data(#"{"schema": "pets.v1"}"#.utf8)).itemFrameDuration, nil)
    }

    func testBackItemsReadTheirPlacementsAndLoops() throws {
        func family(_ x: Int, _ frames: String) -> String { #"{"x": \#(x), "y": -2, "frames": \#(frames)}"# }
        let wings = [("cat", -5), ("dog", -4), ("longDog", 12), ("walk", 11), ("walkLong", 10)]
            .map { #""\#($0.0)": \#(family($0.1, #"[["UU"], ["VV"]]"#))"# }.joined(separator: ", ")
        let file = try PetArtFile.decode(Data(#"{"schema": "pets.v1", "backItems": {"wings": {\#(wings)}}}"#.utf8))
        let item = file.backItem("wings")
        XCTAssertEqual(item.frameCount, 2)
        XCTAssertEqual(item.dog.x, -4)
        XCTAssertEqual(item.walkLong.y, -2)
        XCTAssertEqual(item.walk.frames, try [SpriteGrid("UU"), SpriteGrid("VV")])

        let uneven = wings.replacingOccurrences(of: #""walk": \#(family(11, #"[["UU"], ["VV"]]"#))"#,
                                                with: #""walk": \#(family(11, #"[["UU"]]"#))"#)
        XCTAssertThrowsError(try PetArtFile.decode(Data(#"{"schema": "pets.v1", "backItems": {"wings": {\#(uneven)}}}"#.utf8))) {
            XCTAssertEqual($0 as? PetArtFile.LoadError,
                           .invalidGrid(name: "wings.walk", reason: "1 frames differ from the cat's 2"))
        }
        let resized = wings.replacingOccurrences(of: #""dog": \#(family(-4, #"[["UU"], ["VV"]]"#))"#,
                                                 with: #""dog": \#(family(-4, #"[["UU"], ["V"]]"#))"#)
        XCTAssertThrowsError(try PetArtFile.decode(Data(#"{"schema": "pets.v1", "backItems": {"wings": {\#(resized)}}}"#.utf8))) {
            XCTAssertEqual($0 as? PetArtFile.LoadError,
                           .invalidGrid(name: "wings.dog.frames[1]", reason: "1x1 differs from the item's 2x1 still grid"))
        }
    }

    func testRejectsALoopFrameOfAnotherSize() {
        let json = #"{"schema": "pets.v1", "headItems": {"glint": {"grid": ["YY"], "sitRow": 0, "frames": [["Y"]]}}}"#
        XCTAssertThrowsError(try PetArtFile.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? PetArtFile.LoadError,
                           .invalidGrid(name: "glint.frames[0]", reason: "1x1 differs from the item's 2x1 still grid"))
        }
        let body = #"{"schema": "pets.v1", "bodyItems": {"medal": {"cat": ["Y"], "dog": ["Y"], "longDog": ["Y"], "#
            + #""walk": ["Y"], "walkLong": ["Y"], "frames": [{"cat": ["Y"], "dog": ["YY"], "longDog": ["Y"], "#
            + #""walk": ["Y"], "walkLong": ["Y"]}]}}}"#
        XCTAssertThrowsError(try PetArtFile.decode(Data(body.utf8))) { error in
            XCTAssertEqual(error as? PetArtFile.LoadError,
                           .invalidGrid(name: "medal.frames[0].dog", reason: "2x1 differs from the item's 1x1 still grid"))
        }
        let still = #"{"schema": "pets.v1", "itemFrameDuration": 0}"#
        XCTAssertThrowsError(try PetArtFile.decode(Data(still.utf8))) { error in
            XCTAssertEqual(error as? PetArtFile.LoadError, .invalidValue(path: "itemFrameDuration", value: "0.0"))
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

    func testAnimationFileCoversEveryCase() {
        XCTAssertEqual(Set(PetArt.animations.animations.keys), Set(PetAnimation.allCases))
    }

    /// Timelines name art in other files; every name and index must exist.
    func testTimelinesReferenceRealArt() {
        for animation in PetAnimation.allCases {
            for (index, frame) in animation.timeline.frames.enumerated() {
                let label = "\(animation)[\(index)]"
                for effect in frame.effects {
                    XCTAssertNotNil(PetArt.effect.grids[effect.grid], "\(label) effect \(effect.grid)")
                }
                if let steam = frame.steam {
                    XCTAssertTrue(PropArt.steam.indices.contains(steam), "\(label) steam \(steam)")
                }
                if case .walking(let step) = frame.stance {
                    XCTAssertTrue(WalkArt.cycle.indices.contains(step), "\(label) step \(step)")
                }
            }
        }
    }

    func testTimelinesReadTheirFrames() throws {
        let file = try PetArtFile.decode(Data("""
            {"schema": "pets.v1", "animations": {"nap": {"loops": true, "still": 1, "frames": [
              {"duration": 1},
              {"duration": 0.5, "pose": {"eyes": "sleepy", "prop": {"kind": "toy", "roll": 3, "bat": true}, "lift": 2},
               "stance": {"kind": "curled", "breath": 1}, "shiftY": -4, "steam": 1, "dust": true, "bubble": true,
               "effects": [{"grid": "zLarge", "x": 28, "y": {"head": -9}}]}
            ]}}}
            """.utf8))
        XCTAssertEqual(file.timeline(.nap), PetTimeline(loops: true, still: 1, frames: [
            PetTimeline.Frame(duration: 1),
            PetTimeline.Frame(
                duration: 0.5,
                pose: PetPose(eyes: .sleepy, prop: .toy(roll: 3, bounce: 0, bat: true), lift: 2),
                stance: .curled(breath: 1), shiftY: -4,
                effects: [PetTimeline.Effect(grid: "zLarge", x: .frame(28), y: .head(-9))],
                steam: 1, dust: true, bubble: true
            ),
        ]))
        XCTAssertEqual(file.timeline(.nap).stillIndex, 1)
        XCTAssertEqual(PetTimeline(loops: false, still: nil, frames: [.init(duration: 1), .init(duration: 1)]).stillIndex, 1,
                       "a one-shot clip holds its last frame")
    }

    func testNamesTheBrokenTimelineValue() {
        func error(_ animations: String) -> PetArtFile.LoadError? {
            do {
                _ = try PetArtFile.decode(Data(#"{"schema": "pets.v1", "animations": \#(animations)}"#.utf8))
                return nil
            } catch {
                return error as? PetArtFile.LoadError
            }
        }
        XCTAssertEqual(error(#"{"dance": {"loops": true, "frames": [{"duration": 1}]}}"#),
                       .invalidValue(path: "animations", value: "dance"))
        XCTAssertEqual(error(#"{"sit": {"loops": true, "frames": [{"duration": 1, "pose": {"eyes": "wink"}}]}}"#),
                       .invalidValue(path: "animations.sit.frames[0].pose.eyes", value: "wink"))
        XCTAssertEqual(error(#"{"sit": {"loops": true, "frames": [{"duration": 0}]}}"#),
                       .invalidValue(path: "animations.sit.frames[0].duration", value: "0.0"))
        XCTAssertEqual(error(#"{"sit": {"loops": true, "still": 1, "frames": [{"duration": 1}]}}"#),
                       .invalidValue(path: "animations.sit.still", value: "1"))
        XCTAssertEqual(error(#"{"sit": {"loops": true, "frames": [{"duration": 1, "stance": {"kind": "rolling"}}]}}"#),
                       .invalidValue(path: "animations.sit.frames[0].stance.kind", value: "rolling"))
    }

    /// The schema lists the same animations, eyes and mouths as Swift.
    func testSchemaPosesMatchSwift() throws {
        let properties = try XCTUnwrap(schema()["properties"] as? [String: Any])
        let animations = try XCTUnwrap(properties["animations"] as? [String: Any])
        let names = try XCTUnwrap((animations["propertyNames"] as? [String: Any])?["enum"] as? [String])
        XCTAssertEqual(names, PetAnimation.allCases.map(\.rawValue))
        let defs = try XCTUnwrap(schema()["$defs"] as? [String: Any])
        let pose = try XCTUnwrap((defs["pose"] as? [String: Any])?["properties"] as? [String: Any])
        XCTAssertEqual((pose["eyes"] as? [String: Any])?["enum"] as? [String], PetPose.Eyes.allCases.map(\.rawValue))
        XCTAssertEqual((pose["mouth"] as? [String: Any])?["enum"] as? [String], PetPose.Mouth.allCases.map(\.rawValue))
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
