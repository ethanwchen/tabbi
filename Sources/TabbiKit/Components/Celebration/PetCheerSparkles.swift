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
            Canvas { canvas, size in
                Self.draw(in: &canvas, size: size, elapsed: context.date.timeIntervalSince(startedAt))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func draw(in canvas: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        // Around the pet's middle, a little above the frame's center since
        // the sprite sits low in its frame.
        let origin = CGPoint(x: size.width / 2, y: size.height * 0.5)
        for spark in sparks {
            let t = (elapsed - spark.delay) / lifetime
            guard t >= 0, t < 1 else { continue }
            // Ease out: a quick pop, then a slow drift as it fades.
            let travel = 1 - (1 - t) * (1 - t)
            let radians = spark.angle * .pi / 180
            let x = origin.x + sin(radians) * (popRadius + spark.distance * travel)
            let y = origin.y - cos(radians) * (popRadius + spark.distance * travel)
            let scale = t < 0.2 ? 0.4 + 3 * t : 1 - 0.3 * (t - 0.2)
            var layer = canvas
            layer.opacity = t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4
            layer.translateBy(x: x, y: y)
            layer.rotate(by: .degrees(45 * t))
            let side = spark.size * scale
            layer.scaleBy(x: side, y: side)
            layer.fill(CelebrationShapes.sparkle, with: .color(spark.color))
        }
    }
}
