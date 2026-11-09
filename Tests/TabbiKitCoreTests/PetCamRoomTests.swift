import Foundation
@testable import TabbiKitCore
import XCTest

/// The floor keeps its wrecks legible: every wreck's place lies off the rug
/// and clear of every other place, in sight of its spot's camera, and a
/// tape never sweeps away a wreck that was already on the floor.
final class PetCamRoomTests: XCTestCase {
    /// The rectangle a wreck of any kind covers at `anchor`, with its outline.
    static func footprint(_ anchor: PetCamLayout.Point) -> CGRect {
        let grids = PetCamObjectKind.allCases.map(PetCamScene.wreck)
        let width = grids.map(\.width).max() ?? 0, height = grids.map(\.height).max() ?? 0
        return CGRect(x: anchor.x - width / 2 - 1, y: anchor.y - height - 1, width: width + 2, height: height + 2)
    }

    func testWreckPlacesNeverOverlapAndStayOffTheRug() throws {
        let room = PetCamScene.art.grid("room")
        let places = PetCamSpot.allCases.flatMap { spot in
            PetCamScene.layout.spot(spot).wrecks.enumerated().map { (spot: spot, slot: $0.offset, anchor: $0.element) }
        }
        XCTAssertEqual(places.count, PetCamSpot.allCases.count * PetCamRoom.visibleWrecksPerSpot)
        for (index, place) in places.enumerated() {
            let box = Self.footprint(place.anchor)
            for other in places.dropFirst(index + 1) {
                XCTAssertFalse(box.intersects(Self.footprint(other.anchor)),
                               "\(place.spot) \(place.slot) overlaps \(other.spot) \(other.slot)")
            }
            for y in Int(box.minY)..<Int(box.maxY) {
                for x in Int(box.minX)..<Int(box.maxX) {
                    if case .role(let role) = room.cells[y * room.width + x] {
                        XCTAssertFalse([.accessoryBase, .accessoryShade].contains(role),
                                       "\(place.spot) \(place.slot) lies on the rug at \(x), \(y)")
                    }
                }
            }
            // Its own spot's camera sees it, so a catch shows the evidence.
            let wreck = PetCamWreck(object: PetCamObject(kind: .mug, placedAt: .distantPast, serial: 0), spot: place.spot,
                                    wreckedAt: .distantPast, blockID: "", slot: place.slot)
            XCTAssertTrue(PetCamScene.shows(wreck, in: .spot(place.spot)), "\(place.spot) \(place.slot) in sight")
            // CAM 1's push-in centers on it across, high in the picture.
            let crop = PetCamScene.crop(of: .wreck(place.spot, hidden: false), wrecks: [wreck])
            XCTAssertEqual(Double(place.anchor.x - crop.x) / Double(crop.width), 0.5, accuracy: 0.06)
            XCTAssertLessThan(Double(place.anchor.y - crop.y) / Double(crop.height), 0.5)
        }
    }

    func testEveryStillShowsThePetWholeOrNotAtAll() throws {
        var failures: Set<String> = []
        var checked = 0
        for seed: UInt64 in [0x30, 0xBEA7, 0x5EED_0F, 0xCA11] {
            for record in PetCamCaptionsTests.session(seed: seed) {
                let tape = try XCTUnwrap(PetCamTape(record: record))
                for still in tape.stills {
                    guard let pose = still.shot.pet, let place = still.shot.place else { continue }
                    checked += 1
                    if !PetCamScene.showsWholePet(at: place, pose: pose, in: still.shot, pet: record.pet) {
                        let rect = PetCamScene.crop(of: still.shot.framing, wrecks: still.shot.wrecks)
                        let at = PetCamScene.placement(for: place, pose: pose)
                        let box = PetCamPetArt.canvas(pose, profile: record.pet, facingRight: at.facingRight).opaqueBounds
                        failures.insert("\(place) \(pose) in \(still.shot.framing): pet x \(at.x + (box?.minX ?? 0))..."
                            + "\(at.x + (box?.maxX ?? 31)) y \(at.y + (box?.minY ?? 0))...\(at.y + (box?.maxY ?? 31)), "
                            + "crop x \(rect.x)..<\(rect.x + rect.width) y \(rect.y)..<\(rect.y + rect.height)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 300)
        XCTAssertEqual(failures.sorted(), [], "a pet cut by the frame")
    }

    func testACloserCatchFreezesAFallingObjectInMidAir() throws {
        var frozen = 0
        for seed: UInt64 in [0x30, 0xBEA7, 0x5EED_0F, 0xCA11] {
            for record in PetCamCaptionsTests.session(seed: seed) where record.outcome == .caught {
                let tape = try XCTUnwrap(PetCamTape(record: record))
                guard tape.shape == .closer, let kind = record.struck?.kind, let strike = record.strike,
                      PetCamScene.falls(kind) else { continue }
                XCTAssertEqual(tape.stills.last?.shot.states[strike], .falling, "the \(kind) hangs in mid-air under CAUGHT")
                frozen += 1
            }
        }
        XCTAssertGreaterThan(frozen, 0)
    }

    func testATapeKeepsEveryWreckAlreadyOnTheFloor() throws {
        var game = PetCamGame(seed: 0x5EE9, at: Date(timeIntervalSince1970: 1_790_000_000))
        let pet = PetProfile(name: "", breed: .britishShorthair)
        var date = Date(timeIntervalSince1970: 1_790_000_000)
        var checked = 0
        for index in 0..<24 {
            let strike = game.setup.strike
            let pick = index.isMultiple(of: 3) ? PetCamSpot.allCases.first { $0 != strike } : strike
            game.start(id: "w\(index)", pick: pick, dodge: nil, dare: false, plannedLength: 1500, pet: pet, at: date)
            date.addTimeInterval(1500)
            let record = try XCTUnwrap(game.finish(endedAt: date, worked: 1500))
            date.addTimeInterval(900)
            // Between blocks, each spot keeps only its newest wreck.
            for spot in PetCamSpot.allCases {
                XCTAssertLessThanOrEqual(game.room.visibleWrecks(at: spot).count, 1)
            }
            let tape = try XCTUnwrap(PetCamTape(record: record))
            for still in tape.stills where still.shot.wrecks.count > record.room.wrecks.count {
                XCTAssertTrue(record.room.wrecks.allSatisfy(still.shot.wrecks.contains),
                              "the strike swept a wreck away inside the tape")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 20)
    }
}
