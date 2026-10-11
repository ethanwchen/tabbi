import SwiftUI
import TabbiKitCore

/// The small burst around a cheering pet beside the closed notch: a few
/// sparkles that pop out from behind the pet, drift up and fade.
///
/// The closed notch is only 32 pt tall, so this is a much smaller cousin of
/// `CelebrationBurstView`: seven sparkles on fixed, staggered paths that stay
/// near the pet. Positions are pure functions of the time since the cheer
/// started, so a snapshot draws the same frame as the live notch.
struct PetCheerSparkles: View {
    let startedAt: Date

    /// When the last sparkle is gone, in seconds after the cheer starts.
    static let duration: TimeInterval = 1.6

    private struct Spark {
        /// Direction in degrees away from straight up; negative is left.
        let angle: Double
        let delay: Double
        let distance: Double
        let size: Double
        let color: Color
    }

    private static let gold = Color(red: 1.0, green: 0.82, blue: 0.36)
    private static let pink = Color(red: 1.0, green: 0.62, blue: 0.74)
    /// Mostly to the right and up: the pet sits near the notch's rounded
    /// outer corner, so sparkles to its left stay short to stay in view.
    private static let sparks: [Spark] = [
        Spark(angle: -55, delay: 0.00, distance: 7, size: 6, color: gold),
        Spark(angle: 50, delay: 0.05, distance: 10, size: 5, color: .white),
        Spark(angle: 82, delay: 0.12, distance: 12, size: 6, color: pink),
        Spark(angle: -82, delay: 0.20, distance: 5, size: 4, color: .white),
        Spark(angle: 28, delay: 0.28, distance: 8, size: 5, color: gold),
        Spark(angle: 66, delay: 0.38, distance: 11, size: 4, color: gold),
        Spark(angle: -34, delay: 0.46, distance: 6, size: 5, color: pink),
    ]
    /// How far from the pet's middle a sparkle pops out: just outside its
    /// fur, so none hides against the sprite.
    private static let popRadius: Double = 10
    /// How long one sparkle lives once it pops out.
    private static let lifetime: Double = 0.9

    var body: some View {
        let finished = Date().timeIntervalSince(startedAt) >= Self.duration
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: finished)) { context in
            GeometryReader { proxy in
                let elapsed = context.date.timeIntervalSince(startedAt)
                ForEach(Self.sparks.indices, id: \.self) { index in
                    if let state = Self.state(of: Self.sparks[index], in: proxy.size, elapsed: elapsed) {
                        UnitShape(path: CelebrationShapes.sparkle)
                            .fill(Self.sparks[index].color)
                            .frame(width: state.side, height: state.side)
                            .rotationEffect(.degrees(state.rotation))
                            .opacity(state.opacity)
                            .position(state.center)
                    }
                }
            }
            // Positions are measured from the top left, the way the burst
            // was drawn, so right to left mirrors nothing.
            .environment(\.layoutDirection, .leftToRight)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where one sparkle is and how it looks, or nil before it pops out and
    /// after it fades.
    private struct SparkState {
        let center: CGPoint
        let side: Double
        let rotation: Double
        let opacity: Double
    }

    private static func state(of spark: Spark, in size: CGSize, elapsed: TimeInterval) -> SparkState? {
        // Around the pet's middle, a little above the frame's center since
        // the sprite sits low in its frame.
        let origin = CGPoint(x: size.width / 2, y: size.height * 0.5)
        let t = (elapsed - spark.delay) / lifetime
        guard t >= 0, t < 1 else { return nil }
        // Ease out: a quick pop, then a slow drift as it fades.
        let travel = 1 - (1 - t) * (1 - t)
        let radians = spark.angle * .pi / 180
        let scale = t < 0.2 ? 0.4 + 3 * t : 1 - 0.3 * (t - 0.2)
        return SparkState(
            center: CGPoint(x: origin.x + sin(radians) * (popRadius + spark.distance * travel),
                            y: origin.y - cos(radians) * (popRadius + spark.distance * travel)),
            side: spark.size * scale,
            rotation: 45 * t,
            opacity: t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4)
    }
}
