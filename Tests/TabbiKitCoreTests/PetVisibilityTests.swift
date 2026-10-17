import TabbiKitCore
import XCTest

/// Dark coats must never vanish: every breed, in its own colors, each Closet
/// swatch and each rare fur, keeps a readable silhouette on the black notch
/// and on every theme's brightest card. A new breed, swatch or theme that
/// breaks this fails here.
final class PetVisibilityTests: XCTestCase {
    /// Every fur a pet can wear: the breed's own, each swatch, each rare fur.
    private var tints: [PetColor?] {
        [nil] + PetCloset.furSwatches + RareFur.all.map(\.color)
    }

    func testEveryThemeKeepsPetBackdropsUnderTheCeiling() {
        for theme in ThemeCatalog.all {
            XCTAssertLessThanOrEqual(theme.brightestPetBackdrop.luminance, PetPalette.backdropCeiling,
                                     "\(theme.name) puts pets on a card brighter than PetPalette.backdropCeiling; "
                                         + "darken the card or raise the ceiling (which brightens every dark pet's rim)")
        }
    }

    func testEverySilhouetteReadsOnEveryBackdrop() {
        let backdrops = PetVisibility.backdrops
        XCTAssertEqual(backdrops.count, ThemeCatalog.all.count + 1)
        for breed in PetBreed.allCases {
            let canvas = PetComposer.sitting(breed)
            for tint in tints {
                var profile = PetProfile(name: "", breed: breed)
                profile.tintFur(tint)
                let label = "\(breed) \(tint?.hex ?? "own colors")"
                for backdrop in backdrops {
                    let report = PetVisibility.report(canvas, palette: profile.palette, on: backdrop.color)
                    // The coat's own outline reads at 3:1 all the way round...
                    XCTAssertEqual(report.coatReadablePixels, report.coatEdgePixels, "\(label) on \(backdrop.name)")
                    // ...and so does nearly all of the silhouette: a few pixels
                    // where a mid-tone stripe or patch meets the edge may fall
                    // short on the brightest cards...
                    XCTAssertGreaterThanOrEqual(report.readableShare, 0.9, "\(label) on \(backdrop.name)")
                    // ...but no part of the edge disappears.
                    XCTAssertGreaterThanOrEqual(report.weakest, 1.35, "\(label) on \(backdrop.name)")
                }
            }
        }
    }

    /// The coats that motivated the rim: their edge is all rim, and it reads
    /// at 3:1 everywhere.
    func testDarkCoatsAreFullyOutlinedByTheRim() {
        for breed in [PetBreed.blackCat, .shihTzu, .britishLonghair, .labrador] {
            let canvas = PetComposer.sitting(breed)
            XCTAssertEqual(Set(PetVisibility.edgeColors(canvas, palette: breed.palette)), [breed.palette.rim], "\(breed)")
            for backdrop in PetVisibility.backdrops {
                let report = PetVisibility.report(canvas, palette: breed.palette, on: backdrop.color)
                XCTAssertEqual(report.readableShare, 1, "\(breed) on \(backdrop.name)")
            }
        }
    }

    /// Dark markings at the edge of a light coat (Siamese points, a calico's
    /// black patch, a French Bulldog's ears) get the rim too, while the light
    /// fur around them keeps its dark outline.
    func testDarkMarkingsOnLightCoatsAreRimmedOnlyWhereTheyMeetTheEdge() {
        for breed in [PetBreed.siamese, .calico, .frenchBulldog, .beagle] {
            let palette = breed.palette
            let edge = Set(PetVisibility.edgeColors(PetComposer.sitting(breed), palette: palette))
            XCTAssertTrue(edge.contains(palette.rim), "\(breed)")
            XCTAssertTrue(edge.contains(palette[.outline]), "\(breed)")
        }
    }

    /// The tuxedo's white paws and chest already part it from the backdrop,
    /// so the outline stays dark there and frames the white crisply.
    func testLightPatchesOnADarkCoatKeepTheDarkOutline() {
        let palette = PetBreed.tuxedo.palette
        let edge = PetVisibility.edgeColors(PetComposer.sitting(.tuxedo), palette: palette)
        XCTAssertTrue(edge.contains(palette[.outline]))
        XCTAssertGreaterThan(edge.filter { $0 == palette.rim }.count, edge.count / 2)
    }

    /// The rim is whole sprite pixels in one flat color, so it stays crisp at
    /// pixel size 1 in the closed notch: no blending, no partial alpha.
    func testTheRimIsOneOpaqueColor() {
        for breed in PetBreed.allCases {
            XCTAssertEqual(breed.palette.rim.alpha, 255, "\(breed)")
        }
    }

    func testContrastMatchesWCAG() {
        let white = PetColor(red: 255, green: 255, blue: 255), black = PetColor(red: 0, green: 0, blue: 0)
        XCTAssertEqual(white.contrast(with: black), 21, accuracy: 0.01)
        XCTAssertEqual(black.contrast(with: black), 1, accuracy: 0.001)
    }
}
