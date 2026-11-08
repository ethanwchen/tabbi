import Foundation
@testable import TabbiKitCore
import XCTest

/// The Pet Cam's pure engine: the seeded rolls, the room, the read, the
/// block log and the game's state machine.
final class PetCamEngineTests: XCTestCase {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-11-02 09:00 UTC, a Monday.
    static let monday = Date(timeIntervalSince1970: 1_793_610_000)
    let pet = PetProfile(name: "Mochi", breed: .britishShorthair, outfit: .cozyHoodie, accessories: [.beanie])

    // MARK: Random

    func testRollsAreDeterministicAndStreamsAreIndependent() {
        var a = PetCamRandom(seed: 42), b = PetCamRandom(seed: 42)
        XCTAssertEqual((0..<8).map { _ in a.next() }, (0..<8).map { _ in b.next() })
        var stare = PetCamRandom(seed: 42, stream: "stare"), strike = PetCamRandom(seed: 42, stream: "strike")
        XCTAssertNotEqual(stare.next(), strike.next())
        // FNV-1a and SplitMix64 are fixed algorithms: a port must match these.
        XCTAssertEqual(PetCamRandom.fnv1a(""), 0xCBF2_9CE4_8422_2325)
        XCTAssertEqual(PetCamRandom.fnv1a("a"), 0xAF63_DC4C_8601_EC8C)
        var zero = PetCamRandom(seed: 0)
        XCTAssertEqual(zero.next(), 0xE220_A839_7B1D_CDAF)
    }

    func testWeightedPickFollowsTheWeights() {
        var roll = PetCamRandom(seed: 7)
        var counts = [0, 0, 0]
        for _ in 0..<30000 { counts[roll.pick(weights: [6, 2, 2])] += 1 }
        XCTAssertEqual(Double(counts[0]) / 30000, 0.6, accuracy: 0.015)
        XCTAssertEqual(Double(counts[1]) / 30000, 0.2, accuracy: 0.015)
        var zero = PetCamRandom(seed: 1)
        XCTAssertTrue((0..<3).contains(zero.pick(weights: [0, 0, 0])))
        XCTAssertEqual(zero.pick(weights: [-1, 0, 5]), 2)
    }

    func testSeedsRoundTripAsHexText() throws {
        for seed: UInt64 in [0, 1, 0xFFFF_FFFF_FFFF_FFFF, 0x0123_4567_89AB_CDEF] {
            XCTAssertEqual(PetCamSeed.parse(PetCamSeed.text(seed)), seed)
            XCTAssertEqual(PetCamSeed.text(seed).count, 16)
        }
        let setup = PetCamSetup.prepare(seed: .max, room: .starter(at: Self.monday), species: .cat, tuning: .standard,
                                        at: Self.monday)
        let json = String(decoding: try JSONEncoder().encode(setup), as: UTF8.self)
        XCTAssertTrue(json.contains("\"ffffffffffffffff\""), json)
        XCTAssertEqual(try JSONDecoder().decode(PetCamSetup.self, from: Data(json.utf8)), setup)
    }

    // MARK: Room

    func testTheStarterRoomHasTheMugThePlantAndTheFishbowl() {
        let room = PetCamRoom.starter(at: Self.monday)
        XCTAssertEqual(room.object(at: .counter)?.kind, .mug)
        XCTAssertEqual(room.object(at: .shelf)?.kind, .plant)
        XCTAssertEqual(room.object(at: .table)?.kind, .fishbowl)
        XCTAssertTrue(room.wrecks.isEmpty)
    }

    func testAStrikeLeavesAWreckAndANewObjectOnce() {
        var room = PetCamRoom.starter(at: Self.monday)
        var random = PetCamRandom(seed: 3)
        let later = Self.monday.addingTimeInterval(1800)
        let wreck = room.strike(.counter, at: later, blockID: "b1", random: &random)
        XCTAssertEqual(wreck?.object.kind, .mug)
        XCTAssertEqual(room.wrecks.count, 1)
        let replaced = room.object(at: .counter)
        XCTAssertNotNil(replaced)
        XCTAssertNotEqual(replaced?.kind, .mug, "never the kind just wrecked")
        XCTAssertEqual(replaced?.placedAt, later)
        XCTAssertEqual(Set(room.objects.values.map(\.kind)).count, 3, "three different things always wait")
        // The same block again changes nothing.
        let before = room
        XCTAssertNil(room.strike(.counter, at: later, blockID: "b1", random: &random))
        XCTAssertEqual(room, before)
    }

    func testOnlyTheNewestWrecksPerSpotStayInView() {
        var room = PetCamRoom.starter(at: Self.monday)
        var random = PetCamRandom(seed: 9)
        for index in 0..<5 {
            room.strike(.shelf, at: Self.monday.addingTimeInterval(Double(index) * 600), blockID: "s\(index)",
                        random: &random)
        }
        XCTAssertEqual(room.visibleWrecks(at: .shelf).map(\.blockID), ["s3", "s4"], "older wrecks are swept")
        XCTAssertEqual(room.wrecks.count, PetCamRoom.visibleWrecksPerSpot)
        room.strike(.table, at: Self.monday, blockID: "t0", random: &random)
        XCTAssertEqual(room.wrecks.map(\.blockID), ["t0", "s3", "s4"], "each spot keeps its own, oldest first")
    }

    func testNoFreshObjectStandsNextToTheWreckOfOneLikeIt() {
        // Hundreds of strikes on random spots: whatever is left out is never
        // a kind whose wreck is still on the floor, three different things
        // always wait, and the floor never holds more than it shows.
        var room = PetCamRoom.starter(at: Self.monday)
        var random = PetCamRandom(seed: 0xC0)
        var spots = PetCamRandom(seed: 0xC1)
        var tidied = 0
        for index in 0..<400 {
            let spot = PetCamSpot.allCases[Int(spots.next() % 3)]
            let before = room.wrecks.count
            room.strike(spot, at: Self.monday.addingTimeInterval(Double(index) * 600), blockID: "b\(index)",
                        random: &random)
            if room.wrecks.count < min(before + 1, 3 * PetCamRoom.visibleWrecksPerSpot) { tidied += 1 }
            let standing = room.objects.values.map(\.kind)
            XCTAssertEqual(Set(standing).count, 3)
            XCTAssertTrue(Set(standing).isDisjoint(with: room.wrecks.map(\.object.kind)),
                          "block \(index): \(standing) beside \(room.wrecks.map(\.object.kind))")
            for spot in PetCamSpot.allCases {
                XCTAssertLessThanOrEqual(room.visibleWrecks(at: spot).count, PetCamRoom.visibleWrecksPerSpot)
            }
        }
        XCTAssertGreaterThan(tidied, 0, "when every free kind has a wreck in view, the oldest mess is cleared")
        // An empty spot is refilled by the same rule.
        var refilled = PetCamRoom(objects: [.counter: PetCamObject(kind: .mug, placedAt: Self.monday, serial: 0)],
                                  wrecks: [PetCamWreck(object: PetCamObject(kind: .vase, placedAt: Self.monday, serial: 1),
                                                       spot: .table, wreckedAt: Self.monday, blockID: "v")])
        refilled.refill(at: Self.monday, random: &random)
        XCTAssertFalse(refilled.objects.values.contains { $0.kind == .vase })
        XCTAssertEqual(refilled.objects.count, 3)
    }

    func testARoomFromANewerBuildStillLoads() throws {
        let json = """
        {"spots":[{"spot":"counter","object":{"kind":"mug","placedAt":0,"serial":0}},
                  {"spot":"shelf","object":{"kind":"lavaLamp","placedAt":0,"serial":1}},
                  {"spot":"table","object":{"kind":"vase","placedAt":0,"serial":2}}],
         "wrecks":[{"object":{"kind":"teapot","placedAt":0,"serial":9},"spot":"table","wreckedAt":0,"blockID":"x"}],
         "futureField":true}
        """
        let room = try JSONDecoder().decode(PetCamRoom.self, from: Data(json.utf8))
        XCTAssertEqual(room.object(at: .counter)?.kind, .mug)
        XCTAssertNil(room.object(at: .shelf), "an unknown kind leaves the spot empty for a refill")
        XCTAssertTrue(room.wrecks.isEmpty, "an unknown wreck is dropped, not the room")
        var refilled = room
        var random = PetCamRandom(seed: 1)
        refilled.refill(at: Self.monday, random: &random)
        XCTAssertEqual(Set(refilled.objects.values.map(\.kind)).count, 3)
        XCTAssertGreaterThan(refilled.nextSerial, 2)
    }

    // MARK: The read

    func testTheDefaultReadMatchesItsDocumentedNumbers() {
        let tuning = PetCamTuning.standard
        let plain = tuning.strikeChances(stare: .counter, exception: nil)
        XCTAssertEqual(plain[.counter]!, 0.62, accuracy: 1e-9)
        XCTAssertEqual(plain[.shelf]!, 0.19, accuracy: 1e-9)
        XCTAssertEqual(plain[.table]!, 0.19, accuracy: 1e-9)
        let wobble = tuning.strikeChances(stare: .counter, exception: .table)
        XCTAssertEqual(wobble[.table]!, 0.7975, accuracy: 1e-9, "the wobble is a strong lean, not a sure thing")
        XCTAssertEqual(wobble[.counter]!, 0.155, accuracy: 1e-9)
        XCTAssertEqual(wobble[.shelf]!, 0.0475, accuracy: 1e-9)
        for chances in [plain, wobble] {
            XCTAssertEqual(chances.values.reduce(0, +), 1, accuracy: 1e-9)
        }
    }

    func testTuningIsClampedAndDecodesForgivingly() throws {
        let wild = PetCamTuning(followStare: -3, exceptionChance: 4, exceptionPull: .nan)
        XCTAssertEqual(wild.followStare, 0)
        XCTAssertEqual(wild.exceptionChance, 1)
        XCTAssertEqual(wild.exceptionPull, 0)
        let away = wild.strikeChances(stare: .counter, exception: nil)
        XCTAssertEqual(away[.counter]!, 0, accuracy: 1e-9, "a pet that never follows its stare")
        XCTAssertEqual(away[.shelf]!, 0.5, accuracy: 1e-9)
        let partial = try JSONDecoder().decode(PetCamTuning.self, from: Data(#"{"followStare":0.9,"exception":"tea"}"#.utf8))
        XCTAssertEqual(partial.followStare, 0.9)
        XCTAssertEqual(partial.exception, .wobble, "an unknown exception keeps the default")
        XCTAssertEqual(partial.exceptionPull, PetCamTuning.standard.exceptionPull)
        // A tuning saved by the first prototype (weights) loads as the default read.
        let old = try JSONDecoder().decode(PetCamTuning.self, from: Data(#"{"stareWeight":6,"otherWeight":2}"#.utf8))
        XCTAssertEqual(old, .standard)
    }

    func testTheStareIsFairAndTheExceptionShowsAboutOneBlockInThreeOffTheStare() {
        var stares: [PetCamSpot: Int] = [:]
        var tells = 0
        let room = PetCamRoom.starter(at: Self.monday)
        for seed in 0..<9000 as Range<UInt64> {
            let setup = PetCamSetup.prepare(seed: seed, room: room, species: .cat, tuning: .standard, at: Self.monday)
            stares[setup.stare, default: 0] += 1
            if let tell = setup.tell {
                tells += 1
                XCTAssertNotEqual(tell.spot, setup.stare, "the exception tells something the stare does not")
            }
        }
        for spot in PetCamSpot.allCases {
            XCTAssertEqual(Double(stares[spot] ?? 0) / 9000, 1.0 / 3, accuracy: 0.02)
        }
        XCTAssertEqual(Double(tells) / 9000, PetCamTuning.standard.exceptionChance, accuracy: 0.02)
        XCTAssertEqual(PetCamTuning.standard.exceptionChance, 1.0 / 3, accuracy: 0.01)
    }

    func testTheAppetiteOnlyShowsOnTheFavoriteObjectAwayFromTheStare() throws {
        var tuning = PetCamTuning.standard
        tuning.exception = .appetite
        tuning.exceptionChance = 1
        let room = PetCamRoom.starter(at: Self.monday)
        let seeds = 0..<200 as Range<UInt64>
        let away = try XCTUnwrap(seeds.first {
            PetCamSetup.prepare(seed: $0, room: room, species: .cat, tuning: tuning, at: Self.monday).stare != .table
        })
        let cat = PetCamSetup.prepare(seed: away, room: room, species: .cat, tuning: tuning, at: Self.monday)
        XCTAssertEqual(cat.tell, PetCamTell(exception: .appetite, spot: .table), "the starter fishbowl is on the table")
        let at = try XCTUnwrap(seeds.first {
            PetCamSetup.prepare(seed: $0, room: room, species: .cat, tuning: tuning, at: Self.monday).stare == .table
        })
        XCTAssertNil(PetCamSetup.prepare(seed: at, room: room, species: .cat, tuning: tuning, at: Self.monday).tell,
                     "staring at its favorite already says it")
        let dog = PetCamSetup.prepare(seed: away, room: room, species: .dog, tuning: tuning, at: Self.monday)
        XCTAssertNil(dog.tell, "no donut in the starter room")
    }

    func testTheStrikeIsTheSameRollEveryTime() {
        let room = PetCamRoom.starter(at: Self.monday)
        for seed in 0..<200 as Range<UInt64> {
            let a = PetCamSetup.prepare(seed: seed, room: room, species: .cat, tuning: .standard, at: Self.monday)
            let b = PetCamSetup.prepare(seed: seed, room: room, species: .cat, tuning: .standard,
                                        at: Self.monday.addingTimeInterval(99))
            XCTAssertEqual(a.stare, b.stare)
            XCTAssertEqual(a.tell, b.tell)
            XCTAssertEqual(a.strike, b.strike)
            XCTAssertNotEqual(a.nextSeed, seed)
        }
    }

    // MARK: The game

    func testOnlyALongEnoughBlockArmsTheCamera() {
        var game = PetCamGame(seed: 1, at: Self.monday)
        XCTAssertTrue(game.isFirstBlock)
        XCTAssertEqual(game.minimumBlock, 5 * 60, "the very first block may be five minutes")
        XCTAssertFalse(game.arms(plannedLength: 4 * 60))
        XCTAssertTrue(game.arms(plannedLength: 5 * 60))
        XCTAssertTrue(game.arms(plannedLength: nil), "open-ended blocks arm and are judged at the end")
        XCTAssertNil(game.start(id: "short", pick: nil, dodge: nil, dare: false, plannedLength: 60, pet: pet,
                                at: Self.monday))
        XCTAssertNil(game.active)
        game.start(id: "b1", pick: nil, dodge: nil, dare: false, plannedLength: 300, pet: pet, at: Self.monday)
        game.finish(endedAt: Self.monday.addingTimeInterval(300), worked: 300, calendar: Self.calendar)
        XCTAssertFalse(game.isFirstBlock)
        XCTAssertEqual(game.minimumBlock, 10 * 60)
        XCTAssertFalse(game.arms(plannedLength: 5 * 60))
        XCTAssertTrue(game.arms(plannedLength: 25 * 60))
    }

    func testFinishingCatchesWhenTheCameraIsWhereThePetStrikes() throws {
        for seed in 0..<60 as Range<UInt64> {
            var game = PetCamGame(seed: seed, at: Self.monday)
            let strike = game.setup.strike
            let block = try XCTUnwrap(game.start(id: "b", pick: strike, dodge: "my essay", dare: true,
                                                 plannedLength: 1500, pet: pet, at: Self.monday))
            XCTAssertTrue(block.picked)
            XCTAssertEqual(block.camera, strike)
            let record = try XCTUnwrap(game.finish(endedAt: Self.monday.addingTimeInterval(1500), worked: 1500,
                                                   calendar: Self.calendar))
            XCTAssertEqual(record.outcome, .caught)
            XCTAssertEqual(record.strike, strike)
            XCTAssertEqual(game.log.mugshots.map(\.id), ["b"])
            XCTAssertEqual(record.captions.charge, "CHARGE: OBSTRUCTION OF MY ESSAY")
            XCTAssertFalse(record.captions.publicCharge?.contains("ESSAY") ?? true)
        }
    }

    func testMissingLeavesTheWreckAndANewFrozenFrame() throws {
        var game = PetCamGame(seed: 11, at: Self.monday)
        let first = game.setup
        let wrong = try XCTUnwrap(PetCamSpot.allCases.first { $0 != first.strike })
        game.start(id: "b", pick: wrong, dodge: nil, dare: false, plannedLength: 600, pet: pet, at: Self.monday)
        XCTAssertNotNil(game.active)
        let end = Self.monday.addingTimeInterval(600)
        let record = try XCTUnwrap(game.finish(endedAt: end, worked: 600, calendar: Self.calendar))
        XCTAssertEqual(record.outcome, .missed)
        XCTAssertNil(game.active)
        XCTAssertEqual(game.room.wrecks.map(\.blockID), ["b"])
        XCTAssertEqual(game.room.wrecks.first?.object, record.room.object(at: first.strike))
        XCTAssertEqual(game.setup.seed, first.nextSeed, "the next frozen frame comes from the seed chain")
        XCTAssertEqual(game.setup.preparedAt, end)
        XCTAssertEqual(game.nextUnwatched?.id, "b")
        game.markWatched("b")
        XCTAssertNil(game.nextUnwatched)
        XCTAssertTrue(game.log.mugshots.isEmpty)
    }

    func testFollowingTheStareHidesTheCameraOnTheStare() throws {
        var game = PetCamGame(seed: 21, at: Self.monday)
        let block = try XCTUnwrap(game.start(id: "b", pick: nil, dodge: "  ", dare: false, plannedLength: 900,
                                             pet: pet, at: Self.monday))
        XCTAssertFalse(block.picked)
        XCTAssertEqual(block.camera, game.setup.stare)
        XCTAssertNil(block.dodge, "a blank dodge line is no dodge line")
        XCTAssertNil(game.start(id: "c", pick: nil, dodge: nil, dare: false, plannedLength: 900, pet: pet,
                                at: Self.monday), "one armed block at a time")
    }

    func testStoppingKeepsTheFrozenFrameAndShowsOneStill() throws {
        var game = PetCamGame(seed: 4, at: Self.monday)
        let setup = game.setup
        let room = game.room
        game.start(id: "early", pick: .shelf, dodge: nil, dare: false, plannedLength: 1500, pet: pet, at: Self.monday)
        let stop = try XCTUnwrap(game.stop(at: Self.monday.addingTimeInterval(420), worked: 420, calendar: Self.calendar))
        XCTAssertEqual(stop.outcome, .stopped)
        XCTAssertEqual(game.setup, setup, "stopping never rerolls the tell")
        XCTAssertEqual(game.room, room, "nothing was struck")
        XCTAssertEqual(game.nextUnwatched?.id, "early")
        XCTAssertEqual(stop.captions.opener, "STOPPED AT 09:07. SUSPECT FROZE MID-SNEAK.")
        game.markWatched("early")

        game.start(id: "oops", pick: nil, dodge: nil, dare: false, plannedLength: 1500, pet: pet, at: Self.monday)
        let cancel = try XCTUnwrap(game.stop(at: Self.monday.addingTimeInterval(30), worked: 30, calendar: Self.calendar))
        XCTAssertEqual(cancel.outcome, .cancelled)
        XCTAssertNil(game.nextUnwatched, "a cancel shows nothing")
        XCTAssertEqual(game.setup, setup)
    }

    func testAShortOpenEndedBlockCountsAsAStop() throws {
        var game = PetCamGame(seed: 4, at: Self.monday)
        game.start(id: "flow", pick: nil, dodge: nil, dare: false, plannedLength: nil, pet: pet, at: Self.monday)
        game.finish(endedAt: Self.monday.addingTimeInterval(200), worked: 200, calendar: Self.calendar)
        XCTAssertEqual(game.log.block("flow")?.outcome, .cancelled)
        game.start(id: "flow2", pick: nil, dodge: nil, dare: false, plannedLength: nil, pet: pet, at: Self.monday)
        let record = try XCTUnwrap(game.finish(endedAt: Self.monday.addingTimeInterval(400), worked: 400,
                                               calendar: Self.calendar))
        XCTAssertTrue(record.outcome.hasTape, "the first block needs five minutes")
    }

    func testEachBlockIsCreditedOncePerBlockID() throws {
        var game = PetCamGame(seed: 8, at: Self.monday)
        game.start(id: "same", pick: nil, dodge: nil, dare: false, plannedLength: 600, pet: pet, at: Self.monday)
        let record = try XCTUnwrap(game.finish(endedAt: Self.monday.addingTimeInterval(600), worked: 600,
                                               calendar: Self.calendar))
        let after = game
        XCTAssertFalse(game.absorb(record), "a replayed record changes nothing")
        XCTAssertEqual(game, after)
        XCTAssertNil(game.start(id: "same", pick: nil, dodge: nil, dare: false, plannedLength: 600, pet: pet,
                                at: Self.monday), "a used block id never arms again")

        // A second device absorbing the same record wrecks the same object once.
        var other = PetCamGame(seed: 8, at: Self.monday)
        XCTAssertTrue(other.absorb(record))
        XCTAssertFalse(other.absorb(record))
        XCTAssertEqual(other.room, game.room)
        XCTAssertEqual(other.setup, game.setup)
    }

    func testAWholeRunReplaysFromItsFirstSeed() {
        func play() -> PetCamGame {
            var game = PetCamGame(seed: 0xC0FFEE, at: Self.monday)
            for index in 0..<40 {
                let start = Self.monday.addingTimeInterval(Double(index) * 3600)
                let pick: PetCamSpot? = index % 3 == 0 ? nil : PetCamSpot.allCases[index % 3]
                game.start(id: "b\(index)", pick: pick, dodge: index % 4 == 0 ? "laundry" : nil, dare: false,
                           plannedLength: 1500, pet: pet, at: start)
                if index % 7 == 6 {
                    game.stop(at: start.addingTimeInterval(700), worked: 700, calendar: Self.calendar)
                } else {
                    game.finish(endedAt: start.addingTimeInterval(1500), worked: 1500, calendar: Self.calendar)
                }
            }
            return game
        }
        let a = play(), b = play()
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.log.blocks.count, 40)
        XCTAssertEqual(a.log.blocks.filter { $0.strike != nil }.count, 35)
        // Three kinds stand, so at most the other three lie on the floor.
        XCTAssertTrue((2...3 * PetCamRoom.visibleWrecksPerSpot).contains(a.room.wrecks.count))
        XCTAssertEqual(Set(a.room.objects.values.map(\.kind)).count, 3)
    }

    func testTheGameSavesAndLoadsAdditively() throws {
        var game = PetCamGame(seed: 77, at: Self.monday)
        game.start(id: "b1", pick: .table, dodge: "taxes", dare: true, plannedLength: 600, pet: pet, at: Self.monday)
        game.finish(endedAt: Self.monday.addingTimeInterval(600), worked: 600, calendar: Self.calendar)
        game.start(id: "b2", pick: nil, dodge: nil, dare: false, plannedLength: 600, pet: pet,
                   at: Self.monday.addingTimeInterval(900))
        let data = try PetCamGame.schema.encode(game)
        XCTAssertEqual(VersionedJSON.version(of: data), 1)
        XCTAssertEqual(try PetCamGame.schema.decode(PetCamGame.self, from: data), game)

        // A newer build's extra field, and a record this build cannot read,
        // are skipped rather than failing the file.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["futureFeature"] = ["on": true]
        var log = try XCTUnwrap(object["log"] as? [String: Any])
        var blocks = try XCTUnwrap(log["blocks"] as? [Any])
        blocks.append(["id": "from-the-future", "outcome": "teleported"])
        log["blocks"] = blocks
        object["log"] = log
        let newer = try JSONSerialization.data(withJSONObject: object)
        let loaded = try PetCamGame.schema.decode(PetCamGame.self, from: newer)
        XCTAssertEqual(loaded.log.blocks.map(\.id), ["b1"])
        XCTAssertEqual(loaded.active?.id, "b2")
    }

    // MARK: Log

    func testMergingLogsIsAUnionByBlockID() throws {
        var game = PetCamGame(seed: 2, at: Self.monday)
        var records: [PetCamBlockRecord] = []
        for index in 0..<6 {
            let start = Self.monday.addingTimeInterval(Double(index) * 2000)
            game.start(id: "b\(index)", pick: nil, dodge: nil, dare: false, plannedLength: 600, pet: pet, at: start)
            records.append(try XCTUnwrap(game.finish(endedAt: start.addingTimeInterval(600), worked: 600,
                                                     calendar: Self.calendar)))
        }
        let phone = PetCamLog(blocks: [records[0], records[2], records[3], records[5]])
        let mac = PetCamLog(blocks: [records[4], records[1], records[3]])
        var ab = phone, ba = mac
        ab.merge(mac)
        ba.merge(phone)
        XCTAssertEqual(ab, ba, "merge is commutative")
        XCTAssertEqual(ab.blocks.map(\.id), records.map(\.id), "sorted by when each block ended")
        var twice = ab
        twice.merge(ab)
        XCTAssertEqual(twice, ab, "and idempotent")
        let data = try PetCamLog.schema.encode(ab)
        XCTAssertEqual(try PetCamLog.schema.decode(PetCamLog.self, from: data), ab)
    }

    // MARK: Payout

    func testFinishingNeverPaysWorseThanStopping() {
        for planned in [5, 10, 15, 25, 30, 50, 52, 90, 120] {
            let finish = PetCamPayout(outcome: .missed, worked: Double(planned) * 60)
            let caught = PetCamPayout(outcome: .caught, worked: Double(planned) * 60)
            XCTAssertEqual(finish, caught, "a catch and a miss pay the same points")
            for stopMinute in 0..<planned {
                for seconds in [0.0, 30, 59] {
                    let worked = Double(stopMinute) * 60 + seconds
                    let outcome: PetCamBlockRecord.Outcome = worked >= PetCamRules.standard.commitAfter ? .stopped
                        : .cancelled
                    let stop = PetCamPayout(outcome: outcome, worked: worked)
                    XCTAssertTrue(finish.isAtLeast(stop), "\(planned) min finished vs stopped at \(worked) s")
                }
            }
        }
        XCTAssertGreaterThan(PetCamPayout.Reveal.tape, .still)
        XCTAssertGreaterThan(PetCamPayout.Reveal.still, .nothing)
    }
}
