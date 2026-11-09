import Foundation
@testable import TabbiKitCore
import XCTest

/// The Pet Cam's art: the new poses on every breed and look, the room's
/// grids and layout, and the scene renderer.
final class PetCamArtTests: XCTestCase {
    static let poses: [PetCamPose] = [
        .stare(.counter), .stare(.shelf), .stare(.table), .sneak(step: 0), .sneak(step: 1), .sneak(step: 2),
        .sneak(step: 3), .swipe, .lensStare, .lieDown, .stroll(step: 0), .stroll(step: 1),
    ] + PetCamObjectKind.allCases.map(PetCamPose.act) + [.caughtMidAct(.mug), .caughtMidAct(.donut)]
        + PetCamObjectKind.allCases.map(PetCamPose.guilty) + [.mugshot(.fishbowl, look: 2, tier: 3)]
        + PetCamObjectKind.allCases.map(PetCamPose.walkBy)

    /// Poses whose eyes are shut or squeezed against a splash, a chomp or
    /// soil: they show no eye pixels to count, so the outfit check reads the
    /// whole face instead.
    static func eyesShut(_ pose: PetCamPose) -> Bool {
        if case .act(let kind) = pose { return kind != .mug && kind != .tissues }
        return false
    }
    let eyeRoles: Set<PetPaletteRole> = [.eye, .pupil, .eyeLight]

    func eyePixels(_ canvas: PetCanvas) -> Int {
        canvas.pixels.filter { $0.map(eyeRoles.contains) ?? false }.count
    }

    func testEveryPoseShowsBothEyesOnEveryBreedAndOutfit() {
        for breed in PetBreed.allCases {
            for pose in Self.poses {
                let bare = PetCamPetArt.canvas(pose, profile: PetProfile(name: "", breed: breed))
                let eyes = eyePixels(bare)
                if !Self.eyesShut(pose) { XCTAssertGreaterThanOrEqual(eyes, 4, "\(breed) \(pose) shows its eyes") }
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
            // The evidence a guilty pet wears never covers an eye, and each
            // object leaves its own mark.
            for look in 0..<PetCamPetArt.mugshotLooks {
                let demo = PetProfile(name: "", breed: breed, outfit: .cozyHoodie, accessories: [.beanie])
                let clean = PetCamPetArt.mugshot(look, profile: demo)
                let guilty = PetCamObjectKind.allCases.map {
                    PetCamPetArt.mugshot(look, profile: demo, evidence: $0, tier: look % 3 + 1)
                }
                XCTAssertEqual(Set(guilty).count, guilty.count, "\(breed) look \(look): one mark per object")
                for (kind, picture) in zip(PetCamObjectKind.allCases, guilty) {
                    XCTAssertNotEqual(picture, clean, "\(breed) wears the \(kind)")
                    let covered = clean.pixels.indices.filter {
                        (clean.pixels[$0].map(eyeRoles.contains) ?? false) && picture.pixels[$0] != clean.pixels[$0]
                    }
                    XCTAssertEqual(covered, [], "the \(kind) mark covers an eye on \(breed) look \(look)")
                }
            }
        }
    }

    func testNoFramingZoomsPastTwiceTheWideShotOrCutsThePetOff() {
        let wide = PetCamScene.size(of: .wide)
        func inRoom(_ rect: PetCamLayout.Rect) -> Bool {
            rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= wide.width && rect.y + rect.height <= wide.height
        }
        for spot in PetCamSpot.allCases {
            let crop = PetCamScene.size(of: .spot(spot))
            XCTAssertEqual(crop.width * 2, wide.width)
            XCTAssertEqual(crop.height * 2, wide.height)
            for place in [PetCamPlace.strike(spot), .enter(spot), .lounge(spot)] {
                let rect = PetCamScene.crop(of: .closeUp(place))
                XCTAssertEqual(rect.width * 2, wide.width, "a close-up is at most 2x")
                XCTAssertEqual(rect.height * 2, wide.height)
                XCTAssertTrue(inRoom(rect), "\(place) close-up stays in the room")
                let pet = PetCamScene.placement(for: place, pose: .lensStare)
                XCTAssertTrue(pet.x >= rect.x && pet.y >= rect.y && pet.x + PetComposer.frameSize <= rect.x + rect.width
                    && pet.y + PetComposer.frameSize <= rect.y + rect.height, "the whole pet is in the \(place) close-up")
            }
            for slot in 0..<PetCamRoom.visibleWrecksPerSpot {
                let wreck = PetCamWreck(object: PetCamObject(kind: .vase, placedAt: .distantPast, serial: 0), spot: spot,
                                        wreckedAt: .distantPast, blockID: "w", slot: slot)
                for hidden in [true, false] {
                    let rect = PetCamScene.crop(of: .wreck(spot, hidden: hidden), wrecks: [wreck])
                    XCTAssertEqual(rect.width * 2, wide.width)
                    XCTAssertTrue(inRoom(rect))
                    XCTAssertTrue(PetCamScene.shows(wreck, in: .wreck(spot, hidden: hidden)), "the close-up shows it")
                }
                XCTAssertTrue(PetCamScene.shows(wreck, in: .spot(spot)), "its own camera sees the wreck")
                XCTAssertTrue(PetCamScene.shows(wreck, in: .wide))
            }
        }
    }

    func testTheCaughtStampNeverCoversTheEvidence() throws {
        // Every catch's last frame over a long run: wherever the stamp lands,
        // it covers none of the wreck (Exhibit A) or the object mid-strike.
        let monday = PetCamEngineTests.monday
        let pet = PetProfile(name: "", breed: .britishShorthair, outfit: .cozyHoodie, accessories: [.beanie])
        var game = PetCamGame(seed: 0x57A, tuning: PetCamTuning(followStare: 1, exception: .none), at: monday)
        for index in 0..<24 {
            let start = monday.addingTimeInterval(Double(index) * 2400)
            game.start(id: "s\(index)", pick: nil, dodge: nil, dare: false, plannedLength: 600, pet: pet, at: start)
            let record = try XCTUnwrap(game.finish(endedAt: start.addingTimeInterval(600), worked: 600,
                                                   calendar: PetCamEngineTests.calendar))
            let freeze = try XCTUnwrap(PetCamTape(record: record)?.stills.last)
            let shot = freeze.shot
            let center = PetCamScene.stampCenter(of: shot, pet: pet)
            let crop = PetCamScene.crop(of: shot.framing, wrecks: shot.wrecks)
            let stamp = CGRect(x: (center.x - PetCamScene.stampSize.width / 2) * Double(crop.width) + Double(crop.x),
                               y: (center.y - PetCamScene.stampSize.height / 2) * Double(crop.height) + Double(crop.y),
                               width: PetCamScene.stampSize.width * Double(crop.width),
                               height: PetCamScene.stampSize.height * Double(crop.height))
            let strike = try XCTUnwrap(record.strike), kind = try XCTUnwrap(record.struck?.kind)
            let exhibit: CGRect
            if case .closeUp = shot.framing {
                // The closer freezes on the act: the evidence is the object
                // itself, mid-strike, where it stands or flies.
                let grid = PetCamScene.object(kind), place = PetCamScene.layout.spot(strike)
                let x = place.object.x + (PetCamScene.flies(kind) ? (place.strike.facingRight ? 7 : -7) : 0)
                let y = place.object.y - (PetCamScene.flies(kind) ? 5 : 0)
                let side = max(grid.width, grid.height)
                exhibit = CGRect(x: x - side / 2, y: y - side, width: side, height: side)
            } else {
                let newest = try XCTUnwrap(shot.wrecks.last { $0.spot == strike })
                let grid = PetCamScene.wreck(newest.object.kind), base = PetCamScene.wreckAnchor(newest)
                exhibit = CGRect(x: base.x - grid.width / 2, y: base.y - grid.height, width: grid.width, height: grid.height)
            }
            XCTAssertFalse(stamp.intersects(exhibit), "\(kind) on the \(strike) (\(shot.framing)): \(center)")
        }
    }

    func testAWreckCloseUpExposesTheWreckItNames() {
        // The side table's tissues beside an older puddle, filmed from CAM 1:
        // the tissues are drawn as if lit and on top, the puddle stays dim.
        let pet = PetProfile(name: "", breed: .britishShorthair)
        let day = PetCamEngineTests.monday
        let puddle = PetCamWreck(object: PetCamObject(kind: .fishbowl, placedAt: day, serial: 1), spot: .table,
                                 wreckedAt: day, blockID: "a", slot: 0)
        let tissues = PetCamWreck(object: PetCamObject(kind: .tissues, placedAt: day, serial: 2), spot: .table,
                                  wreckedAt: day.addingTimeInterval(60), blockID: "b", slot: 1)
        let close = PetCamShot(framing: .wreck(.table, hidden: false), objects: [:], wrecks: [puddle, tissues])
        var wide = close
        wide.framing = .wide
        let shown = PetCamScene.frame(close, pet: pet, daylight: false)
        let room = PetCamScene.frame(wide, pet: pet, daylight: false)
        let crop = PetCamScene.crop(of: close.framing, wrecks: close.wrecks)
        let base = PetCamScene.wreckAnchor(tissues)
        // A pixel inside the tissue trail is brighter in the close-up than in
        // the wide shot, where the same wreck is just one in the dark.
        let grid = PetCamScene.wreck(.tissues)
        var brighter = 0, total = 0
        for y in 0..<grid.height {
            for x in 0..<grid.width where grid[x, y] != .empty {
                let rx = base.x - (grid.width + 2) / 2 + 1 + x, ry = base.y - (grid.height + 2) + 2 + y
                total += 1
                let near = shown[rx - crop.x, ry - crop.y].luminance, far = room[rx, ry].luminance
                XCTAssertGreaterThanOrEqual(near, far - 1e-9, "never darker in its own close-up")
                if near > far { brighter += 1 }
            }
        }
        XCTAssertGreaterThan(Double(brighter) / Double(total), 0.5, "the named wreck reads in its close-up")
    }

    func testWrecksAreRingedInLightAndObjectsInInk() {
        let ink = PetCamScene.palette[.ink]
        let light = PetCamScene.palette[.coatShade]
        for kind in PetCamObjectKind.allCases {
            for wrecked in [false, true] {
                let sprite = PetCamScene.sprite(kind, wrecked: wrecked)
                // The leftmost opaque pixel is always part of the outline.
                let edge = (0..<sprite.width).lazy.compactMap { x in
                    (0..<sprite.height).compactMap { sprite.colors[$0 * sprite.width + x] }.first
                }.first
                XCTAssertEqual(edge, wrecked ? light : ink, "\(kind) \(wrecked ? "wreck" : "object") outline")
            }
        }
    }

    func testThePetStandsBehindWhatIsInFrontOfIt() {
        // On the counter the pet sits behind the object (its feet are
        // higher up the frame than the object's base), so wherever both
        // draw, the object wins; at the side table the pet stands on the
        // floor in front of it.
        let pet = PetProfile(name: "", breed: .britishShorthair, outfit: .cozyHoodie, accessories: [.beanie])
        for (spot, objectInFront) in [(PetCamSpot.counter, true), (.table, false)] {
            let objects = [spot: PetCamObject(kind: .donut, placedAt: .distantPast, serial: 0)]
            let both = PetCamShot(framing: .wide, objects: objects, pet: .swipe, place: .strike(spot))
            var objectOnly = both
            objectOnly.pet = nil
            var petOnly = both
            petOnly.objects = [:]
            var empty = petOnly
            empty.pet = nil
            let a = PetCamScene.frame(both, pet: pet, daylight: false)
            let o = PetCamScene.frame(objectOnly, pet: pet, daylight: false)
            let p = PetCamScene.frame(petOnly, pet: pet, daylight: false)
            let e = PetCamScene.frame(empty, pet: pet, daylight: false)
            let overlap = a.pixels.indices.filter { o.pixels[$0] != e.pixels[$0] && p.pixels[$0] != e.pixels[$0] }
            XCTAssertFalse(overlap.isEmpty, "the pet and the object overlap on the \(spot)")
            for index in overlap {
                XCTAssertEqual(a.pixels[index], objectInFront ? o.pixels[index] : p.pixels[index], "\(spot) at \(index)")
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
                switch pose {
                case .caughtMidAct(let kind) where !kind.isEaten:
                    XCTAssertLessThanOrEqual(bounds.maxY, PetComposer.frameSize - 3, "\(breed) is caught in mid-air")
                default:
                    XCTAssertEqual(bounds.maxY, PetComposer.frameSize - 1 - (pose == .act(.mug) ? 1 : 0),
                                   "\(breed) \(pose) stands on the bottom row (the swat hops a pixel)")
                }
                XCTAssertGreaterThan(bounds.minY, 0, "\(breed) \(pose) keeps its head in the frame")
                let demo = PetCamPetArt.canvas(pose, profile: PetProfile(name: "", breed: breed, outfit: .cozyHoodie,
                                                                         accessories: [.beanie]))
                XCTAssertGreaterThan(try XCTUnwrap(demo.opaqueBounds).minY, 0, "the beanie stays in frame: \(pose)")
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

    func testTheRoomHasNoHalosAndReadsEvenly() {
        // The dithered pools turned close-ups to mush, so the room is lit
        // evenly: nothing is in a pool, and at night the far wall and the
        // near floor are both still readable, not black.
        XCTAssertTrue(PetCamScene.layout.pools.isEmpty)
        XCTAssertFalse(PetCamScene.light.contains { $0.lit })
        let night = PetCamScene.frame(PetCamShot(framing: .wide, objects: [:]), pet: PetProfile(name: "", breed: .calico),
                                      daylight: false)
        let day = PetCamScene.frame(PetCamShot(framing: .wide, objects: [:]), pet: PetProfile(name: "", breed: .calico),
                                    daylight: true)
        for (x, y) in [(52, 18), (96, 4), (4, 150), (60, 100)] {
            XCTAssertGreaterThan(night[x, y].luminance, 0.05, "readable at night at \(x),\(y)")
            XCTAssertGreaterThan(day[x, y].luminance, night[x, y].luminance, "brighter by day at \(x),\(y)")
        }
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
