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
    public func colors(using palette: PetPalette) -> [PetColor?] {
        pixels.map { $0.map { palette[$0] } }
    }
}
