import CoreGraphics
import Foundation
import Testing
import TabbiKitCore
import UIKit
@testable import TabbiPhone

/// The share clip's words stay where no feed draws over them: every beat of
/// every clip shape, catch and miss, with and without the player's words,
/// at rest and mid-jolt, is drawn as words only, and the drawn pixels must
/// sit inside the canvas, below its top 200 pixels, above its bottom 280
/// and left of its last 120.
@Suite @MainActor struct TapeCardLayoutTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    /// A dodge as long as the field keeps, so the headline wraps its most.
    static let longDodge = "the chapter nine practice problems for organic chemistry before friday"

    /// Twelve blocks through the real game: catches and misses in turn,
    /// every third with a dodge, a 25-minute block each.
    static func records() -> [PetCamBlockRecord] {
        var game = PetCamGame(seed: 0x5AFE_C0DE, at: t0)
        let pet = PetProfile(name: "Mochi", breed: .britishShorthair, outfit: .cozyHoodie, accessories: [.beanie])
        var date = t0
        var records: [PetCamBlockRecord] = []
        for index in 0..<12 {
            let strike = game.setup.strike
            let pick = index.isMultiple(of: 2) ? strike : PetCamSpot.allCases.first { $0 != strike }
            game.start(id: "b\(index)", pick: pick, dodge: index % 3 == 0 ? longDodge : nil, dare: false,
                       plannedLength: 1500, pet: pet, at: date)
            date.addTimeInterval(1500)
            if let record = game.finish(endedAt: date, worked: 1500) { records.append(record) }
            date.addTimeInterval(600)
        }
        return records
    }

    @Test func everyWordOfEveryBeatSitsWhereNoFeedDraws() throws {
        let records = Self.records()
        let shapes = Set(records.compactMap { record in record.shape.map { "\(record.outcome)-\($0)" } })
        #expect(shapes.count == 6, "every catch and miss shape is drawn: \(shapes.sorted())")
        let area = TapeCard.wordsArea
        var beats = 0
        for record in records {
            let clip = try #require(PetCamTape.clip(record), "a clip of \(record.outcome)")
            for includeDodge in [false, true] {
                let headline = PetCamCaptions.caseLine(record, includeDodge: includeDodge) ?? ""
                // The headline never needs a fourth line, nor the caption a third.
                #expect(Self.lines(headline, size: TapeCard.headlineSize * 0.6, weight: .heavy) <= 3, "\(headline)")
                for still in clip {
                    let card = TapeCard(record: record, still: still, caseNumber: 4, headline: headline,
                                        grainFrame: 0, textOnly: true)
                    #expect(Self.lines(card.caption, size: TapeCard.captionSize * 0.85, weight: .bold) <= 2,
                            "\(card.caption)")
                    // At rest, and as far as a jolt or the stamp's shake knocks it.
                    var moves: [(offset: CGFloat, zoom: CGFloat)] = [(0, 1)]
                    if still.shake || still.stamp == .caught { moves += [(26, 1), (-20, 1)] }
                    if still.punchIn { moves.append((0, 1.22)) }
                    for move in moves {
                        var moved = card
                        moved.offset = move.offset
                        moved.zoom = move.zoom
                        let image = try TapeExporter.render(moved)
                        let box = try #require(Self.inkBounds(image), "words on \(still.caption)")
                        #expect(area.contains(box), "\(record.outcome) \(still.caption) \(move): words at \(box)")
                        beats += 1
                    }
                }
            }
        }
        #expect(beats >= 100)
    }

    /// How many lines `text` takes across the words' width at `size`.
    static func lines(_ text: String, size: CGFloat, weight: UIFont.Weight) -> Int {
        let font = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        let box = (PetCamCaptions.keepingDodgeTogether(text) as NSString).boundingRect(
            with: CGSize(width: TapeCard.wordsArea.width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin, attributes: [.font: font], context: nil)
        return Int((box.height / font.lineHeight).rounded())
    }

    /// The smallest rectangle holding every pixel drawn, in the frame's
    /// coordinates (y down); nil when nothing is drawn.
    static func inkBounds(_ image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        // The bitmap's rows run top down, as the frame's do.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
