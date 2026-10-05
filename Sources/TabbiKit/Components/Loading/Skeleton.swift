import SwiftUI
import TabbiKitCore

/// One placeholder line of a skeleton: a capsule in the surface color,
/// shaped like the text it stands in for.
///
/// Build a skeleton from these in the layout of the real content (same row
/// heights, same columns), so nothing jumps when the content arrives, and
/// add `.shimmering()` to the whole group.
public struct SkeletonLine: View {
    private let width: Width
    private let height: CGFloat

    private enum Width {
        case fixed(CGFloat)
        case fraction(CGFloat)
    }

    /// A line `fraction` of the available width wide (0 to 1).
    public init(fraction: CGFloat, height: CGFloat = 8) {
        width = .fraction(min(max(fraction, 0), 1))
        self.height = height
    }

    /// A line exactly `width` points wide, for a fixed column such as a time.
    public init(width: CGFloat, height: CGFloat = 8) {
        self.width = .fixed(width)
        self.height = height
    }

    public var body: some View {
        switch width {
        case .fixed(let width):
            capsule.frame(width: width, height: height)
        case .fraction(let fraction):
            GeometryReader { proxy in
                capsule.frame(width: proxy.size.width * fraction, height: height)
            }
            .frame(height: height)
        }
    }

    private var capsule: some View {
        Capsule(style: .continuous).fill(Theme.Palette.surfaceHover)
    }
}

public extension View {
    /// Sweeps a soft highlight across this view's shapes while `isActive`,
    /// the loading state for a skeleton. The highlight is masked to the
    /// view itself, so only the placeholder lines light up.
    ///
    /// It draws from a `TimelineView` capped at `LoaderClock.frameRate` and
    /// paused while inactive, so it stops as soon as it leaves the screen.
    /// Under Reduce Motion the skeleton breathes in place instead.
    func shimmering(_ isActive: Bool = true) -> some View {
        modifier(ShimmerModifier(isActive: isActive))
    }
}

private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1 / LoaderClock.frameRate, paused: !isActive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            content
                .opacity(isActive && reduceMotion ? LoaderClock.breathingOpacity(at: time) : 1)
                .overlay {
                    if isActive && !reduceMotion {
                        highlight(at: LoaderClock.shimmerOffset(at: time))
                            .mask(content)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func highlight(at offset: Double) -> some View {
        GeometryReader { proxy in
            LinearGradient(colors: [.clear, .white.opacity(0.14), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: proxy.size.width * LoaderClock.shimmerBand)
                .offset(x: proxy.size.width * offset)
        }
    }
}
