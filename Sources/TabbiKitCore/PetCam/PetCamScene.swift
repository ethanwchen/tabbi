import CoreGraphics
import Foundation

/// Where everything is in the room, as `PetCamData/room.json` lays it out:
/// the light pools, each spot's object and wreck anchors, its camera's
/// crop, and where the pet stands for each place.
struct PetCamLayout: Decodable, Sendable {
    struct Point: Decodable, Hashable, Sendable {
        let x, y: Int
    }

    struct Rect: Decodable, Hashable, Sendable {
        let x, y, width, height: Int
    }

    /// The pet's 32x32 frame's top-left corner and the way it faces.
    struct Placement: Decodable, Hashable, Sendable {
        let x, y: Int
        let facingRight: Bool
    }

    struct Pool: Decodable, Hashable, Sendable {
        let x, y, rx, ry: Double
        let tint: [Double]
    }

    struct Spot: Decodable, Sendable {
        /// The object's bottom center.
        let object: Point
        /// Bottom centers of the wrecks on the floor, oldest first.
        let wrecks: [Point]
        let crop: Rect
        let strike, approach, enter, lounge: Placement
    }

    let width, height: Int
    /// Multipliers for unlit pixels at night and by day.
    let night, day: [Double]
    /// How far past a pool's edge the dither runs, as a fraction of its radius.
    let band: Double
    /// How much light a wreck on a dark floor still catches (0...1).
    let wreckLight: Double
    let pools: [Pool]
    let window: Point
    let home: Point
    let spots: [String: Spot]

    func spot(_ spot: PetCamSpot) -> Spot {
        guard let value = spots[spot.rawValue] else { preconditionFailure("room.json has no layout for \(spot)") }
        return value
    }

    private struct File: Decodable {
        let layout: PetCamLayout
    }

    static func load() -> PetCamLayout {
        guard let url = KitResources.bundle?.url(forResource: "room", withExtension: "json",
                                                  subdirectory: PetCamData.subdirectory) else {
            preconditionFailure("Missing \(PetCamData.subdirectory)/room.json")
        }
        do {
            return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).layout
        } catch {
            preconditionFailure("Invalid room.json layout: \(error)")
        }
    }
}

/// Draws a `PetCamShot`: the room seen from its high corner camera at
/// night (or by day), dark but for three warm pools of light on the spots
/// and a moonbeam on the rug, with the objects, the wrecks on the floor
/// and the pet composited in whole sprite pixels.
///
/// The room, objects and effects are pets.v1 grids colored by the room's
/// own palette (`room.json`'s `basePalette`, in the pet palette roles), and
/// the pet is the shared pet art resolved by `PetCanvas.colors(using:)` with
/// its own palette, exactly as everywhere else, so dark coats keep their
/// rim. Light falls off in an ordered dither, the pixel-art way, never a
/// blur, and the final picture is scaled by `PetRenderer.render(colors:)`.
public enum PetCamScene {
    static let art = PetCamData.load("room")
    static let layout = PetCamLayout.load()
    /// The room's palette: what each role means in the room (wall, floor,
    /// walnut, ceramic). Only roles without per-pixel rules are drawn, so
    /// colors map one to one.
    static let palette = PetPalette(art.basePalette)

    /// A picture of the room at one sprite pixel per pixel, opaque.
    public struct Frame: Hashable, Sendable {
        public let width: Int
        public let height: Int
        public let pixels: [PetColor]

        public subscript(x: Int, y: Int) -> PetColor { pixels[y * width + x] }

        /// The picture scaled by a whole number, nearest neighbor.
        public func image(scale: Int) -> CGImage? {
            PetRenderer.render(colors: pixels, width: width, height: height, scale: scale)
        }
    }

    /// The size of a framing's picture in sprite pixels.
    public static func size(of framing: PetCamShot.Framing) -> (width: Int, height: Int) {
        let rect = crop(of: framing)
        return (rect.width, rect.height)
    }

    /// The part of the room a framing shows, given the wrecks on the floor
    /// (a wreck close-up centers on the newest under its spot). Every
    /// framing but the wide shot is half the room across, so each scales by
    /// exactly twice the wide shot and the pixels stay square and even, and
    /// no close-up ever cuts the pet off.
    static func crop(of framing: PetCamShot.Framing, wrecks: [PetCamWreck] = []) -> PetCamLayout.Rect {
        let width = layout.width / 2, height = layout.height / 2
        func centered(x: Int, y: Int) -> PetCamLayout.Rect {
            PetCamLayout.Rect(x: min(max(x - width / 2, 0), layout.width - width),
                              y: min(max(y - height / 2, 0), layout.height - height), width: width, height: height)
        }
        switch framing {
        case .wide:
            return PetCamLayout.Rect(x: 0, y: 0, width: layout.width, height: layout.height)
        case .spot(let spot):
            return layout.spot(spot).crop
        case .closeUp(let place):
            // The whole 32x32 frame, centered.
            let pet = placement(for: place, pose: .lensStare)
            return centered(x: pet.x + 16, y: pet.y + 16)
        case .wreck(let spot, _):
            let anchor = wrecks.last { $0.spot == spot }.map(wreckAnchor) ?? layout.spot(spot).object
            return centered(x: anchor.x, y: anchor.y - 4)
        }
    }

    /// Where a wreck lies on the floor (its bottom center).
    static func wreckAnchor(_ wreck: PetCamWreck) -> PetCamLayout.Point {
        let anchors = layout.spot(wreck.spot).wrecks
        return anchors[min(max(wreck.slot, 0), anchors.count - 1)]
    }

    /// Whether `wreck` lies inside what `framing` shows, so a caption about
    /// it ("RIGHT NEXT TO THE PUDDLE") only plays over a picture of it.
    static func shows(_ wreck: PetCamWreck, in framing: PetCamShot.Framing) -> Bool {
        let rect = crop(of: framing, wrecks: [wreck])
        let anchor = wreckAnchor(wreck)
        return anchor.x >= rect.x + 3 && anchor.x < rect.x + rect.width - 3
            && anchor.y - 3 >= rect.y && anchor.y - 3 < rect.y + rect.height
    }

    /// The part of the wide shot a spot covers, in sprite pixels: its
    /// object with room around it, for a tap target and the viewfinder.
    public static func spotRect(_ spot: PetCamSpot) -> CGRect {
        let base = layout.spot(spot).object
        return CGRect(x: base.x - 12, y: base.y - 21, width: 24, height: 26)
    }

    /// One object on its own, intact or wrecked, outlined in ink and in the
    /// room's palette (colors row-major, nil for transparent), for the
    /// mugshot's evidence tag.
    public static func sprite(_ kind: PetCamObjectKind, wrecked: Bool) -> (colors: [PetColor?], width: Int, height: Int) {
        let grid = wrecked ? wreck(kind) : object(kind)
        var canvas = PetCanvas(width: grid.width + 2, height: grid.height + 2)
        canvas.stamp(grid, x: 1, y: 1)
        return (canvas.outlined(with: wrecked ? .coatShade : .ink).colors(using: palette), canvas.width, canvas.height)
    }

    /// The share of a picture the CAUGHT stamp covers, across and down.
    public static let stampSize = (width: 0.56, height: 0.17)

    /// Where the CAUGHT stamp's center goes in `shot`'s picture, as
    /// fractions of its width and height: of a few places low and high, the
    /// one where a stamp of `stampSize` covers least of the pet and the
    /// evidence (the object being struck and every wreck on the floor),
    /// counting the burn-in band along the top as taken, so the last frame
    /// shows suspect, evidence and verdict together. Ties go to the lowest
    /// place, then the trailing side.
    public static func stampCenter(of shot: PetCamShot, pet: PetProfile) -> (x: Double, y: Double) {
        let crop = crop(of: shot.framing, wrecks: shot.wrecks)
        func unit(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> CGRect {
            CGRect(x: Double(x - crop.x) / Double(crop.width), y: Double(y - crop.y) / Double(crop.height),
                   width: Double(width) / Double(crop.width), height: Double(height) / Double(crop.height))
        }
        var taken: [(rect: CGRect, weight: Double)] = [(CGRect(x: 0, y: 0, width: 1, height: 0.13), 1)]
        if let pose = shot.pet, let place = shot.place {
            let at = placement(for: place, pose: pose)
            let canvas = PetCamPetArt.canvas(pose, profile: pet, facingRight: at.facingRight)
            if let box = canvas.opaqueBounds {
                taken.append((unit(at.x + shot.petOffset.x + box.minX, at.y + shot.petOffset.y + box.minY,
                                   box.maxX - box.minX + 1, box.maxY - box.minY + 1), 1))
            }
        }
        // The evidence counts double: the stamp must never hide Exhibit A.
        for wreck in shot.wrecks {
            let grid = Self.wreck(wreck.object.kind), base = wreckAnchor(wreck)
            taken.append((unit(base.x - grid.width / 2 - 1, base.y - grid.height - 1, grid.width + 2, grid.height + 2), 2))
        }
        for (spot, state) in shot.states where state == .struck {
            guard let kind = shot.objects[spot]?.kind else { continue }
            let grid = object(kind), place = layout.spot(spot)
            let base = flies(kind) ? PetCamLayout.Point(x: place.object.x + (place.strike.facingRight ? 7 : -7),
                                                        y: place.object.y - 5) : place.object
            let side = max(grid.width, grid.height) + 2
            taken.append((unit(base.x - side / 2, base.y - side, side, side), 2))
        }
        var best = (x: 0.5, y: 0.8), least = Double.infinity
        for y in [0.84, 0.7, 0.56, 0.42, 0.26] {
            for x in [0.68, 0.32, 0.5] {
                let stamp = CGRect(x: x - stampSize.width / 2, y: y - stampSize.height / 2, width: stampSize.width,
                                   height: stampSize.height)
                let covered = taken.reduce(0.0) { total, item in
                    let overlap = stamp.intersection(item.rect)
                    return total + (overlap.isNull ? 0 : overlap.width * overlap.height * item.weight)
                }
                if covered < least - 1e-9 {
                    least = covered
                    best = (x, y)
                }
            }
        }
        return best
    }

    /// The middle of the pet in `shot`'s picture, as fractions of its width
    /// and height, for a push-in centered on it; nil with no pet in the shot.
    public static func petCenter(in shot: PetCamShot) -> (x: Double, y: Double)? {
        guard let pose = shot.pet, let place = shot.place else { return nil }
        let crop = crop(of: shot.framing, wrecks: shot.wrecks)
        let at = placement(for: place, pose: pose)
        let x = Double(at.x + shot.petOffset.x + 16 - crop.x) / Double(crop.width)
        let y = Double(at.y + shot.petOffset.y + 14 - crop.y) / Double(crop.height)
        return (min(max(x, 0), 1), min(max(y, 0), 1))
    }

    /// Whether the burn-in hour is daylight (07:00 to 18:59), when the
    /// window shows a blue sky and the room is less dark.
    public static func isDaylight(_ date: Date, calendar: Calendar = .current) -> Bool {
        (7..<19).contains(calendar.component(.hour, from: date))
    }

    /// Draws `shot` with `pet`. `tick` moves what moves on the live
    /// frozen frame (a wobbling object rocks a pixel each tick).
    public static func frame(_ shot: PetCamShot, pet: PetProfile, daylight: Bool, tick: Int = 0) -> Frame {
        var picture = Picture(room: daylight ? Self.dayRoom : Self.nightRoom, daylight: daylight)
        // Wrecks lie flat on the floor, under everything, each ringed in a
        // light line so it reads against the dark boards.
        for wreck in shot.wrecks {
            picture.sprite(Self.wreck(wreck.object.kind), base: wreckAnchor(wreck), light: .wreck, outline: .coatShade)
        }
        // The objects and the pet by where they stand, the nearest drawn
        // last, so the pet sits behind a plate at the front of its table.
        // Whatever is in mid-air or flying off a strike is drawn on top.
        var layers: [(depth: Int, draw: (inout Picture) -> Void)] = []
        for spot in PetCamSpot.allCases {
            guard let object = shot.objects[spot] else { continue }
            let state = shot.states[spot] ?? .still
            let flying = state == .struck && Self.flies(object.kind)
            layers.append((flying ? Int.max : layout.spot(spot).object.y, { picture in
                picture.object(object.kind, state: state, at: layout.spot(spot), tick: tick)
            }))
        }
        if let pose = shot.pet, let place = shot.place {
            let placement = Self.placement(for: place, pose: pose)
            let canvas = PetCamPetArt.canvas(pose, profile: pet, facingRight: placement.facingRight)
            let at = PetCamLayout.Placement(x: placement.x + shot.petOffset.x, y: placement.y + shot.petOffset.y,
                                            facingRight: placement.facingRight)
            let feet = at.y + (canvas.opaqueBounds?.maxY ?? PetComposer.frameSize - 1)
            let airborne = if case .caughtMidAct(let kind) = pose { !kind.isEaten } else { false }
            layers.append((airborne ? Int.max - 1 : feet, { picture in
                // In mid-air its shadow stays on the ground below it.
                if airborne { picture.shadow(x: at.x + 16, y: placement.y + PetComposer.frameSize - 1) }
                picture.pet(canvas.colors(using: pet.palette), width: canvas.width, at: at)
            }))
        }
        for layer in layers.enumerated().sorted(by: {
            $0.element.depth != $1.element.depth ? $0.element.depth < $1.element.depth : $0.offset < $1.offset
        }) {
            layer.element.draw(&picture)
        }
        for spot in PetCamSpot.allCases where shot.states[spot] == .struck {
            if let kind = shot.objects[spot]?.kind { picture.act(kind, at: layout.spot(spot)) }
        }
        if let from = shot.debrisFrom, case .spot(let camera) = shot.framing {
            picture.debris(from: from, toward: camera, kind: shot.objects[from]?.kind, step: shot.debrisStep)
        }
        return picture.cropped(to: shot.framing, wrecks: shot.wrecks)
    }

    /// Whether a strike sends the object flying off its spot (a swat or a
    /// shove) rather than leaving it standing as the pet works on it.
    static func flies(_ kind: PetCamObjectKind) -> Bool {
        kind == .mug || kind == .vase
    }

    /// Where the pet's frame goes for `place`, and which way it faces.
    static func placement(for place: PetCamPlace, pose: PetCamPose) -> PetCamLayout.Placement {
        switch place {
        case .home:
            let right = if case .stare(let spot) = pose { PetCamPetArt.facesRight(staringAt: spot) } else { false }
            return PetCamLayout.Placement(x: layout.home.x, y: layout.home.y, facingRight: right)
        case .approach(let spot): return layout.spot(spot).approach
        case .strike(let spot): return layout.spot(spot).strike
        case .enter(let spot): return layout.spot(spot).enter
        case .lounge(let spot): return layout.spot(spot).lounge
        }
    }

    // MARK: Art

    static func object(_ kind: PetCamObjectKind) -> SpriteGrid { art.grid("object.\(kind.rawValue)") }
    static func wreck(_ kind: PetCamObjectKind) -> SpriteGrid { art.grid("wreck.\(kind.rawValue)") }
    static func effect(_ name: String) -> SpriteGrid { art.grid("effect.\(name)") }

    /// The room's base colors before lighting, night and day.
    private static let nightRoom = roomColors(window: "windowNight")
    private static let dayRoom = roomColors(window: "windowDay")

    private static func roomColors(window: String) -> [PetColor] {
        var canvas = PetCanvas(width: layout.width, height: layout.height)
        canvas.stamp(art.grid("room"), x: 0, y: 0)
        canvas.stamp(art.grid(window), x: layout.window.x, y: layout.window.y)
        return canvas.colors(using: palette).map { $0 ?? PetColor(red: 0, green: 0, blue: 0) }
    }

    /// How lit each room pixel is: 1 inside a pool, 0 in the dark, with an
    /// ordered (Bayer) dither across each pool's edge, and the tint of the
    /// nearest pool's light.
    static let light: [(lit: Bool, tint: [Double])] = {
        let bayer = [[0.0, 2.0], [3.0, 1.0]]
        var map: [(lit: Bool, tint: [Double])] = []
        map.reserveCapacity(layout.width * layout.height)
        for y in 0..<layout.height {
            for x in 0..<layout.width {
                var nearest = (distance: Double.infinity, tint: [1.0, 1.0, 1.0])
                for pool in layout.pools {
                    let dx = (Double(x) - pool.x) / pool.rx, dy = (Double(y) - pool.y) / pool.ry
                    let distance = (dx * dx + dy * dy).squareRoot()
                    if distance < nearest.distance { nearest = (distance, pool.tint) }
                }
                let lit: Bool
                if nearest.distance <= 1 {
                    lit = true
                } else if nearest.distance > 1 + layout.band {
                    lit = false
                } else {
                    let fraction = 1 - (nearest.distance - 1) / layout.band
                    lit = fraction > (bayer[y % 2][x % 2] + 0.5) / 4
                }
                map.append((lit, nearest.tint))
            }
        }
        return map
    }()

    /// The picture being composed, in room coordinates.
    private struct Picture {
        enum Light { case room, wreck }

        var pixels: [PetColor]
        let daylight: Bool
        let width = PetCamScene.layout.width
        let height = PetCamScene.layout.height

        init(room: [PetColor], daylight: Bool) {
            self.daylight = daylight
            pixels = room
            for index in pixels.indices { pixels[index] = shade(pixels[index], at: index, light: .room) }
        }

        /// `color` lit by its pool, or dimmed by the night (or day) air.
        func shade(_ color: PetColor, at index: Int, light: Light) -> PetColor {
            let spot = PetCamScene.light[index]
            let ambient = daylight ? PetCamScene.layout.day : PetCamScene.layout.night
            func channel(_ value: UInt8, _ i: Int) -> UInt8 {
                let v = Double(value)
                let lit = v * spot.tint[i]
                let dim = v * ambient[i] + 4
                let out: Double = if spot.lit {
                    lit
                } else if light == .wreck {
                    dim + (lit - dim) * PetCamScene.layout.wreckLight
                } else {
                    dim
                }
                return UInt8(min(max(out.rounded(), 0), 255))
            }
            return PetColor(red: channel(color.red, 0), green: channel(color.green, 1), blue: channel(color.blue, 2))
        }

        mutating func blend(_ color: PetColor, x: Int, y: Int, light: Light?) {
            guard x >= 0, y >= 0, x < width, y < height, color.alpha > 0 else { return }
            let index = y * width + x
            let shaded = light.map { shade(color, at: index, light: $0) } ?? color
            guard color.alpha < 255 else {
                pixels[index] = shaded
                return
            }
            let a = Double(color.alpha) / 255, under = pixels[index]
            func mix(_ top: UInt8, _ bottom: UInt8) -> UInt8 { UInt8((Double(top) * a + Double(bottom) * (1 - a)).rounded()) }
            pixels[index] = PetColor(red: mix(shaded.red, under.red), green: mix(shaded.green, under.green),
                                     blue: mix(shaded.blue, under.blue))
        }

        /// A room-palette sprite outlined (in ink unless `outline` says),
        /// its bottom center at `base`.
        mutating func sprite(_ grid: SpriteGrid, base: PetCamLayout.Point, light: Light, outline: PetPaletteRole = .ink,
                             dx: Int = 0, dy: Int = 0) {
            var canvas = PetCanvas(width: grid.width + 2, height: grid.height + 2)
            canvas.stamp(grid, x: 1, y: 1)
            let colors = canvas.outlined(with: outline).colors(using: PetCamScene.palette)
            let originX = base.x - canvas.width / 2 + dx, originY = base.y - canvas.height + 1 + dy
            for y in 0..<canvas.height {
                for x in 0..<canvas.width {
                    if let color = colors[y * canvas.width + x] { blend(color, x: originX + x, y: originY + y, light: light) }
                }
            }
        }

        /// An effect grid (white marks), not outlined, top-left at (x, y);
        /// `fragments` recolors its solid white marks, and `light` shades
        /// them like the room (effects that are light themselves stay bright).
        mutating func effect(_ grid: SpriteGrid, x originX: Int, y originY: Int, fragments: PetPaletteRole? = nil,
                             light: Light? = nil) {
            var canvas = PetCanvas(width: grid.width, height: grid.height)
            canvas.stamp(grid, x: 0, y: 0)
            if let fragments {
                for y in 0..<canvas.height {
                    for x in 0..<canvas.width where canvas[x, y] == .effect { canvas[x, y] = fragments }
                }
            }
            let colors = canvas.colors(using: PetCamScene.palette)
            for y in 0..<canvas.height {
                for x in 0..<canvas.width {
                    if let color = colors[y * canvas.width + x] { blend(color, x: originX + x, y: originY + y, light: light) }
                }
            }
        }

        mutating func object(_ kind: PetCamObjectKind, state: PetCamObjectState, at spot: PetCamLayout.Spot, tick: Int) {
            let grid = PetCamScene.object(kind)
            let top = spot.object.y - grid.height - 1
            let left = spot.object.x - (grid.width + 2) / 2
            switch state {
            case .gone:
                return
            case .still:
                sprite(grid, base: spot.object, light: .room)
            case .wobbling:
                // Rocks a pixel either way, with tick marks at its sides.
                sprite(grid, base: spot.object, light: .room, dx: tick % 2 == 0 ? 1 : -1)
                let arcs = PetCamScene.effect("wobbleLeft")
                effect(arcs, x: left - arcs.width - 1, y: top + 1)
                effect(PetCamScene.effect("wobbleRight"), x: left + grid.width + 3, y: top + 1)
            case .scented:
                sprite(grid, base: spot.object, light: .room)
                let scent = PetCamScene.effect("scent")
                effect(scent, x: spot.object.x - scent.width / 2, y: top - scent.height - 1 - tick % 2)
            case .struck where PetCamScene.flies(kind):
                // Swatted or shoved off its spot: turned over in mid-air,
                // flying away from the pet, with a swoosh where it was hit.
                let fliesRight = spot.strike.facingRight
                let turned = fliesRight ? grid.rotatedClockwise() : grid.rotatedCounterclockwise()
                let base = flyingBase(spot)
                sprite(turned, base: base, light: .room)
                let motion = PetCamScene.effect(fliesRight ? "motionLeft" : "motionRight")
                let x = fliesRight ? base.x - (turned.width + 2) / 2 - motion.width - 1 : base.x + (turned.width + 2) / 2 + 1
                effect(motion, x: x, y: base.y - (turned.height + 2) / 2 - motion.height / 2)
            case .struck where kind.isEaten:
                // In the pet's mouth: the plate is bare.
                return
            case .struck:
                // Still standing while the pet works on it, rocked a pixel.
                sprite(grid, base: spot.object, light: .room, dx: spot.strike.facingRight ? 1 : -1)
            }
        }

        /// Where an object knocked off `spot` is in mid-air.
        func flyingBase(_ spot: PetCamLayout.Spot) -> PetCamLayout.Point {
            PetCamLayout.Point(x: spot.object.x + (spot.strike.facingRight ? 7 : -7), y: spot.object.y - 5)
        }

        /// What the act throws up, over everything: water out of the bowl,
        /// shreds of tissue, soil, crumbs, petals off the vase, coffee off the
        /// mug. Drawn above the object, thrown away from the pet.
        mutating func act(_ kind: PetCamObjectKind, at spot: PetCamLayout.Spot) {
            let grid = PetCamScene.art.grid("act.\(kind.rawValue)")
            // The pet faces the object, so whatever flies off goes the way
            // the pet faces.
            let away = spot.strike.facingRight
            let flecks = away ? grid : grid.mirrored()
            let flying = PetCamScene.flies(kind)
            let object = flying ? flyingBase(spot) : spot.object
            let top = object.y - (flying ? PetCamScene.object(kind).width : PetCamScene.object(kind).height)
            sprite(flecks, base: PetCamLayout.Point(x: object.x + (away ? 4 : -4), y: top + 3), light: .room)
        }

        /// A soft oval of shade on the floor, centered at (x, y).
        mutating func shadow(x: Int, y: Int) {
            let shade = PetColor(red: 0, green: 0, blue: 0, alpha: 110)
            for dx in -7...7 { blend(shade, x: x + dx, y: y, light: nil) }
            for dx in -5...5 { blend(shade, x: x + dx, y: y - 1, light: nil) }
        }

        mutating func pet(_ colors: [PetColor?], width canvasWidth: Int, at placement: PetCamLayout.Placement) {
            for (index, color) in colors.enumerated() {
                guard let color else { continue }
                blend(color, x: placement.x + index % canvasWidth, y: placement.y + index / canvasWidth, light: nil)
            }
        }

        /// Dust and fragments rolling in from the edge of `camera`'s frame
        /// nearest `spot`: a strike heard, not seen. The fragments take the
        /// broken object's main color (white shards, green leaves, water).
        mutating func debris(from spot: PetCamSpot, toward camera: PetCamSpot, kind: PetCamObjectKind?, step: Int) {
            let crop = PetCamScene.layout.spot(camera).crop
            let source = PetCamScene.layout.spot(spot).object
            let fromRight = source.x > crop.x + crop.width / 2
            var grid = PetCamScene.effect("debris")
            if fromRight { grid = grid.mirrored() }
            // Just over the edge as it lands, then skidding a few pixels in.
            let inset = step <= 0 ? -grid.width / 3 : 4
            let x = fromRight ? crop.x + crop.width - grid.width - inset : crop.x + inset
            let y = crop.y + min(max(source.y - crop.y + 4, 6), crop.height - grid.height - 6)
            effect(grid, x: x, y: y, fragments: kind.map(Self.fragmentRole))
        }

        static func fragmentRole(_ kind: PetCamObjectKind) -> PetPaletteRole {
            switch kind {
            case .mug, .tissues: .coat
            case .plant: .leaf
            case .fishbowl, .vase: .eye
            case .donut: .blush
            }
        }

        func cropped(to framing: PetCamShot.Framing, wrecks: [PetCamWreck]) -> Frame {
            if case .wide = framing { return Frame(width: width, height: height, pixels: pixels) }
            let crop = PetCamScene.crop(of: framing, wrecks: wrecks)
            var cut: [PetColor] = []
            cut.reserveCapacity(crop.width * crop.height)
            for y in crop.y..<(crop.y + crop.height) {
                for x in crop.x..<(crop.x + crop.width) { cut.append(pixels[y * width + x]) }
            }
            return Frame(width: crop.width, height: crop.height, pixels: cut)
        }
    }
}

extension SpriteGrid {
    /// A quarter turn to the right: the top ends up on the right.
    func rotatedClockwise() -> SpriteGrid {
        var turned = SpriteGrid(width: height, height: width)
        for y in 0..<turned.height {
            for x in 0..<turned.width { turned[x, y] = self[y, height - 1 - x] }
        }
        return turned
    }

    /// A quarter turn to the left: the top ends up on the left.
    func rotatedCounterclockwise() -> SpriteGrid {
        var turned = SpriteGrid(width: height, height: width)
        for y in 0..<turned.height {
            for x in 0..<turned.width { turned[x, y] = self[width - 1 - y, x] }
        }
        return turned
    }
}
