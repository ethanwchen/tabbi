import XCTest
import NotchDeckCore

final class PetColorTests: XCTestCase {
    func testParsesAndFormatsHex() {
        XCTAssertEqual(PetColor(hex: "#FF8000"), PetColor(red: 255, green: 128, blue: 0))
        XCTAssertEqual(PetColor(hex: "ff800080")?.alpha, 128)
        XCTAssertEqual(PetColor(red: 1, green: 2, blue: 3).hex, "#010203")
        XCTAssertEqual(PetColor(red: 1, green: 2, blue: 3, alpha: 4).hex, "#01020304")
        XCTAssertNil(PetColor(hex: "#12345"))
        XCTAssertNil(PetColor(hex: "#GG0000"))
    }

    func testLuminanceOrdersDarkBelowLight() {
        XCTAssertEqual(PetColor(hex: "#000000")!.luminance, 0, accuracy: 0.0001)
        XCTAssertEqual(PetColor(hex: "#FFFFFF")!.luminance, 1, accuracy: 0.0001)
        XCTAssertLessThan(PetColor(hex: "#2B2830")!.luminance, PetColor(hex: "#F2A65A")!.luminance)
    }
}

final class PetPaletteTests: XCTestCase {
    func testEveryRoleHasAColorAndOverridesWin() {
        let palette = PetPalette([.furBase: PetColor(hex: "#112233")!])
        for role in PetPaletteRole.allCases { _ = palette[role] }
        let recolored = palette.applying([.furBase: PetColor(hex: "#445566")!])
        XCTAssertEqual(recolored[.furBase].hex, "#445566")
        XCTAssertEqual(recolored[.eye], palette[.eye])
    }

    func testRoundTripsThroughJSONAsHexStrings() throws {
        let palette = PetPalette([.costumeBase: PetColor(hex: "#ABCDEF")!])
        let data = try JSONEncoder().encode(palette)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"costumeBase\":\"#ABCDEF\""))
        XCTAssertEqual(try JSONDecoder().decode(PetPalette.self, from: data), palette)
    }

    func testDarkFurGetsAWarmRimSoItNeverVanishesOnBlack() {
        let black = PetPalette([.furBase: PetColor(hex: "#1A1A1A")!, .outline: PetColor(hex: "#000000")!])
        XCTAssertEqual(black.withVisibleRim()[.outline], PetPalette.warmRim)

        let orange = PetPalette([.furBase: PetColor(hex: "#F2A65A")!, .outline: PetColor(hex: "#2A1A14")!])
        XCTAssertEqual(orange.withVisibleRim(), orange)
    }

    func testRoleSymbolsAreUniqueAndRoundTrip() {
        let symbols = PetPaletteRole.allCases.map(\.symbol) + PetPatternZone.allCases.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count)
        for role in PetPaletteRole.allCases { XCTAssertEqual(PetPaletteRole(symbol: role.symbol), role) }
        for zone in PetPatternZone.allCases { XCTAssertEqual(PetPatternZone(symbol: zone.symbol), zone) }
    }
}

final class SpriteGridTests: XCTestCase {
    func testParsesRolesZonesEmptyAndErase() throws {
        let grid = try SpriteGrid("""

            .BxW
            m S.

            """)
        XCTAssertEqual(grid.width, 4)
        XCTAssertEqual(grid.height, 2)
        XCTAssertEqual(grid[0, 0], .empty)
        XCTAssertEqual(grid[1, 0], .role(.furBase))
        XCTAssertEqual(grid[2, 0], .erase)
        XCTAssertEqual(grid[0, 1], .zone(.muzzle))
        XCTAssertEqual(grid[1, 1], .empty)
        XCTAssertEqual(grid.text, ".BxW\nm.S.")
    }

    func testReportsRaggedRowsAndUnknownSymbolsWithPositions() {
        XCTAssertThrowsError(try SpriteGrid("BB\nB")) { error in
            XCTAssertEqual(error as? SpriteGrid.ParseError, .raggedRow(row: 2, expected: 2, found: 1))
        }
        XCTAssertThrowsError(try SpriteGrid("BB\nB?")) { error in
            XCTAssertEqual(error as? SpriteGrid.ParseError, .unknownSymbol("?", row: 2, column: 2))
        }
        XCTAssertThrowsError(try SpriteGrid("\n  \n")) { error in
            XCTAssertEqual(error as? SpriteGrid.ParseError, .empty)
        }
    }

    func testMirrorsLeftToRight() throws {
        XCTAssertEqual(try SpriteGrid("BS.\nW..").mirrored().text, ".SB\n..W")
    }
}

final class PetCanvasTests: XCTestCase {
    func testLaterLayersPaintOverAndEraseClears() throws {
        var canvas = PetCanvas(width: 3, height: 1)
        canvas.stamp(try SpriteGrid("BBB"), x: 0, y: 0)
        canvas.stamp(try SpriteGrid(".Cx"), x: 0, y: 0)
        XCTAssertEqual(canvas.pixels, [.furBase, .costumeBase, nil])
    }

    func testZonesResolveThroughThePatternWithDefaults() throws {
        var canvas = PetCanvas(width: 3, height: 1)
        canvas.stamp(try SpriteGrid("pms"), x: 0, y: 0, pattern: PetPattern([.paws: .belly]))
        XCTAssertEqual(canvas.pixels, [.belly, .belly, .furBase])
    }

    func testStampingClipsOutsideTheCanvas() throws {
        var canvas = PetCanvas(width: 2, height: 2)
        canvas.stamp(try SpriteGrid("BS\nWE"), x: 1, y: -1)
        XCTAssertEqual(canvas.pixels, [nil, .belly, nil, nil], "top row and right column fall outside")
    }

    func testOutlineUsesDirectNeighborsSoCornersStayRound() throws {
        var canvas = PetCanvas(width: 3, height: 3)
        canvas.stamp(try SpriteGrid("B"), x: 1, y: 1)
        let outlined = canvas.outlined()
        XCTAssertEqual(outlined[1, 0], .outline)
        XCTAssertEqual(outlined[0, 1], .outline)
        XCTAssertNil(outlined[0, 0], "diagonal corners stay empty")
        XCTAssertEqual(outlined[1, 1], .furBase)
    }

    func testOutlineSkipsExcludedEffectPixels() throws {
        var canvas = PetCanvas(width: 3, height: 1)
        canvas.stamp(try SpriteGrid(".Z."), x: 0, y: 0)
        XCTAssertEqual(canvas.outlined(except: [.effect]).pixels, [nil, .effect, nil])
    }
}

final class PetRendererTests: XCTestCase {
    func testScalesWithExactPixelBlocks() throws {
        var canvas = PetCanvas(width: 2, height: 1)
        canvas.stamp(try SpriteGrid("B."), x: 0, y: 0)
        let palette = PetPalette([.furBase: PetColor(hex: "#FF0000")!])
        let image = try XCTUnwrap(PetRenderer.render(canvas, palette: palette, scale: 3))
        XCTAssertEqual(image.width, 6)
        XCTAssertEqual(image.height, 3)
        let pixels = try rgba(image)
        XCTAssertEqual(Array(pixels[0..<4]), [255, 0, 0, 255])
        XCTAssertEqual(Array(pixels[(2 * 6 + 2) * 4..<(2 * 6 + 3) * 4]), [255, 0, 0, 255])
        XCTAssertEqual(pixels[(2 * 6 + 3) * 4 + 3], 0, "transparent half stays clear")
    }

    func testCachesIdenticalRequests() {
        let renderer = PetRenderer(capacity: 2)
        let canvas = PetComposer.sitting(.tuxedo)
        let first = renderer.image(for: canvas, palette: PetBreed.tuxedo.palette)
        let second = renderer.image(for: canvas, palette: PetBreed.tuxedo.palette)
        XCTAssertTrue(first === second)
        _ = renderer.image(for: canvas, palette: PetBreed.calico.palette)
        _ = renderer.image(for: canvas, palette: PetBreed.siamese.palette)
        XCTAssertEqual(renderer.cachedCount, 2, "oldest entry is evicted at capacity")
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }
}

final class PetBreedTests: XCTestCase {
    func testCatalogHasEveryCatBreed() {
        XCTAssertEqual(PetBreed.breeds(of: .cat).count, 8)
    }

    func testEveryBreedSitsInsideTheFrameWithAMargin() throws {
        for breed in PetBreed.allCases {
            let canvas = PetComposer.sitting(breed)
            let bounds = try XCTUnwrap(canvas.opaqueBounds, "\(breed) is blank")
            XCTAssertGreaterThan(bounds.minX, 0, "\(breed)")
            XCTAssertLessThan(bounds.maxX, PetComposer.frameSize - 1, "\(breed)")
            XCTAssertGreaterThan(bounds.minY, 0, "\(breed)")
            XCTAssertEqual(bounds.maxY, PetComposer.frameSize - 1, "\(breed) paws rest on the baseline")
        }
    }

    func testBreedsWithTheSameArtStillLookDifferent() {
        let looks = PetBreed.allCases.map { breed in
            PetComposer.sitting(breed).colors(using: breed.palette.withVisibleRim())
        }
        XCTAssertEqual(Set(looks.map { $0.map { $0?.hex ?? "-" } }).count, PetBreed.allCases.count)
    }
}
