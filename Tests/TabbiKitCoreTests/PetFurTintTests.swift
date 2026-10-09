import XCTest
@testable import TabbiKitCore

/// Every breed in every Closet swatch must look intentional: white stays
/// white, markings keep their light and dark meaning, and faces stay
/// readable on the coat.
final class PetFurTintTests: XCTestCase {
    private func tinted(_ breed: PetBreed, _ pick: PetColor) -> PetPalette {
        var profile = PetProfile(name: "", breed: breed)
        profile.tintFur(pick)
        return profile.palette
    }

    /// WCAG contrast ratio between two colors.
    private func contrast(_ a: PetColor, _ b: PetColor) -> Double {
        let (light, dark) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (light + 0.05) / (dark + 0.05)
    }

    /// OKLab distance: about 0.02 is barely visible, 0.1 clearly different.
    private func difference(_ a: PetColor, _ b: PetColor) -> Double {
        let (p, q) = (a.oklch, b.oklch)
        let da = p.chroma * cos(p.hue) - q.chroma * cos(q.hue)
        let db = p.chroma * sin(p.hue) - q.chroma * sin(q.hue)
        let dl = p.lightness - q.lightness
        return (dl * dl + da * da + db * db).squareRoot()
    }

    func testOKLCHRoundTripsSRGB() {
        for hex in ["#F2A65A", "#5E5856", "#9EC3EC", "#FFFFFF", "#000000", "#2B2830"] {
            let color = PetColor(hex: hex)!
            let lch = color.oklch
            XCTAssertEqual(PetColor(oklchLightness: lch.lightness, chroma: lch.chroma, hue: lch.hue), color, hex)
        }
    }

    func testTonesNeverClipToBlackOrWhite() {
        for pick in PetCloset.furSwatches + [PetColor(hex: "#000000")!, PetColor(hex: "#FFFFFF")!] {
            for breed in PetBreed.allCases {
                for (role, color) in breed.furTint(pick) {
                    let lightness = color.oklch.lightness
                    XCTAssertGreaterThanOrEqual(lightness, PetFurTone.darkest - 0.01, "\(breed) \(role) \(pick)")
                    XCTAssertLessThanOrEqual(lightness, PetFurTone.lightest + 0.01, "\(breed) \(role) \(pick)")
                }
            }
        }
    }

    func testDarkerAndLighterTonesKeepTheirDirectionOnEverySwatch() {
        for pick in PetCloset.furSwatches {
            let base = pick.oklch.lightness
            XCTAssertLessThan(PetFurTone.darker(0.2).color(from: pick).oklch.lightness, base - 0.02, "\(pick)")
            XCTAssertGreaterThan(PetFurTone.lighter(0.2).color(from: pick).oklch.lightness, base + 0.005, "\(pick)")
        }
    }

    func testWhiteMarkingsStayWhite() {
        // Bibs, muzzles, and paws drawn in the breed's white belly keep it.
        for breed in [PetBreed.tuxedo, .calico, .britishShorthair, .corgi, .beagle, .frenchBulldog] {
            for pick in PetCloset.furSwatches {
                XCTAssertEqual(tinted(breed, pick)[.belly], breed.palette[.belly], "\(breed) \(pick)")
            }
        }
        // White-coated pied breeds keep the white coat; the pick colors the patches.
        for breed in [PetBreed.calico, .frenchBulldog] {
            for pick in PetCloset.furSwatches {
                XCTAssertEqual(tinted(breed, pick)[.furBase], breed.palette[.furBase], "\(breed) \(pick)")
            }
        }
    }

    func testPatchesOnWhiteStayVisible() {
        let markings: [(PetBreed, PetPaletteRole)] = [(.calico, .furAccent), (.calico, .furSpot),
                                                       (.frenchBulldog, .furSpot)]
        for (breed, role) in markings {
            for pick in PetCloset.furSwatches {
                let palette = tinted(breed, pick)
                XCTAssertGreaterThan(palette[.furBase].oklch.lightness - palette[role].oklch.lightness, 0.1,
                                     "\(breed) \(role) \(pick)")
            }
        }
    }

    func testShihTzuKeepsItsMouthStainOnEverySwatch() {
        // The black Shih Tzu's coat follows the pick; the brown stain around
        // its mouth is part of the breed and never changes.
        let stain = PetBreed.shihTzu.palette[.furSpot]
        XCTAssertLessThan(PetBreed.shihTzu.palette[.furBase].luminance, 0.05, "black by default")
        XCTAssertEqual(PetBreed.shihTzu.pattern.role(for: .muzzle), .furSpot)
        for pick in PetCloset.furSwatches {
            let palette = tinted(.shihTzu, pick)
            XCTAssertEqual(palette[.furBase], pick, "\(pick)")
            XCTAssertEqual(palette[.furSpot], stain, "\(pick)")
        }
    }

    func testSiamesePointsAreADarkerSofterPick() {
        for pick in PetCloset.furSwatches {
            let palette = tinted(.siamese, pick)
            let body = palette[.furBase].oklch.lightness
            let points = palette[.furAccent].oklch.lightness
            XCTAssertGreaterThan(body - points, 0.15, "\(pick): points stand out from the body")
            XCTAssertGreaterThan(points, 0.35, "\(pick): points are never near-black")
            XCTAssertLessThan(palette[.furSpot].oklch.lightness, body, "\(pick): the mask is darker than the body")
        }
    }

    func testStripesAreAGentleDarkerShade() {
        for breed in [PetBreed.orangeTabby, .grayTabby] {
            for pick in PetCloset.furSwatches {
                let palette = tinted(breed, pick)
                let step = palette[.furBase].oklch.lightness - palette[.furAccent].oklch.lightness
                XCTAssertTrue((0.05...0.25).contains(step), "\(breed) \(pick): \(step)")
                XCTAssertLessThanOrEqual(palette[.furAccent].oklch.chroma, pick.oklch.chroma + 0.005, "no harsh saturation")
            }
        }
    }

    func testFacesStayReadableOnEverySwatch() {
        for breed in PetBreed.allCases {
            for pick in PetCloset.furSwatches {
                var profile = PetProfile(name: "", breed: breed)
                profile.tintFur(pick)
                let canvas = profile.sittingCanvas()
                let colors = canvas.colors(using: profile.palette)
                // The fur pixels touching a face feature, averaged.
                func furAround(_ roles: Set<PetPaletteRole>) -> (feature: [PetColor], fur: PetColor)? {
                    var feature: [PetColor] = [], fur: [PetColor] = []
                    for y in 0..<canvas.height {
                        for x in 0..<canvas.width where canvas[x, y].map(roles.contains) == true {
                            feature.append(colors[y * canvas.width + x]!)
                            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                                guard let around = canvas[x + dx, y + dy],
                                      PetPalette.tintableFurRoles.contains(around) else { continue }
                                fur.append(colors[(y + dy) * canvas.width + x + dx]!)
                            }
                        }
                    }
                    guard !fur.isEmpty else { return nil }
                    let lightest = fur.max { $0.luminance < $1.luminance }!
                    return (feature, lightest)
                }
                let label = "\(breed) on \(pick)"
                // An eye reads by its dark pupil or by a bright iris.
                if let eye = furAround([.eye, .pupil]) {
                    let best = eye.feature.map { contrast($0, eye.fur) }.max()!
                    XCTAssertGreaterThan(best, 2, "eye: \(label)")
                }
                if let mouth = furAround([.mouth]) {
                    let worst = mouth.feature.map { contrast($0, mouth.fur) }.min()!
                    XCTAssertGreaterThan(worst, 1.8, "mouth: \(label)")
                }
                // A pink nose on a brown mask reads by hue, so it is judged by color difference.
                if let nose = furAround([.nose]) {
                    XCTAssertGreaterThan(difference(nose.feature[0], nose.fur), 0.07, "nose: \(label)")
                }
            }
        }
    }

    func testSwatchesNeedNoRimSoNoRingAroundDarkPicks() {
        // The darkest swatch is a soft charcoal, light enough to read on the
        // black notch with the breed's own outline.
        for pick in PetCloset.furSwatches {
            for breed in PetBreed.allCases {
                let palette = tinted(breed, pick)
                XCTAssertEqual(palette[.outline], breed.palette[.outline], "\(breed) \(pick)")
            }
        }
    }
}
