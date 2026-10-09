import SwiftUI
import TabbiKitCore

/// Tabbi's progress ring: a track and an accent arc that fills clockwise
/// from twelve o'clock, with whatever readout you put inside.
///
/// The arc follows `progress` with the content spring, so a growing tally or
/// an added break glides instead of jumping. A move too small to see (a
/// countdown's once-a-second tick) is set without a spring, so a running
/// timer doesn't keep the notch redrawing. A big drop is a new start (a
/// Pomodoro phase change, a usage window that rolled over), so the arc snaps
/// back to empty rather than sweeping backwards (`RingProgress.change`).
/// Under Reduce Motion it eases with the short crossfade curve instead.
public struct ProgressRing<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let progress: Double
    private let tint: Color
    private let track: Color?
    private let lineWidth: CGFloat
    private let content: Content
    @State private var shown: Double

    /// - Parameters:
    ///   - progress: the fraction done; clamped to `0...1`, and `nil` or
    ///     non-finite values draw an empty ring.
    ///   - tint: the arc color, usually the module accent.
    ///   - track: the unfilled track; defaults to a faint `tint`.
    ///   - lineWidth: the stroke width, centered on the ring's frame.
    ///   - content: the readout drawn inside the ring.
    public init(progress: Double?, tint: Color, track: Color? = nil, lineWidth: CGFloat = 2.5,
                @ViewBuilder content: () -> Content) {
        self.progress = RingProgress.clamped(progress)
        self.tint = tint
        self.track = track
        self.lineWidth = lineWidth
        self.content = content()
        _shown = State(initialValue: RingProgress.clamped(progress))
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(track ?? tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
        .onChange(of: progress) { old, new in
            switch RingProgress.change(from: old, to: new) {
            case .none:
                break
            case .advance, .unwind:
                withAnimation(Motion.adapted(Motion.content, reduceMotion: reduceMotion)) { shown = new }
            case .step, .restart:
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { shown = new }
            }
        }
    }
}

public extension ProgressRing where Content == EmptyView {
    /// A ring with nothing inside.
    init(progress: Double?, tint: Color, track: Color? = nil, lineWidth: CGFloat = 2.5) {
        self.init(progress: progress, tint: tint, track: track, lineWidth: lineWidth) { EmptyView() }
    }
}
