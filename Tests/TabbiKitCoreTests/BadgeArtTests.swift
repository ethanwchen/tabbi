import Foundation
import TabbiKitCore
import XCTest

/// The Goals badges are sprites: every track at every state composes to a
/// 28 by 28 canvas whose colors are pinned, pixel for pixel, in
/// `shared/fixtures/pets/badges.json`, which the Windows port replays.
/// Run with `TABBI_RECORD_FIXTURES=1` to rewrite it after an intended
/// art change.
final class BadgeArtTests: XCTestCase {
    func testEveryBadgeIsAWholeSpriteWithItsGlyphInside() {
        for track in ProgressTrack.allCases {
            for state in BadgeArt.State.allCases {
                let canvas = BadgeArt.canvas(track: track, state: state)
                let label = "\(track) \(state.name)"
                XCTAssertEqual(canvas.width, BadgeArt.size, label)
                XCTAssertEqual(canvas.height, BadgeArt.size, label)
                let glyph = canvas.pixels.filter { $0 == .belly }.count
                XCTAssertGreaterThan(glyph, 8, "the glyph shows: \(label)")
                // The glyph never reaches the outline: it sits on the inner disc.
                let origin = state == .tier(.silver) ? (10, 8) : (10, 10)
                for y in origin.1..<(origin.1 + 9) {
                    for x in origin.0..<(origin.0 + 9) where canvas[x, y] == .belly {
                        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                            XCTAssertNotNil(canvas[x + dx, y + dy], "glyph touches air: \(label) at \(x),\(y)")
                        }
                    }
                }
                let colors = BadgeArt.colors(track: track, state: state)
                XCTAssertEqual(colors.count, BadgeArt.size * BadgeArt.size, label)
                XCTAssertTrue(colors.contains { $0 == BadgePalette.colors(for: state).glyph }, label)
            }
        }
    }

    func testTiersAddTheirOwnShapes() {
        func count(_ state: BadgeArt.State, _ role: PetPaletteRole) -> Int {
            BadgeArt.canvas(track: .water, state: state).pixels.filter { $0 == role }.count
        }
        // Every medal carries the two pixel highlight as drawn; on the quiet
        // coin it is a shade lighter than the rim, not a shine. Starlight's
        // highlight is the sparkle's own white, so it is drawn in that role.
        for state in [BadgeArt.State.notYet, .tier(.bronze), .tier(.silver), .tier(.gold)] {
            XCTAssertEqual(count(state, .eyeLight), 2, "the two pixel highlight: \(state.name)")
        }
        XCTAssertEqual(count(.tier(.starlight), .effect), 8, "a four point sparkle, a dot and the two pixel highlight")
        XCTAssertGreaterThan(count(.tier(.silver), .costumeShade), count(.tier(.bronze), .costumeShade),
                             "the rosette's petals and a ribbon tail are in the shade color")
        XCTAssertGreaterThan(count(.tier(.gold), .leaf) + count(.tier(.gold), .furShade), 20, "the laurel")
        XCTAssertEqual(count(.tier(.bronze), .leaf), 0)
        let still = BadgeArt.canvas(track: .water, state: .tier(.starlight))
        let twinkle = BadgeArt.canvas(track: .water, state: .tier(.starlight), twinkle: true)
        XCTAssertNotEqual(still, twinkle, "the sparkle swaps")
        XCTAssertEqual(BadgeArt.canvas(track: .water, state: .tier(.gold), twinkle: true),
                       BadgeArt.canvas(track: .water, state: .tier(.gold)), "only Starlight twinkles")
    }

    /// The light glyph on its darker disc reaches 3:1 (WCAG's floor for
    /// graphical objects) on every earned tier, as the approved colors do
    /// (about 4:1 on gold, 4.3:1 on silver, 7:1 and up on the rest); the
    /// quiet coin's dim glyph is meant to read as not earned.
    func testTheGlyphReadsOnEveryDisc() {
        for state in BadgeArt.State.allCases {
            let colors = BadgePalette.colors(for: state)
            let (light, dark) = (max(colors.glyph.luminance, colors.inner.luminance),
                                 min(colors.glyph.luminance, colors.inner.luminance))
            let contrast = (light + 0.05) / (dark + 0.05)
            XCTAssertGreaterThanOrEqual(contrast, state == .notYet ? 1.8 : 3, "\(state.name) glyph on its disc")
        }
    }

    func testScaleIsWholePixels() {
        XCTAssertEqual(BadgeArt.scale(pixelSize: 1.5, displayScale: 2), 3)
        XCTAssertEqual(BadgeArt.scale(pixelSize: 2, displayScale: 2), 4)
        XCTAssertEqual(BadgeArt.scale(pixelSize: 1.5, displayScale: 1), 1, "no fractional scale on a 1x display")
        XCTAssertEqual(BadgeArt.scale(pixelSize: 2, displayScale: 1), 2)
        XCTAssertNotNil(BadgeArt.image(track: .focusHours, state: .tier(.gold), scale: 3))
        XCTAssertEqual(BadgeArt.image(track: .focusHours, state: .tier(.gold), scale: 3)?.width, 84)
    }

    func testBadgesMatchGoldenFixture() throws {
        let url = PetGoldenFixtures.folder.appendingPathComponent("badges.json")
        let current = BadgeGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(BadgeGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.badges.map(\.name), current.badges.map(\.name))
        for (old, new) in zip(stored.badges, current.badges) { XCTAssertEqual(old, new, old.name) }
        XCTAssertEqual(stored, current, "badges.json no longer matches the composed badges")
    }
}

/// Every badge rendered to colors, in the pets fixture's `rendered.json`
/// encoding: the frame's distinct colors in order of first appearance and
/// run-length rows of their indices.
struct BadgeGoldenFixture: Codable, Equatable {
    struct Badge: Codable, Equatable {
        var track: String
        var state: String
        var twinkle: Bool
        var colors: [String]
        var rle: String

        var name: String { "\(track) \(state)\(twinkle ? " twinkle" : "")" }
    }

    var schema = PetGoldenFixtures.schema
    var version = PetGoldenFixtures.version
    var size = BadgeArt.size
    var badges: [Badge]

    static func current() -> BadgeGoldenFixture {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        var badges: [Badge] = []
        for track in ProgressTrack.allCases {
            for state in BadgeArt.State.allCases {
                for twinkle in state == .tier(.starlight) ? [false, true] : [false] {
                    let colors = BadgeArt.colors(track: track, state: state, twinkle: twinkle)
                    var seen: [PetColor] = []
                    var rows: [String] = []
                    for y in 0..<BadgeArt.size {
                        var row = ""
                        for x in 0..<BadgeArt.size {
                            guard let color = colors[y * BadgeArt.size + x] else { row.append("."); continue }
                            let index = seen.firstIndex(of: color) ?? { seen.append(color); return seen.count - 1 }()
                            row.append(letters[index])
                        }
                        rows.append(row)
                    }
                    badges.append(Badge(track: track.rawValue, state: state.name, twinkle: twinkle,
                                        colors: seen.map(\.hex), rle: PetGoldenFixtures.runLength(rows)))
                }
            }
        }
        return BadgeGoldenFixture(badges: badges)
    }
}
