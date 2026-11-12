import Foundation
import TabbiKitCore

// Radiant upgrades, design round (not shipped): an owned Showpiece bought a
// second time keeps its look and gains an animated effect. Effects are built
// from a few reusable pieces (a glint sweeping an item's pixels, a pixel
// blinking, particles drifting along a path, an orbit, a burst), placed from
// what the real composer drew: the item's own pixels (the dressed frame minus
// the bare one), the pet's bounds and its face. So one effect fits every breed
// and pose, and adding an item is one entry in `RadiantCatalog.items`.

/// One composed frame of the pet wearing the normal item, plus what the
/// effect pieces are placed from.
struct RadiantScene: Sendable {
    /// The pet in the normal item at this tick, effects (heart, "z") included.
    let dressed: PetCanvas
    /// The same frame undressed.
    let bare: PetCanvas
    /// Pixels the item drew (index into the canvas), with their role.
    let item: [Int: PetPaletteRole]
    let animation: PetAnimation
    /// Nothing is drawn above this row (the closed notch), or nil.
    let ceiling: Int?

    struct Box {
        var minX: Int, minY: Int, maxX: Int, maxY: Int
        var midX: Int { (minX + maxX) / 2 }
        var midY: Int { (minY + maxY) / 2 }
        func shifted(_ dy: Int) -> Box { Box(minX: minX, minY: minY + dy, maxX: maxX, maxY: maxY + dy) }
    }

    static let effectRoles: Set<PetPaletteRole> = [.effect, .effectFaint, .heart]
    static let eyeRoles: Set<PetPaletteRole> = [.eye, .pupil, .eyeLight]
    static let faceRoles: Set<PetPaletteRole> = [.eye, .pupil, .eyeLight, .nose, .mouth]

    var width: Int { dressed.width }
    func point(_ index: Int) -> PetPoint { PetPoint(x: index % width, y: index / width) }
    func index(_ p: PetPoint) -> Int { p.y * width + p.x }

    /// The item's pixels of `roles`, top to bottom, left to right.
    func itemPixels(_ roles: Set<PetPaletteRole>) -> [PetPoint] {
        item.filter { roles.contains($0.value) }.keys.sorted().map(point)
    }

    /// Bounds of the item's pixels (outline left out).
    var itemBox: Box? { box(item.filter { $0.value != .outline }.keys.map(point)) }

    /// Bounds of the bare pet (its effects left out).
    var petBox: Box? {
        box(bare.pixels.indices.filter { bare.pixels[$0] != nil && !Self.effectRoles.contains(bare.pixels[$0]!) }
            .map(point))
    }

    /// The face (eyes, nose, mouth) grown by 3 pixels: nothing may cover it.
    var faceBox: Box? {
        guard let face = box(bare.pixels.indices.filter { bare.pixels[$0].map(Self.faceRoles.contains) ?? false }
            .map(point)) else { return nil }
        return Box(minX: face.minX - 3, minY: face.minY - 3, maxX: face.maxX + 3, maxY: face.maxY + 3)
    }

    var hanging: Bool { animation == .peekIn || animation == .peekOut }

    func box(_ points: [PetPoint]) -> Box? {
        guard let first = points.first else { return nil }
        return points.reduce(Box(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)) { box, p in
            Box(minX: min(box.minX, p.x), minY: min(box.minY, p.y), maxX: max(box.maxX, p.x), maxY: max(box.maxY, p.y))
        }
    }
}

/// What an effect adds on one tick.
struct RadiantLayer {
    /// Item pixels recolored (a glint), keyed by point.
    var recolor: [PetPoint: PetPaletteRole] = [:]
    /// Item pixels moved: cleared back to the bare pet, then painted at a
    /// new spot over fur (a swinging tassel).
    var move: [(from: [PetPoint], to: [(PetPoint, PetPaletteRole)])] = []
    var particles: [RadiantParticle] = []

    mutating func merge(_ other: RadiantLayer) {
        recolor.merge(other.recolor) { _, new in new }
        move += other.move
        particles += other.particles
    }
}

struct RadiantParticle {
    enum Mode {
        /// In the free air, never touching the pet; left out whole when it
        /// would (it seems to pass behind), like an aura petal.
        case air
        /// Pixel by pixel in the free air: a long shape (a rainbow, a trace)
        /// that disappears behind the pet where it crosses it.
        case behind
        /// Like `behind`, but may touch the item itself (a rainbow leaving
        /// the cloud), never the pet.
        case behindItem
        /// In front of the body with an outline ring cut around it, so it
        /// reads on fur; left out whole near the face.
        case front
    }
    var pixels: [(PetPoint, PetPaletteRole)]
    var mode: Mode = .air
}

/// A part of an effect: what it adds on a tick, from the scene.
typealias RadiantPiece = @Sendable (RadiantScene, Int) -> RadiantLayer

struct RadiantEffect: Sendable {
    let name: String
    /// Ticks of `PetFrame.itemFrameDuration` (150 ms) before it repeats.
    let loop: Int
    let summary: [String]
    let pieces: [RadiantPiece]

    func layer(_ scene: RadiantScene, tick: Int) -> RadiantLayer {
        var layer = RadiantLayer()
        for piece in pieces { layer.merge(piece(scene, tick % loop)) }
        return layer
    }
}

// MARK: - Applying a layer

extension RadiantScene {
    /// The frame with the effect: recolors land only on the item, moved
    /// pixels only on fur outside the face, particles by their mode.
    func render(_ layer: RadiantLayer) -> PetCanvas {
        var out = dressed
        for (p, role) in layer.recolor where item[index(p)] != nil {
            out[p.x, p.y] = role
        }
        let face = faceBox
        func inFace(_ p: PetPoint) -> Bool {
            guard let face else { return false }
            return p.x >= face.minX && p.x <= face.maxX && p.y >= face.minY && p.y <= face.maxY
        }
        for move in layer.move {
            let targets = move.to.filter { p, _ in
                guard let under = dressed[p.x, p.y], !inFace(p) else { return false }
                if Self.faceRoles.contains(under) || Self.effectRoles.contains(under) { return false }
                // Never on the silhouette's outer edge.
                let around = [dressed[p.x - 1, p.y], dressed[p.x + 1, p.y], dressed[p.x, p.y - 1], dressed[p.x, p.y + 1]]
                return !around.contains { $0 == nil }
            }
            guard targets.count == move.to.count else { continue }
            for p in move.from where item[index(p)] != nil { out[p.x, p.y] = bare[p.x, p.y] }
            for (p, role) in targets { out[p.x, p.y] = role }
        }
        guard !hanging else { return out }
        let top = max(1, ceiling ?? 1)
        func inBounds(_ p: PetPoint) -> Bool { p.x >= 1 && p.x <= width - 2 && p.y >= top && p.y <= dressed.height - 2 }
        func neighbors(_ p: PetPoint) -> [PetPoint] {
            [PetPoint(x: p.x - 1, y: p.y), PetPoint(x: p.x + 1, y: p.y), PetPoint(x: p.x, y: p.y - 1),
             PetPoint(x: p.x, y: p.y + 1)]
        }
        func clear(_ p: PetPoint) -> Bool {
            inBounds(p) && dressed[p.x, p.y] == nil && neighbors(p).allSatisfy { dressed[$0.x, $0.y] == nil }
        }
        func clearOfPet(_ p: PetPoint) -> Bool {
            inBounds(p) && dressed[p.x, p.y] == nil
                && neighbors(p).allSatisfy { dressed[$0.x, $0.y] == nil || item[index($0)] != nil }
        }
        for particle in layer.particles {
            switch particle.mode {
            case .air:
                guard particle.pixels.allSatisfy({ clear($0.0) }) else { continue }
                for (p, role) in particle.pixels { out[p.x, p.y] = role }
            case .behind:
                for (p, role) in particle.pixels where clear(p) { out[p.x, p.y] = role }
            case .behindItem:
                for (p, role) in particle.pixels where clearOfPet(p) { out[p.x, p.y] = role }
            case .front:
                let own = Set(particle.pixels.map { index($0.0) })
                let ring = particle.pixels.flatMap { neighbors($0.0) }
                    .filter { !own.contains(index($0)) && dressed[$0.x, $0.y] != nil }
                guard particle.pixels.allSatisfy({ inBounds($0.0) && !inFace($0.0) }),
                      ring.allSatisfy({ !inFace($0) && !Self.eyeRoles.contains(dressed[$0.x, $0.y]!) }),
                      particle.pixels.allSatisfy({ dressed[$0.0.x, $0.0.y].map { !Self.eyeRoles.contains($0) } ?? true })
                else { continue }
                for (p, role) in particle.pixels { out[p.x, p.y] = role }
                for p in ring { out[p.x, p.y] = .outline }
            }
        }
        return out
    }
}

// MARK: - Pieces

/// Shapes, as pixel offsets from a center.
enum RadiantShape {
    static func dot(_ role: PetPaletteRole) -> [(Int, Int, PetPaletteRole)] { [(0, 0, role)] }
    /// A small four-pointed star: a center and four arms.
    static func star(_ arm: PetPaletteRole, center: PetPaletteRole = .effect) -> [(Int, Int, PetPaletteRole)] {
        [(0, 0, center), (-1, 0, arm), (1, 0, arm), (0, -1, arm), (0, 1, arm)]
    }
    /// A plus sign for the white coat: a solid 3x3 cross.
    static func plus(_ role: PetPaletteRole) -> [(Int, Int, PetPaletteRole)] {
        [(0, 0, role), (-1, 0, role), (1, 0, role), (0, -1, role), (0, 1, role)]
    }
    /// A two-pixel leaf or confetti strip, turned by `turn` (0 flat, 1 slanted).
    static func strip(_ role: PetPaletteRole, turn: Int) -> [(Int, Int, PetPaletteRole)] {
        switch turn % 4 {
        case 0: [(0, 0, role), (1, 0, role)]
        case 1: [(0, 0, role), (1, -1, role)]
        case 2: [(0, 0, role), (0, -1, role)]
        default: [(0, 0, role), (-1, -1, role)]
        }
    }
}

/// Where a piece is placed from in each frame.
indirect enum RadiantAnchor: Sendable {
    /// The item's bounds; `x` is a fraction across, `y` a fraction down.
    case item(Double, Double)
    /// The item's topmost pixel (a hat's tip), its rightmost on that row.
    case itemTip
    /// The bare pet's bounds.
    case pet(Double, Double)
    /// A fixed frame pixel.
    case frame(Int, Int)
    /// The bounds of the item's pixels of one role (a cloud's white).
    case itemRole(PetPaletteRole, Double, Double)
    /// Another anchor moved by a few pixels.
    case offset(RadiantAnchor, Int, Int)

    func point(in scene: RadiantScene) -> PetPoint? {
        func at(_ box: RadiantScene.Box?, _ fx: Double, _ fy: Double) -> PetPoint? {
            guard let box else { return nil }
            return PetPoint(x: box.minX + Int((Double(box.maxX - box.minX) * fx).rounded()),
                            y: box.minY + Int((Double(box.maxY - box.minY) * fy).rounded()))
        }
        switch self {
        case .item(let fx, let fy): return at(scene.itemBox, fx, fy)
        case .itemTip:
            let points = scene.itemPixels(Set(PetPaletteRole.allCases).subtracting([.outline]))
            guard let top = points.map(\.y).min() else { return nil }
            return points.filter { $0.y == top }.max { $0.x < $1.x }
        case .pet(let fx, let fy): return at(scene.petBox, fx, fy)
        case .frame(let x, let y): return PetPoint(x: x, y: y)
        case .itemRole(let role, let fx, let fy): return at(scene.box(scene.itemPixels([role])), fx, fy)
        case .offset(let anchor, let dx, let dy):
            return anchor.point(in: scene).map { PetPoint(x: $0.x + dx, y: $0.y + dy) }
        }
    }
}

enum RadiantPieces {
    /// A diagonal glint sweeping across the item's pixels of `roles`: the
    /// pixels on diagonal `position(tick)` (counted from the item's top-left)
    /// take `color`, `width` diagonals wide. nil hides it on that tick.
    static func sweep(_ roles: Set<PetPaletteRole>, color: PetPaletteRole, width: Int = 1, rows: Int? = nil,
                      slope: Int = 1, slant: Int = 1, near: Int? = nil,
                      position: @escaping @Sendable (Int) -> Int?) -> RadiantPiece {
        { scene, tick in
            var layer = RadiantLayer()
            guard let at = position(tick) else { return layer }
            let pixels = scene.itemPixels(roles)
            guard let minX = pixels.map(\.x).min(), let minY = pixels.map(\.y).min() else { return layer }
            let mid = scene.itemBox?.midX ?? 0
            for p in pixels where rows.map({ p.y - minY < $0 }) ?? true {
                if let near, abs(p.x - mid) > near { continue }
                let diagonal = slant * (p.x - minX) + slope * (p.y - minY)
                if diagonal >= at && diagonal < at + width { layer.recolor[p] = color }
            }
            return layer
        }
    }

    /// The `which` pixels of the item's `roles` (in reading order; negative
    /// counts from the end) take `color` on `ticks`.
    static func blink(_ roles: Set<PetPaletteRole>, which: [Int], color: PetPaletteRole, ticks: Set<Int>) -> RadiantPiece {
        { scene, tick in
            var layer = RadiantLayer()
            guard ticks.contains(tick) else { return layer }
            let pixels = scene.itemPixels(roles)
            for n in which {
                let i = n < 0 ? pixels.count + n : n
                if pixels.indices.contains(i) { layer.recolor[pixels[i]] = color }
            }
            return layer
        }
    }

    /// Every item pixel of `roles` in a run of columns takes `color`: a glint
    /// hopping across a crown's points or a dinosaur's spikes, one group of
    /// touching columns at a time. `group(tick)` picks the group (nil: none).
    static func hop(_ roles: Set<PetPaletteRole>, color: PetPaletteRole, aboveRow fraction: Double = 1,
                    group: @escaping @Sendable (Int) -> Int?) -> RadiantPiece {
        { scene, tick in
            var layer = RadiantLayer()
            guard let g = group(tick), let box = scene.itemBox else { return layer }
            let limit = box.minY + Int(Double(box.maxY - box.minY) * fraction)
            let pixels = scene.itemPixels(roles).filter { $0.y <= limit }
            let columns = Set(pixels.map(\.x)).sorted()
            var groups: [[Int]] = []
            for x in columns {
                if let last = groups.last?.last, x == last + 1 { groups[groups.count - 1].append(x) } else { groups.append([x]) }
            }
            guard !groups.isEmpty else { return layer }
            let pick = Set(groups[g % groups.count])
            // The top pixel of each column in the group.
            for x in pick {
                if let p = pixels.filter({ $0.x == x }).min(by: { $0.y < $1.y }) { layer.recolor[p] = color }
            }
            return layer
        }
    }

    /// Particles that each follow `path` (offsets from `anchor`), one step
    /// per tick, drawn as `look(age)` (nil: gone). A new one starts on every
    /// tick in `starts`; `mirror` sends every other one the other way.
    static func drift(from anchor: RadiantAnchor, path: [(Int, Int)], starts: [Int], loop: Int,
                      mode: RadiantParticle.Mode = .air, mirror: Bool = false,
                      look: @escaping @Sendable (Int, Int) -> [(Int, Int, PetPaletteRole)]?) -> RadiantPiece {
        { scene, tick in
            var layer = RadiantLayer()
            guard let origin = anchor.point(in: scene) else { return layer }
            for (n, start) in starts.enumerated() {
                let age = ((tick - start) % loop + loop) % loop
                guard age < path.count, let shape = look(age, n) else { continue }
                let (dx, dy) = path[age]
                let center = PetPoint(x: origin.x + dx, y: origin.y + dy)
                var pixels = shape.map { (PetPoint(x: center.x + $0.0, y: center.y + $0.1), $0.2) }
                // Every other one goes to the other side of the pet.
                // Mirrored about the face (the tail makes the pet lopsided).
                if mirror, n % 2 == 1, let axis = (scene.faceBox ?? scene.petBox).map({ $0.minX + $0.maxX }) {
                    pixels = pixels.map { (PetPoint(x: axis - $0.0.x, y: $0.0.y), $0.1) }
                }
                layer.particles.append(RadiantParticle(pixels: pixels, mode: mode))
            }
            return layer
        }
    }

    /// A body circling `anchor` on an ellipse, `loop` ticks a turn,
    /// clockwise seen from above: in front of the pet on the lower half
    /// (with an outline ring), behind it on the upper half. `trail` earlier
    /// positions are drawn as fading dots.
    static func orbit(around anchor: RadiantAnchor, rx: Double, ry: Double, loop: Int, phase: Int = 0,
                      body: [(Int, Int, PetPaletteRole)], trail: [PetPaletteRole] = []) -> RadiantPiece {
        { scene, tick in
            var layer = RadiantLayer()
            guard let c = anchor.point(in: scene) else { return layer }
            func spot(_ t: Int) -> (PetPoint, Bool) {
                let angle = 2 * Double.pi * Double(t + phase) / Double(loop)
                let p = PetPoint(x: c.x + Int((rx * cos(angle)).rounded()), y: c.y + Int((ry * sin(angle)).rounded()))
                return (p, sin(angle) > 0.05)
            }
            for (age, role) in trail.enumerated().reversed() {
                // The trail only shows in the free air: ringed dots over fur read as holes.
                let (p, _) = spot(tick - age - 1)
                layer.particles.append(RadiantParticle(pixels: [(p, role)], mode: .air))
            }
            let (p, front) = spot(tick)
            layer.particles.append(RadiantParticle(
                pixels: body.map { (PetPoint(x: p.x + $0.0, y: p.y + $0.1), $0.2) }, mode: front ? .front : .air))
            return layer
        }
    }

    /// Fixed particles (offsets from `anchor`) shown as `look(tick)`.
    static func at(_ anchor: RadiantAnchor, _ offset: (Int, Int), mode: RadiantParticle.Mode = .air,
                   look: @escaping @Sendable (Int) -> [(Int, Int, PetPaletteRole)]?) -> RadiantPiece {
        { scene, tick in
            var layer = RadiantLayer()
            guard let origin = anchor.point(in: scene), let shape = look(tick) else { return layer }
            layer.particles.append(RadiantParticle(
                pixels: shape.map { (PetPoint(x: origin.x + offset.0 + $0.0, y: origin.y + offset.1 + $0.1), $0.2) },
                mode: mode))
            return layer
        }
    }

    /// The lower part of a hanging item piece (a tassel) swings a pixel to
    /// each side: pixels of `roles` at or below `fromRow` rows under the
    /// piece's top move by `swing(tick)` columns, over fur.
    static func swing(_ roles: Set<PetPaletteRole>, column: @escaping @Sendable (RadiantScene) -> ClosedRange<Int>, fromRow: Int,
                      swing: @escaping @Sendable (Int) -> Int) -> RadiantPiece {
        { scene, tick in
            var layer = RadiantLayer()
            let dx = swing(tick)
            guard dx != 0 else { return layer }
            let range = column(scene)
            let piece = scene.itemPixels(roles).filter { range.contains($0.x) }
            guard let top = piece.map(\.y).min() else { return layer }
            let moving = piece.filter { $0.y >= top + fromRow }
            let to = moving.map { (PetPoint(x: $0.x + dx, y: $0.y), scene.item[scene.index($0)]!) }
            layer.move.append((from: moving, to: to))
            return layer
        }
    }
}
