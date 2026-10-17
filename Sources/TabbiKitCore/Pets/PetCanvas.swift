import Foundation

/// How a breed colors the pattern zones of shared art. Zones not listed use
/// `PetPatternZone.defaultRole`.
public struct PetPattern: Hashable, Sendable {
    public var zones: [PetPatternZone: PetPaletteRole]

    public init(_ zones: [PetPatternZone: PetPaletteRole] = [:]) {
        self.zones = zones
    }

    public func role(for zone: PetPatternZone) -> PetPaletteRole {
        zones[zone] ?? zone.defaultRole
    }

    public static let plain = PetPattern()
}

/// A frame being composed: a grid of palette roles (nil = transparent).
///
/// Layers are stamped in order (body, pattern, face, costume, accessory), so a
/// later layer simply paints over an earlier one. Working in roles rather than
/// colors means a single composed frame can be rendered with any palette.
public struct PetCanvas: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [PetPaletteRole?]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = Array(repeating: nil, count: width * height)
    }

    public subscript(x: Int, y: Int) -> PetPaletteRole? {
        get { contains(x, y) ? pixels[y * width + x] : nil }
        set { if contains(x, y) { pixels[y * width + x] = newValue } }
    }

    private func contains(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    /// Paints `grid` with its top-left corner at (`x`, `y`). Pixels falling
    /// outside the canvas are clipped, which is how the peek animation slides
    /// a pet in from beyond the top edge.
    public mutating func stamp(_ grid: SpriteGrid, x originX: Int, y originY: Int, pattern: PetPattern = .plain) {
        for gy in 0..<grid.height {
            for gx in 0..<grid.width {
                let x = originX + gx, y = originY + gy
                guard contains(x, y) else { continue }
                switch grid[gx, gy] {
                case .empty: break
                case .erase: self[x, y] = nil
                case .role(let role): self[x, y] = role
                case .zone(let zone): self[x, y] = pattern.role(for: zone)
                }
            }
        }
    }

    /// Adds a one-pixel `role` border around every opaque shape, using the
    /// four direct neighbors only so corners stay rounded. This keeps the
    /// silhouette consistent across all art and lets contributors skip
    /// drawing outer outlines by hand. Pixels listed in `except` (effects
    /// like the sleep "z") are left without a border.
    public func outlined(with role: PetPaletteRole = .outline, except: Set<PetPaletteRole> = []) -> PetCanvas {
        var result = self
        for y in 0..<height {
            for x in 0..<width where self[x, y] == nil {
                let neighbors = [self[x - 1, y], self[x + 1, y], self[x, y - 1], self[x, y + 1]]
                if neighbors.contains(where: { $0 != nil && !except.contains($0!) }) {
                    result[x, y] = role
                }
            }
        }
        return result
    }

    /// A copy moved by (`x`, `y`) pixels; whatever leaves the canvas is
    /// clipped. Used for hops and for sliding out of the top edge.
    public func shifted(x dx: Int, y dy: Int) -> PetCanvas {
        guard dx != 0 || dy != 0 else { return self }
        var result = PetCanvas(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width { result[x + dx, y + dy] = self[x, y] }
        }
        return result
    }

    /// Upside-down copy, for a pet hanging out of the notch head first.
    public func flippedVertically() -> PetCanvas {
        var result = PetCanvas(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width { result[x, height - 1 - y] = self[x, y] }
        }
        return result
    }

    /// The smallest rectangle containing every opaque pixel, or nil if empty.
    public var opaqueBounds: (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where self[x, y] != nil {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? nil : (minX, minY, maxX, maxY)
    }

    /// Resolves roles to colors, row-major, nil for transparent pixels.
    ///
    /// Two kinds of pixels depend on what they sit on, so one drawing reads
    /// on any coat, any recolor and any dark backdrop:
    ///
    /// - `mouth` pixels and inner `outline` lines take the palette's dark
    ///   color on light fur and the light `sheen` on near-black fur (judged
    ///   from their four direct neighbors). One face grid then works on a
    ///   tuxedo's white muzzle, a black cat, a Siamese mask and any recolor.
    /// - The silhouette's outer edge (`outline` pixels touching transparency)
    ///   becomes the light `rim` where the fur inside it would melt into the
    ///   backdrop (see `edgeNeedsRim`), so the pet's shape keeps
    ///   `PetPalette.silhouetteContrast` on dark cards and the black notch.
    ///   Elsewhere it stays the dark outline, so light coats look exactly as
    ///   drawn. Every rim pixel is a whole sprite pixel; nothing is blurred.
    public func colors(using palette: PetPalette) -> [PetColor?] {
        // Each role is looked up, measured and classified once, into slots;
        // pixels then work on plain arrays. A pet frame is rendered on every
        // cache miss, so this stays as cheap as a plain role-to-color map.
        var slotOf: [PetPaletteRole: Int] = [:]
        var slotColor: [PetColor] = [], slotLuminance: [Double] = []
        var codes = [Int](repeating: -1, count: pixels.count)
        var colors = [PetColor?](repeating: nil, count: pixels.count)
        var previous: (role: PetPaletteRole, slot: Int)?
        for index in pixels.indices {
            guard let role = pixels[index] else { continue }
            let slot: Int
            if let previous, previous.role == role {
                // Runs of one role are the common case: skip the lookup.
                slot = previous.slot
            } else if let known = slotOf[role] {
                slot = known
            } else {
                slot = slotColor.count
                let color = palette[role]
                slotOf[role] = slot
                slotColor.append(color)
                slotLuminance.append(color.luminance)
            }
            previous = (role, slot)
            codes[index] = slot
            colors[index] = slotColor[slot]
        }
        let outline = slotOf[.outline] ?? -2, mouth = slotOf[.mouth] ?? -2
        guard outline >= 0 || mouth >= 0 else { return colors }

        let coatStandsOut = PetPalette.standsOut(palette[.furBase])
        lazy var rim = palette.rim
        lazy var sheen = palette.sheen
        // Whether fill of each slot votes for the rim (see `edgeNeedsRim`).
        lazy var rimmedFill: [Bool] = slotColor.map {
            coatStandsOut ? !PetPalette.standsOut($0) : !PetPalette.isLightPatch($0, against: rim)
        }
        func code(_ x: Int, _ y: Int) -> Int {
            x >= 0 && y >= 0 && x < width && y < height ? codes[y * width + x] : -1
        }
        func isFill(_ code: Int) -> Bool { code >= 0 && code != outline && code != mouth }

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x, own = codes[index]
                guard own >= 0, own == outline || own == mouth else { continue }
                let direct = (code(x - 1, y), code(x + 1, y), code(x, y - 1), code(x, y + 1))
                if own == outline, direct.0 < 0 || direct.1 < 0 || direct.2 < 0 || direct.3 < 0 {
                    // The silhouette's edge: the fill around it votes, a tie
                    // follows the coat (see `edgeNeedsRim`).
                    var fill = 0, rimmed = 0
                    for dy in -1...1 {
                        for dx in -1...1 where (dx != 0 || dy != 0) && (coatStandsOut || dx == 0 || dy == 0) {
                            let neighbor = code(x + dx, y + dy)
                            guard isFill(neighbor) else { continue }
                            fill += 1
                            if rimmedFill[neighbor] { rimmed += 1 }
                        }
                    }
                    if edgeNeedsRim(fill: fill, rimmed: rimmed, coatStandsOut: coatStandsOut) { colors[index] = rim }
                    continue
                }
                // A mouth weighs everything but other mouth pixels (lines
                // around steam count); an inner line weighs only the fill.
                var sum = 0.0, count = 0
                for neighbor in [direct.0, direct.1, direct.2, direct.3]
                where neighbor >= 0 && neighbor != mouth && (own == mouth || neighbor != outline) {
                    sum += slotLuminance[neighbor]
                    count += 1
                }
                if count == 0, own == outline {
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let neighbor = code(x + dx, y + dy)
                            guard isFill(neighbor) else { continue }
                            sum += slotLuminance[neighbor]
                            count += 1
                        }
                    }
                }
                if count > 0, sum / Double(count) < PetPalette.darkMouthBackground { colors[index] = sheen }
            }
        }
        return colors
    }

    /// Whether an edge pixel gets the light rim, from how many of the fill
    /// pixels around it vote for it (`rimmed` of `fill`).
    ///
    /// On a coat that stands out from dark backdrops by itself
    /// (`PetPalette.standsOut`), the dark outline stays except around
    /// markings that do not (Siamese points, a calico's black patch, a
    /// beagle's saddle, a tabby's dark tail tip). Those are rimmed only
    /// where most of the eight neighbors are such markings, so the rim runs
    /// in clean stretches and a lone stripe end never lights a stray pixel.
    ///
    /// On a coat that does not stand out (black fur, a chocolate Labrador,
    /// a charcoal tint), the whole edge is rim except where the pixel
    /// directly inside it is clearly lighter than the rim (a tuxedo's white
    /// paws), which a light rim would blur into; only the four direct
    /// neighbors vote there. Lighter curl tips on a charcoal poodle take the
    /// rim, so no dark nubs break the lit edge. Ties follow the coat.
    private func edgeNeedsRim(fill: Int, rimmed: Int, coatStandsOut: Bool) -> Bool {
        if rimmed * 2 == fill { return !coatStandsOut }
        return rimmed * 2 > fill
    }
}
