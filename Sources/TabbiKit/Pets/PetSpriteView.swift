import SwiftUI
import TabbiKitCore

/// One still pet picture (no animation), drawn as crisp pixel art: for
/// thumbnails such as the Closet's wardrobe tiles. Use `PetView` for a live
/// pet.
public struct PetSpriteView: View {
    let canvas: PetCanvas
    let palette: PetPalette
    /// Points per sprite pixel, as in `PetView`.
    var pixelSize: CGFloat

    @Environment(\.displayScale) private var displayScale

    public init(canvas: PetCanvas, palette: PetPalette, pixelSize: CGFloat = 1) {
        self.canvas = canvas
        self.palette = palette
        self.pixelSize = pixelSize
    }

    /// The profile sitting in its own outfit and accessories.
    public init(profile: PetProfile, pixelSize: CGFloat = 1) {
        self.init(canvas: profile.sittingCanvas(), palette: profile.palette, pixelSize: pixelSize)
    }

    public var body: some View {
        let width = CGFloat(canvas.width) * pixelSize
        let height = CGFloat(canvas.height) * pixelSize
        // Whole device pixels per sprite pixel, like `PetView`.
        let scale = max(1, Int((pixelSize * displayScale).rounded()))
        Group {
            if let image = PetRenderer.shared.image(for: canvas, palette: palette, scale: scale) {
                Image(decorative: image, scale: CGFloat(scale) / pixelSize)
                    .interpolation(.none)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: width, height: height)
    }
}
