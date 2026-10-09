import XCTest
import TabbiKitCore

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

    func testDarkFurGetsALightRimSoItNeverVanishesOnBlack() {
        let black = PetPalette([.furBase: PetColor(hex: "#1A1A1A")!, .outline: PetColor(hex: "#000000")!])
        XCTAssertEqual(black.withVisibleRim()[.outline], black.rim)

        let orange = PetPalette([.furBase: PetColor(hex: "#F2A65A")!, .outline: PetColor(hex: "#2A1A14")!])
        XCTAssertEqual(orange.withVisibleRim(), orange)
    }

    func testCatMouthContrastsWithTheFurItSitsOn() {
        func mouthColors(_ breed: PetBreed, tint: PetColor? = nil) -> Set<PetColor> {
            var profile = PetProfile(name: "", breed: breed)
            profile.tintFur(tint)
            let canvas = PetComposer.sitting(breed)
            let colors = canvas.colors(using: profile.palette)
            let mouth = canvas.pixels.indices.filter { canvas.pixels[$0] == .mouth }
            XCTAssertFalse(mouth.isEmpty, "\(breed) draws a mouth")
            return Set(mouth.compactMap { colors[$0] })
        }
        let dark = PetPalette([:])[.mouth]
        // The tuxedo is black fur with a white muzzle: a rim-colored mouth would smudge it.
        XCTAssertEqual(mouthColors(.tuxedo), [dark])
        XCTAssertEqual(mouthColors(.orangeTabby), [dark])
        // A dark mouth vanishes into black fur.
        XCTAssertEqual(mouthColors(.blackCat), [PetBreed.blackCat.palette.rim])
        // The Siamese mask is a soft mid-brown, light enough for the dark mouth.
        XCTAssertEqual(mouthColors(.siamese), [dark])
        XCTAssertEqual(mouthColors(.blackCat, tint: PetColor(hex: "#F4F0EA")!), [dark], "recolors adapt too")
    }

    func testSiameseMaskIsSofterThanItsPointsSoTheFaceStaysReadable() {
        let palette = PetBreed.siamese.palette
        let maskRole = PetBreed.siamese.pattern.role(for: .muzzle)
        XCTAssertEqual(PetBreed.siamese.pattern.role(for: .mask), maskRole, "one even mask, no dark diamond on top")
        let mask = palette[maskRole].luminance
        // Darker than the cream coat, lighter than the seal ears, paws and tail.
        XCTAssertLessThan(mask, palette[.furBase].luminance)
        XCTAssertGreaterThan(mask, palette[PetBreed.siamese.pattern.role(for: .ears)].luminance)
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
    func testCatalogHasEveryCatAndDogBreed() {
        XCTAssertEqual(PetBreed.breeds(of: .cat).count, 10)
        XCTAssertEqual(PetBreed.breeds(of: .cat).last, .scottishFold)
        XCTAssertEqual(PetBreed.breeds(of: .dog), [
            .goldenRetriever, .labrador, .frenchBulldog, .corgi, .dachshund, .beagle, .poodle, .shihTzu,
        ])
    }

    func testDogsUseDistinctSilhouettesWhereColorAloneIsNotEnough() {
        // Each of these breeds must be recognizable by shape, not just color.
        let shapes: [PetBreed] = [
            .goldenRetriever, .labrador, .frenchBulldog, .corgi, .dachshund, .poodle, .shihTzu,
        ]
        let silhouettes = shapes.map { breed in PetComposer.sitting(breed).pixels.map { $0 != nil } }
        XCTAssertEqual(Set(silhouettes).count, shapes.count)
    }

    func testSphynxHasItsOwnHairlessSilhouette() {
        // The big flared ears must set the Sphynx apart by shape, not only
        // by its pink skin.
        let sphynx = PetComposer.sitting(.sphynx)
        let silhouette = sphynx.pixels.map { $0 != nil }
        for other in PetBreed.breeds(of: .cat) where other != .sphynx {
            XCTAssertNotEqual(PetComposer.sitting(other).pixels.map { $0 != nil }, silhouette, "\(other)")
        }
        // Hairless: no stripes, spots, or a dark mask, and visible pink blush.
        let roles = Set(sphynx.pixels.compactMap { $0 })
        XCTAssertFalse(roles.contains(.furAccent))
        XCTAssertFalse(roles.contains(.furSpot))
        XCTAssertTrue(roles.contains(.blush))
        XCTAssertTrue(roles.contains(.furShade), "wrinkles are hinted with shading")
    }

    func testScottishFoldLoadsAsAGrayCatWithItsOwnFoldedEarSilhouette() throws {
        XCTAssertEqual(PetBreed(rawValue: "scottishFold"), .scottishFold)
        XCTAssertEqual(PetBreed.scottishFold.species, .cat)
        XCTAssertEqual(PetBreed.scottishFold.displayName, "Scottish Fold")
        let profile = PetProfile(name: "Moon", breed: .scottishFold)
        let decoded = try JSONDecoder().decode(PetProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded.breed, .scottishFold)

        // Gray by default: a low-saturation, mid-light coat that can be recolored.
        let palette = PetBreed.scottishFold.palette
        let fur = palette[.furBase]
        XCTAssertLessThan(max(fur.red, fur.green, fur.blue) - min(fur.red, fur.green, fur.blue), 30)
        XCTAssertTrue((0.3...0.7).contains(fur.luminance), "\(fur.luminance)")
        let tinted = PetProfile(name: "", breed: .scottishFold, paletteOverrides: [.furBase: PetColor(hex: "#F2A65A")!])
        XCTAssertTrue(tinted.sittingCanvas().colors(using: tinted.palette).contains(tinted.palette[.furBase]))

        // Folded ears: no ear tip pokes above the crown, so the top of the
        // head is one round dome centered over the face instead of two ear
        // tips, and it is no taller than any upright-eared cat.
        let fold = PetComposer.sitting(.scottishFold)
        let top = try XCTUnwrap(fold.opaqueBounds).minY
        let crown = (0..<fold.width).filter { fold[$0, top] != nil }
        XCTAssertEqual(crown.count, try XCTUnwrap(crown.last) - crown[0] + 1, "one dome, no separate ear tips")
        XCTAssertEqual(crown[0] + crown.last!, 6 * 2 + 19, "centered over the head")
        for other in PetBreed.breeds(of: .cat) where other != .scottishFold {
            XCTAssertGreaterThanOrEqual(top, try XCTUnwrap(PetComposer.sitting(other).opaqueBounds).minY, "\(other)")
            XCTAssertNotEqual(PetComposer.sitting(other).pixels.map { $0 != nil }, fold.pixels.map { $0 != nil })
        }
        // Folded ears hide their pink insides.
        let headRows = 0..<14
        XCTAssertFalse(headRows.contains { y in (0..<fold.width).contains { fold[$0, y] == .blush } })
    }

    func testScottishFoldHasTheSharedCatEyesInEveryAnimation() {
        func eyePixels(_ canvas: PetCanvas) -> [String] {
            (0..<canvas.height).flatMap { y in
                (0..<canvas.width).compactMap { x in
                    let role = canvas[x, y]
                    return role == .eye || role == .eyeLight ? "\(x),\(y),\(role!.symbol)" : nil
                }
            }
        }
        let fold = PetClipSet(profile: PetProfile(name: "", breed: .scottishFold))
        let tabby = PetClipSet(profile: PetProfile(name: "", breed: .orangeTabby))
        for animation in PetAnimation.allCases {
            for (frame, plain) in zip(fold[animation].frames, tabby[animation].frames) {
                XCTAssertEqual(eyePixels(frame.canvas), eyePixels(plain.canvas), "\(animation)")
            }
        }
    }

    func testScottishFoldRendersEveryAnimationInEveryCostume() {
        let palette = PetBreed.scottishFold.palette
        let looks = [PetProfile(name: "", breed: .scottishFold)]
            + PetOutfit.allCases.dropFirst().map { PetProfile(name: "", breed: .scottishFold, outfit: $0) }
            + PetAccessory.allCases.map { PetProfile(name: "", breed: .scottishFold, accessories: [$0]) }
        for look in looks {
            let clips = PetClipSet(profile: look)
            for animation in PetAnimation.allCases {
                // A peek starts or ends hidden inside the notch.
                let shown = clips[animation].frames.filter { $0.canvas.opaqueBounds != nil }
                XCTAssertFalse(shown.isEmpty, "\(animation) \(look.outfit) \(look.accessories)")
                for frame in shown {
                    XCTAssertTrue(frame.canvas.colors(using: palette).contains(palette[.furBase]),
                                  "the gray fur shows: \(animation) \(look.outfit) \(look.accessories)")
                }
            }
        }
    }

    func testPoodleHasACurlyCoatATopknotAndAPomTail() throws {
        let poodle = PetComposer.sitting(.poodle)
        // Curls are light and dark dots over the base coat.
        let roles = Set(poodle.pixels.compactMap { $0 })
        XCTAssertTrue(roles.isSuperset(of: [.furBase, .furShade, .furAccent]))
        // The topknot makes it the tallest of the floppy-eared dogs.
        let top = try XCTUnwrap(poodle.opaqueBounds).minY
        for other in [PetBreed.goldenRetriever, .labrador, .beagle] {
            XCTAssertLessThan(top, try XCTUnwrap(PetComposer.sitting(other).opaqueBounds).minY, "\(other)")
        }
        // The pom tail reaches past the golden's plain tail.
        let reach = try XCTUnwrap(poodle.opaqueBounds).maxX
        XCTAssertGreaterThan(reach, try XCTUnwrap(PetComposer.sitting(.goldenRetriever).opaqueBounds).maxX)
    }

    func testShihTzuHasAFlowingCoatATopknotAndBigRoundEyes() throws {
        let shihTzu = PetComposer.sitting(.shihTzu)
        let golden = PetComposer.sitting(.goldenRetriever)
        // The coat falls to the floor, so the bottom row is wider than a
        // dog sitting on its paws.
        let floor = PetComposer.frameSize - 1
        let width: (PetCanvas) -> Int = { canvas in (0..<canvas.width).filter { canvas[$0, floor] != nil }.count }
        XCTAssertGreaterThan(width(shihTzu), width(golden))
        // The topknot sits above every floppy-eared dog's skull.
        let top = try XCTUnwrap(shihTzu.opaqueBounds).minY
        for other in [PetBreed.goldenRetriever, .labrador, .beagle] {
            XCTAssertLessThan(top, try XCTUnwrap(PetComposer.sitting(other).opaqueBounds).minY, "\(other)")
        }
        // Big round eyes: more eye than the shared dog face.
        XCTAssertGreaterThan(shihTzu.pixels.filter { $0 == .eye }.count, golden.pixels.filter { $0 == .eye }.count)
        // Gold and white: a gold mask and ears over a white coat.
        XCTAssertTrue(Set(shihTzu.pixels.compactMap { $0 }).isSuperset(of: [.furBase, .furAccent, .belly]))
    }

    func testDarkDogsStillGetTheLightRim() {
        XCTAssertEqual(PetBreed.dachshund.palette.withVisibleRim()[.outline], PetBreed.dachshund.palette.rim)
    }

    func testTheRimIsASoftSheenInTheCoatsOwnHue() {
        for breed in [PetBreed.blackCat, .tuxedo, .dachshund] {
            let palette = breed.palette
            let rim = palette.withVisibleRim()[.outline]
            // Bright enough to part the coat from the black notch...
            XCTAssertGreaterThan(rim.luminance, 0.15, "\(breed)")
            XCTAssertGreaterThan(rim.luminance, palette[.furBase].luminance * 4, "\(breed)")
            // ...but a gentle mid tone, not a bright frame that outshines the face.
            XCTAssertLessThan(rim.luminance, palette[.eyeLight].luminance / 3, "\(breed)")
            // A muted sheen, not a colored frame: no channel strays far from the others.
            let channels = [Int(rim.red), Int(rim.green), Int(rim.blue)]
            XCTAssertLessThan(channels.max()! - channels.min()!, 40, "\(breed)")
        }
        // A cool black cat gets a cool rim; the old fixed tan rim was redder than it was blue.
        let blackCatRim = PetBreed.blackCat.palette.rim
        XCTAssertGreaterThan(blackCatRim.blue, blackCatRim.red)
        // A recolored navy pet gets a blue-gray rim, not a brown one.
        let navy = PetPalette([.furBase: PetColor(hex: "#14203A")!]).rim
        XCTAssertGreaterThan(navy.blue, navy.red)
    }

    func testBlackCatChestHasASoftSheenSoTheCoatIsNotAFlatBlob() {
        let breed = PetBreed.blackCat
        let chest = breed.palette[breed.pattern.role(for: .chest)]
        XCTAssertGreaterThan(chest.luminance, breed.palette[.furBase].luminance)
        XCTAssertLessThan(chest.luminance, 0.06, "still reads as a black cat")
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

final class PetEyeTests: XCTestCase {
    /// Every open eye has a highlight, an iris, and a dark pupil, so no breed
    /// stares out of flat blocks of color.
    func testEveryBreedHasAPupilAndAWhiteHighlight() {
        for breed in PetBreed.allCases {
            let palette = breed.palette.withVisibleRim()
            let pixels = PetComposer.sitting(breed).pixels
            XCTAssertTrue(pixels.contains(.pupil), "\(breed)")
            XCTAssertTrue(pixels.contains(.eyeLight), "\(breed)")
            XCTAssertGreaterThan(palette[.eyeLight].luminance, 0.9, "a white catchlight: \(breed)")
            XCTAssertLessThan(palette[.pupil].luminance, palette[.eye].luminance + 0.001,
                              "the pupil is never lighter than the iris: \(breed)")
            XCTAssertLessThan(palette[.pupil].luminance, 0.15, "a dark pupil: \(breed)")
        }
    }

    /// Dark coats get a tinted pupil, so the eye keeps its shape instead of
    /// melting into black fur.
    func testPupilsStandOutFromDarkFur() {
        for breed in [PetBreed.blackCat, .tuxedo, .dachshund] {
            let palette = breed.palette
            XCTAssertNotEqual(palette[.pupil], PetPalette.base[.pupil], "\(breed)")
            XCTAssertGreaterThan(palette[.pupil].luminance, palette[.furBase].luminance, "\(breed)")
        }
    }

    /// Closed, sleepy, happy, and squeezed eyes clear the whole open eye,
    /// pupil included, so no dark pixel is left behind.
    func testClosedEyesLeaveNoPupilBehind() {
        for breed in PetBreed.allCases {
            for eyes in [PetPose.Eyes.closed, .sleepy, .happy, .squeezed] {
                let canvas = PetComposer.sitting(breed, pose: PetPose(eyes: eyes))
                XCTAssertFalse(canvas.pixels.contains(.pupil), "\(breed) \(eyes)")
                XCTAssertFalse(canvas.pixels.contains(.eyeLight), "\(breed) \(eyes)")
            }
        }
    }
}
