import Foundation

/// A rectangle of frame pixels, inclusive.
struct RadiantBox: Hashable, Sendable {
    var minX: Int, minY: Int, maxX: Int, maxY: Int

    var midX: Int { (minX + maxX) / 2 }

    func contains(_ x: Int, _ y: Int) -> Bool { x >= minX && x <= maxX && y >= minY && y <= maxY }

    /// The pixel `px` percent across and `py` percent down, rounded down.
    func at(_ px: Int, _ py: Int) -> PetPoint {
        PetPoint(x: minX + (maxX - minX) * px / 100, y: minY + (maxY - minY) * py / 100)
    }

    static func around(_ points: some Sequence<PetPoint>) -> RadiantBox? {
        var box: RadiantBox?
        for p in points {
            if var current = box {
                current.minX = min(current.minX, p.x); current.maxX = max(current.maxX, p.x)
                current.minY = min(current.minY, p.y); current.maxY = max(current.maxY, p.y)
                box = current
            } else {
                box = RadiantBox(minX: p.x, minY: p.y, maxX: p.x, maxY: p.y)
            }
        }
        return box
    }
}

/// Where the pet is in one frame, measured from the bare pet: its bounds,
/// its face, and the zones around it (`RadiantZone`).
///
/// The head runs from the pet's top row down to the chin (two rows under
/// the lowest eye, nose or mouth pixel); the zones beside it are the columns
/// left and right of the head's widest pixels, and below the chin the
/// columns beside the body's. So every pixel of the frame falls in exactly
/// one zone or on the head itself, in every pose.
struct RadiantGeometry: Hashable, Sendable {
    static let effectRoles: Set<PetPaletteRole> = [.effect, .effectFaint, .heart]
    static let eyeRoles: Set<PetPaletteRole> = [.eye, .pupil, .eyeLight]
    static let faceRoles: Set<PetPaletteRole> = [.eye, .pupil, .eyeLight, .nose, .mouth]
    /// How far around the eyes, nose and mouth nothing may be drawn over the pet.
    static let faceMargin = 3

    let pet: RadiantBox?
    /// The eyes, nose and mouth.
    let face: RadiantBox?
    let top: Int
    let chin: Int
    let head: ClosedRange<Int>
    let body: ClosedRange<Int>

    init(bare: PetCanvas) {
        var petPoints: [PetPoint] = []
        var facePoints: [PetPoint] = []
        for y in 0..<bare.height {
            for x in 0..<bare.width {
                guard let role = bare[x, y], !Self.effectRoles.contains(role) else { continue }
                petPoints.append(PetPoint(x: x, y: y))
                if Self.faceRoles.contains(role) { facePoints.append(PetPoint(x: x, y: y)) }
            }
        }
        pet = RadiantBox.around(petPoints)
        face = RadiantBox.around(facePoints)
        top = pet?.minY ?? bare.height
        chin = min(bare.height - 1, (face?.maxY ?? top) + 2)
        let chinRow = chin
        let headXs = petPoints.filter { $0.y <= chinRow }.map(\.x)
        let bodyXs = petPoints.filter { $0.y > chinRow }.map(\.x)
        let headRange = (headXs.min() ?? 0)...(headXs.max() ?? 0)
        head = headRange
        body = bodyXs.isEmpty ? headRange : (bodyXs.min()!)...(bodyXs.max()!)
    }

    /// The face grown by `faceMargin`.
    var faceGuard: RadiantBox? {
        face.map { RadiantBox(minX: $0.minX - Self.faceMargin, minY: $0.minY - Self.faceMargin,
                              maxX: $0.maxX + Self.faceMargin, maxY: $0.maxY + Self.faceMargin) }
    }

    /// The zone a pixel is in, or nil on the head itself.
    func zone(_ x: Int, _ y: Int) -> RadiantZone? {
        guard pet != nil else { return nil }
        if y < top {
            return x < head.lowerBound ? .topLeft : x > head.upperBound ? .topRight : .aboveHead
        }
        if y <= chin {
            return x < head.lowerBound ? .leftOfHead : x > head.upperBound ? .rightOfHead : nil
        }
        return x < body.lowerBound ? .leftOfBody : x > body.upperBound ? .rightOfBody : .chest
    }
}

/// One Radiant item in a frame: the pixels it drew (the frame with it minus
/// the frame without it) and their bounds.
struct RadiantItemScene: Sendable {
    let pixels: [Int: PetPaletteRole]
    let width: Int
    /// The item's pixels in reading order, with their roles.
    let ordered: [(index: Int, role: PetPaletteRole)]
    /// Bounds of the item's pixels, outline left out.
    let box: RadiantBox?

    init(with: PetCanvas, without: PetCanvas) {
        var pixels: [Int: PetPaletteRole] = [:]
        var ordered: [(index: Int, role: PetPaletteRole)] = []
        for i in with.pixels.indices {
            guard let role = with.pixels[i], role != without.pixels[i] else { continue }
            pixels[i] = role
            ordered.append((i, role))
        }
        self.pixels = pixels
        self.ordered = ordered
        width = with.width
        box = RadiantBox.around(ordered.filter { $0.role != .outline }.map { PetPoint(x: $0.index % with.width, y: $0.index / with.width) })
    }

    func point(_ index: Int) -> PetPoint { PetPoint(x: index % width, y: index / width) }

    /// The item's pixels of `roles`, in reading order.
    func points(_ roles: Set<PetPaletteRole>) -> [PetPoint] {
        ordered.filter { roles.contains($0.role) }.map { point($0.index) }
    }
}

/// What one effect draws in a frame before it is placed.
struct RadiantLayer: Sendable {
    struct Particle: Sendable {
        var pixels: [(PetPoint, PetPaletteRole)]
        var mode: RadiantParticleMode
        /// For an orbit: the near side, drawn in front of the pet.
        var near = false
    }

    /// Item pixels recolored, by point.
    var recolor: [PetPoint: PetPaletteRole] = [:]
    /// Item pixels moved over the fur (a swinging tassel).
    var moves: [(from: [PetPoint], to: [(PetPoint, PetPaletteRole)])] = []
    var particles: [Particle] = []
}

/// What `RadiantRenderer.render` did, for the tests: which effect drew each
/// pixel, and how many particle pixels another effect's pixels kept out.
struct RadiantRenderReport: Sendable {
    /// Per frame pixel, the index of the job that drew it, or -1.
    var owner: [Int] = []
    var collisions = 0
}

/// Draws Radiant effects onto a composed frame.
enum RadiantRenderer {
    /// One effect to draw: its placement, the tick of its own loop, and its
    /// item in this frame.
    struct Job: Sendable {
        let placement: RadiantPlacement
        let tick: Int
        let item: RadiantItemScene
    }

    /// Draws `jobs` in order onto `dressed` (the pet in all its items, with
    /// its effects). Recolors land only on each effect's own item; moved
    /// pixels only on fur outside the face; particles only in their
    /// placement's zones, in the free air (or, for an orbit's near side, over
    /// fur outside the face), never on or beside a pixel another effect drew,
    /// inside a one-pixel margin and below `ceiling`. Nothing floats while
    /// the pet hangs from the notch.
    static func render(_ jobs: [Job], dressed: PetCanvas, bare: PetCanvas, geometry: RadiantGeometry? = nil,
                       hanging: Bool, ceiling: Int?, art: RadiantArt = .shared,
                       report: inout RadiantRenderReport) -> PetCanvas {
        let geometry = geometry ?? RadiantGeometry(bare: bare)
        var out = dressed
        let width = dressed.width, height = dressed.height
        let top = max(1, ceiling ?? 1)
        func index(_ p: PetPoint) -> Int { p.y * width + p.x }
        func inBounds(_ p: PetPoint) -> Bool { p.x >= 1 && p.x <= width - 2 && p.y >= top && p.y <= height - 2 }
        func neighbors(_ p: PetPoint) -> [PetPoint] {
            [PetPoint(x: p.x - 1, y: p.y), PetPoint(x: p.x + 1, y: p.y), PetPoint(x: p.x, y: p.y - 1),
             PetPoint(x: p.x, y: p.y + 1)]
        }
        /// Whether `test` holds for the four neighbors of `p` (off the frame counts as empty).
        func around(_ p: PetPoint, _ test: (Int, Int) -> Bool) -> Bool {
            test(p.x - 1, p.y) && test(p.x + 1, p.y) && test(p.x, p.y - 1) && test(p.x, p.y + 1)
        }
        if report.owner.count != width * height { report.owner = Array(repeating: -1, count: width * height) }
        func ownerAt(_ x: Int, _ y: Int) -> Int {
            x >= 0 && y >= 0 && x < width && y < height ? report.owner[y * width + x] : -1
        }
        let faceGuard = geometry.faceGuard
        func inFace(_ p: PetPoint) -> Bool { faceGuard?.contains(p.x, p.y) ?? false }
        /// Fur: part of the bare pet, not covered by an item or effect.
        func isFur(_ p: PetPoint) -> Bool {
            guard let role = dressed[p.x, p.y] else { return false }
            return bare[p.x, p.y] == role && !RadiantGeometry.faceRoles.contains(role)
                && !RadiantGeometry.effectRoles.contains(role)
        }

        for (n, job) in jobs.enumerated() {
            let layer = self.layer(job, geometry: geometry, art: art)
            /// Free of every other effect's pixels, and of the space beside them.
            func clearOfOthers(_ p: PetPoint) -> Bool {
                let own = ownerAt(p.x, p.y)
                return (own == -1 || own == n) && around(p) { let o = ownerAt($0, $1); return o == -1 || o == n }
            }
            func claim(_ p: PetPoint, _ role: PetPaletteRole) {
                out[p.x, p.y] = role
                report.owner[index(p)] = n
            }
            for (p, role) in layer.recolor where job.item.pixels[index(p)] != nil {
                claim(p, role)
            }
            for move in layer.moves {
                // Onto fur or the item's own pixels (inner lines included),
                // never onto the silhouette's edge.
                let fits = move.to.allSatisfy { p, _ in
                    let own = job.item.pixels[index(p)] != nil
                    return inBounds(p) && (isFur(p) || own) && !inFace(p)
                        && (report.owner[index(p)] == -1 || report.owner[index(p)] == n)
                        && around(p) { dressed[$0, $1] != nil }
                }
                guard fits else { continue }
                for p in move.from where job.item.pixels[index(p)] != nil {
                    out[p.x, p.y] = bare[p.x, p.y]
                    report.owner[index(p)] = n
                }
                for (p, role) in move.to { claim(p, role) }
            }
            guard !hanging else { continue }
            let zones = job.placement.zones
            func inZone(_ p: PetPoint) -> Bool { geometry.zone(p.x, p.y).map(zones.contains) ?? false }
            func free(_ p: PetPoint) -> Bool {
                inBounds(p) && inZone(p) && dressed[p.x, p.y] == nil && around(p) { dressed[$0, $1] == nil }
            }
            func freeBesideItem(_ p: PetPoint) -> Bool {
                inBounds(p) && inZone(p) && dressed[p.x, p.y] == nil
                    && around(p) { dressed[$0, $1] == nil || job.item.pixels[$1 * width + $0] != nil }
            }
            for particle in layer.particles {
                enum Kind { case whole, pixels(besideItem: Bool), front }
                let kind: Kind = switch particle.mode {
                case .air: .whole
                case .orbit: particle.near ? .front : .whole
                case .behind: .pixels(besideItem: false)
                case .behindItem: .pixels(besideItem: true)
                }
                switch kind {
                case .whole:
                    guard particle.pixels.allSatisfy({ free($0.0) }) else { continue }
                    guard particle.pixels.allSatisfy({ clearOfOthers($0.0) }) else {
                        report.collisions += particle.pixels.count
                        continue
                    }
                    for (p, role) in particle.pixels { claim(p, role) }
                case .pixels(let besideItem):
                    for (p, role) in particle.pixels {
                        guard besideItem ? freeBesideItem(p) : free(p) else { continue }
                        guard clearOfOthers(p) else {
                            report.collisions += 1
                            continue
                        }
                        claim(p, role)
                    }
                case .front:
                    let own = Set(particle.pixels.map { index($0.0) })
                    let ring = Set(particle.pixels.flatMap { neighbors($0.0) }.filter {
                        !own.contains(index($0)) && dressed[$0.x, $0.y] != nil
                    }.map(index)).sorted().map { PetPoint(x: $0 % width, y: $0 / width) }
                    let fits = particle.pixels.allSatisfy { p, _ in
                        inBounds(p) && inZone(p) && !inFace(p) && (dressed[p.x, p.y] == nil || isFur(p))
                    } && ring.allSatisfy { inBounds($0) && inZone($0) && !inFace($0) && isFur($0) }
                    guard fits else { continue }
                    guard (particle.pixels.map(\.0) + ring).allSatisfy(clearOfOthers) else {
                        report.collisions += particle.pixels.count
                        continue
                    }
                    for (p, role) in particle.pixels { claim(p, role) }
                    for p in ring { claim(p, .outline) }
                }
            }
        }
        return out
    }

    // MARK: Pieces

    static func layer(_ job: Job, geometry: RadiantGeometry, art: RadiantArt) -> RadiantLayer {
        var layer = RadiantLayer()
        let tick = job.tick, item = job.item
        let loop = art.loop
        func anchorPoint(_ anchor: RadiantAnchor) -> PetPoint? {
            let base: PetPoint?
            switch anchor.origin {
            case .item: base = item.box?.at(anchor.x, anchor.y)
            case .itemTip:
                let points = item.ordered.filter { $0.role != .outline }.map { item.point($0.index) }
                if let top = points.map(\.y).min() {
                    base = points.filter { $0.y == top }.max { $0.x < $1.x }
                } else {
                    base = nil
                }
            case .pet: base = geometry.pet?.at(anchor.x, anchor.y)
            case .itemRole: base = RadiantBox.around(item.points([anchor.role!])).map { $0.at(anchor.x, anchor.y) }
            }
            return base.map { PetPoint(x: $0.x + anchor.dx, y: $0.y + anchor.dy) }
        }
        func shape(_ name: String, at center: PetPoint) -> [(PetPoint, PetPaletteRole)] {
            (art.shapes[name]?.pixels ?? []).map { (PetPoint(x: center.x + $0.dx, y: center.y + $0.dy), $0.role) }
        }
        for piece in job.placement.pieces {
            switch piece {
            case let .glint(roles, color, width, slope, slant, rows, near, positions):
                guard let at = positions[tick % loop] else { continue }
                let points = item.points(roles)
                guard let minX = points.map(\.x).min(), let minY = points.map(\.y).min() else { continue }
                let mid = item.box?.midX ?? minX
                for p in points {
                    if let rows, p.y - minY >= rows { continue }
                    if let near, abs(p.x - mid) > near { continue }
                    let diagonal = slant * (p.x - minX) + slope * (p.y - minY)
                    if diagonal >= at && diagonal < at + width { layer.recolor[p] = color }
                }
            case let .blink(roles, which, color, ticks):
                guard ticks.contains(tick % loop) else { continue }
                let points = item.points(roles)
                for n in which {
                    let i = n < 0 ? points.count + n : n
                    if points.indices.contains(i) { layer.recolor[points[i]] = color }
                }
            case let .hop(roles, color, abovePercent, groups, spark):
                guard let g = groups[tick % loop], let box = item.box else { continue }
                let limit = box.minY + (box.maxY - box.minY) * abovePercent / 100
                let points = item.points(roles).filter { $0.y <= limit }
                var runs: [[Int]] = []
                for x in Set(points.map(\.x)).sorted() {
                    if let last = runs.last?.last, x == last + 1 { runs[runs.count - 1].append(x) } else { runs.append([x]) }
                }
                guard !runs.isEmpty else { continue }
                let run = runs[g % runs.count]
                var tops: [PetPoint] = []
                for x in run {
                    if let p = points.filter({ $0.x == x }).min(by: { $0.y < $1.y }) {
                        layer.recolor[p] = color
                        tops.append(p)
                    }
                }
                if let spark, let highest = tops.min(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
                    let center = PetPoint(x: run[run.count / 2], y: highest.y - 2)
                    layer.particles.append(.init(pixels: shape(spark, at: center), mode: .air))
                }
            case let .particles(anchor, path, starts, looks, mode, mirror):
                guard let origin = anchorPoint(anchor) else { continue }
                for (n, start) in starts.enumerated() {
                    let age = ((tick - start) % loop + loop) % loop
                    guard age < path.count, let look = looks[age] else { continue }
                    let step = path[age]
                    var pixels = shape(look, at: PetPoint(x: origin.x + step[0], y: origin.y + step[1]))
                    let axis: Int? = switch mirror {
                    case .none: nil
                    case .alternate: n % 2 == 1 ? (geometry.face ?? geometry.pet).map { $0.minX + $0.maxX } : nil
                    case .item: item.box.map { $0.minX + $0.maxX }
                    }
                    if let axis { pixels = pixels.map { (PetPoint(x: axis - $0.0.x, y: $0.0.y), $0.1) } }
                    layer.particles.append(.init(pixels: pixels, mode: mode, near: step.count > 2 && step[2] == 1))
                }
            case let .fixed(anchor, offset, looks, mode):
                guard let look = looks[tick % loop], let origin = anchorPoint(anchor) else { continue }
                let center = PetPoint(x: origin.x + offset[0], y: origin.y + (offset.count > 1 ? offset[1] : 0))
                layer.particles.append(.init(pixels: shape(look, at: center), mode: mode))
            case let .swing(roles, fromMid, toMax, fromRow, steps):
                let dx = steps[tick % loop]
                guard dx != 0, let box = item.box else { continue }
                let columns = (box.midX + fromMid)...max(box.midX + fromMid, box.maxX + toMax)
                let piece = item.points(roles).filter { columns.contains($0.x) }
                guard let pieceTop = piece.map(\.y).min() else { continue }
                let moving = piece.filter { $0.y >= pieceTop + fromRow }
                guard !moving.isEmpty else { continue }
                layer.moves.append((from: moving,
                                    to: moving.map { (PetPoint(x: $0.x + dx, y: $0.y), item.pixels[$0.y * item.width + $0.x]!) }))
            case let .grid(anchor, rows, columns, mode):
                guard let shown = columns[tick % loop], shown.count == 2, let origin = anchorPoint(anchor) else { continue }
                var pixels: [(PetPoint, PetPaletteRole)] = []
                for (y, row) in rows.enumerated() {
                    for (x, symbol) in row.enumerated() where x >= shown[0] && x < shown[1] {
                        guard let role = PetPaletteRole(symbol: symbol) else { continue }
                        pixels.append((PetPoint(x: origin.x + x, y: origin.y + y), role))
                    }
                }
                layer.particles.append(.init(pixels: pixels, mode: mode))
            case let .trace(pulse, window, pens, line, pen, fade, baseline, left):
                guard let at = pens[tick % loop], let pet = geometry.pet else { continue }
                let base = pet.minY + baseline, start = pet.minX + left
                var pixels: [(PetPoint, PetPaletteRole)] = []
                for i in max(0, at - window)...at where i < pulse.count {
                    let y = base + pulse[i], previous = i > 0 ? base + pulse[i - 1] : y
                    let role = i == at ? pen : i < at - window / 2 ? fade : line
                    for row in min(y, previous)...max(y, previous) {
                        pixels.append((PetPoint(x: start + i, y: row), role))
                    }
                }
                layer.particles.append(.init(pixels: pixels, mode: .behind))
            case let .surfaceTrace(roles, pulse, window, pens, line, pen, rowPercent):
                guard let at = pens[tick % loop], let box = item.box else { continue }
                let base = box.minY + (box.maxY - box.minY) * rowPercent / 100, start = box.minX + 1
                let surface = Set(item.points(roles))
                for i in max(0, at - window)...at where i < pulse.count {
                    let y = base + pulse[i], previous = i > 0 ? base + pulse[i - 1] : y
                    for row in min(y, previous)...max(y, previous) {
                        let p = PetPoint(x: start + i, y: row)
                        if surface.contains(p) { layer.recolor[p] = i == at ? pen : line }
                    }
                }
            case let .satellite(anchor, body, moon, nearRole, farRole):
                guard let center = anchorPoint(anchor) else { continue }
                let planet = shape(body, at: center)
                let step = moon[tick % loop]
                let spot = PetPoint(x: center.x + step[0], y: center.y + step[1])
                let covered = planet.contains { $0.0 == spot }
                layer.particles.append(.init(pixels: planet, mode: .air))
                if step[2] == 1 {
                    layer.particles.append(.init(pixels: [(spot, nearRole)], mode: .air))
                } else if !covered {
                    layer.particles.append(.init(pixels: [(spot, farRole)], mode: .air))
                }
            }
        }
        return layer
    }
}
