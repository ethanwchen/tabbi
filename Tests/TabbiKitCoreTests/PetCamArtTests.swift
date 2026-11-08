import Foundation
@testable import TabbiKitCore
import XCTest

/// The Pet Cam's art: the new poses on every breed and look, the room's
/// grids and layout, and the scene renderer.
final class PetCamArtTests: XCTestCase {
    static let poses: [PetCamPose] = [
        .stare(.counter), .stare(.shelf), .stare(.table), .sneak(step: 0), .sneak(step: 1), .sneak(step: 2),
        .sneak(step: 3), .swipe, .midAct, .lensStare, .lieDown, .stroll(step: 0), .stroll(step: 1),
    ]
    let eyeRoles: Set<PetPaletteRole> = [.eye, .pupil, .eyeLight]

    func eyePixels(_ canvas: PetCanvas) -> Int {
        canvas.pixels.filter { $0.map(eyeRoles.contains) ?? false }.count
    }

    func testEveryPoseShowsBothEyesOnEveryBreedAndOutfit() {
        for breed in PetBreed.allCases {
            for pose in Self.poses {
                let bare = PetCamPetArt.canvas(pose, profile: PetProfile(name: "", breed: breed))
                let eyes = eyePixels(bare)
                XCTAssertGreaterThanOrEqual(eyes, 4, "\(breed) \(pose) shows its eyes")
                for outfit in PetOutfit.allCases where outfit != .none {
                    let dressed = PetCamPetArt.canvas(pose, profile: PetProfile(name: "", breed: breed, outfit: outfit))
                    XCTAssertEqual(eyePixels(dressed), eyes, "\(outfit) covers an eye on \(breed) in \(pose)")
                }
                let demo = PetCamPetArt.canvas(pose, profile: PetProfile(name: "", breed: breed, outfit: .cozyHoodie,
                                                                         accessories: [.beanie]))
                XCTAssertEqual(eyePixels(demo), eyes, "the demo look covers an eye on \(breed) in \(pose)")
            }
        }
    }

    func testEveryMugshotLookShowsTheEyesAndDiffersFromTheNext() {
        for breed in PetBreed.allCases {
            let bare = PetProfile(name: "", breed: breed)
            let looks = (0..<PetCamPetArt.mugshotLooks).map { PetCamPetArt.mugshot($0, profile: bare) }
            XCTAssertEqual(Set(looks).count, looks.count, "\(breed) pulls a different face for each case")
            XCTAssertEqual(PetCamPetArt.mugshot(PetCamPetArt.mugshotLooks, profile: bare), looks[0], "the looks cycle")
            for (index, look) in looks.enumerated() {
                let eyes = eyePixels(look)
                XCTAssertGreaterThanOrEqual(eyes, 4, "\(breed) look \(index) shows its eyes")
                let demo = PetCamPetArt.mugshot(index, profile: PetProfile(name: "", breed: breed, outfit: .cozyHoodie,
                                                                           accessories: [.beanie]))
                XCTAssertEqual(eyePixels(demo), eyes, "the demo look covers an eye on \(breed) look \(index)")
            }
            XCTAssertNotEqual(PetCamPetArt.mugshotProfile(bare), looks[0], "a side view as well as the front")
        }
    }

    func testEveryFramingIsAWholeMultipleOfTheWideShot() {
        let wide = PetCamScene.size(of: .wide)
        for spot in PetCamSpot.allCases {
            let crop = PetCamScene.size(of: .spot(spot))
            XCTAssertEqual(crop.width * 2, wide.width)
            XCTAssertEqual(crop.height * 2, wide.height)
            for place in [PetCamPlace.strike(spot), .enter(spot), .lounge(spot)] {
                let rect = PetCamScene.crop(of: .closeUp(place))
                XCTAssertEqual(rect.width * 4, wide.width)
                XCTAssertEqual(rect.height * 4, wide.height)
                XCTAssertTrue(rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= wide.width
                    && rect.y + rect.height <= wide.height, "\(place) close-up stays in the room")
            }
        }
    }

    func testPosesKeepTheFrameAndTheFloor() throws {
        for breed in PetBreed.allCases {
            let profile = PetProfile(name: "", breed: breed)
            for pose in Self.poses {
                let canvas = PetCamPetArt.canvas(pose, profile: profile)
                XCTAssertEqual(canvas.width, PetComposer.frameSize)
                let bounds = try XCTUnwrap(canvas.opaqueBounds)
                XCTAssertEqual(bounds.maxY, PetComposer.frameSize - 1 - (pose == .midAct ? 1 : 0),
                               "\(breed) \(pose) stands on the bottom row (the swat hops a pixel)")
                XCTAssertGreaterThan(bounds.minY, 0, "\(breed) \(pose) keeps its head in the frame")
            }
            // Facing right is the exact mirror image.
            let left = PetCamPetArt.canvas(.sneak(step: 1), profile: profile)
            let right = PetCamPetArt.canvas(.sneak(step: 1), profile: profile, facingRight: true)
            XCTAssertEqual(right.mirroredHorizontally(), left)
        }
    }

    func testThePosesDifferFromEachOtherAndFromTheShippedSittingFrame() {
        let profile = PetProfile(name: "", breed: .britishShorthair, outfit: .cozyHoodie, accessories: [.beanie])
        // The side table's stare is the counter's crouch, turned to face
        // right where it is placed; every other pose is its own picture.
        let poses = Self.poses.filter { $0 != .stare(.table) }
        let frames = poses.map { PetCamPetArt.canvas($0, profile: profile) }
        for (i, a) in frames.enumerated() {
            for (j, b) in frames.enumerated() where j > i && a == b {
                XCTFail("\(poses[i]) and \(poses[j]) draw the same picture")
            }
        }
        XCTAssertTrue(PetCamPetArt.facesRight(staringAt: .table))
        XCTAssertFalse(PetCamPetArt.facesRight(staringAt: .counter))
        XCTAssertFalse(frames.contains(profile.sittingCanvas()))
        // The glance overlays look the same way with both eyes.
        XCTAssertEqual(PetCamPetArt.lookLeft.left, PetCamPetArt.lookLeft.right)
    }

    func testTheShippedSittingFrameIsUnchangedByTheComposerExtras() {
        for breed in PetBreed.allCases {
            let plain = PetComposer.compose(breed, pose: PetPose(), outfit: .none, accessories: []).picture
            let extras = PetComposer.compose(breed, pose: PetPose(), outfit: .none, accessories: [],
                                             extras: PetComposer.Extras()).picture
            XCTAssertEqual(plain, extras)
            XCTAssertEqual(plain, PetComposer.sitting(breed))
        }
    }

    func testTheRendererScalesColorsLikeACanvas() throws {
        let profile = PetProfile(name: "", breed: .tuxedo)
        let canvas = PetCamPetArt.canvas(.lensStare, profile: profile)
        let a = try XCTUnwrap(PetRenderer.render(canvas, palette: profile.palette, scale: 3))
        let b = try XCTUnwrap(PetRenderer.render(colors: canvas.colors(using: profile.palette), width: canvas.width,
                                                 height: canvas.height, scale: 3))
        XCTAssertEqual(a.width, 96)
        XCTAssertEqual(a.dataProvider?.data as Data?, b.dataProvider?.data as Data?)
        XCTAssertNil(PetRenderer.render(colors: [nil], width: 2, height: 2), "a size that does not match is refused")
    }

    // MARK: Room

    func testTheRoomArtCoversEveryObjectAndSpot() {
        XCTAssertEqual(PetCamScene.art.grid("room").width, PetCamScene.layout.width)
        XCTAssertEqual(PetCamScene.art.grid("room").height, PetCamScene.layout.height)
        for kind in PetCamObjectKind.allCases {
            XCTAssertLessThanOrEqual(PetCamScene.object(kind).width, 14)
            XCTAssertLessThanOrEqual(PetCamScene.wreck(kind).width, 16)
        }
        for spot in PetCamSpot.allCases {
            let place = PetCamScene.layout.spot(spot)
            let crop = place.crop
            XCTAssertEqual(crop.width * 2, PetCamScene.layout.width, "a spot camera is a 2x zoom")
            XCTAssertEqual(crop.height * 2, PetCamScene.layout.height)
            XCTAssertTrue(crop.x >= 0 && crop.y >= 0 && crop.x + crop.width <= PetCamScene.layout.width
                && crop.y + crop.height <= PetCamScene.layout.height)
            func inside(_ x: Int, _ y: Int) -> Bool {
                x >= crop.x && x < crop.x + crop.width && y >= crop.y && y < crop.y + crop.height
            }
            XCTAssertTrue(inside(place.object.x, place.object.y), "\(spot)'s object is in its camera's frame")
            XCTAssertEqual(place.wrecks.count, PetCamRoom.visibleWrecksPerSpot)
            for wreck in place.wrecks { XCTAssertTrue(inside(wreck.x, wreck.y), "\(spot)'s wrecks are in frame") }
            for pet in [place.strike, place.approach, place.enter, place.lounge] {
                // The pet's body (the middle of its frame) is on camera.
                XCTAssertTrue(inside(pet.x + 16, pet.y + 24), "\(spot) keeps the pet in frame at \(pet)")
            }
        }
        XCTAssertEqual(PetCamScene.layout.pools.count, 4, "three lit spots and the moonbeam")
    }

    func testScenesAreDeterministicAndShowWhatTheShotSays() throws {
        let monday = PetCamEngineTests.monday
        let pet = PetProfile(name: "Mochi", breed: .britishShorthair, outfit: .cozyHoodie, accessories: [.beanie])
        let room = PetCamRoom.starter(at: monday)
        let setup = PetCamSetup(seed: 9, stare: .counter, tell: PetCamTell(exception: .wobble, spot: .table),
                                tuning: .standard, preparedAt: monday)
        let home = PetCamShot.frozenFrame(room: room, setup: setup)
        let a = PetCamScene.frame(home, pet: pet, daylight: false)
        XCTAssertEqual(a, PetCamScene.frame(home, pet: pet, daylight: false))
        XCTAssertEqual(a.width, 100)
        XCTAssertEqual(a.height, 160)
        XCTAssertNotEqual(a, PetCamScene.frame(home, pet: pet, daylight: true), "day and night differ")
        XCTAssertNotEqual(a, PetCamScene.frame(home, pet: pet, daylight: false, tick: 1), "the wobble rocks")
        var empty = home
        empty.pet = nil
        XCTAssertNotEqual(a, PetCamScene.frame(empty, pet: pet, daylight: false))
        var gone = home
        gone.states[.counter] = .gone
        XCTAssertNotEqual(a, PetCamScene.frame(gone, pet: pet, daylight: false))

        let close = PetCamShot(framing: .spot(.shelf), objects: room.objects, pet: .lensStare, place: .strike(.shelf))
        let frame = PetCamScene.frame(close, pet: pet, daylight: false)
        XCTAssertEqual(frame.width, 50)
        XCTAssertEqual(frame.height, 80)
        let image = try XCTUnwrap(frame.image(scale: 4))
        XCTAssertEqual(image.width, 200)
    }

    func testTheLitSpotsAreLitAndTheRestOfTheRoomIsDark() {
        let layout = PetCamScene.layout
        func lit(_ x: Double, _ y: Double) -> Bool { PetCamScene.light[Int(y) * layout.width + Int(x)].lit }
        for pool in layout.pools {
            XCTAssertTrue(lit(pool.x, pool.y), "pool at \(pool.x),\(pool.y)")
            XCTAssertTrue(lit(pool.x + pool.rx * 0.9, pool.y))
        }
        XCTAssertFalse(lit(4, 150), "the near floor is dark")
        XCTAssertFalse(lit(96, 4), "the top of the back wall is dark")
        let share = Double(PetCamScene.light.filter(\.lit).count) / Double(PetCamScene.light.count)
        XCTAssertLessThan(share, 0.4, "most of the room is in the dark")
        // The same wall pixel is brighter in a pool than in the dark.
        let night = PetCamScene.frame(PetCamShot(framing: .wide, objects: [:]), pet: PetProfile(name: "", breed: .calico),
                                      daylight: false)
        XCTAssertGreaterThan(night[52, 18].luminance, night[96, 4].luminance * 1.5)
    }

    func testQuarterTurnsRoundTrip() throws {
        let grid = try SpriteGrid("""
            BB.
            .SS
            """)
        XCTAssertEqual(grid.rotatedClockwise().width, 2)
        XCTAssertEqual(grid.rotatedClockwise().rotatedCounterclockwise(), grid)
        XCTAssertEqual(grid.rotatedClockwise().text, ".B\nSB\nS.")
    }
}
