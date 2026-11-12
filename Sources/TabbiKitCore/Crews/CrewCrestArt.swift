import CoreGraphics
import Foundation

/// A crew's crest: a frame (the silhouette, filled with the crew color), an
/// emblem stamped into the frame's slot, the crew color, and for the weekly
/// top 3 a laurel in gold, silver or bronze, plus up to three trophy pips.
public struct CrewCrest: Hashable, Sendable {
    public var frame: String
    public var emblem: String
    public var color: String

    public init(frame: String, emblem: String, color: String) {
        self.frame = frame
        self.emblem = emblem
        self.color = color
    }

    /// The crest a crew shows: its own ids where the app has art for them,
    /// the first frame, emblem or color otherwise, so a newer server never
    /// breaks an older app.
    public init(_ crew: CrewSummary) {
        self.init(frame: crew.frame, emblem: crew.emblem, color: crew.color)
    }

    /// The same crest with every id this app has no art for replaced by the default.
    public var resolved: CrewCrest {
        CrewCrest(frame: CrewCatalog.frame(frame), emblem: CrewCatalog.emblem(emblem), color: CrewCatalog.color(color).id)
    }

    public static var `default`: CrewCrest {
        CrewCrest(frame: CrewCatalog.frames[0], emblem: CrewCatalog.emblems[0], color: CrewCatalog.colors[0].id)
    }

    /// A random crest, for the builder's Shuffle.
    public static func random<G: RandomNumberGenerator>(using generator: inout G) -> CrewCrest {
        CrewCrest(frame: CrewCatalog.frames.randomElement(using: &generator)!,
                  emblem: CrewCatalog.emblems.randomElement(using: &generator)!,
                  color: CrewCatalog.colors.randomElement(using: &generator)!.id)
    }
}

/// Draws crests from one data file, `Pets/PetArt/crew.json` (format
/// `crewCrests.v1`, see docs/design/crews.md), so new frames and emblems are
/// data, not code. Every layer is a grid of palette characters (`.` is
/// clear, a later layer paints only its own cells): the laurel first, then
/// the frame, the emblem at the frame's slot, and the pips. `C`, `D` and `H`
/// take the crew color's base, shade and highlight, a crew color may set
/// further roles of its own (the emblem outline, light on dark crews), `g`
/// and `h` take the rank's leaf and shade, and every other character has a
/// fixed color. Nearest
/// neighbor only, like the pets and badges. The Windows port composes the
/// same file the same way (`crewCrestArt.ts`), and
/// `shared/fixtures/crews/crests.json` pins the pixels of a spread of
/// crests, which match the design's reference compositor.
public enum CrewCrestArt {
    /// Points per sprite pixel in crew rows and pages (48 pt).
    public static let regularPixelSize: CGFloat = 1.5
    /// Points per sprite pixel in tight rows and pickers (32 pt).
    public static let compactPixelSize: CGFloat = 1
    /// Points per sprite pixel in the builder's preview (64 pt).
    public static let largePixelSize: CGFloat = 2
    /// The most trophy pips a crest shows.
    public static let maxPips = 3

    /// The shipped art. It ships inside the app, so a missing or broken file
    /// is a build mistake and stops with the reason.
    public static let art: CrewCrestSet = {
        guard let url = KitResources.bundle?.url(forResource: "crew", withExtension: "json", subdirectory: "PetArt") else {
            preconditionFailure("Missing crew crest art PetArt/crew.json")
        }
        do {
            return try CrewCrestSet.decode(Data(contentsOf: url))
        } catch {
            preconditionFailure("Invalid crew crest art: \(error)")
        }
    }()

    /// The canvas side, in sprite pixels.
    public static var size: Int { art.grid }

    /// The composed crest as characters, row-major, nil for clear.
    public static func canvas(_ crest: CrewCrest, laurel: CrewLaurel?, pips: Int = 0,
                              in art: CrewCrestSet = art) -> [Character?] {
        art.compose(crest, laurel: laurel != nil, pips: pips)
    }

    /// The crest's pixels as colors, row-major, nil for transparent.
    public static func colors(_ crest: CrewCrest, laurel: CrewLaurel?, pips: Int = 0,
                              in art: CrewCrestSet = art) -> [PetColor?] {
        let palette = art.palette(color: crest.color, laurel: laurel)
        return art.compose(crest, laurel: laurel != nil, pips: pips).map { $0.flatMap { palette[$0] } }
    }

    /// The crest as a crisp image at a whole number of device pixels per
    /// sprite pixel, cached.
    public static func image(_ crest: CrewCrest, laurel: CrewLaurel?, pips: Int = 0, scale: Int) -> CGImage? {
        CrewCrestImageCache.shared.image(crest.resolved, laurel: laurel, pips: min(max(pips, 0), maxPips), scale: max(1, scale))
    }
}

/// One `crewCrests.v1` file, checked on load.
public struct CrewCrestSet: Sendable, Equatable {
    public static let schema = "crewCrests.v1"

    public struct Frame: Sendable, Equatable {
        public let id: String
        public let name: String
        /// Where the emblem's top-left corner lands.
        public let slot: (x: Int, y: Int)
        let pixels: [Character?]

        public static func == (lhs: Frame, rhs: Frame) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name && lhs.slot == rhs.slot && lhs.pixels == rhs.pixels
        }
    }

    public struct Emblem: Sendable, Equatable {
        public let id: String
        public let name: String
        /// Any size up to the slot; it is centered in the frame's slot.
        public let width: Int
        public let height: Int
        let pixels: [Character?]
    }

    public struct Tones: Sendable, Equatable {
        public let base: PetColor
        public let shade: PetColor
        public let highlight: PetColor
        /// Further characters this crew color sets, such as the emblem outline
        /// (`emblemOutline`) that turns light on a dark crew color.
        let overrides: [Character: PetColor]
    }

    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case unsupportedSchema(String)
        case invalid(String)

        public var description: String {
            switch self {
            case .unsupportedSchema(let schema): "Unsupported schema \"\(schema)\"; expected \"\(CrewCrestSet.schema)\""
            case .invalid(let reason): reason
            }
        }
    }

    /// The canvas side.
    public let grid: Int
    /// The side of the box each frame keeps for its emblem; an emblem may be
    /// smaller and is centered in it.
    public let slot: Int
    public let frames: [Frame]
    public let emblems: [Emblem]
    /// Crew colors in picker order.
    public let colorIDs: [String]
    let colors: [String: Tones]
    let fixed: [Character: PetColor]
    let ranks: [CrewLaurel: (leaf: PetColor, shade: PetColor)]
    let laurel: [Character?]
    let pip: (side: Int, pixels: [Character?])
    let pipPositions: [(x: Int, y: Int)]

    public static func == (lhs: CrewCrestSet, rhs: CrewCrestSet) -> Bool {
        lhs.grid == rhs.grid && lhs.frames == rhs.frames && lhs.emblems == rhs.emblems && lhs.colorIDs == rhs.colorIDs
            && lhs.laurel == rhs.laurel
    }

    /// The crew color's tones, or nil for an id the file lacks.
    public func tones(_ color: String) -> Tones? { colors[color] }

    private struct Raw: Decodable {
        struct Role: Decodable { let role: String; let hex: String? }
        struct RawFrame: Decodable { let id: String; let name: String; let slot: [Int]; let grid: [String] }
        struct RawEmblem: Decodable { let id: String; let name: String; let grid: [String] }
        /// A crew color: its id and three tones, and any other key naming a
        /// palette role (such as `emblemOutline`) with the color it takes.
        struct RawColor: Decodable {
            let id: String
            let base: String
            let shade: String
            let hi: String
            let roles: [String: String]

            private struct Key: CodingKey {
                var stringValue: String
                var intValue: Int? { nil }
                init(stringValue: String) { self.stringValue = stringValue }
                init?(intValue: Int) { nil }
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: Key.self)
                func text(_ key: String) throws -> String { try container.decode(String.self, forKey: Key(stringValue: key)) }
                id = try text("id")
                base = try text("base")
                shade = try text("shade")
                hi = try text("hi")
                var roles: [String: String] = [:]
                for key in container.allKeys where !["id", "base", "shade", "hi"].contains(key.stringValue) {
                    roles[key.stringValue] = try container.decode(String.self, forKey: key)
                }
                self.roles = roles
            }
        }
        struct RawRank: Decodable { let leaf: String; let shade: String }
        let schema: String
        let grid: Int
        let slot: Int
        let palette: [String: Role]
        let crewColors: [RawColor]
        let ranks: [String: RawRank]
        let frames: [RawFrame]
        let emblems: [RawEmblem]
        let laurel: [String]
        let pip: [String]
        let pipPositions: [[Int]]
    }

    /// The characters whose color comes from the crew color and the rank.
    static let crewCharacters: (base: Character, shade: Character, highlight: Character) = ("C", "D", "H")
    static let rankCharacters: (leaf: Character, shade: Character) = ("g", "h")

    public static func decode(_ data: Data) throws -> CrewCrestSet {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        guard raw.schema == schema else { throw LoadError.unsupportedSchema(raw.schema) }
        guard (8...64).contains(raw.grid), (1...raw.grid).contains(raw.slot) else { throw LoadError.invalid("bad grid or slot size") }
        func hex(_ text: String, _ what: String) throws -> PetColor {
            guard let color = PetColor(hex: text) else { throw LoadError.invalid("\(what): bad color \(text)") }
            return color
        }
        var fixed: [Character: PetColor] = [:]
        var known = Set<Character>()
        var byRole: [String: Character] = [:]
        for (key, role) in raw.palette {
            guard key.count == 1, let c = key.first, c != "." else { throw LoadError.invalid("palette key \(key)") }
            known.insert(c)
            byRole[role.role] = c
            if let value = role.hex { fixed[c] = try hex(value, "palette.\(key)") }
        }
        for c in [crewCharacters.base, crewCharacters.shade, crewCharacters.highlight, rankCharacters.leaf, rankCharacters.shade]
        where !known.contains(c) {
            throw LoadError.invalid("palette lacks \(c)")
        }
        func parse(_ rows: [String], _ name: String, width: Int, height: Int) throws -> [Character?] {
            guard rows.count == height, rows.allSatisfy({ $0.count == width }) else {
                throw LoadError.invalid("\(name) must be \(width) by \(height)")
            }
            return try rows.flatMap { row in
                try row.map { c -> Character? in
                    if c == "." { return nil }
                    guard known.contains(c) else { throw LoadError.invalid("\(name): unknown character \(c)") }
                    return c
                }
            }
        }
        var frames: [Frame] = []
        for frame in raw.frames {
            guard !frame.id.isEmpty, !frames.contains(where: { $0.id == frame.id }) else { throw LoadError.invalid("frame id \(frame.id)") }
            guard frame.slot.count == 2, frame.slot.allSatisfy({ (0...(raw.grid - raw.slot)).contains($0) }) else {
                throw LoadError.invalid("frame \(frame.id): slot outside the grid")
            }
            frames.append(Frame(id: frame.id, name: frame.name, slot: (frame.slot[0], frame.slot[1]),
                                pixels: try parse(frame.grid, "frame \(frame.id)", width: raw.grid, height: raw.grid)))
        }
        var emblems: [Emblem] = []
        for emblem in raw.emblems {
            guard !emblem.id.isEmpty, !emblems.contains(where: { $0.id == emblem.id }) else { throw LoadError.invalid("emblem id \(emblem.id)") }
            let width = emblem.grid.first?.count ?? 0, height = emblem.grid.count
            guard (1...raw.slot).contains(width), (1...raw.slot).contains(height) else {
                throw LoadError.invalid("emblem \(emblem.id) must fit the \(raw.slot) by \(raw.slot) slot")
            }
            emblems.append(Emblem(id: emblem.id, name: emblem.name, width: width, height: height,
                                  pixels: try parse(emblem.grid, "emblem \(emblem.id)", width: width, height: height)))
        }
        guard !frames.isEmpty, !emblems.isEmpty, !raw.crewColors.isEmpty else { throw LoadError.invalid("no frames, emblems or colors") }
        var colors: [String: Tones] = [:]
        for color in raw.crewColors {
            guard colors[color.id] == nil else { throw LoadError.invalid("color id \(color.id)") }
            var overrides: [Character: PetColor] = [:]
            for (role, value) in color.roles {
                guard let c = byRole[role] else { throw LoadError.invalid("color \(color.id): unknown role \(role)") }
                overrides[c] = try hex(value, "\(color.id).\(role)")
            }
            colors[color.id] = Tones(base: try hex(color.base, color.id), shade: try hex(color.shade, color.id),
                                     highlight: try hex(color.hi, color.id), overrides: overrides)
        }
        // Every character must get a color from the fixed table, the crew
        // color, the rank or every crew color's own role.
        let crewSet: Set<Character> = [crewCharacters.base, crewCharacters.shade, crewCharacters.highlight]
        let rankSet: Set<Character> = [rankCharacters.leaf, rankCharacters.shade]
        for c in known where fixed[c] == nil && !crewSet.contains(c) && !rankSet.contains(c) {
            guard colors.values.allSatisfy({ $0.overrides[c] != nil }) else {
                throw LoadError.invalid("character \(c) has no color for every crew color")
            }
        }
        var ranks: [CrewLaurel: (PetColor, PetColor)] = [:]
        for laurel in CrewLaurel.allCases {
            guard let rank = raw.ranks[laurel.rawValue] else { throw LoadError.invalid("ranks.\(laurel.rawValue) missing") }
            ranks[laurel] = (try hex(rank.leaf, "rank"), try hex(rank.shade, "rank"))
        }
        let pipSide = raw.pip.count
        let pip = try parse(raw.pip, "pip", width: pipSide, height: pipSide)
        let positions = try raw.pipPositions.map { position -> (Int, Int) in
            guard position.count == 2, position.allSatisfy({ (0...(raw.grid - pipSide)).contains($0) }) else {
                throw LoadError.invalid("pip position outside the grid")
            }
            return (position[0], position[1])
        }
        return CrewCrestSet(grid: raw.grid, slot: raw.slot, frames: frames, emblems: emblems,
                            colorIDs: raw.crewColors.map(\.id), colors: colors, fixed: fixed, ranks: ranks,
                            laurel: try parse(raw.laurel, "laurel", width: raw.grid, height: raw.grid),
                            pip: (pipSide, pip), pipPositions: positions)
    }

    public func frame(_ id: String) -> Frame { frames.first { $0.id == id } ?? frames[0] }
    public func emblem(_ id: String) -> Emblem { emblems.first { $0.id == id } ?? emblems[0] }

    /// The layers, in order: laurel, frame, emblem at the frame's slot, pips.
    func compose(_ crest: CrewCrest, laurel withLaurel: Bool, pips: Int) -> [Character?] {
        var pixels: [Character?] = withLaurel ? laurel : Array(repeating: nil, count: grid * grid)
        let frame = frame(crest.frame)
        for (index, c) in frame.pixels.enumerated() where c != nil { pixels[index] = c }
        let emblem = emblem(crest.emblem)
        // Centered in the slot, rounding toward the top left.
        let ox = frame.slot.x + (slot - emblem.width) / 2, oy = frame.slot.y + (slot - emblem.height) / 2
        for y in 0..<emblem.height {
            for x in 0..<emblem.width {
                if let c = emblem.pixels[y * emblem.width + x] { pixels[(oy + y) * grid + ox + x] = c }
            }
        }
        for position in pipPositions.prefix(max(0, pips)) {
            for y in 0..<pip.side {
                for x in 0..<pip.side {
                    if let c = pip.pixels[y * pip.side + x] { pixels[(position.y + y) * grid + position.x + x] = c }
                }
            }
        }
        return pixels
    }

    /// Every character's color for one crew color (the first for an unknown
    /// id) and laurel.
    func palette(color: String, laurel: CrewLaurel?) -> [Character: PetColor] {
        var palette = fixed
        let tones = colors[color] ?? colors[colorIDs[0]]!
        palette[Self.crewCharacters.base] = tones.base
        palette[Self.crewCharacters.shade] = tones.shade
        palette[Self.crewCharacters.highlight] = tones.highlight
        palette.merge(tones.overrides) { _, crew in crew }
        if let laurel, let rank = ranks[laurel] {
            palette[Self.rankCharacters.leaf] = rank.leaf
            palette[Self.rankCharacters.shade] = rank.shade
        }
        return palette
    }
}

/// Rendered crests, keyed by crest, laurel, pips and scale.
final class CrewCrestImageCache: @unchecked Sendable {
    private struct Key: Hashable {
        let crest: CrewCrest
        let laurel: CrewLaurel?
        let pips: Int
        let scale: Int
    }

    static let shared = CrewCrestImageCache()
    private let lock = NSLock()
    private var cache: [Key: CGImage] = [:]

    func image(_ crest: CrewCrest, laurel: CrewLaurel?, pips: Int, scale: Int) -> CGImage? {
        let key = Key(crest: crest, laurel: laurel, pips: pips, scale: scale)
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let colors = CrewCrestArt.colors(crest, laurel: laurel, pips: pips)
        guard let image = PixelImage.render(colors, side: CrewCrestArt.size, scale: scale) else { return nil }
        lock.lock(); defer { lock.unlock() }
        // A builder session can try a few hundred crests; keep the cache bounded.
        if cache.count > 2_000 { cache.removeAll() }
        cache[key] = image
        return image
    }
}

/// Square pixel art to a premultiplied RGBA image, every sprite pixel an
/// exact `scale` block, like `PetRenderer.render`.
enum PixelImage {
    static func render(_ colors: [PetColor?], side: Int, scale: Int) -> CGImage? {
        let width = side * scale, height = side * scale
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for sy in 0..<side {
            for sx in 0..<side {
                guard let color = colors[sy * side + sx] else { continue }
                let a = UInt16(color.alpha)
                let premultiplied = [color.red, color.green, color.blue].map { UInt8(UInt16($0) * a / 255) }
                for dy in 0..<scale {
                    var offset = ((sy * scale + dy) * width + sx * scale) * 4
                    for _ in 0..<scale {
                        bytes[offset] = premultiplied[0]
                        bytes[offset + 1] = premultiplied[1]
                        bytes[offset + 2] = premultiplied[2]
                        bytes[offset + 3] = color.alpha
                        offset += 4
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
