import SwiftUI
import TabbiKitCore

/// A round checkbox glyph that turns on with a small bounce: the accent
/// fill pops in from the center and the check stroke draws on, short leg
/// first. Turning off retracts it without a bounce. Under Reduce Motion the
/// finished check crossfades in instead. `CheckDraw` holds the timing.
///
/// It is only the glyph; wrap it in a button (or nothing, for a check that
/// follows other state). `ring` is the outline while off; pass nil when the
/// caller draws its own.
public struct CheckGlyph: View {
    let isOn: Bool
    let tint: Color
    let ring: Color?
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isOn: Bool, tint: Color, ring: Color? = Theme.Palette.tertiaryText, size: CGFloat = 16) {
        self.isOn = isOn
        self.tint = tint
        self.ring = ring
        self.size = size
    }

    public var body: some View {
        CheckGlyphFrame(progress: isOn ? 1 : 0, tint: tint, ring: ring, size: size, reduceMotion: reduceMotion)
            .animation(Motion.adapted(isOn ? Motion.check : Motion.snappy, reduceMotion: reduceMotion), value: isOn)
    }
}

/// `CheckGlyph` at one `progress` (0 off, 1 on, past 1 while the spring
/// overshoots). SwiftUI interpolates `progress`, so every frame of the draw
/// goes through `CheckDraw`. Public so snapshot frame strips can draw it.
public struct CheckGlyphFrame: View, Animatable {
    var progress: Double
    let tint: Color
    let ring: Color?
    let size: CGFloat
    let reduceMotion: Bool

    public init(progress: Double, tint: Color, ring: Color? = Theme.Palette.tertiaryText,
                size: CGFloat = 16, reduceMotion: Bool = false) {
        self.progress = progress
        self.tint = tint
        self.ring = ring
        self.size = size
        self.reduceMotion = reduceMotion
    }

    public nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    public var body: some View {
        let state = CheckDraw(progress: progress, reduceMotion: reduceMotion)
        ZStack {
            if let ring {
                Circle()
                    .strokeBorder(ring, lineWidth: 1.5)
                    .opacity(state.ringOpacity)
            }
            Circle()
                .fill(tint)
                .scaleEffect(state.fillScale)
                .opacity(state.fillOpacity)
            CheckStroke()
                .trim(from: 0, to: state.checkTrim)
                .stroke(Theme.Palette.background,
                        style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
                .scaleEffect(min(state.fillScale, 1))
                .opacity(state.checkOpacity)
        }
        .frame(width: size, height: size)
    }
}

/// The check mark as one stroke, short leg first, in the unit square of
/// the box, so a trim draws it the way a pen would.
private struct CheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: point(0.29, 0.52))
        path.addLine(to: point(0.44, 0.67))
        path.addLine(to: point(0.72, 0.36))
        return path
    }
}
