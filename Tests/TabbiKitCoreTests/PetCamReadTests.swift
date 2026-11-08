import Foundation
@testable import TabbiKitCore
import XCTest

/// Scripted players against the default read, the caption grammar and the
/// tape scripts.
final class PetCamReadTests: XCTestCase {
    let calendar = PetCamEngineTests.calendar
    let monday = PetCamEngineTests.monday
    let pet = PetProfile(name: "Mochi", breed: .britishShorthair, outfit: .cozyHoodie, accessories: [.beanie])

    /// How a scripted player hides the camera, given the frozen frame.
    enum Player: String, CaseIterable {
        /// Never taps a spot: the camera follows the stare.
        case followsTheStare = "always follows the stare"
        /// Taps one of the three spots at random.
        case random = "picks a random spot"
        /// The week-six expert: the stare, unless the exception shows
        /// somewhere else, then the exception.
        case expert = "reads the exception too"

        func pick(_ setup: PetCamSetup, _ roll: inout PetCamRandom) -> PetCamSpot? {
            switch self {
            case .followsTheStare: return nil
            case .random: return PetCamSpot.allCases[Int(roll.next() % 3)]
            case .expert: return setup.tell?.spot ?? setup.stare
            }
        }
    }

    /// Plays `blocks` 25-minute blocks through the real game loop and
    /// returns the share caught.
    func catchRate(_ player: Player, tuning: PetCamTuning = .standard, blocks: Int = 3000, seed: UInt64 = 0x7AB1) -> Double {
        var game = PetCamGame(seed: seed, tuning: tuning, at: monday)
        var roll = PetCamRandom(seed: seed, stream: player.rawValue)
        var caught = 0
        for index in 0..<blocks {
            let start = monday.addingTimeInterval(Double(index) * 2400)
            game.start(id: "b\(index)", pick: player.pick(game.setup, &roll), dodge: nil, dare: false,
                       plannedLength: 1500, pet: pet, at: start)
            let record = game.finish(endedAt: start.addingTimeInterval(1500), worked: 1500, calendar: calendar)
            if record?.outcome == .caught { caught += 1 }
        }
        return Double(caught) / Double(blocks)
    }

    func testScriptedPlayersFindTheReadWorthReadingButNotSolved() {
        let follow = catchRate(.followsTheStare)
        let random = catchRate(.random)
        let expert = catchRate(.expert)
        let line = { (player: Player, rate: Double) in
            "Pet Cam catch rate, default tuning, 3000 blocks: \(player.rawValue) \(String(format: "%.1f%%", rate * 100))"
        }
        print(line(.followsTheStare, follow))
        print(line(.random, random))
        print(line(.expert, expert))
        // Not a coin flip: the stare alone beats guessing.
        XCTAssertEqual(random, 1.0 / 3, accuracy: 0.04)
        XCTAssertGreaterThan(follow, 0.39)
        XCTAssertLessThan(follow, 0.46)
        // Reading the one exception is worth about thirty points.
        XCTAssertGreaterThanOrEqual(expert, 0.70)
        XCTAssertGreaterThan(expert - follow, 0.25)
        // Not solved: even the expert misses about one block in four, so
        // the miss stays the regular laugh it is meant to be.
        XCTAssertLessThan(expert, 0.78)
    }

    func testTheExceptionChangesTheReadOnlyWhenItIsOn() {
        var off = PetCamTuning.standard
        off.exception = .none
        let plain = catchRate(.followsTheStare, tuning: off, blocks: 2000)
        print("Pet Cam catch rate, no exception, 2000 blocks: always follows the stare "
            + String(format: "%.1f%%", plain * 100))
        XCTAssertEqual(plain, off.followStare, accuracy: 0.04)
        XCTAssertEqual(catchRate(.expert, tuning: off, blocks: 2000), plain, accuracy: 1e-9,
                       "with no exception the expert is the stare follower")
    }

    // MARK: Captions

    func testAgeCallbacksCountFromWhenTheObjectWasLeftOut() {
        let mug = PetCamObject(kind: .mug, placedAt: monday, serial: 0)
        func age(_ hours: Double) -> String {
            PetCamCaptions.age(of: mug, at: monday.addingTimeInterval(hours * 3600), calendar: calendar)
        }
        XCTAssertEqual(age(0.4), "MUG, LEFT OUT SINCE 09:00")
        XCTAssertEqual(age(5), "MUG, LEFT OUT 5 HOURS AGO")
        XCTAssertEqual(age(20), "MUG, LEFT OUT YESTERDAY")
        XCTAssertEqual(age(24 * 3 + 2), "MUG, LEFT OUT 3 DAYS AGO")
    }

    func testCallbacksAppearAfterSeveralBlocks() throws {
        // The camera always follows the stare, blocks every 40 minutes.
        var game = PetCamGame(seed: 0x51DE, at: monday)
        var callbacks: [String] = []
        for index in 0..<12 {
            let start = monday.addingTimeInterval(Double(index) * 2400)
            game.start(id: "b\(index)", pick: nil, dodge: nil, dare: false, plannedLength: 1500, pet: pet, at: start)
            let record = try XCTUnwrap(game.finish(endedAt: start.addingTimeInterval(1500), worked: 1500,
                                                   calendar: calendar))
            if index == 0 { XCTAssertNil(record.captions.callback, "a fresh history has nothing to call back to") }
            callbacks += [record.captions.callback].compactMap { $0 }
        }
        print("Pet Cam callbacks over 12 blocks: \(callbacks)")
        XCTAssertGreaterThanOrEqual(callbacks.count, 4)
        XCTAssertTrue(callbacks.contains { $0.contains("TODAY") || $0.contains("AGAIN") || $0.contains("NEXT TO") })
    }

    func testRepeatOffensesAreCounted() throws {
        // A pet that always strikes where it stares, filmed every time: by
        // the seventh wreck of the day some kind has come round again.
        let tuning = PetCamTuning(followStare: 1, exception: .none)
        var game = PetCamGame(seed: 3, tuning: tuning, at: monday)
        var lines: [String] = []
        for index in 0..<12 {
            let start = monday.addingTimeInterval(Double(index) * 2400)
            game.start(id: "b\(index)", pick: nil, dodge: nil, dare: false, plannedLength: 600, pet: pet, at: start)
            let record = try XCTUnwrap(game.finish(endedAt: start.addingTimeInterval(600), worked: 600, calendar: calendar))
            XCTAssertEqual(record.outcome, .caught)
            lines += [record.captions.callback].compactMap { $0 }
        }
        XCTAssertTrue(lines.contains { $0.hasPrefix("2ND") && $0.hasSuffix("TODAY") }, "\(lines)")
        XCTAssertTrue(game.log.mugshots.last?.captions.priors == "PRIOR OFFENSES: 11")
    }

    func testDodgeLinesAreTrimmedUppercasedAndShortened() {
        XCTAssertNil(PetCamCaptions.cleanDodge("   \n "))
        XCTAssertEqual(PetCamCaptions.cleanDodge("  my essay\non WW2 "), "MY ESSAY ON WW2")
        let long = PetCamCaptions.cleanDodge("replying to the group chat about the trip next month and the budget")
        XCTAssertLessThanOrEqual(long?.count ?? 99, PetCamCaptions.maximumDodgeLength)
        XCTAssertFalse(long?.hasSuffix(" ") ?? true)
    }

    func testCaptionsNeverMentionStudyingOrUseForbiddenCharacters() throws {
        var game = PetCamGame(seed: 0xA11, at: monday)
        var words: [String] = []
        for index in 0..<30 {
            let start = monday.addingTimeInterval(Double(index) * 5000)
            game.start(id: "b\(index)", pick: PetCamSpot.allCases[index % 3], dodge: nil, dare: false,
                       plannedLength: 1500, pet: pet, at: start)
            if index % 5 == 4 {
                game.stop(at: start.addingTimeInterval(400), worked: 400, calendar: calendar)
            } else {
                game.finish(endedAt: start.addingTimeInterval(1500), worked: 1500, calendar: calendar)
            }
        }
        for record in game.log.blocks {
            let set = record.captions
            words += [set.opener, set.watch, set.strike, set.turn, set.closer]
                + [set.age, set.callback, set.publicCharge, set.priors].compactMap { $0 }
        }
        let text = words.joined(separator: " ").lowercased()
        for banned in ["study", "studied", "focus", "exam", "homework", "pomodoro", "timer"] {
            XCTAssertFalse(text.contains(banned), "a shared tape never mentions studying: \(banned)")
        }
        XCTAssertFalse(text.contains("\u{2014}"))
        XCTAssertEqual(text, text.filter { $0.isASCII }, "captions are plain ASCII")
    }

    // MARK: Tapes

    func testEveryTapeIsFourToSixStillsOfTenToFifteenSeconds() throws {
        var game = PetCamGame(seed: 0x7A9E, at: monday)
        var shapes: [PetCamBlockRecord.Outcome: [PetCamTape.Shape]] = [:]
        for index in 0..<60 {
            let start = monday.addingTimeInterval(Double(index) * 3600)
            game.start(id: "b\(index)", pick: PetCamSpot.allCases[index % 3], dodge: "x", dare: false,
                       plannedLength: 1500, pet: pet, at: start)
            let record = try XCTUnwrap(game.finish(endedAt: start.addingTimeInterval(1500), worked: 1500,
                                                   calendar: calendar))
            let tape = try XCTUnwrap(PetCamTape(record: record))
            shapes[tape.outcome, default: []].append(tape.shape)
            XCTAssertTrue((4...6).contains(tape.stills.count))
            XCTAssertTrue(PetCamTape.durationRange.contains(tape.duration), "\(tape.shape) runs \(tape.duration) s")
            // Timestamps run forward, except where the tape rewinds.
            for (a, b) in zip(tape.stills, tape.stills.dropFirst()) where b.stamp != .rewind {
                XCTAssertLessThanOrEqual(a.time, b.time)
            }
            XCTAssertTrue(tape.stills.allSatisfy { $0.time >= record.startedAt && $0.time <= record.endedAt })
            for still in tape.stills {
                switch still.shot.framing {
                case .wide: break
                case .spot(let spot): XCTAssertEqual(spot, record.camera, "the hidden camera's own view")
                case .closeUp(let place): XCTAssertEqual(place.spot, record.camera, "pushed in on its own view")
                }
            }
            XCTAssertEqual(tape.stills.filter { $0.stamp == .rewind }.count, tape.shape == .coldOpen ? 1 : 0)
            for (a, b) in zip(tape.stills, tape.stills.dropFirst()) {
                XCTAssertNotEqual(a.caption, b.caption, "each cut says something new")
            }
            let last = try XCTUnwrap(tape.stills.last)
            if record.outcome == .caught {
                XCTAssertEqual(last.stamp, .caught)
                XCTAssertEqual(last.shot.pet, .lensStare)
                XCTAssertTrue(tape.stills.contains { $0.shot.pet == .midAct })
            } else {
                XCTAssertTrue(tape.stills.contains { $0.shot.pet == .lieDown }, "the alibi: lying down, staring")
                XCTAssertTrue(tape.stills.contains { $0.shot.debrisFrom == record.strike && $0.caption.hasPrefix("[") },
                              "the strike is only heard")
                XCTAssertFalse(tape.stills.contains { $0.shot.pet == .midAct }, "and never seen")
                // The pet is on camera by about second three.
                var elapsed = 0.0
                for still in tape.stills {
                    if let place = still.shot.place, place.spot == record.camera { break }
                    elapsed += still.duration
                }
                XCTAssertLessThanOrEqual(elapsed, 3.0, "\(tape.shape): the pet walks in at \(elapsed) s")
                XCTAssertEqual(tape.stills.filter { $0.shot.debrisFrom != nil }.count, 1, "one short beat on the crash")
            }
            // A replay from the record is the same tape.
            XCTAssertEqual(PetCamTape(record: record), tape)
        }
        for (outcome, sequence) in shapes {
            XCTAssertEqual(Set(sequence).count, PetCamTape.Shape.allCases.count, "\(outcome) uses every shape")
            for (a, b) in zip(sequence, sequence.dropFirst()) {
                XCTAssertNotEqual(a, b, "never the same \(outcome) shape twice in a row")
            }
            print("Pet Cam tape shapes, \(outcome.rawValue): \(sequence.prefix(8).map { "\($0)" })")
        }
        XCTAssertEqual(Set(shapes.keys), [.caught, .missed])
    }

    func testTheTellIsNamedWhenItDecidedTheStrike() throws {
        let tuning = PetCamTuning(exceptionChance: 1, exceptionPull: 1)
        var game = PetCamGame(seed: 0xBEE, tuning: tuning, at: monday)
        let tell = try XCTUnwrap(game.setup.tell)
        XCTAssertEqual(game.setup.strike, tell.spot)
        game.start(id: "w", pick: game.setup.stare, dodge: nil, dare: false, plannedLength: 600, pet: pet, at: monday)
        let record = try XCTUnwrap(game.finish(endedAt: monday.addingTimeInterval(600), worked: 600, calendar: calendar))
        XCTAssertEqual(record.outcome, .missed, "following the stare against a wobble misses")
        XCTAssertEqual(record.captions.tell, "IT WAS ALREADY WOBBLING.")
        let tape = try XCTUnwrap(PetCamTape(record: record))
        XCTAssertEqual(tape.stills.last?.detail, "IT WAS ALREADY WOBBLING.", "the miss's last still says why")
    }

    func testAStopShowsOneFrozenStillThatGivesNothingAway() throws {
        var game = PetCamGame(seed: 0x5709, at: monday)
        let stare = game.setup.stare
        game.start(id: "s", pick: nil, dodge: nil, dare: true, plannedLength: 1500, pet: pet, at: monday)
        let record = try XCTUnwrap(game.stop(at: monday.addingTimeInterval(600), worked: 600, calendar: calendar))
        let tape = try XCTUnwrap(PetCamTape(record: record))
        XCTAssertEqual(tape.stills.count, 1)
        let still = try XCTUnwrap(tape.stills.first)
        XCTAssertEqual(still.stamp, .frozen)
        XCTAssertEqual(still.shot.framing, .wide)
        XCTAssertEqual(still.shot.place, .approach(stare), "heading where the frozen frame already showed")
        XCTAssertEqual(still.detail, "NO TAPE THIS TIME.")

        game.start(id: "c", pick: nil, dodge: nil, dare: false, plannedLength: 1500, pet: pet, at: monday)
        let cancel = try XCTUnwrap(game.stop(at: monday.addingTimeInterval(5), worked: 5, calendar: calendar))
        XCTAssertNil(PetCamTape(record: cancel))
    }

    func testTheFrozenFrameShowsTheStareAndTheTell() {
        let room = PetCamRoom.starter(at: monday)
        let setup = PetCamSetup(seed: 1, stare: .shelf, tell: PetCamTell(exception: .wobble, spot: .table),
                                tuning: .standard, preparedAt: monday)
        let shot = PetCamShot.frozenFrame(room: room, setup: setup)
        XCTAssertEqual(shot.framing, .wide)
        XCTAssertEqual(shot.pet, .stare(.shelf))
        XCTAssertEqual(shot.place, .home)
        XCTAssertEqual(shot.states, [.table: .wobbling])
        XCTAssertEqual(shot.objects.count, 3)
    }
}
