import Foundation

/// The hand-drawn pet art, loaded from the `pets.v1` JSON files in
/// `Pets/PetArt` (one per art family: cat, dog, costume, effect, paw, prop,
/// tail, walk).
///
/// The art is data so the Mac app and the Windows port draw the very same
/// pixels from one source: each grid is an array of text rows in the
/// `SpriteCell` legend (see docs/study/pets.md), and costume items carry
/// their anchors next to their grids. The format is described by
/// `shared/schemas/pets.v1.schema.json`. The code that places and animates
/// the art stays in Swift (`PetComposer`, `PetAnimator`).
enum PetArt {
    static let cat = load("cat")
    static let dog = load("dog")
    static let costume = load("costume")
    static let effect = load("effect")
    static let paw = load("paw")
    static let prop = load("prop")
    static let tail = load("tail")
    static let walk = load("walk")

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

/// One `pets.v1` art file: named grids, named grid sequences (animation
/// frames such as a swaying tail) and, in the costume file, the body, face
/// and head items with their anchors.
struct PetArtFile: Sendable {
    enum LoadError: Error, Equatable, CustomStringConvertible {
        case unsupportedSchema(String)
        case invalidGrid(name: String, reason: String)

        var description: String {
            switch self {
            case .unsupportedSchema(let schema): "Unsupported schema \"\(schema)\"; expected \"\(PetArt.schema)\""
            case let .invalidGrid(name, reason): "Grid \"\(name)\": \(reason)"
            }
        }
    }

    private(set) var grids: [String: SpriteGrid] = [:]
    private(set) var sequences: [String: [SpriteGrid]] = [:]
    private(set) var bodyItems: [String: CostumeArt.BodyItem] = [:]
    private(set) var faceItems: [String: CostumeArt.FaceItem] = [:]
    private(set) var headItems: [String: CostumeArt.HeadItem] = [:]

    func grid(_ name: String) -> SpriteGrid { lookUp(grids, name, "grid") }
    func sequence(_ name: String) -> [SpriteGrid] { lookUp(sequences, name, "sequence") }
    func bodyItem(_ name: String) -> CostumeArt.BodyItem { lookUp(bodyItems, name, "body item") }
    func faceItem(_ name: String) -> CostumeArt.FaceItem { lookUp(faceItems, name, "face item") }
    func headItem(_ name: String) -> CostumeArt.HeadItem { lookUp(headItems, name, "head item") }

    private func lookUp<Value>(_ table: [String: Value], _ name: String, _ kind: String) -> Value {
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
            file.bodyItems[name] = try CostumeArt.BodyItem(
                cat: parse(item.cat, "\(name).cat"),
                dog: parse(item.dog, "\(name).dog"),
                longDog: parse(item.longDog, "\(name).longDog"),
                walk: parse(item.walk, "\(name).walk"),
                walkLong: parse(item.walkLong, "\(name).walkLong"),
                rise: item.rise ?? 0
            )
        }
        for (name, item) in raw.faceItems ?? [:] {
            file.faceItems[name] = try CostumeArt.FaceItem(
                cat: parse(item.cat, "\(name).cat"),
                dog: parse(item.dog, "\(name).dog"),
                eyeRow: item.eyeRow
            )
        }
        for (name, item) in raw.headItems ?? [:] {
            file.headItems[name] = try CostumeArt.HeadItem(grid: parse(item.grid, "\(name).grid"), sitRow: item.sitRow)
        }
        return file
    }

    /// The file as written: grids are arrays of text rows.
    private struct Raw: Decodable {
        struct BodyItem: Decodable {
            let cat, dog, longDog, walk, walkLong: [String]
            let rise: Int?
        }

        struct FaceItem: Decodable {
            let cat, dog: [String]
            let eyeRow: Int
        }

        struct HeadItem: Decodable {
            let grid: [String]
            let sitRow: Int
        }

        let schema: String
        let grids: [String: [String]]?
        let sequences: [String: [[String]]]?
        let bodyItems: [String: BodyItem]?
        let faceItems: [String: FaceItem]?
        let headItems: [String: HeadItem]?
    }
}
