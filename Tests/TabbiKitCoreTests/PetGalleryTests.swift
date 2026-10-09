import XCTest
import TabbiKitCore

final class PetGalleryTests: XCTestCase {
    func testBodyShapeBreedsCoverEveryShapeOnce() {
        let shapes = PetGallery.bodyShapeBreeds.map(\.bodyShape)
        XCTAssertEqual(shapes, PetBodyShape.allCases)
    }

    func testCostumeSheetShowsEveryLookOnEveryBodyShape() {
        let sheet = PetGallery.costumes()
        XCTAssertEqual(sheet.rows.count, PetBodyShape.allCases.count)
        let looks = PetOutfit.allCases.count + PetAccessory.allCases.count
        XCTAssertTrue(sheet.rows.allSatisfy { $0.count == looks })
        // The bare pet, then the first outfit: dressing changes the picture.
        XCTAssertNotEqual(sheet.rows[0][0].canvas, sheet.rows[0][1].canvas)
        XCTAssertTrue(sheet.rows.joined().allSatisfy { $0.duration == nil })
    }

    func testAnimationSheetHasEveryFrameOfEveryClipWithItsTiming() {
        let sheet = PetGallery.animations()
        let looks = PetGallery.dressedLooks
        XCTAssertEqual(sheet.groupSize, looks.count)
        XCTAssertEqual(sheet.rows.count, PetAnimation.allCases.count * looks.count)
        for (group, animation) in PetAnimation.allCases.enumerated() {
            for (offset, look) in looks.enumerated() {
                let clip = PetComposer.clip(animation, for: look.breed, outfit: look.outfit,
                                            accessories: look.accessories)
                let row = sheet.rows[group * looks.count + offset]
                XCTAssertEqual(row.map(\.canvas), clip.frames.map(\.canvas), "\(animation)")
                XCTAssertEqual(row.map(\.duration), clip.frames.map(\.duration), "\(animation)")
                XCTAssertTrue(row.allSatisfy { $0.loops == animation.loops }, "\(animation)")
            }
        }
    }

    func testRenderMatchesTheReportedSizeAndEncodesPNG() throws {
        let sheet = PetGallery.animations()
        let image = try XCTUnwrap(sheet.render(scale: 2))
        let size = sheet.size(scale: 2)
        XCTAssertEqual(image.width, size.width)
        XCTAssertEqual(image.height, size.height)
        let png = try XCTUnwrap(sheet.png(scale: 2))
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testSizeAddsGroupGapsBetweenGroupsOnly() {
        let cell = PetGallery.Cell(canvas: PetComposer.sitting(.calico), palette: PetBreed.calico.palette)
        let single = PetGallery(rows: [[cell], [cell]], groupSize: 1).size(scale: 1)
        let paired = PetGallery(rows: [[cell], [cell]], groupSize: 2).size(scale: 1)
        XCTAssertEqual(single.width, paired.width)
        XCTAssertGreaterThan(single.height, paired.height, "two groups need a wider gap than one")
    }
}
