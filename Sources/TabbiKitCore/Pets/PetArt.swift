import Foundation

/// The hand-drawn pet art, loaded from the `pets.v1` JSON files in
/// `Pets/PetArt` (one per art family: cat, dog, costume, effect, paw, prop,
/// tail, walk), the breeds that color it (`breeds.json`) and the animation
/// timelines that pose it (`animations.json`).
///
/// The art is data so the Mac app and the Windows port draw the very same
/// pixels from one source: each grid is an array of text rows in the
/// `SpriteCell` legend (see docs/study/pets.md), and costume items carry
/// their anchors next to their grids. The format is described by
/// `shared/schemas/pets.v1.schema.json`. The code that places the art
/// (`PetComposer`) and picks what to play (`PetAnimator`) stays in Swift.
enum PetArt {
    static let cat = load("cat")
    static let dog = load("dog")
    static let costume = load("costume")
    static let effect = load("effect")
    static let paw = load("paw")
    static let prop = load("prop")
    static let tail = load("tail")
    static let walk = load("walk")
    /// The base palette, the body shapes and every breed's palette, pattern,
    /// name and tail.
    static let breeds = load("breeds")
    /// How every animation plays: per frame the pose, stance, timing and
    /// effects.
    static let animations = load("animations")

    /// The version every art file declares in its `schema` key.
    static let schema = "pets.v1"

    static let subdirectory = "PetArt"

    /// Reads and checks one art file. The art ships inside the app, so a
    /// missing or broken file is a build mistake: like `SpriteGrid(art:)`,
    /// this stops with the reason instead of drawing a broken pet.
    static func load(_ name: String) -> PetArtFile {
        guard let url = KitResources.bundle?.url(forResource: name, withExtension: "json", subdirectory: subdirectory) else {
            preconditionFailure("Missing pet art \(subdirectory)/\(name).json")
        }
        do {
            return try PetArtFile.decode(Data(contentsOf: url))
        } catch {
            preconditionFailure("Invalid pet art \(name).json: \(error)")
        }
    }
}

/// One `pets.v1` file: named grids, named grid sequences (animation frames
/// such as a swaying tail) and, in the costume file, the body, face and head
/// items with their anchors; or the breeds; or the animation timelines.
struct PetArtFile: Sendable {
    enum LoadError: Error, Equatable, CustomStringConvertible {
        case unsupportedSchema(String)
        case invalidGrid(name: String, reason: String)
        /// A name, role, zone or color in the breed definitions that the
        /// Swift types do not know, at `path` (such as `breeds[2].palette`).
        case invalidValue(path: String, value: String)

        var description: String {
            switch self {
            case .unsupportedSchema(let schema): "Unsupported schema \"\(schema)\"; expected \"\(PetArt.schema)\""
            case let .invalidGrid(name, reason): "Grid \"\(name)\": \(reason)"
            case let .invalidValue(path, value): "\(path): unknown value \"\(value)\""
            }
        }
    }

    /// One breed as the file defines it. `palette` holds only the colors the
    /// breed sets; `PetPalette` fills the rest from the base palette.
    struct BreedDefinition: Equatable, Sendable {
        let name: String
        let bodyShape: PetBodyShape
        let hasTail: Bool
        let palette: [PetPaletteRole: PetColor]
        let pattern: [PetPatternZone: PetPaletteRole]
    }

    private(set) var grids: [String: SpriteGrid] = [:]
    private(set) var sequences: [String: [SpriteGrid]] = [:]
    private(set) var bodyItems: [String: CostumeArt.BodyItem] = [:]
    private(set) var faceItems: [String: CostumeArt.FaceItem] = [:]
    private(set) var headItems: [String: CostumeArt.HeadItem] = [:]
    private(set) var backItems: [String: CostumeArt.BackItem] = [:]
    private(set) var auraItems: [String: CostumeArt.AuraItem] = [:]
    private(set) var basePalette: [PetPaletteRole: PetColor] = [:]
    private(set) var bodyShapes: [PetBodyShape: PetSpecies] = [:]
    /// Breeds in file order, which is the order pickers list them in.
    private(set) var breedOrder: [PetBreed] = []
    private(set) var breeds: [PetBreed: BreedDefinition] = [:]
    private(set) var animations: [PetAnimation: PetTimeline] = [:]
    /// Seconds each frame of an animated costume item's loop stays on
    /// screen (costume file only).
    private(set) var itemFrameDuration: TimeInterval?

    func grid(_ name: String) -> SpriteGrid { lookUp(grids, name, "grid") }
    func sequence(_ name: String) -> [SpriteGrid] { lookUp(sequences, name, "sequence") }
    func bodyItem(_ name: String) -> CostumeArt.BodyItem { lookUp(bodyItems, name, "body item") }
    func faceItem(_ name: String) -> CostumeArt.FaceItem { lookUp(faceItems, name, "face item") }
    func headItem(_ name: String) -> CostumeArt.HeadItem { lookUp(headItems, name, "head item") }
    func backItem(_ name: String) -> CostumeArt.BackItem { lookUp(backItems, name, "back item") }
    func auraItem(_ name: String) -> CostumeArt.AuraItem { lookUp(auraItems, name, "aura item") }
    func species(of shape: PetBodyShape) -> PetSpecies { lookUp(bodyShapes, shape, "body shape") }
    func breed(_ breed: PetBreed) -> BreedDefinition { lookUp(breeds, breed, "breed") }
    func timeline(_ animation: PetAnimation) -> PetTimeline { lookUp(animations, animation, "animation") }

    private func lookUp<Key, Value>(_ table: [Key: Value], _ name: Key, _ kind: String) -> Value {
        guard let value = table[name] else { preconditionFailure("No pet art \(kind) named \"\(name)\"") }
        return value
    }

    /// Parses a file, checking its schema version and every grid.
    static func decode(_ data: Data) throws -> PetArtFile {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        guard raw.schema == PetArt.schema else { throw LoadError.unsupportedSchema(raw.schema) }
        func parse(_ rows: [String], _ name: String) throws -> SpriteGrid {
            do {
                return try SpriteGrid(rows.joined(separator: "\n"))
            } catch {
                throw LoadError.invalidGrid(name: name, reason: "\(error)")
            }
        }
        var file = PetArtFile()
        for (name, rows) in raw.grids ?? [:] {
            file.grids[name] = try parse(rows, name)
        }
        for (name, frames) in raw.sequences ?? [:] {
            file.sequences[name] = try frames.enumerated().map { try parse($1, "\(name)[\($0)]") }
        }
        for (name, item) in raw.bodyItems ?? [:] {
            func grids(_ frame: Raw.BodyFrame, _ path: String) throws -> CostumeArt.BodyItem {
                try CostumeArt.BodyItem(
                    cat: parse(frame.cat, "\(path).cat"),
                    dog: parse(frame.dog, "\(path).dog"),
                    longDog: parse(frame.longDog, "\(path).longDog"),
                    walk: parse(frame.walk, "\(path).walk"),
                    walkLong: parse(frame.walkLong, "\(path).walkLong"),
                    rise: item.rise ?? 0
                )
            }
            var body = try grids(item.still, name)
            body.moreFrames = try (item.frames ?? []).enumerated().map { index, frame in
                let path = "\(name).frames[\(index)]"
                let grids = try grids(frame, path)
                for (still, moving, family) in [(body.cat, grids.cat, "cat"), (body.dog, grids.dog, "dog"),
                                                 (body.longDog, grids.longDog, "longDog"), (body.walk, grids.walk, "walk"),
                                                 (body.walkLong, grids.walkLong, "walkLong")] {
                    try sameSize(moving, as: still, "\(path).\(family)")
                }
                return grids
            }
            file.bodyItems[name] = body
        }
        for (name, item) in raw.faceItems ?? [:] {
            file.faceItems[name] = try CostumeArt.FaceItem(
                cat: parse(item.cat, "\(name).cat"),
                dog: parse(item.dog, "\(name).dog"),
                eyeRow: item.eyeRow
            )
        }
        for (name, item) in raw.headItems ?? [:] {
            let grid = try parse(item.grid, "\(name).grid")
            let frames = try (item.frames ?? []).enumerated().map { index, rows in
                let path = "\(name).frames[\(index)]"
                let frame = try parse(rows, path)
                try sameSize(frame, as: grid, path)
                return frame
            }
            file.headItems[name] = CostumeArt.HeadItem(grid: grid, sitRow: item.sitRow, moreFrames: frames)
        }
        func placement(_ raw: Raw.BackPlacement, _ path: String) throws -> CostumeArt.BackItem.Placement {
            guard !raw.frames.isEmpty else { throw LoadError.invalidGrid(name: path, reason: "no frames") }
            let frames = try raw.frames.enumerated().map { try parse($1, "\(path).frames[\($0)]") }
            for (index, frame) in frames.enumerated().dropFirst() {
                try sameSize(frame, as: frames[0], "\(path).frames[\(index)]")
            }
            return CostumeArt.BackItem.Placement(x: raw.x, y: raw.y, frames: frames)
        }
        for (name, item) in raw.backItems ?? [:] {
            let back = try CostumeArt.BackItem(
                cat: placement(item.cat, "\(name).cat"), dog: placement(item.dog, "\(name).dog"),
                longDog: placement(item.longDog, "\(name).longDog"), walk: placement(item.walk, "\(name).walk"),
                walkLong: placement(item.walkLong, "\(name).walkLong")
            )
            // Every family plays the loop in step on the one item clock.
            for (family, placement) in [("dog", back.dog), ("longDog", back.longDog), ("walk", back.walk),
                                        ("walkLong", back.walkLong)] where placement.frames.count != back.frameCount {
                throw LoadError.invalidGrid(name: "\(name).\(family)", reason: "\(placement.frames.count) frames "
                    + "differ from the cat's \(back.frameCount)")
            }
            file.backItems[name] = back
        }
        for (name, item) in raw.auraItems ?? [:] {
            let front = try placement(item.front, "\(name).front")
            let aura = try CostumeArt.AuraItem(front: front, side: placement(item.side, "\(name).side"),
                                               longDog: item.longDog.map { try placement($0, "\(name).longDog") } ?? front)
            for (view, placement) in [("side", aura.side), ("longDog", aura.longDog)]
            where placement.frames.count != aura.frameCount {
                throw LoadError.invalidGrid(name: "\(name).\(view)", reason: "\(placement.frames.count) frames "
                    + "differ from the front's \(aura.frameCount)")
            }
            file.auraItems[name] = aura
        }
        if let duration = raw.itemFrameDuration {
            guard duration > 0 else { throw LoadError.invalidValue(path: "itemFrameDuration", value: "\(duration)") }
            file.itemFrameDuration = duration
        }
        if let base = raw.basePalette {
            file.basePalette = try colors(base, at: "basePalette")
        }
        for (name, shape) in raw.bodyShapes ?? [:] {
            file.bodyShapes[try value(PetBodyShape(rawValue: name), name, at: "bodyShapes")] =
                try value(PetSpecies(rawValue: shape.species), shape.species, at: "bodyShapes.\(name).species")
        }
        for (index, entry) in (raw.breeds ?? []).enumerated() {
            let path = "breeds[\(index)]"
            let breed = try value(PetBreed(rawValue: entry.id), entry.id, at: "\(path).id")
            var pattern: [PetPatternZone: PetPaletteRole] = [:]
            for (zone, role) in entry.pattern {
                pattern[try value(PetPatternZone(rawValue: zone), zone, at: "\(path).pattern")] =
                    try value(PetPaletteRole(rawValue: role), role, at: "\(path).pattern.\(zone)")
            }
            file.breedOrder.append(breed)
            file.breeds[breed] = try BreedDefinition(
                name: entry.name,
                bodyShape: value(PetBodyShape(rawValue: entry.bodyShape), entry.bodyShape, at: "\(path).bodyShape"),
                hasTail: entry.hasTail,
                palette: colors(entry.palette, at: "\(path).palette"),
                pattern: pattern
            )
        }
        for (name, timeline) in raw.animations ?? [:] {
            let path = "animations.\(name)"
            file.animations[try value(PetAnimation(rawValue: name), name, at: "animations")] =
                try PetTimeline(timeline, at: path)
        }
        return file
    }

    /// Every frame of an item's loop is drawn over the same spot, so it
    /// must be the size of the item's still grid.
    private static func sameSize(_ frame: SpriteGrid, as still: SpriteGrid, _ name: String) throws {
        guard frame.width == still.width, frame.height == still.height else {
            throw LoadError.invalidGrid(name: name, reason: "\(frame.width)x\(frame.height) differs from the item's "
                + "\(still.width)x\(still.height) still grid")
        }
    }

    private static func value<Value>(_ parsed: Value?, _ raw: String, at path: String) throws -> Value {
        guard let parsed else { throw LoadError.invalidValue(path: path, value: raw) }
        return parsed
    }

    /// A `{ "role": "#RRGGBB" }` table.
    private static func colors(_ raw: [String: String], at path: String) throws -> [PetPaletteRole: PetColor] {
        var colors: [PetPaletteRole: PetColor] = [:]
        for (role, hex) in raw {
            colors[try value(PetPaletteRole(rawValue: role), role, at: path)] =
                try value(PetColor(hex: hex), hex, at: "\(path).\(role)")
        }
        return colors
    }

    /// The file as written: grids are arrays of text rows.
    private struct Raw: Decodable {
        /// One frame of a body item: a grid per body family.
        struct BodyFrame: Decodable {
            let cat, dog, longDog, walk, walkLong: [String]
        }

        struct BodyItem: Decodable {
            let still: BodyFrame
            let rise: Int?
            /// The rest of an animated item's loop, after `still`.
            let frames: [BodyFrame]?

            enum CodingKeys: CodingKey { case rise, frames }

            init(from decoder: Decoder) throws {
                still = try BodyFrame(from: decoder)
                let container = try decoder.container(keyedBy: CodingKeys.self)
                rise = try container.decodeIfPresent(Int.self, forKey: .rise)
                frames = try container.decodeIfPresent([BodyFrame].self, forKey: .frames)
            }
        }

        struct FaceItem: Decodable {
            let cat, dog: [String]
            let eyeRow: Int
        }

        struct HeadItem: Decodable {
            let grid: [String]
            let sitRow: Int
            /// The rest of an animated item's loop, after `grid`.
            let frames: [[String]]?
        }

        /// A back item's loop for one body family and its offset from that
        /// family's body origin.
        struct BackPlacement: Decodable {
            let x, y: Int
            let frames: [[String]]
        }

        struct BackItem: Decodable {
            let cat, dog, longDog, walk, walkLong: BackPlacement
        }

        /// An aura item's loop around a pet facing the viewer and seen
        /// from the side, offset from the frame's top-left corner, and
        /// optionally around the dachshund, which sits side-on.
        struct AuraItem: Decodable {
            let front, side: BackPlacement
            let longDog: BackPlacement?
        }

        let schema: String
        let grids: [String: [String]]?
        let sequences: [String: [[String]]]?
        let bodyItems: [String: BodyItem]?
        let faceItems: [String: FaceItem]?
        let headItems: [String: HeadItem]?
        let backItems: [String: BackItem]?
        let auraItems: [String: AuraItem]?
        let basePalette: [String: String]?
        let bodyShapes: [String: BodyShape]?
        let breeds: [Breed]?
        let animations: [String: PetTimeline.Raw]?
        let itemFrameDuration: Double?

        struct BodyShape: Decodable {
            let species: String
        }

        struct Breed: Decodable {
            let id, name, bodyShape: String
            let hasTail: Bool
            let palette: [String: String]
            let pattern: [String: String]
        }
    }
}
