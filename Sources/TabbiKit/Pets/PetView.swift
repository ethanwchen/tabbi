import SwiftUI
import TabbiKitCore

/// Draws a `PetPlayer`'s pet as crisp pixel art, redrawing only when the
/// frame changes.
///
/// The view is a fixed square of `PetComposer.frameSize` sprite pixels, so
/// placement never jumps between frames (hops and peeks happen inside it).
/// Each frame is rendered at an integer device-pixel scale and drawn with
/// interpolation off, keeping edges sharp on any display.
public struct PetView: View {
    @ObservedObject var player: PetPlayer
    /// Points per sprite pixel. 1 makes a 32 pt pet, which reads clearly
    /// beside the notch; use 0.75 for a 24 pt pet.
    var pixelSize: CGFloat = 1

    @Environment(\.displayScale) private var displayScale

    public init(player: PetPlayer, pixelSize: CGFloat = 1) {
        self.player = player
        self.pixelSize = pixelSize
    }

    private var side: CGFloat { CGFloat(PetComposer.frameSize) * pixelSize }

    public var body: some View {
        TimelineView(player.schedule) { context in
            if let frame = player.frame(at: context.date) {
                PetFrameView(frame: frame, palette: player.palette, pixelSize: pixelSize,
                             displayScale: displayScale)
            }
        }
        .frame(width: side, height: side)
        .accessibilityElement()
        .accessibilityLabel("\(player.profile.name), \(player.profile.breed.displayName)")
    }
}

/// One composed frame plus its speech bubble.
private struct PetFrameView: View {
    let frame: PetFrame
    let palette: PetPalette
    let pixelSize: CGFloat
    let displayScale: CGFloat

    var body: some View {
        let side = CGFloat(frame.canvas.width) * pixelSize
        // Render with whole device pixels per sprite pixel; the frame below
        // then maps them 1:1 whenever pixelSize × displayScale is whole.
        let scale = max(1, Int((pixelSize * displayScale).rounded()))
        ZStack(alignment: .topLeading) {
            if let image = PetRenderer.shared.image(for: frame.canvas, palette: palette, scale: scale) {
                Image(decorative: image, scale: CGFloat(scale) / pixelSize)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: side, height: side)
            }
            if let anchor = frame.bubbleAnchor {
                // The tail tip sits one sprite pixel up and right of the anchor.
                PetSpeechBubble(pixelSize: pixelSize)
                    .offset(x: CGFloat(anchor.x + 1) * pixelSize,
                            y: CGFloat(anchor.y - PetSpeechBubble.height) * pixelSize)
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
    }
}

/// A pixel-art "!" speech bubble drawn on the pet's own pixel grid, so it is
/// as crisp as the sprite. Its tail tip is the bottom-left pixel. Cream,
/// not white, to match the warm pet palette.
private struct PetSpeechBubble: View {
    let pixelSize: CGFloat

    /// `C` cream, `K` ink, `.` transparent.
    private static let rows = [
        ".CCCCCCC.",
        "CCCCKCCCC",
        "CCCCKCCCC",
        "CCCCKCCCC",
        "CCCCCCCCC",
        "CCCCKCCCC",
        ".CCCCCCC.",
        "CC.......",
        "C........",
    ]
    static let width = rows[0].count
    static let height = rows.count

    private static let cream = Color(red: 1.0, green: 0.96, blue: 0.88)
    private static let ink = Color(red: 0.24, green: 0.15, blue: 0.10)

    var body: some View {
        Canvas { context, _ in
            // One path per color, so fractional pixel sizes never show seams
            // between neighboring cells.
            var cream = Path(), ink = Path()
            for (y, row) in Self.rows.enumerated() {
                for (x, character) in row.enumerated() {
                    let cell = CGRect(x: CGFloat(x) * pixelSize, y: CGFloat(y) * pixelSize,
                                      width: pixelSize, height: pixelSize)
                    switch character {
                    case "C": cream.addRect(cell)
                    case "K": ink.addRect(cell)
                    default: break
                    }
                }
            }
            context.fill(cream, with: .color(Self.cream))
            context.fill(ink, with: .color(Self.ink))
        }
        .frame(width: CGFloat(Self.width) * pixelSize, height: CGFloat(Self.height) * pixelSize)
    }
}
