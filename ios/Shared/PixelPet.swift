import SwiftUI
import TabbiKitCore

/// One pet frame as crisp pixel art, the way the Mac draws it.
///
/// The shared `PetRenderer` writes every sprite pixel as an exact square of
/// device pixels, and the image is shown at its natural size, never resized,
/// so nothing is interpolated: `pixelSize` is snapped down to whole device
/// pixels for the screen's scale. A 32 pixel frame at `pixelSize` 6 is 192
/// points wide on every iPhone.
struct PixelPet: View {
    let canvas: PetCanvas
    let palette: PetPalette
    /// Points per sprite pixel before snapping.
    var pixelSize: CGFloat

    @Environment(\.displayScale) private var displayScale

    init(canvas: PetCanvas, palette: PetPalette, pixelSize: CGFloat) {
        self.canvas = canvas
        self.palette = palette
        self.pixelSize = pixelSize
    }

    /// The pet sitting in its own outfit and accessories.
    init(profile: PetProfile, pixelSize: CGFloat) {
        self.init(canvas: profile.sittingCanvas(), palette: profile.palette, pixelSize: pixelSize)
    }

    var body: some View {
        let scale = Self.devicePixels(per: pixelSize, displayScale: displayScale)
        let points = CGFloat(scale) / max(displayScale, 1)
        Group {
            if let image = PetRenderer.shared.image(for: canvas, palette: palette, scale: scale) {
                Image(decorative: image, scale: max(displayScale, 1))
                    .interpolation(.none)
            } else {
                Color.clear
            }
        }
        .frame(width: CGFloat(canvas.width) * points, height: CGFloat(canvas.height) * points)
    }

    /// Whole device pixels per sprite pixel: `pixelSize` points rounded down
    /// on this screen, and never less than one.
    nonisolated static func devicePixels(per pixelSize: CGFloat, displayScale: CGFloat) -> Int {
        max(1, Int((pixelSize * max(displayScale, 1)).rounded(.down)))
    }
}

extension PetCanvas {
    /// The frame cut down to its opaque pixels plus `margin`, for small
    /// places such as the Dynamic Island where the empty part of the 32
    /// pixel canvas would only shrink the pet.
    func trimmed(margin: Int = 0) -> PetCanvas {
        guard let bounds = opaqueBounds else { return self }
        let minX = max(bounds.minX - margin, 0), minY = max(bounds.minY - margin, 0)
        let maxX = min(bounds.maxX + margin, width - 1), maxY = min(bounds.maxY + margin, height - 1)
        var cut = PetCanvas(width: maxX - minX + 1, height: maxY - minY + 1)
        for y in minY...maxY {
            for x in minX...maxX {
                cut[x - minX, y - minY] = self[x, y]
            }
        }
        return cut
    }
}
