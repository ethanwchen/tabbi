import SwiftUI
import TabbiKitCore

/// Tabbi's spinner: an accent arc that turns once a second.
///
/// Use it instead of `ProgressView`, whose AppKit-backed spinner doesn't
/// render in snapshots and ignores the module accent. It draws from a
/// `TimelineView` capped at `LoaderClock.frameRate`, so it stops ticking as
/// soon as it leaves the screen. Under Reduce Motion the arc stays still and
/// breathes instead.
public struct Spinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let tint: Color
    private let size: CGFloat
    private let lineWidth: CGFloat

    /// - Parameters:
    ///   - tint: the arc color, usually the module accent.
    ///   - size: the diameter, in points.
    ///   - lineWidth: the arc's stroke width; defaults to a sixth of `size`.
    public init(tint: Color = .secondary, size: CGFloat = 12, lineWidth: CGFloat? = nil) {
        self.tint = tint
        self.size = size
        self.lineWidth = lineWidth ?? max(1.5, size / 6)
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / LoaderClock.frameRate)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(reduceMotion ? -90 : LoaderClock.spinAngle(at: time)))
                .opacity(reduceMotion ? LoaderClock.breathingOpacity(at: time) : 1)
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

public extension View {
    /// Turns this view once a second while `isActive`, for a glyph that shows
    /// work in progress (a refresh or sync button). Under Reduce Motion it
    /// breathes in place instead. The clock is paused while inactive, so an
    /// idle button costs nothing.
    func spinning(_ isActive: Bool) -> some View {
        modifier(SpinningModifier(isActive: isActive))
    }
}

private struct SpinningModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1 / LoaderClock.frameRate, paused: !isActive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            content
                .rotationEffect(.degrees(isActive && !reduceMotion ? LoaderClock.spinAngle(at: time) : 0))
                .opacity(isActive && reduceMotion ? LoaderClock.breathingOpacity(at: time) : 1)
        }
    }
}
