import Foundation

/// How strongly a Radiant item shows its effect, picked per item in the
/// Closet. A new upgrade starts on `bold`; `off` keeps the upgrade but draws
/// the normal item.
public enum PetRadiantIntensity: String, CaseIterable, Codable, Sendable {
    case bold
    case subtle
    case off
}

/// A named part of the space around the pet that a Radiant effect may draw
/// its particles in. The zones split every frame into disjoint regions,
/// measured from the bare pet in that very frame (`RadiantGeometry`), so two
/// effects given different zones can never draw on the same pixel.
public enum RadiantZone: String, CaseIterable, Codable, Sendable {
    /// Above the head, between its left and right edges.
    case aboveHead
    /// Above the head and left (or right) of it: the frame's top corners.
    case topLeft
    case topRight
    /// Beside the head, from its top down to the chin.
    case leftOfHead
    case rightOfHead
    /// Beside the body, below the chin.
    case leftOfBody
    case rightOfBody
    /// The body's front below the chin, between its edges. Only an effect
    /// that passes in front of the pet (the sorcerer's orb) uses it.
    case chest
}

/// One shape a particle can take: pixels around its center.
struct RadiantShape: Hashable, Sendable {
    let pixels: [RadiantPixel]
}

struct RadiantPixel: Hashable, Sendable {
    let dx: Int
    let dy: Int
    let role: PetPaletteRole
}

/// Where a piece is placed from in each frame.
struct RadiantAnchor: Hashable, Sendable {
    enum Origin: String, Hashable, Sendable {
        /// The bounds of the item's own pixels.
        case item
        /// The item's topmost pixel, the rightmost on that row (a hat's tip).
        case itemTip
        /// The bounds of the bare pet.
        case pet
        /// The bounds of the item's pixels of one role (a cloud's white).
        case itemRole
    }

    let origin: Origin
    /// Percent across and down the bounds, rounded down.
    let x: Int
    let y: Int
    let dx: Int
    let dy: Int
    let role: PetPaletteRole?
}

/// How a particle is drawn.
enum RadiantParticleMode: String, Hashable, Sendable {
    /// In the free air, never touching the pet; left out whole when it would,
    /// so it seems to pass behind.
    case air
    /// Pixel by pixel in the free air: a long shape that goes behind the pet
    /// where it crosses it.
    case behind
    /// Like `behind`, but it may touch the item itself (a rainbow leaving the
    /// cloud).
    case behindItem
    /// A body on an orbit: in front of the pet's fur with an outline ring on
    /// the steps the path marks near, in the free air on the others.
    case orbit
}

/// Which particles of a piece are mirrored.
enum RadiantMirror: String, Hashable, Sendable {
    case none
    /// Every other particle goes to the other side of the face.
    case alternate
    /// Every particle is mirrored about the item's middle column.
    case item
}

/// One part of an effect. Every per-tick table has one entry per tick of the
/// Radiant loop (`RadiantArt.loop`), spelled out in the data so both apps
/// replay it with plain integer math.
enum RadiantPiece: Hashable, Sendable {
    /// A glint over the item's pixels of `roles`: those on diagonal
    /// `positions[tick]` (counted from the top-left of those pixels as
    /// `slant * dx + slope * dy`), `width` diagonals wide, take `color`.
    /// `rows` keeps it to the top rows, `near` to columns that close to the
    /// item's middle.
    case glint(roles: Set<PetPaletteRole>, color: PetPaletteRole, width: Int, slope: Int, slant: Int, rows: Int?,
               near: Int?, positions: [Int?])
    /// The `which` pixels of the item's `roles` (in reading order; negative
    /// counts from the end) take `color` on `ticks`.
    case blink(roles: Set<PetPaletteRole>, which: [Int], color: PetPaletteRole, ticks: Set<Int>)
    /// A glint hopping across groups of touching columns (a crown's points):
    /// the top pixel of each column of group `groups[tick]`, among the item's
    /// pixels of `roles` in its top `abovePercent`, takes `color`. A `spark`
    /// shape floats two rows above the group's middle column.
    case hop(roles: Set<PetPaletteRole>, color: PetPaletteRole, abovePercent: Int, groups: [Int?], spark: String?)
    /// Particles that each follow `path` from the anchor, one step a tick,
    /// drawn as `looks[age]`; one starts on every tick in `starts`. A path
    /// step's third number marks the near side of an orbit.
    case particles(anchor: RadiantAnchor, path: [[Int]], starts: [Int], looks: [String?], mode: RadiantParticleMode,
                   mirror: RadiantMirror)
    /// A particle at a fixed offset from the anchor, drawn as `looks[tick]`.
    case fixed(anchor: RadiantAnchor, offset: [Int], looks: [String?], mode: RadiantParticleMode)
    /// The lower part of a hanging piece (a tassel) swings: the item's pixels
    /// of `roles` in the columns from the item's middle plus `fromMid` to its
    /// right edge plus `toMax`, `fromRow` rows or more below their top, move
    /// `steps[tick]` columns over the fur.
    case swing(roles: Set<PetPaletteRole>, fromMid: Int, toMax: Int, fromRow: Int, steps: [Int])
    /// A drawing (a rainbow) at the anchor, its columns `columns[tick]`
    /// (from, to) shown.
    case grid(anchor: RadiantAnchor, rows: [String], columns: [[Int]?], mode: RadiantParticleMode)
    /// A heartbeat trace written left to right `baseline` rows above the
    /// pet's top: `pulse` gives each column's rise, `pens[tick]` the column
    /// the pen is on, and the last `window` columns show, fading.
    case trace(pulse: [Int], window: Int, pens: [Int?], line: PetPaletteRole, pen: PetPaletteRole,
               fade: PetPaletteRole, baseline: Int, left: Int)
    /// The same trace written on the item itself, across its pixels of
    /// `roles`, `rowPercent` of the way down.
    case surfaceTrace(roles: Set<PetPaletteRole>, pulse: [Int], window: Int, pens: [Int?], line: PetPaletteRole,
                      pen: PetPaletteRole, rowPercent: Int)
    /// A body (a planet) at the anchor with a moon circling it: `moon[tick]`
    /// is its offset and whether it is on the near side, where it passes over
    /// the body in `near`; on the far side the body hides it.
    case satellite(anchor: RadiantAnchor, body: String, moon: [[Int]], near: PetPaletteRole, far: PetPaletteRole)
}

/// One way to lay out an effect: the zones its particles may use and the
/// pieces it draws. Every effect ends on a placement with no zones, which
/// draws on the item alone and so always fits.
struct RadiantPlacement: Hashable, Sendable {
    let zones: Set<RadiantZone>
    let pieces: [RadiantPiece]
}

struct RadiantEffectArt: Hashable, Sendable {
    let name: String
    let placements: [RadiantPlacement]
}

struct RadiantItemArt: Hashable, Sendable {
    let item: PetItem
    let subtle: RadiantEffectArt
    let bold: RadiantEffectArt

    func effect(_ intensity: PetRadiantIntensity) -> RadiantEffectArt? {
        switch intensity {
        case .bold: bold
        case .subtle: subtle
        case .off: nil
        }
    }
}

/// The Radiant effects, read from `Pets/PetArt/radiant.json` (`radiant.v1`),
/// and their measured per-tick pixel costs from `radiant-costs.json`. Both
/// apps read these files, so the Mac and Windows draw the same effects.
struct RadiantArt: Sendable {
    static let schema = "radiant.v1"
    static let costsSchema = "radiant-costs.v1"

    /// Ticks of the item clock in every Radiant loop.
    let loop: Int
    /// A Radiant upgrade costs this many times the item's price.
    let upgradeMultiplier: Int
    /// The order slots claim zones in when several Radiant items are worn.
    let slotPriority: [String]
    let shapes: [String: RadiantShape]
    /// The Closet tile's Radiant pip (`RadiantMarkerArt`).
    let marker: [String]
    /// In catalog order.
    let items: [RadiantItemArt]

    static let shared: RadiantArt = {
        guard let url = KitResources.bundle?.url(forResource: "radiant", withExtension: "json",
                                                 subdirectory: PetArt.subdirectory),
              let data = try? Data(contentsOf: url) else {
            preconditionFailure("Missing pet art \(PetArt.subdirectory)/radiant.json")
        }
        do {
            return try decode(data)
        } catch {
            preconditionFailure("Invalid pet art radiant.json: \(error)")
        }
    }()

    /// Pixels each placement changes from one tick to the next, at most, on
    /// any breed and pose: `[item id][intensity][placement][tick]`.
    static let costs: RadiantCosts = {
        guard let url = KitResources.bundle?.url(forResource: "radiant-costs", withExtension: "json",
                                                 subdirectory: PetArt.subdirectory),
              let data = try? Data(contentsOf: url) else { return RadiantCosts(perTickBudget: 0, combinedBudget: 0, table: [:]) }
        do {
            return try RadiantCosts.decode(data)
        } catch {
            preconditionFailure("Invalid pet art radiant-costs.json: \(error)")
        }
    }()

    func item(_ item: PetItem) -> RadiantItemArt? { items.first { $0.item == item } }

    enum LoadError: Error, Equatable, CustomStringConvertible {
        case unsupportedSchema(String)
        case invalid(String)

        var description: String {
            switch self {
            case .unsupportedSchema(let schema): "Unsupported schema \"\(schema)\"; expected \"\(RadiantArt.schema)\""
            case .invalid(let reason): reason
            }
        }
    }

    static func decode(_ data: Data) throws -> RadiantArt {
        let raw = try JSONDecoder().decode(RawFile.self, from: data)
        guard raw.schema == schema else { throw LoadError.unsupportedSchema(raw.schema) }
        var shapes: [String: RadiantShape] = [:]
        for (name, shape) in raw.shapes {
            var pixels: [RadiantPixel] = []
            for (y, row) in shape.rows.enumerated() {
                for (x, symbol) in row.enumerated() where symbol != "." {
                    guard let role = PetPaletteRole(symbol: symbol) else {
                        throw LoadError.invalid("Shape \"\(name)\": unknown symbol \(symbol)")
                    }
                    pixels.append(RadiantPixel(dx: x - shape.origin[0], dy: y - shape.origin[1], role: role))
                }
            }
            shapes[name] = RadiantShape(pixels: pixels)
        }
        let items = try raw.items.map { item -> RadiantItemArt in
            guard let petItem = PetItem(id: item.item) else { throw LoadError.invalid("Unknown item \(item.item)") }
            return RadiantItemArt(item: petItem, subtle: try item.subtle.art(raw.loop, shapes),
                                  bold: try item.bold.art(raw.loop, shapes))
        }
        guard let width = raw.marker.first?.count, raw.marker.allSatisfy({ $0.count == width }) else {
            throw LoadError.invalid("The marker's rows must all be the same width")
        }
        return RadiantArt(loop: raw.loop, upgradeMultiplier: raw.upgradeMultiplier, slotPriority: raw.slotPriority,
                          shapes: shapes, marker: raw.marker, items: items)
    }

    // MARK: Raw JSON

    private struct RawFile: Decodable {
        let schema: String
        let loop: Int
        let upgradeMultiplier: Int
        let slotPriority: [String]
        let marker: [String]
        let shapes: [String: RawShape]
        let items: [RawItem]
    }

    private struct RawShape: Decodable {
        let rows: [String]
        let origin: [Int]
    }

    private struct RawItem: Decodable {
        let item: String
        let subtle: RawEffect
        let bold: RawEffect
    }

    private struct RawEffect: Decodable {
        let name: String
        let placements: [RawPlacement]

        func art(_ loop: Int, _ shapes: [String: RadiantShape]) throws -> RadiantEffectArt {
            guard placements.last?.zones.isEmpty == true else {
                throw LoadError.invalid("\(name): the last placement must use no zones")
            }
            return RadiantEffectArt(name: name, placements: try placements.map { placement in
                var zones = Set<RadiantZone>()
                for zone in placement.zones {
                    guard let parsed = RadiantZone(rawValue: zone) else { throw LoadError.invalid("\(name): unknown zone \(zone)") }
                    zones.insert(parsed)
                }
                return RadiantPlacement(zones: zones, pieces: try placement.pieces.map { try $0.piece(name, loop, shapes) })
            })
        }
    }

    private struct RawPlacement: Decodable {
        let zones: [String]
        let pieces: [RawPiece]
    }

    private struct RawAnchor: Decodable {
        let of: String
        let x: Int
        let y: Int
        let dx: Int?
        let dy: Int?
        let role: String?

        func anchor(_ effect: String) throws -> RadiantAnchor {
            guard let origin = RadiantAnchor.Origin(rawValue: of) else { throw LoadError.invalid("\(effect): unknown anchor \(of)") }
            let parsed = try role.map { try RawPiece.role($0, effect) }
            if origin == .itemRole, parsed == nil { throw LoadError.invalid("\(effect): itemRole anchor needs a role") }
            return RadiantAnchor(origin: origin, x: x, y: y, dx: dx ?? 0, dy: dy ?? 0, role: parsed)
        }
    }

    private struct RawPiece: Decodable {
        let type: String
        let roles: [String]?
        let color: String?
        let width: Int?
        let slope: Int?
        let slant: Int?
        let rows: RawRows?
        let near: Int?
        let positions: [Int?]?
        let which: [Int]?
        let ticks: [Int]?
        let abovePercent: Int?
        let groups: [Int?]?
        let spark: String?
        let anchor: RawAnchor?
        let path: [[Int]]?
        let starts: [Int]?
        let looks: [String?]?
        let mode: String?
        let mirror: String?
        let offset: [Int]?
        let fromMid: Int?
        let toMax: Int?
        let fromRow: Int?
        let steps: [Int]?
        let columns: [[Int]?]?
        let pulse: [Int]?
        let window: Int?
        let pens: [Int?]?
        let line: String?
        let pen: String?
        let fade: String?
        let baseline: Int?
        let left: Int?
        let rowPercent: Int?
        let body: String?
        let moon: [[Int]]?
        let far: String?
        // `near` doubles as the satellite's near-side role, so it is read as either.
        let nearRole: String?

        enum CodingKeys: String, CodingKey {
            case type, roles, color, width, slope, slant, rows, near, positions, which, ticks, abovePercent, groups,
                 spark, anchor, path, starts, looks, mode, mirror, offset, fromMid, toMax, fromRow, steps, columns,
                 pulse, window, pens, line, pen, fade, baseline, left, rowPercent, body, moon, far
        }

        /// `rows` is a count for a glint and the art for a grid.
        enum RawRows: Decodable {
            case count(Int)
            case art([String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let count = try? container.decode(Int.self) { self = .count(count) } else {
                    self = .art(try container.decode([String].self))
                }
            }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            roles = try c.decodeIfPresent([String].self, forKey: .roles)
            color = try c.decodeIfPresent(String.self, forKey: .color)
            width = try c.decodeIfPresent(Int.self, forKey: .width)
            slope = try c.decodeIfPresent(Int.self, forKey: .slope)
            slant = try c.decodeIfPresent(Int.self, forKey: .slant)
            rows = try c.decodeIfPresent(RawRows.self, forKey: .rows)
            if let number = try? c.decodeIfPresent(Int.self, forKey: .near) {
                near = number
                nearRole = nil
            } else {
                near = nil
                nearRole = try c.decodeIfPresent(String.self, forKey: .near)
            }
            positions = try c.decodeIfPresent([Int?].self, forKey: .positions)
            which = try c.decodeIfPresent([Int].self, forKey: .which)
            ticks = try c.decodeIfPresent([Int].self, forKey: .ticks)
            abovePercent = try c.decodeIfPresent(Int.self, forKey: .abovePercent)
            groups = try c.decodeIfPresent([Int?].self, forKey: .groups)
            spark = try c.decodeIfPresent(String.self, forKey: .spark)
            anchor = try c.decodeIfPresent(RawAnchor.self, forKey: .anchor)
            path = try c.decodeIfPresent([[Int]].self, forKey: .path)
            starts = try c.decodeIfPresent([Int].self, forKey: .starts)
            looks = try c.decodeIfPresent([String?].self, forKey: .looks)
            mode = try c.decodeIfPresent(String.self, forKey: .mode)
            mirror = try c.decodeIfPresent(String.self, forKey: .mirror)
            offset = try c.decodeIfPresent([Int].self, forKey: .offset)
            fromMid = try c.decodeIfPresent(Int.self, forKey: .fromMid)
            toMax = try c.decodeIfPresent(Int.self, forKey: .toMax)
            fromRow = try c.decodeIfPresent(Int.self, forKey: .fromRow)
            steps = try c.decodeIfPresent([Int].self, forKey: .steps)
            columns = try c.decodeIfPresent([[Int]?].self, forKey: .columns)
            pulse = try c.decodeIfPresent([Int].self, forKey: .pulse)
            window = try c.decodeIfPresent(Int.self, forKey: .window)
            pens = try c.decodeIfPresent([Int?].self, forKey: .pens)
            line = try c.decodeIfPresent(String.self, forKey: .line)
            pen = try c.decodeIfPresent(String.self, forKey: .pen)
            fade = try c.decodeIfPresent(String.self, forKey: .fade)
            baseline = try c.decodeIfPresent(Int.self, forKey: .baseline)
            left = try c.decodeIfPresent(Int.self, forKey: .left)
            rowPercent = try c.decodeIfPresent(Int.self, forKey: .rowPercent)
            body = try c.decodeIfPresent(String.self, forKey: .body)
            moon = try c.decodeIfPresent([[Int]].self, forKey: .moon)
            far = try c.decodeIfPresent(String.self, forKey: .far)
        }

        static func role(_ symbol: String, _ effect: String) throws -> PetPaletteRole {
            guard symbol.count == 1, let role = PetPaletteRole(symbol: Character(symbol)) else {
                throw LoadError.invalid("\(effect): unknown role \(symbol)")
            }
            return role
        }

        func need<T>(_ value: T?, _ key: String, _ effect: String) throws -> T {
            guard let value else { throw LoadError.invalid("\(effect): \(type) needs \(key)") }
            return value
        }

        func roleSet(_ effect: String) throws -> Set<PetPaletteRole> {
            Set(try need(roles, "roles", effect).map { try Self.role($0, effect) })
        }

        func perTick<T>(_ values: [T]?, _ key: String, _ effect: String, _ loop: Int) throws -> [T] {
            let values = try need(values, key, effect)
            guard values.count == loop else {
                throw LoadError.invalid("\(effect): \(type) \(key) has \(values.count) entries, not \(loop)")
            }
            return values
        }

        func looksChecked(_ looks: [String?], _ effect: String, _ shapes: [String: RadiantShape]) throws -> [String?] {
            for case let name? in looks where shapes[name] == nil {
                throw LoadError.invalid("\(effect): unknown shape \(name)")
            }
            return looks
        }

        func particleMode(_ effect: String) throws -> RadiantParticleMode {
            guard let mode = RadiantParticleMode(rawValue: mode ?? "air") else {
                throw LoadError.invalid("\(effect): unknown mode \(mode ?? "")")
            }
            return mode
        }

        func piece(_ effect: String, _ loop: Int, _ shapes: [String: RadiantShape]) throws -> RadiantPiece {
            switch type {
            case "glint":
                guard case .count(let count)? = rows ?? .count(Int.max) else {
                    throw LoadError.invalid("\(effect): glint rows must be a count")
                }
                return .glint(roles: try roleSet(effect), color: try Self.role(try need(color, "color", effect), effect),
                              width: width ?? 1, slope: slope ?? 1, slant: slant ?? 1,
                              rows: count == Int.max ? nil : count, near: near,
                              positions: try perTick(positions, "positions", effect, loop))
            case "blink":
                return .blink(roles: try roleSet(effect), which: try need(which, "which", effect),
                              color: try Self.role(try need(color, "color", effect), effect),
                              ticks: Set(try need(ticks, "ticks", effect)))
            case "hop":
                if let spark, shapes[spark] == nil { throw LoadError.invalid("\(effect): unknown shape \(spark)") }
                return .hop(roles: try roleSet(effect), color: try Self.role(try need(color, "color", effect), effect),
                            abovePercent: try need(abovePercent, "abovePercent", effect),
                            groups: try perTick(groups, "groups", effect, loop), spark: spark)
            case "particles":
                let path = try need(path, "path", effect)
                let looks = try looksChecked(try need(looks, "looks", effect), effect, shapes)
                guard looks.count == path.count, path.allSatisfy({ $0.count >= 2 }) else {
                    throw LoadError.invalid("\(effect): particles need one look per path step")
                }
                guard let mirror = RadiantMirror(rawValue: mirror ?? "none") else {
                    throw LoadError.invalid("\(effect): unknown mirror")
                }
                return .particles(anchor: try need(anchor, "anchor", effect).anchor(effect), path: path,
                                  starts: try need(starts, "starts", effect), looks: looks, mode: try particleMode(effect),
                                  mirror: mirror)
            case "fixed":
                return .fixed(anchor: try need(anchor, "anchor", effect).anchor(effect), offset: offset ?? [0, 0],
                              looks: try looksChecked(try perTick(looks, "looks", effect, loop), effect, shapes),
                              mode: try particleMode(effect))
            case "swing":
                return .swing(roles: try roleSet(effect), fromMid: fromMid ?? 0, toMax: toMax ?? 0, fromRow: fromRow ?? 0,
                              steps: try perTick(steps, "steps", effect, loop))
            case "grid":
                guard case .art(let art)? = rows else { throw LoadError.invalid("\(effect): grid needs rows") }
                for row in art {
                    for symbol in row where symbol != "." && PetPaletteRole(symbol: symbol) == nil {
                        throw LoadError.invalid("\(effect): unknown symbol \(symbol)")
                    }
                }
                return .grid(anchor: try need(anchor, "anchor", effect).anchor(effect), rows: art,
                             columns: try perTick(columns, "columns", effect, loop), mode: try particleMode(effect))
            case "trace":
                return .trace(pulse: try need(pulse, "pulse", effect), window: window ?? 8,
                              pens: try perTick(pens, "pens", effect, loop),
                              line: try Self.role(try need(line, "line", effect), effect),
                              pen: try Self.role(try need(pen, "pen", effect), effect),
                              fade: try Self.role(try need(fade, "fade", effect), effect),
                              baseline: baseline ?? -3, left: left ?? 0)
            case "surfaceTrace":
                return .surfaceTrace(roles: try roleSet(effect), pulse: try need(pulse, "pulse", effect),
                                     window: window ?? 8, pens: try perTick(pens, "pens", effect, loop),
                                     line: try Self.role(try need(line, "line", effect), effect),
                                     pen: try Self.role(try need(pen, "pen", effect), effect),
                                     rowPercent: try need(rowPercent, "rowPercent", effect))
            case "satellite":
                let body = try need(body, "body", effect)
                guard shapes[body] != nil else { throw LoadError.invalid("\(effect): unknown shape \(body)") }
                let moon = try perTick(moon, "moon", effect, loop)
                guard moon.allSatisfy({ $0.count == 3 }) else { throw LoadError.invalid("\(effect): moon steps need 3 numbers") }
                return .satellite(anchor: try need(anchor, "anchor", effect).anchor(effect), body: body, moon: moon,
                                  near: try Self.role(try need(nearRole, "near", effect), effect),
                                  far: try Self.role(try need(far, "far", effect), effect))
            default:
                throw LoadError.invalid("\(effect): unknown piece type \(type)")
            }
        }
    }
}

/// The measured cost of every placement (pixels changed from one tick to the
/// next, at most, over every breed and pose) and the Radiant budgets, from
/// `radiant-costs.json`. `RadiantBudgetTests` records the costs and checks
/// them against the effects as drawn.
struct RadiantCosts: Hashable, Sendable {
    /// The most pixels one Radiant effect may change from one tick to the next.
    let perTickBudget: Int
    /// The most pixels all the Radiant effects worn together may change from
    /// one tick to the next.
    let combinedBudget: Int
    /// `[item id][intensity]` to one row of per-tick costs per placement.
    let table: [String: [String: [[Int]]]]

    func cost(_ item: PetItem, _ intensity: PetRadiantIntensity, placement: Int) -> [Int]? {
        table[item.id]?[intensity.rawValue]?[safe: placement]
    }

    static func decode(_ data: Data) throws -> RadiantCosts {
        struct Raw: Decodable {
            let schema: String
            let perTickBudget: Int
            let combinedBudget: Int
            let costs: [String: [String: [[Int]]]]
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        guard raw.schema == RadiantArt.costsSchema else { throw RadiantArt.LoadError.unsupportedSchema(raw.schema) }
        return RadiantCosts(perTickBudget: raw.perTickBudget, combinedBudget: raw.combinedBudget, table: raw.costs)
    }
}

fileprivate extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
