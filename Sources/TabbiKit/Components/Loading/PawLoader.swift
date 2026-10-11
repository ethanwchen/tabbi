import SwiftUI
import TabbiKitCore

/// Tabbi's loader for longer waits: a trail of paw prints, left, right,
/// left, right, as if the pet were trotting past.
///
/// Use it where a wait usually takes seconds (Claude thinking, Anki
/// starting up) and `Spinner` for quick ones. It stays invisible for
/// `PawTrail.revealDelay` and then fades in, so an answer that comes fast
/// never flashes a loader. It draws from a `TimelineView` capped at
/// `LoaderClock.frameRate`, so it stops ticking when it leaves the screen.
/// Under Reduce Motion the prints stand still and breathe together.
public struct PawLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.loaderRevealDelay) private var revealDelay
    @State private var shownAt = Date()
    private let tint: Color
    private let size: CGFloat
    private let label: String

    /// - Parameters:
    ///   - tint: the prints' color, usually the module accent.
    ///   - size: the trail's height, in points; it is about twice as wide.
    ///   - label: what VoiceOver reads, such as "Thinking".
    public init(tint: Color, size: CGFloat = 16, label: String = "Loading") {
        self.tint = tint
        self.size = size
        self.label = label
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / LoaderClock.frameRate)) { context in
            PawTrailFrame(tint: tint, size: size,
                          time: context.date.timeIntervalSinceReferenceDate,
                          reduceMotion: reduceMotion)
                .opacity(PawTrail.revealOpacity(elapsed: context.date.timeIntervalSince(shownAt),
                                                delay: revealDelay))
        }
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

/// One frame of the paw print trail at `time`, without the reveal delay,
/// for `PawLoader` and the snapshot frame strips.
public struct PawTrailFrame: View {
    private let tint: Color
    private let size: CGFloat
    private let time: TimeInterval
    private let reduceMotion: Bool

    public init(tint: Color, size: CGFloat, time: TimeInterval, reduceMotion: Bool = false) {
        self.tint = tint
        self.size = size
        self.time = time
        self.reduceMotion = reduceMotion
    }

    /// Each print is a little under half the trail's height.
    private var printSize: CGFloat { size * 0.46 }
    /// The distance between one print and the next, along the trail.
    private var stride: CGFloat { size * 0.52 }

    public var body: some View {
        let calm = LoaderClock.breathingOpacity(at: time)
        let shape = UnitShape(path: CelebrationShapes.pawPrint)
        ZStack(alignment: .topLeading) {
            ForEach(0..<PawTrail.stepCount, id: \.self) { step in
                let opacity = reduceMotion ? calm : PawTrail.opacity(ofStep: step, at: time)
                if opacity > 0 {
                    let side = printSize * (reduceMotion ? 1 : PawTrail.scale(ofStep: step, at: time))
                    let lane: CGFloat = PawTrail.isLeftFoot(step) ? -1 : 1
                    shape
                        .fill(tint.opacity(opacity))
                        .frame(width: side, height: side)
                        .rotationEffect(.degrees(90)) // toes point along the trail
                        .position(x: printSize / 2 + CGFloat(step) * stride, y: size / 2 + lane * size * 0.2)
                }
            }
        }
        .frame(width: printSize + CGFloat(PawTrail.stepCount - 1) * stride, height: size)
        // The trail runs left to right in every language, as it always has.
        .environment(\.layoutDirection, .leftToRight)
    }
}

private struct LoaderRevealDelayKey: EnvironmentKey {
    static let defaultValue = PawTrail.revealDelay
}

public extension EnvironmentValues {
    /// How long a `PawLoader` waits before it shows, in seconds. Snapshot
    /// runs set it to 0, since they render the moment a view appears.
    var loaderRevealDelay: Double {
        get { self[LoaderRevealDelayKey.self] }
        set { self[LoaderRevealDelayKey.self] = newValue }
    }
}
