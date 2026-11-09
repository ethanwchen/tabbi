import Foundation
@testable import TabbiKitCore
import XCTest

/// The tapes keep saying new things: over a scripted 30-block session no
/// line comes back to its beat within four tapes that use that beat, and a
/// callback that names a spot only sits on a still filmed at that spot or
/// on CAM 1.
final class PetCamCaptionsTests: XCTestCase {
    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    /// Thirty 25-minute blocks, five a day, catching about every other one.
    static func session(seed: UInt64) -> [PetCamBlockRecord] {
        var game = PetCamGame(seed: seed, at: start)
        let pet = PetProfile(name: "", breed: .britishShorthair)
        var records: [PetCamBlockRecord] = []
        var date = start
        for index in 0..<30 {
            let strike = game.setup.strike
            let pick = index % 5 == 1 || index % 5 == 3 ? PetCamSpot.allCases.first { $0 != strike } : strike
            game.start(id: "s\(seed)-\(index)", pick: pick, dodge: nil, dare: false, plannedLength: 1500, pet: pet,
                       at: date)
            date.addTimeInterval(1500)
            if let record = game.finish(endedAt: date, worked: 1500) { records.append(record) }
            date.addTimeInterval(index % 5 == 4 ? 18 * 3600 : 600)
        }
        return records
    }

    /// A beat: where its line is kept, the templates it is drawn from, and
    /// which tapes use it (nil: every tape).
    struct Beat {
        let name: String
        let line: (PetCamCaptionSet) -> String?
        let templates: [String]
        let outcome: PetCamBlockRecord.Outcome?
    }

    static var beats: [Beat] {
        let grammar = PetCamCaptions.grammar
        return [
            Beat(name: "opener", line: \.opener, templates: grammar.opener + grammar.openerDays + grammar.newArrival,
                 outcome: nil),
            Beat(name: "rewind", line: \.rewind, templates: grammar.rewind, outcome: nil),
            Beat(name: "motion", line: \.watch, templates: grammar.motion, outcome: .caught),
            Beat(name: "strike", line: \.strike, templates: grammar.act + grammar.eaten, outcome: .caught),
            Beat(name: "noticed", line: \.turn, templates: grammar.noticed, outcome: .caught),
            Beat(name: "windUp", line: \.windUp, templates: grammar.windUp, outcome: .caught),
            Beat(name: "aftermath", line: \.aftermath, templates: grammar.aftermath, outcome: .caught),
            Beat(name: "quiet", line: \.watch, templates: grammar.quiet, outcome: .missed),
            Beat(name: "returns", line: \.turn, templates: grammar.returns, outcome: .missed),
            Beat(name: "innocent", line: \.closer, templates: grammar.innocent, outcome: .missed),
            Beat(name: "alibi", line: \.alibi, templates: grammar.alibiOpen, outcome: .missed),
            Beat(name: "meanwhile", line: \.reveal, templates: grammar.meanwhile, outcome: .missed),
            Beat(name: "offCamera", line: \.offCamera, templates: grammar.offCamera, outcome: .missed),
            Beat(name: "walkBy", line: \.walkBy, templates: grammar.walkBy, outcome: .missed),
            Beat(name: "denial", line: \.denial, templates: grammar.denial, outcome: .missed),
        ]
    }

    func testNoLineComesBackToItsBeatWithinFourTapesThatUseIt() throws {
        for seed: UInt64 in [0x30, 0xBEA7, 0x5EED_0F] {
            let records = Self.session(seed: seed)
            XCTAssertEqual(records.count, 30)
            for beat in Self.beats {
                // The template each tape that uses the beat drew, oldest first.
                var drawn: [Int] = []
                for record in records where beat.outcome == nil || record.outcome == beat.outcome {
                    let line = try XCTUnwrap(beat.line(record.captions), "\(beat.name) on \(record.outcome)")
                    let template = try XCTUnwrap(beat.templates.firstIndex { PetCamCaptions.matches(line, template: $0) },
                                                 "\(line) is a \(beat.name) line")
                    XCTAssertFalse(drawn.suffix(PetCamCaptions.freshness).contains(template),
                                   "\(beat.name) repeats \(line) within four tapes (seed \(seed))")
                    drawn.append(template)
                }
            }
            if seed == 0x30, let last = records.last, let tape = PetCamTape(record: last) {
                // Tape 30, as the plan asks to watch it.
                print("Tape 30 (\(last.outcome), \(tape.shape)): "
                      + tape.stills.map { PetCamCaptions.spoken($0.caption, $0.detail) }.joined(separator: " / "))
            }
        }
    }

    func testACallbackNamingASpotIsFilmedThereOrOnCAM1() throws {
        var named = 0
        for seed: UInt64 in [0x30, 0xBEA7, 0x5EED_0F, 0xCA11] {
            for record in Self.session(seed: seed) {
                let tape = try XCTUnwrap(PetCamTape(record: record))
                for still in tape.stills {
                    for text in [still.caption, still.detail].compactMap({ $0 }) {
                        guard text == record.captions.callback, let spot = PetCamCaptions.spotNamed(in: text) else {
                            continue
                        }
                        named += 1
                        XCTAssertTrue(["CAM 1", "CAM \(spot.cameraNumber)"].contains(still.cameraLabel),
                                      "\(text) on \(still.cameraLabel)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(named, 5, "the sessions have callbacks that name a spot")
    }
}
