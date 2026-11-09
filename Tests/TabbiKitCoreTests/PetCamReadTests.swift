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
        // Not a coin flip: the stare alone beats guessing, at about 46%.
        XCTAssertEqual(random, 1.0 / 3, accuracy: 0.04)
        XCTAssertEqual(follow, 0.46, accuracy: 0.03)
        // Reading the one exception is worth about twenty points, at about
        // 68%: a wobble is a strong lean, not a sure thing.
        XCTAssertEqual(expert, 0.68, accuracy: 0.03)
        XCTAssertGreaterThan(expert - follow, 0.17)
        // Not solved: even the expert misses about one block in three, so
        // the miss stays the regular laugh it is meant to be.
        XCTAssertLessThan(expert, 0.72)
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

    func testLeftOutSinceRunsAtMostOneTapeInThree() throws {
        // Blocks back to back, so almost every object is under two hours
        // old and would get the SINCE form.
        var game = PetCamGame(seed: 0x51CE, at: monday)
        var ages: [String?] = []
        for index in 0..<30 {
            let start = monday.addingTimeInterval(Double(index) * 1600)
            game.start(id: "b\(index)", pick: nil, dodge: nil, dare: false, plannedLength: 1500, pet: pet, at: start)
            let record = try XCTUnwrap(game.finish(endedAt: start.addingTimeInterval(1500), worked: 1500,
                                                   calendar: calendar))
            ages.append(record.captions.age)
        }
        let since = ages.map(PetCamCaptions.isSinceForm)
        for start in 0..<(since.count - 2) {
            XCTAssertLessThanOrEqual(since[start..<start + 3].filter { $0 }.count, 1, "tapes \(start)...: \(ages)")
        }
        XCTAssertGreaterThanOrEqual(since.filter { $0 }.count, 8, "it still runs: \(ages)")
        XCTAssertTrue(PetCamCaptions.isSinceForm("MUG, LEFT OUT SINCE 09:00"))
        XCTAssertFalse(PetCamCaptions.isSinceForm("MUG, LEFT OUT 5 HOURS AGO"))
    }

    /// A finished tape block for hand-made histories.
    func block(_ id: String, outcome: PetCamBlockRecord.Outcome, strike: PetCamSpot, kind: PetCamObjectKind,
               camera: PetCamSpot? = nil, at end: Date) -> PetCamBlockRecord {
        let setup = PetCamSetup(seed: 1, stare: strike, tell: nil, tuning: .standard, preparedAt: end)
        return PetCamBlockRecord(
            id: id, setup: setup, camera: camera ?? (outcome == .caught ? strike : strike == .counter ? .shelf : .counter),
            picked: false, dodge: nil, dare: false, plannedLength: 1500, startedAt: end.addingTimeInterval(-1500),
            endedAt: end, worked: 1500, outcome: outcome, strike: strike,
            struck: PetCamObject(kind: kind, placedAt: end, serial: 0), room: .starter(at: end), pet: pet,
            captions: PetCamCaptionSet(opener: "", watch: "", strike: "", turn: "", closer: ""))
    }

    func testTheStrongCallbacksComeFirstAndAWreckOnlyWhenItIsInTheShot() {
        let now = monday.addingTimeInterval(4 * 3600)
        let mug = PetCamObject(kind: .mug, placedAt: now, serial: 7)
        var room = PetCamRoom.starter(at: monday)
        var random = PetCamRandom(seed: 2)
        room.strike(.table, at: monday.addingTimeInterval(600), blockID: "old", random: &random)
        func line(_ history: [PetCamBlockRecord], camera: PetCamSpot, outcome: PetCamBlockRecord.Outcome,
                  seed: UInt64) -> String? {
            PetCamCaptions.callback(strike: .table, struck: mug, room: room, camera: camera, outcome: outcome,
                                    history: history, at: now, seed: seed, calendar: calendar)
        }
        // Only the puddle to call back to: a catch, filmed by the side
        // table's own camera, gets it.
        XCTAssertEqual(line([], camera: .table, outcome: .caught, seed: 1), "RIGHT NEXT TO THE PUDDLE FROM 09:10")
        // A miss filmed over the counter cannot see the puddle, so it says
        // nothing rather than point at an empty picture.
        XCTAssertNil(line([], camera: .counter, outcome: .missed, seed: 1))
        // The same spot as last time beats the puddle on every seed.
        let last = [block("a", outcome: .missed, strike: .table, kind: .vase, at: monday.addingTimeInterval(3600))]
        for seed: UInt64 in 0..<40 {
            XCTAssertEqual(line(last, camera: .table, outcome: .caught, seed: seed), "THE SIDE TABLE AGAIN")
        }
        // A mug earlier today beats a mug earlier this week.
        let today = [block("m", outcome: .caught, strike: .counter, kind: .mug, at: monday.addingTimeInterval(7200))]
        for seed: UInt64 in 0..<40 {
            XCTAssertEqual(line(today, camera: .table, outcome: .caught, seed: seed), "2ND MUG TODAY")
        }
    }

    func testTheWantedObjectIsTheOneLongestAtLarge() throws {
        var game = PetCamGame(seed: 0x3A7, tuning: PetCamTuning(followStare: 1, exception: .none), at: monday)
        XCTAssertNil(game.setup.wanted, "nothing is wanted before the first tape")
        var strikes: [PetCamSpot: Bool] = [:]
        var wantedCatches = 0
        for index in 0..<40 {
            let start = monday.addingTimeInterval(Double(index) * 2400)
            let setup = game.setup
            if index > 0 {
                let wanted = try XCTUnwrap(setup.wanted, "block \(index + 1) has a WANTED object")
                // Every other object in the room was caught more recently
                // than the wanted one (or it was never caught with at all).
                let history = game.log.blocks
                let since = { (spot: PetCamSpot) in
                    PetCamSetup.wantedSince(game.room.object(at: spot)!.kind, history: history, before: start)!
                }
                for spot in PetCamSpot.allCases { XCTAssertLessThanOrEqual(since(wanted), since(spot)) }
                // It never moves the pet.
                var fresh = setup
                fresh.wanted = nil
                XCTAssertEqual(fresh.strike, setup.strike)
                strikes[wanted] = true
            }
            // Always hide the camera on the wanted spot, to catch it with it.
            game.start(id: "b\(index)", pick: setup.wanted, dodge: nil, dare: false, plannedLength: 1500, pet: pet,
                       at: start)
            let record = try XCTUnwrap(game.finish(endedAt: start.addingTimeInterval(1500), worked: 1500,
                                                   calendar: calendar))
            if record.outcome == .caught, record.strike == setup.wanted {
                wantedCatches += 1
                let line = try XCTUnwrap(record.captions.wanted)
                XCTAssertTrue(line.hasPrefix("WANTED "), line)
                let tape = try XCTUnwrap(PetCamTape(record: record))
                XCTAssertEqual(tape.stills.last?.detail, line, "the closer says how long it was wanted")
            } else {
                XCTAssertNil(record.captions.wanted)
            }
        }
        XCTAssertGreaterThan(wantedCatches, 0)
        XCTAssertEqual(strikes.count, 3, "the tag moves around the room")
        // Days at large read as days.
        XCTAssertEqual(PetCamCaptions.wanted(since: monday, at: monday.addingTimeInterval(3 * 86400), calendar: calendar),
                       "WANTED FOR 3 DAYS.")
        XCTAssertEqual(PetCamCaptions.wanted(since: monday, at: monday.addingTimeInterval(600), calendar: calendar),
                       "WANTED SINCE 09:00.")
        // An older save without the field still loads, with no tag.
        let setup = PetCamSetup(seed: 4, stare: .shelf, tell: nil, wanted: .table, tuning: .standard, preparedAt: monday)
        let data = try JSONEncoder().encode(setup)
        XCTAssertEqual(try JSONDecoder().decode(PetCamSetup.self, from: data), setup)
        var plain = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        plain["wanted"] = nil
        let old = try JSONDecoder().decode(PetCamSetup.self, from: JSONSerialization.data(withJSONObject: plain))
        XCTAssertNil(old.wanted)
    }

    func testTheDodgeLineIsChargedAsObstructionAndFiledAsOnePhrase() throws {
        var game = PetCamGame(seed: 7, tuning: PetCamTuning(followStare: 1, exception: .none), at: monday)
        game.start(id: "c", pick: nil, dodge: " my tax return ", dare: false, plannedLength: 600, pet: pet, at: monday)
        let record = try XCTUnwrap(game.finish(endedAt: monday.addingTimeInterval(600), worked: 600, calendar: calendar))
        XCTAssertEqual(record.outcome, .caught)
        XCTAssertEqual(record.captions.charge, "CHARGE: OBSTRUCTION OF MY TAX RETURN")
        XCTAssertFalse(record.captions.publicCharge?.contains("TAX") ?? true, "the shared charge keeps the dodge out")
        XCTAssertEqual(PetCamCaptions.chargeLabel, "CHARGE")
        XCTAssertEqual(PetCamCaptions.filedCharge("CHARGE: OBSTRUCTION OF MY TAX RETURN"),
                       "OBSTRUCTION OF MY\u{00A0}TAX\u{00A0}RETURN")
        XCTAssertEqual(PetCamCaptions.filedCharge("CHARGE: FISHING WITHOUT A LICENSE"), "FISHING WITHOUT A LICENSE")
        XCTAssertEqual(PetCamCaptions.keepingDodgeTogether("CHARGE: OBSTRUCTION OF MY TAX RETURN"),
                       "CHARGE: OBSTRUCTION OF MY\u{00A0}TAX\u{00A0}RETURN", "the tape wraps before the dodge too")
        XCTAssertEqual(PetCamCaptions.ownerAway(1500), "OWNER AWAY 25:00.")
        XCTAssertEqual(PetCamCaptions.ownerAway(3725), "OWNER AWAY 1:02:05.")
    }

    func testAShapeIsNeverOneOfTheLastTwo() {
        for seed: UInt64 in 0..<200 {
            for recent in [[PetCamTape.Shape.straight, .closer], [.coldOpen, .straight], [.closer, .coldOpen]] {
                XCTAssertFalse(recent.contains(PetCamTape.shape(seed: seed, recent: recent)))
            }
            XCTAssertNotEqual(PetCamTape.shape(seed: seed, recent: [.closer]), .closer)
        }
        XCTAssertEqual(Set((0..<60).map { PetCamTape.shape(seed: $0, recent: []) }).count, 3)
    }

    func testTweensSlideThePetBetweenTwoStillsOfOneCamera() throws {
        var game = PetCamGame(seed: 0x7EE, tuning: PetCamTuning(followStare: 1, exception: .none), at: monday)
        game.start(id: "t", pick: nil, dodge: nil, dare: false, plannedLength: 600, pet: pet, at: monday)
        let record = try XCTUnwrap(game.finish(endedAt: monday.addingTimeInterval(600), worked: 600, calendar: calendar))
        let tape = try XCTUnwrap(PetCamTape(record: record))
        let sneak = try XCTUnwrap(tape.stills.firstIndex { if case .sneak = $0.shot.pet { true } else { false } })
        let next = tape.stills[sneak + 1]
        let tweens = PetCamTape.tweens(from: tape.stills[sneak], to: next, count: 3)
        XCTAssertEqual(tweens.count, 3)
        XCTAssertTrue(tweens.allSatisfy { $0.pet == next.shot.pet && $0.framing == next.shot.framing })
        XCTAssertNotEqual(tweens.first?.petOffset, tweens.last?.petOffset, "the pet moves")
        XCTAssertEqual(PetCamTape.tweens(from: tape.stills[0], to: tape.stills[1], count: 3), [], "a cut between cameras")
    }

    func testACallbackShowsWithinFiveTapesAndNoLineDoublesItsPunctuation() throws {
        // Many fresh games, catches and misses mixed, blocks back to back:
        // the history gives a callback by the fifth tape in every one, and
        // no caption or line under it ever reads ".." or ".,".
        var latest = 0
        for seed: UInt64 in 0..<120 {
            var game = PetCamGame(seed: seed &* 104_729 &+ 7, at: monday)
            var roll = PetCamRandom(seed: seed, stream: "player")
            var first: Int?
            for index in 0..<6 {
                let start = monday.addingTimeInterval(Double(index) * 720)
                let strike = game.setup.strike
                let pick = roll.unit() < 0.5 ? strike : PetCamSpot.allCases.first { $0 != strike }
                game.start(id: "b\(index)", pick: pick, dodge: index == 2 ? "my essay." : nil, dare: false,
                           plannedLength: 600, pet: pet, at: start)
                let record = try XCTUnwrap(game.finish(endedAt: start.addingTimeInterval(600), worked: 600,
                                                       calendar: calendar))
                if record.captions.callback != nil, first == nil { first = index + 1 }
                for still in try XCTUnwrap(PetCamTape(record: record)).stills {
                    for line in [still.caption, still.detail, PetCamCaptions.spoken(still.caption, still.detail)]
                        .compactMap({ $0 }) {
                        XCTAssertFalse(line.contains("..") || line.contains(".,") || line.contains(",."), line)
                    }
                }
            }
            latest = max(latest, try XCTUnwrap(first, "seed \(seed) never called back"))
        }
        XCTAssertLessThanOrEqual(latest, 5)
        XCTAssertEqual(PetCamCaptions.spoken("CAM 3. ALL QUIET.", "NO WITNESSES."), "CAM 3. ALL QUIET. NO WITNESSES.")
        XCTAssertEqual(PetCamCaptions.spoken("SUSPECT RETURNS", "2ND MUG TODAY"), "SUSPECT RETURNS. 2ND MUG TODAY")
        XCTAssertEqual(PetCamCaptions.spoken("[CRASH]", nil), "[CRASH]")
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
        words += game.log.blocks.compactMap(\.captions.windUp) + game.log.blocks.compactMap(\.captions.wanted)
            + [PetCamCaptions.ownerAway(1500)]
        let text = words.joined(separator: " ").lowercased()
        for banned in ["study", "studied", "focus", "exam", "homework", "pomodoro", "timer"] {
            XCTAssertFalse(text.contains(banned), "a shared tape never mentions studying: \(banned)")
        }
        XCTAssertFalse(text.contains("\u{2014}"))
        XCTAssertEqual(text, text.filter { $0.isASCII }, "captions are plain ASCII")
    }

    // MARK: Tapes

    func testEveryTapeIsFiveToSevenStillsOfTenToFifteenSeconds() throws {
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
            XCTAssertTrue((5...7).contains(tape.stills.count), "\(tape.shape) has \(tape.stills.count) stills")
            XCTAssertTrue(PetCamTape.durationRange.contains(tape.duration), "\(tape.shape) runs \(tape.duration) s")
            // Timestamps run forward, except where the tape rewinds.
            for (a, b) in zip(tape.stills, tape.stills.dropFirst()) where b.stamp != .rewind {
                XCTAssertLessThanOrEqual(a.time, b.time)
            }
            XCTAssertTrue(tape.stills.allSatisfy { $0.time >= record.startedAt && $0.time <= record.endedAt })
            let kind = try XCTUnwrap(record.struck?.kind)
            for still in tape.stills {
                switch still.shot.framing {
                case .wide: break
                case .spot(let spot): XCTAssertEqual(spot, record.camera, "the hidden camera's own view")
                case .closeUp(let place): XCTAssertEqual(place.spot, record.camera, "pushed in on its own view")
                case .wreck(let spot, let hidden):
                    XCTAssertEqual(spot, record.strike, "the close-up is of the wreck just made")
                    XCTAssertEqual(hidden, record.outcome == .caught, "a miss sees it from CAM 1")
                }
            }
            XCTAssertEqual(tape.stills.filter { $0.stamp == .rewind }.count, tape.shape == .coldOpen ? 1 : 0)
            for (a, b) in zip(tape.stills, tape.stills.dropFirst()) where b.shot.debrisStep == 0 {
                XCTAssertNotEqual(a.caption, b.caption, "each cut says something new")
            }
            let acts = tape.stills.compactMap { still -> PetCamObjectKind? in
                switch still.shot.pet {
                case .act(let kind), .caughtMidAct(let kind): kind
                default: nil
                }
            }
            let last = try XCTUnwrap(tape.stills.last)
            if record.outcome == .caught {
                XCTAssertEqual(last.stamp, .caught)
                XCTAssertEqual(last.cue, .stamp)
                XCTAssertFalse(acts.isEmpty)
                XCTAssertTrue(acts.allSatisfy { $0 == kind }, "the act is the \(kind)'s own")
                let strike = try XCTUnwrap(tape.stills.first { $0.cue == .strike(kind) })
                XCTAssertEqual(strike.detail, record.captions.tell ?? PetCamCaptions.sound(of: kind),
                               "the act plays under its own sound")
                switch tape.shape {
                case .straight:
                    XCTAssertEqual(last.shot.pet, .lensStare)
                case .coldOpen:
                    XCTAssertEqual(tape.stills.first?.shot.framing, .wreck(record.camera, hidden: true))
                    XCTAssertNil(tape.stills.first?.shot.pet, "the cold open is the wreck alone")
                case .closer:
                    XCTAssertEqual(last.shot.pet, .caughtMidAct(kind), "frozen mid-air or with its mouth full")
                }
            } else {
                XCTAssertTrue(tape.stills.contains { $0.shot.pet == .lieDown }, "the alibi: lying down, staring")
                XCTAssertTrue(tape.stills.contains { $0.shot.debrisFrom == record.strike && $0.caption.hasPrefix("[") },
                              "the strike is only heard")
                XCTAssertEqual(acts, [], "and never seen")
                XCTAssertEqual(last.shot.framing, .wreck(try XCTUnwrap(record.strike), hidden: false),
                               "every miss ends on the wreck")
                if let place = last.shot.place, let pose = last.shot.pet {
                    XCTAssertTrue(PetCamScene.showsWholePet(at: place, pose: pose, in: last.shot),
                                  "the witness is all in the picture or not in it")
                }
                // The pet is on camera by about second three.
                var elapsed = 0.0
                for still in tape.stills {
                    if let place = still.shot.place, place.spot == record.camera { break }
                    elapsed += still.duration
                }
                XCTAssertLessThanOrEqual(elapsed, 3.0, "\(tape.shape): the pet walks in at \(elapsed) s")
                let crash = tape.stills.filter { $0.shot.debrisFrom != nil }
                XCTAssertEqual(crash.map(\.shot.debrisStep), [0, 1], "the debris lands, then skids in")
                XCTAssertEqual(crash.map(\.shake), [true, false])
            }
            // A replay from the record is the same tape.
            XCTAssertEqual(PetCamTape(record: record), tape)
        }
        for (outcome, sequence) in shapes {
            for start in 0..<max(sequence.count - 2, 0) {
                XCTAssertEqual(Set(sequence[start..<start + 3]).count, 3, "any three \(outcome) tapes in a row differ")
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
