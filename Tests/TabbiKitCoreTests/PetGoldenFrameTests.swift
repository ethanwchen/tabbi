import CryptoKit
import Foundation
import TabbiKitCore
import XCTest

/// Pins every composed pet frame to golden fixtures in `shared/fixtures/pets`.
///
/// The fixtures were written by the Swift art (string grids in `Pets/Art`)
/// before it moved to JSON, so this proves the move changes no pixel, and the
/// Windows port checks its own composer against the same files.
/// Run with `TABBI_RECORD_FIXTURES=1` to rewrite them after an intended art
/// change; the diff then shows exactly which pets changed.
///
/// Encodings (documented for other clients in `shared/fixtures/pets/README.md`):
/// - A frame is `PetComposer.frameSize` rows of role symbols
///   (`PetPaletteRole.symbol`, `.` for transparent).
/// - A digest is the SHA-256 of every frame of every animation, in
///   `PetAnimation.allCases` order, written as: animation name and a 0 byte,
///   the frame count (UInt32), then per frame the duration (Float64 bits),
///   a bubble anchor flag byte with x and y (Int32 each, 0 when absent) and
///   the row-major symbol bytes. A frame where an animated costume item
///   moves then adds its item frame count (UInt32) and each item frame's
///   symbol bytes. All integers are little-endian.
final class PetGoldenFrameTests: XCTestCase {
    func testComposedFrameDigestsMatchGoldenFixture() throws {
        try check(PetGoldenFixtures.digests(), file: "composed-digests.json")
    }

    func testComposedFramesMatchGoldenFixture() throws {
        try check(PetGoldenFixtures.frames(), file: "frames.json")
    }

    func testBreedPalettesMatchGoldenFixture() throws {
        try check(PetGoldenFixtures.palettes(), file: "palettes.json")
    }

    func testRunLengthEncodingRoundTrips() {
        let canvas = PetComposer.sitting(.calico, outfit: .scrubs, accessories: [.stethoscope])
        let rows = PetGoldenFixtures.rows(canvas)
        XCTAssertEqual(PetGoldenFixtures.decodeRunLength(PetGoldenFixtures.runLength(rows)), rows)
    }

    // MARK: Helpers

    private func check<Value: Codable & Equatable>(_ value: Value, file: String) throws {
        let url = PetGoldenFixtures.folder.appendingPathComponent(file)
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: PetGoldenFixtures.folder, withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(value).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored, value, "\(file) no longer matches the composed pets")
    }
}

/// Builds the golden pet fixtures from the live Swift composer.
enum PetGoldenFixtures {
    static let schema = "tabbi.pets.golden"
    static let version = 1

    static var folder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/pets")
    }

    /// One dressed pet: the unit a digest or a frame list covers.
    struct Dress: Codable, Equatable {
        var breed: String
        var outfit: String
        var accessories: [String]

        init(_ breed: PetBreed, _ outfit: PetOutfit = .none, _ accessories: [PetAccessory] = []) {
            self.breed = breed.rawValue
            self.outfit = outfit.rawValue
            self.accessories = accessories.map(\.rawValue)
        }

        var clips: PetClipSet {
            PetClipSet(
                breed: PetBreed(rawValue: breed)!,
                outfit: PetOutfit(rawValue: outfit)!,
                accessories: accessories.map { PetAccessory(rawValue: $0)! }
            )
        }
    }

    /// Every breed, bare, in each outfit, in each accessory, and in a few
    /// full looks that stack all three accessory slots on an outfit.
    static var digestDresses: [Dress] {
        let looks: [(PetOutfit, [PetAccessory])] = [
            (.scrubs, [.stethoscope, .roundGlasses, .surgicalCap]),
            (.whiteCoat, [.bowTie, .coolSunglasses, .headMirror]),
            (.dinosaurHoodie, [.scarf, .pirateHat]),
            (.wizardRobe, [.chunkyHeadphones, .blindfoldedSorcerer]),
        ]
        return PetBreed.allCases.flatMap { breed in
            PetOutfit.allCases.map { Dress(breed, $0) }
                + PetAccessory.allCases.map { Dress(breed, .none, [$0]) }
                + looks.map { Dress(breed, $0.0, $0.1) }
        }
    }

    // MARK: Digests

    struct DigestFile: Codable, Equatable {
        var schema: String
        var version: Int
        var frameSize: Int
        var dresses: [Entry]

        struct Entry: Codable, Equatable {
            var dress: Dress
            var frameCount: Int
            var sha256: String
        }
    }

    /// Composes every dress on all cores: the corpus is 76,500 frames,
    /// which takes about a minute on one core in a debug build.
    static func digests() -> DigestFile {
        let dresses = digestDresses
        let entries = Results(count: dresses.count)
        DispatchQueue.concurrentPerform(iterations: dresses.count) { index in
            entries[index] = digest(dresses[index])
        }
        return DigestFile(schema: schema, version: version, frameSize: PetComposer.frameSize, dresses: entries.all)
    }

    private static func digest(_ dress: Dress) -> DigestFile.Entry {
        let clips = dress.clips
        var bytes: [UInt8] = []
        var frameCount = 0
        for animation in PetAnimation.allCases {
            let frames = clips[animation].frames
            frameCount += frames.count
            bytes += Array(animation.rawValue.utf8) + [0]
            append(UInt32(frames.count), to: &bytes)
            for frame in frames {
                append(frame.duration.bitPattern, to: &bytes)
                bytes.append(frame.bubbleAnchor == nil ? 0 : 1)
                append(Int32(frame.bubbleAnchor?.x ?? 0), to: &bytes)
                append(Int32(frame.bubbleAnchor?.y ?? 0), to: &bytes)
                bytes += symbols(frame.canvas)
                if !frame.itemFrames.isEmpty {
                    append(UInt32(frame.itemFrames.count), to: &bytes)
                    for canvas in frame.itemFrames { bytes += symbols(canvas) }
                }
            }
        }
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return .init(dress: dress, frameCount: frameCount, sha256: hash)
    }

    /// Collects results written from `concurrentPerform` (the package
    /// targets macOS 14, which has no `Mutex`).
    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [DigestFile.Entry?]

        init(count: Int) { values = Array(repeating: nil, count: count) }

        subscript(index: Int) -> DigestFile.Entry? {
            get { lock.withLock { values[index] } }
            set { lock.withLock { values[index] = newValue } }
        }

        var all: [DigestFile.Entry] { lock.withLock { values.map { $0! } } }
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to bytes: inout [UInt8]) {
        withUnsafeBytes(of: value.littleEndian) { bytes += $0 }
    }

    private static func symbols(_ canvas: PetCanvas) -> [UInt8] {
        canvas.pixels.map { $0?.symbol.asciiValue ?? UInt8(ascii: ".") }
    }

    // MARK: Frames

    /// Readable frames for a compact subset: every animation for a cat and a
    /// dog, and the sitting frame of every breed and every item.
    struct FrameFile: Codable, Equatable {
        var schema: String
        var version: Int
        var frameSize: Int
        var clips: [Clip]
        var sitting: [Sitting]

        struct Clip: Codable, Equatable {
            var dress: Dress
            var animation: String
            var loops: Bool
            var frames: [Frame]
        }

        struct Frame: Codable, Equatable {
            var duration: Double
            var bubbleAnchor: [Int]?
            /// Run-length encoded rows, see `runLength(_:)`.
            var rle: String
        }

        struct Sitting: Codable, Equatable {
            var dress: Dress
            var rle: String
        }
    }

    static func frames() -> FrameFile {
        let clips = [PetBreed.orangeTabby, .goldenRetriever].flatMap { breed in
            let set = PetClipSet(breed: breed)
            return PetAnimation.allCases.map { animation in
                let clip = set[animation]
                return FrameFile.Clip(
                    dress: Dress(breed), animation: animation.rawValue, loops: clip.loops,
                    frames: clip.frames.map { frame in
                        FrameFile.Frame(
                            duration: frame.duration,
                            bubbleAnchor: frame.bubbleAnchor.map { [$0.x, $0.y] },
                            rle: runLength(rows(frame.canvas))
                        )
                    }
                )
            }
        }
        let dresses = PetBreed.allCases.map { Dress($0) }
            + PetOutfit.allCases.dropFirst().map { Dress(.orangeTabby, $0) }
            + PetAccessory.allCases.map { Dress(.orangeTabby, .none, [$0]) }
            + PetOutfit.allCases.dropFirst().map { Dress(.goldenRetriever, $0) }
            + PetAccessory.allCases.map { Dress(.goldenRetriever, .none, [$0]) }
        let sitting = dresses.map { dress in
            FrameFile.Sitting(dress: dress, rle: runLength(rows(PetComposer.sitting(
                PetBreed(rawValue: dress.breed)!,
                outfit: PetOutfit(rawValue: dress.outfit)!,
                accessories: dress.accessories.map { PetAccessory(rawValue: $0)! }
            ))))
        }
        return FrameFile(schema: schema, version: version, frameSize: PetComposer.frameSize, clips: clips, sitting: sitting)
    }

    static func rows(_ canvas: PetCanvas) -> [String] {
        let symbols = symbols(canvas)
        return (0..<canvas.height).map { y in
            String(decoding: symbols[(y * canvas.width)..<((y + 1) * canvas.width)], as: UTF8.self)
        }
    }

    /// Rows joined by `/`, each a list of runs written as an optional count
    /// and a symbol: `12.3B.` is twelve transparent pixels, three `B`, one
    /// transparent.
    static func runLength(_ rows: [String]) -> String {
        rows.map { row in
            var out = "", previous: Character?, count = 0
            func flush() {
                guard let previous else { return }
                out += (count > 1 ? String(count) : "") + String(previous)
            }
            for symbol in row {
                if symbol == previous {
                    count += 1
                } else {
                    flush()
                    previous = symbol
                    count = 1
                }
            }
            flush()
            return out
        }.joined(separator: "/")
    }

    static func decodeRunLength(_ text: String) -> [String] {
        text.split(separator: "/", omittingEmptySubsequences: false).map { row in
            var out = "", count = ""
            for character in row {
                if character.isNumber {
                    count.append(character)
                } else {
                    out += String(repeating: character, count: Int(count) ?? 1)
                    count = ""
                }
            }
            return out
        }
    }

    // MARK: Palettes

    struct PaletteFile: Codable, Equatable {
        var schema: String
        var version: Int
        var breeds: [Breed]

        struct Breed: Codable, Equatable {
            var breed: String
            /// Role name to `#RRGGBB`, after `withVisibleRim()`.
            var colors: [String: String]
            var rim: String
        }
    }

    static func palettes() -> PaletteFile {
        PaletteFile(schema: schema, version: version, breeds: PetBreed.allCases.map { breed in
            let palette = breed.palette.withVisibleRim()
            return .init(
                breed: breed.rawValue,
                colors: Dictionary(uniqueKeysWithValues: PetPaletteRole.allCases.map { ($0.rawValue, palette[$0].hex) }),
                rim: palette.rim.hex
            )
        })
    }

    // MARK: Writing

    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value) + Data("\n".utf8)
    }
}
