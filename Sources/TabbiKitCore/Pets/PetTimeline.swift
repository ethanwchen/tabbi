import Foundation

/// One animation as `animations.json` (`pets.v1`) defines it: whether it
/// loops, the frame a still pet holds, and each frame's pose, stance,
/// timing and effects. `PetComposer.clip` turns a timeline into canvases for
/// a dressed breed, so the Mac app and the Windows port play the very same
/// frames from one source.
struct PetTimeline: Equatable, Sendable {
    /// Where an effect lands on one axis.
    enum Coordinate: Equatable, Sendable {
        /// A fixed frame pixel.
        case frame(Int)
        /// Pixels from the top-right corner of the head in the clip's first
        /// frame, so a drifting "z" stays put while the head breathes.
        case head(Int)
    }

    /// An effect grid (`effect.json`) painted behind the pet.
    struct Effect: Equatable, Sendable {
        let grid: String
        let x: Coordinate
        let y: Coordinate
    }

    struct Frame: Equatable, Sendable {
        var duration: TimeInterval
        var pose = PetPose()
        var stance: PetComposer.Stance = .sitting
        /// Rows the whole frame moves down (negative: up), for the peek.
        var shiftY = 0
        var effects: [Effect] = []
        /// The `prop.json` steam wisp rising from the mug, over the chest.
        var steam: Int?
        /// Dust puffs beside the paws on the floor, for a landing.
        var dust = false
        /// Whether the frame points a speech bubble at the head.
        var bubble = false
    }

    let loops: Bool
    /// The frame a still pet shows under Reduce Motion; nil means the first
    /// frame of a loop and the last of a one-shot clip.
    let still: Int?
    let frames: [Frame]

    var stillIndex: Int { still ?? (loops ? 0 : frames.count - 1) }
}

extension PetTimeline {
    /// The timelines as written in `animations.json`.
    struct Raw: Decodable {
        struct Point: Decodable {
            let head: Int
        }

        enum Axis: Decodable {
            case frame(Int)
            case head(Int)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let value = try? container.decode(Int.self) {
                    self = .frame(value)
                } else {
                    self = .head(try container.decode(Point.self).head)
                }
            }
        }

        struct Effect: Decodable {
            let grid: String
            let x, y: Axis
        }

        struct Prop: Decodable {
            let kind: String
            let tap, raise, roll, bounce: Int?
            let bat: Bool?
        }

        struct Gesture: Decodable {
            let kind: String
            let swing, reach: Int?
        }

        struct Pose: Decodable {
            let eyes, mouth: String?
            let prop: Prop?
            let gesture: Gesture?
            let tailSwing, headDrop, lift: Int?
        }

        struct Stance: Decodable {
            let kind: String
            let step, depth, wag, breath: Int?
        }

        struct Frame: Decodable {
            let duration: Double
            let pose: Pose?
            let stance: Stance?
            let shiftY: Int?
            let effects: [Effect]?
            let steam: Int?
            let dust, bubble: Bool?
        }

        let loops: Bool
        let still: Int?
        let frames: [Frame]
    }

    /// Checks a raw timeline; `path` names it in errors (`animations.sleep`).
    init(_ raw: Raw, at path: String) throws {
        typealias LoadError = PetArtFile.LoadError
        guard !raw.frames.isEmpty else { throw LoadError.invalidValue(path: "\(path).frames", value: "[]") }
        if let still = raw.still, !raw.frames.indices.contains(still) {
            throw LoadError.invalidValue(path: "\(path).still", value: "\(still)")
        }
        loops = raw.loops
        still = raw.still
        frames = try raw.frames.enumerated().map { index, frame in
            let path = "\(path).frames[\(index)]"
            guard frame.duration > 0 else { throw LoadError.invalidValue(path: "\(path).duration", value: "\(frame.duration)") }
            return try Frame(
                duration: frame.duration,
                pose: frame.pose.map { try Self.pose($0, at: "\(path).pose") } ?? PetPose(),
                stance: frame.stance.map { try Self.stance($0, at: "\(path).stance") } ?? .sitting,
                shiftY: frame.shiftY ?? 0,
                effects: (frame.effects ?? []).map { effect in
                    Effect(grid: effect.grid, x: Self.coordinate(effect.x), y: Self.coordinate(effect.y))
                },
                steam: frame.steam,
                dust: frame.dust ?? false,
                bubble: frame.bubble ?? false
            )
        }
    }

    private static func coordinate(_ axis: Raw.Axis) -> Coordinate {
        switch axis {
        case .frame(let value): .frame(value)
        case .head(let value): .head(value)
        }
    }

    private static func pose(_ raw: Raw.Pose, at path: String) throws -> PetPose {
        func parse<Value: RawRepresentable<String>>(_ value: String?, _ key: String, default fallback: Value) throws -> Value {
            guard let value else { return fallback }
            guard let parsed = Value(rawValue: value) else {
                throw PetArtFile.LoadError.invalidValue(path: "\(path).\(key)", value: value)
            }
            return parsed
        }
        return try PetPose(
            eyes: parse(raw.eyes, "eyes", default: .open),
            mouth: parse(raw.mouth, "mouth", default: .closed),
            prop: raw.prop.map { try prop($0, at: "\(path).prop") },
            gesture: raw.gesture.map { try gesture($0, at: "\(path).gesture") },
            tailSwing: raw.tailSwing ?? 0,
            headDrop: raw.headDrop ?? 0,
            lift: raw.lift ?? 0
        )
    }

    private static func prop(_ raw: Raw.Prop, at path: String) throws -> PetPose.Prop {
        switch raw.kind {
        case "laptop": .laptop(tap: raw.tap ?? 0)
        case "mug": .mug(raise: raw.raise ?? 0)
        case "toy": .toy(roll: raw.roll ?? 0, bounce: raw.bounce ?? 0, bat: raw.bat ?? false)
        default: throw PetArtFile.LoadError.invalidValue(path: "\(path).kind", value: raw.kind)
        }
    }

    private static func gesture(_ raw: Raw.Gesture, at path: String) throws -> PetPose.Gesture {
        switch raw.kind {
        case "wave": .wave(swing: raw.swing ?? 0)
        case "groom": .groom(reach: raw.reach ?? 0)
        default: throw PetArtFile.LoadError.invalidValue(path: "\(path).kind", value: raw.kind)
        }
    }

    private static func stance(_ raw: Raw.Stance, at path: String) throws -> PetComposer.Stance {
        switch raw.kind {
        case "sitting": .sitting
        case "hanging": .hanging
        case "walking": .walking(step: raw.step ?? 0)
        case "stretching": .stretching(depth: raw.depth ?? 0, wag: raw.wag ?? 0)
        case "curled": .curled(breath: raw.breath ?? 0)
        default: throw PetArtFile.LoadError.invalidValue(path: "\(path).kind", value: raw.kind)
        }
    }
}
