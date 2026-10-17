import Foundation

/// Measures how well a rendered pet's silhouette stands out from what is
/// behind it, so tests (and the gallery's backdrop sheet) can hold every
/// breed, fur tint and theme to `PetPalette.silhouetteContrast`.
///
/// The silhouette is the ring of pixels that touch transparency (the
/// automatic outline). An edge pixel reads when it, or the fill just inside
/// it, contrasts with the backdrop: a light coat's dark outline is fine on
/// black because the fur right behind it is bright, and a black cat's edge
/// reads because the renderer lights it with the rim.
public enum PetVisibility {
    /// What a silhouette looks like against one backdrop.
    public struct Report: Hashable, Sendable {
        /// Silhouette pixels measured.
        public var edgePixels: Int
        /// Silhouette pixels that reach `PetPalette.silhouetteContrast`.
        public var readablePixels: Int
        /// The weakest silhouette pixel's contrast.
        public var weakest: Double
        /// Silhouette pixels right outside the main coat (`furBase`), and
        /// how many of those reach the target: the coat's own outline,
        /// apart from markings.
        public var coatEdgePixels: Int
        public var coatReadablePixels: Int

        /// Share of the silhouette that reaches the target, 0...1.
        public var readableShare: Double {
            edgePixels == 0 ? 1 : Double(readablePixels) / Double(edgePixels)
        }

        /// Share of the coat's own outline that reaches the target, 0...1.
        public var coatReadableShare: Double {
            coatEdgePixels == 0 ? 1 : Double(coatReadablePixels) / Double(coatEdgePixels)
        }
    }

    /// A named, opaque color a pet is drawn on.
    public struct Backdrop: Hashable, Sendable {
        public var name: String
        public var color: PetColor

        public init(name: String, color: PetColor) {
            self.name = name
            self.color = color
        }
    }

    /// The closed notch (pure black in every theme) and each theme's
    /// brightest card (`AppTheme.brightestPetBackdrop`).
    public static var backdrops: [Backdrop] {
        [Backdrop(name: "notch", color: PetColor(red: 0, green: 0, blue: 0))]
            + ThemeCatalog.all.map { Backdrop(name: $0.id.rawValue, color: PetColor($0.brightestPetBackdrop)) }
    }

    /// Row-major indices of the silhouette: opaque pixels with a transparent
    /// (or off-canvas) direct neighbor.
    public static func edge(of canvas: PetCanvas) -> [Int] {
        var indices: [Int] = []
        for y in 0..<canvas.height {
            for x in 0..<canvas.width where canvas[x, y] != nil {
                let direct = [canvas[x - 1, y], canvas[x + 1, y], canvas[x, y - 1], canvas[x, y + 1]]
                if direct.contains(nil) { indices.append(y * canvas.width + x) }
            }
        }
        return indices
    }

    /// The rendered colors of the silhouette, in row-major order.
    public static func edgeColors(_ canvas: PetCanvas, palette: PetPalette) -> [PetColor] {
        let colors = canvas.colors(using: palette)
        return edge(of: canvas).compactMap { colors[$0] }
    }

    /// How `canvas` drawn with `palette` reads on `backdrop`.
    public static func report(_ canvas: PetCanvas, palette: PetPalette, on backdrop: PetColor) -> Report {
        let colors = canvas.colors(using: palette)
        let edge = edge(of: canvas)
        let onEdge = Set(edge)
        let background = backdrop.luminance
        let coat = palette[.furBase]
        var readable = 0, coatEdge = 0, coatReadable = 0
        var weakest = Double.infinity
        for index in edge {
            guard let color = colors[index] else { continue }
            let x = index % canvas.width, y = index / canvas.width
            var best = PetColor.contrast(color.luminance, background)
            var outlinesCoat = false
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            where nx >= 0 && ny >= 0 && nx < canvas.width && ny < canvas.height {
                let neighbor = ny * canvas.width + nx
                guard !onEdge.contains(neighbor), let inside = colors[neighbor] else { continue }
                best = max(best, PetColor.contrast(inside.luminance, background))
                outlinesCoat = outlinesCoat || inside == coat
            }
            let reads = best >= PetPalette.silhouetteContrast
            if reads { readable += 1 }
            if outlinesCoat {
                coatEdge += 1
                if reads { coatReadable += 1 }
            }
            weakest = min(weakest, best)
        }
        return Report(edgePixels: edge.count, readablePixels: readable, weakest: edge.isEmpty ? 21 : weakest,
                      coatEdgePixels: coatEdge, coatReadablePixels: coatReadable)
    }
}

extension PetColor {
    /// The 8-bit color nearest an opaque theme color.
    init(_ color: ThemeColor) {
        func byte(_ value: Double) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }
        self.init(red: byte(color.red), green: byte(color.green), blue: byte(color.blue))
    }
}
