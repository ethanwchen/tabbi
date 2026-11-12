import CryptoKit
import Foundation
import XCTest
@testable import TabbiKitCore

/// Pins the Radiant effects for the Windows port (`shared/fixtures/pets/radiant.json`):
/// how every set of Radiant items worn together is laid out, digests of
/// every frame and tick of every animation for each effect on five breeds
/// and every combination on the British Shorthair, full size and under the
/// notch's ceiling, and readable ticks of a few loops. Record with
/// `TABBI_RECORD_FIXTURES=1`.
final class RadiantGoldenTests: XCTestCase {
    func testRadiantMatchesGoldenFixture() throws {
        let url = PetGoldenFixtures.folder.appendingPathComponent("radiant.json")
        let value = RadiantGoldenFixtures.file()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try PetGoldenFixtures.encode(value).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(RadiantGoldenFixtures.File.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.layouts, value.layouts, "radiant.json layouts no longer match")
        XCTAssertEqual(stored.digests, value.digests, "radiant.json digests no longer match")
        XCTAssertEqual(stored.frames, value.frames, "radiant.json frames no longer match")
    }
}

enum RadiantGoldenFixtures {
    struct Worn: Codable, Equatable, Hashable {
        var item: String
        var intensity: String
    }

    struct Dress: Codable, Equatable {
        var breed: String
        var outfit: String
        var accessories: [String]
        var radiant: [Worn]

        init(_ breed: PetBreed, _ items: [PetItem], _ intensities: [PetRadiantIntensity]) {
            let (outfit, accessories) = RadiantAudit.wearing(items)
            self.breed = breed.rawValue
            self.outfit = outfit.rawValue
            self.accessories = accessories.map(\.rawValue)
            radiant = zip(items, intensities).map { Worn(item: $0.id, intensity: $1.rawValue) }
        }

        func clip(_ animation: PetAnimation, ceiling: Int?) -> PetClip {
            var look: [PetItem: PetRadiantIntensity] = [:]
            for worn in radiant { look[PetItem(id: worn.item)!] = PetRadiantIntensity(rawValue: worn.intensity)! }
            return PetComposer.clip(animation, for: PetBreed(rawValue: breed)!, outfit: PetOutfit(rawValue: outfit)!,
                                    accessories: accessories.map { PetAccessory(rawValue: $0)! },
                                    radiant: PetRadiantLook(look), ceiling: ceiling)
        }
    }

    struct Layout: Codable, Equatable {
        struct Entry: Codable, Equatable {
            var item: String
            var intensity: String
            var placement: Int
            var turn: Int?
        }

        var worn: [Worn]
        var entries: [Entry]
        var cycles: Int
    }

    struct Digest: Codable, Equatable {
        var dress: Dress
        var ceiling: Int?
        var frameCount: Int
        var sha256: String
    }

    struct Frames: Codable, Equatable {
        var dress: Dress
        var animation: String
        var ceiling: Int?
        var frame: Int
        /// One run-length frame (`PetGoldenFixtures.runLength`) per tick.
        var ticks: [String]
    }

    struct File: Codable, Equatable {
        var schema: String
        var version: Int
        var layouts: [Layout]
        var digests: [Digest]
        var frames: [Frames]
    }

    /// Every set of Radiant items that can be worn together (one, two or
    /// three), with every mix of intensities.
    static var wornSets: [[Worn]] {
        let singles = PetRadiant.eligibleItems.map { [$0] }
        var sets: [[Worn]] = []
        for items in singles + RadiantAudit.combinations {
            for mix in 0..<(1 << items.count) {
                sets.append(items.enumerated().map { n, item in
                    Worn(item: item.id, intensity: (mix >> n) & 1 == 0 ? "bold" : "subtle")
                })
            }
        }
        return sets
    }

    static func file() -> File {
        let layouts = wornSets.map { worn -> Layout in
            var look: [PetItem: PetRadiantIntensity] = [:]
            for w in worn { look[PetItem(id: w.item)!] = PetRadiantIntensity(rawValue: w.intensity)! }
            let (outfit, accessories) = RadiantAudit.wearing(worn.map { PetItem(id: $0.item)! })
            let layout = RadiantLayout.resolve(PetRadiantLook(look), outfit: outfit, accessories: accessories)!
            return Layout(worn: worn, entries: layout.entries.map {
                .init(item: $0.item.id, intensity: $0.intensity.rawValue, placement: $0.placement, turn: $0.turn)
            }, cycles: layout.cycles)
        }
        var dresses: [Dress] = []
        for item in PetRadiant.eligibleItems {
            for breed in [PetBreed.britishShorthair, .blackCat, .goldenRetriever, .dachshund, .shihTzu] {
                for intensity in [PetRadiantIntensity.bold, .subtle] { dresses.append(Dress(breed, [item], [intensity])) }
            }
        }
        for items in RadiantAudit.combinations {
            dresses.append(Dress(.britishShorthair, items, items.map { _ in .bold }))
        }
        let jobs = dresses.flatMap { dress in [nil, 2].map { (dress, $0) } }
        let results = Results(count: jobs.count)
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            results[index] = digest(jobs[index].0, ceiling: jobs[index].1)
        }
        let frames = [
            Frames(dress: Dress(.britishShorthair, [.accessory(.blindfoldedSorcerer)], [.bold]), animation: "idle",
                   ceiling: nil, frame: 0, ticks: []),
            Frames(dress: Dress(.blackCat, [.accessory(.rainCloud)], [.bold]), animation: "idle", ceiling: 2, frame: 0,
                   ticks: []),
            Frames(dress: Dress(.goldenRetriever, [.outfit(.whiteCoat), .accessory(.graduationCap)], [.bold, .bold]),
                   animation: "celebrate", ceiling: nil, frame: 2, ticks: []),
        ].map { entry -> Frames in
            var entry = entry
            let frame = entry.dress.clip(PetAnimation(rawValue: entry.animation)!, ceiling: entry.ceiling).frames[entry.frame]
            let ticks = frame.itemFrames.isEmpty ? [frame.canvas] : frame.itemFrames
            entry.ticks = ticks.map { PetGoldenFixtures.runLength(PetGoldenFixtures.rows($0)) }
            return entry
        }
        return File(schema: PetGoldenFixtures.schema, version: PetGoldenFixtures.version, layouts: layouts,
                    digests: results.all, frames: frames)
    }

    /// The `composed-digests.json` digest of every animation of a dress.
    static func digest(_ dress: Dress, ceiling: Int?) -> Digest {
        var bytes: [UInt8] = []
        var frameCount = 0
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { bytes += $0 } }
        func symbols(_ canvas: PetCanvas) -> [UInt8] {
            canvas.pixels.map { $0?.symbol.asciiValue ?? UInt8(ascii: ".") }
        }
        for animation in PetAnimation.allCases {
            let frames = dress.clip(animation, ceiling: ceiling).frames
            frameCount += frames.count
            bytes += Array(animation.rawValue.utf8) + [0]
            append(UInt32(frames.count))
            for frame in frames {
                append(frame.duration.bitPattern)
                bytes.append(frame.bubbleAnchor == nil ? 0 : 1)
                append(Int32(frame.bubbleAnchor?.x ?? 0))
                append(Int32(frame.bubbleAnchor?.y ?? 0))
                bytes += symbols(frame.canvas)
                if !frame.itemFrames.isEmpty {
                    append(UInt32(frame.itemFrames.count))
                    for canvas in frame.itemFrames { bytes += symbols(canvas) }
                }
            }
        }
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return Digest(dress: dress, ceiling: ceiling, frameCount: frameCount, sha256: hash)
    }

    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Digest?]

        init(count: Int) { values = Array(repeating: nil, count: count) }

        subscript(index: Int) -> Digest? {
            get { lock.withLock { values[index] } }
            set { lock.withLock { values[index] = newValue } }
        }

        var all: [Digest] { lock.withLock { values.map { $0! } } }
    }
}
