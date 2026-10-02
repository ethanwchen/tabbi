import XCTest
import NotchKitCore

final class PetCostumeTests: XCTestCase {
    func testWearableKeepsOneAccessoryPerSlotInDrawingOrder() {
        XCTAssertEqual(
            PetAccessory.wearable([.beanie, .roundGlasses, .stethoscope, .graduationCap, .scarf]),
            [.scarf, .roundGlasses, .graduationCap],
            "last item per slot wins; neck, face, then head"
        )
        XCTAssertEqual(PetAccessory.wearable([]), [])
    }

    func testEveryItemChangesTheLookOfEveryBreed() {
        for breed in PetBreed.allCases {
            let plain = PetComposer.sitting(breed)
            for outfit in PetOutfit.allCases.dropFirst() {
                XCTAssertNotEqual(PetComposer.sitting(breed, outfit: outfit), plain, "\(outfit) on \(breed)")
            }
            for accessory in PetAccessory.allCases {
                XCTAssertNotEqual(PetComposer.sitting(breed, accessories: [accessory]), plain, "\(accessory) on \(breed)")
            }
        }
    }

    func testFullLooksStayInsideTheFrameAndOnTheBaseline() throws {
        let looks: [(PetOutfit, [PetAccessory])] = [
            (.scrubs, [.stethoscope, .surgicalCap]),
            (.whiteCoat, [.roundGlasses, .graduationCap]),
            (.none, [.scarf, .headMirror]),
            (.none, [.beanie]),
        ]
        for breed in PetBreed.allCases {
            for (outfit, accessories) in looks {
                let canvas = PetComposer.sitting(breed, outfit: outfit, accessories: accessories)
                let bounds = try XCTUnwrap(canvas.opaqueBounds)
                let label = "\(breed) in \(outfit) \(accessories)"
                XCTAssertGreaterThan(bounds.minY, 0, "hat clipped at the top: \(label)")
                XCTAssertGreaterThan(bounds.minX, 0, label)
                XCTAssertLessThan(bounds.maxX, PetComposer.frameSize - 1, label)
                XCTAssertEqual(bounds.maxY, PetComposer.frameSize - 1, label)
            }
        }
    }

    func testCostumesNeverCoverTheEyes() {
        // Eyes carry the character; glasses frame them and hats sit above them.
        for breed in PetBreed.allCases {
            let eyes = PetComposer.sitting(breed).pixels.filter { $0 == .eye || $0 == .eyeLight }.count
            let dressed = PetComposer.sitting(breed, outfit: .whiteCoat, accessories: [.roundGlasses, .beanie])
            XCTAssertEqual(dressed.pixels.filter { $0 == .eye || $0 == .eyeLight }.count, eyes, "\(breed)")
        }
    }

    func testScrubsAndCapFollowTheRecolorableCostumeRoles() {
        let canvas = PetComposer.sitting(.corgi, outfit: .scrubs, accessories: [.surgicalCap])
        XCTAssertTrue(canvas.pixels.contains(.costumeBase))
        XCTAssertFalse(canvas.pixels.contains(.coat), "the white coat has its own roles")
        let pink = PetColor(hex: "#F28DB2")!
        let colors = canvas.colors(using: PetBreed.corgi.palette.applying([.costumeBase: pink]))
        XCTAssertTrue(colors.contains(pink))
        XCTAssertTrue(PetPaletteRole.userEditable.contains(.costumeBase))
        XCTAssertFalse(PetPaletteRole.userEditable.contains(.coat))
    }

    func testCostumeIdentifiersAreStableForPersistence() throws {
        let data = try JSONEncoder().encode([PetAccessory.headMirror, .roundGlasses])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["headMirror","roundGlasses"]"#)
        XCTAssertEqual(try JSONDecoder().decode(PetOutfit.self, from: Data(#""whiteCoat""#.utf8)), .whiteCoat)
    }
}
