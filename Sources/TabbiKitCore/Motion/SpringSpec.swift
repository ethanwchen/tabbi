import Foundation

/// A spring described the way SwiftUI's `Animation.spring(duration:bounce:)`
/// and WWDC23 "Animate with springs" describe it: a perceptual duration and a
/// bounce from -1 to 1 (0 is critically damped, no overshoot).
///
/// Kept as a pure value so the motion tokens can be tested (for example that
/// the notch closes with no overshoot and settles within its time budget)
/// without SwiftUI. `TabbiKit` turns it into an `Animation`.
public struct SpringSpec: Hashable, Sendable {
    /// Perceptual duration in seconds.
    public var duration: Double
    /// -1 to 1; 0 means no overshoot, about 0.15 feels brisk, above 0.4 feels exaggerated.
    public var bounce: Double

    public init(duration: Double, bounce: Double = 0) {
        self.duration = max(duration, 0.01)
        self.bounce = min(max(bounce, -1), 1)
    }

    /// Stiffness with unit mass: (2 pi / duration)^2.
    public var stiffness: Double {
        let omega = 2 * Double.pi / duration
        return omega * omega
    }

    /// Damping with unit mass, Apple's conversion from duration and bounce.
    public var damping: Double {
        let base = 4 * Double.pi / duration
        return bounce >= 0 ? (1 - bounce) * base : base / (1 + bounce)
    }

    /// 1 is critically damped; below 1 overshoots.
    public var dampingRatio: Double {
        damping / (2 * stiffness.squareRoot())
    }

    /// True when the spring overshoots its target before settling.
    public var overshoots: Bool { dampingRatio < 1 - 1e-9 }

    /// Fraction of the distance travelled at time `t`, starting at rest
    /// (0 at t = 0, settling at 1). Can exceed 1 for a bouncy spring.
    public func value(at t: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = stiffness.squareRoot()
        let zeta = dampingRatio
        if zeta < 1 - 1e-9 {
            let omegaD = omega * (1 - zeta * zeta).squareRoot()
            let envelope = exp(-zeta * omega * t)
            return 1 - envelope * (cos(omegaD * t) + zeta * omega / omegaD * sin(omegaD * t))
        } else if zeta > 1 + 1e-9 {
            let root = (zeta * zeta - 1).squareRoot()
            let r1 = -omega * (zeta - root)
            let r2 = -omega * (zeta + root)
            return 1 - (r2 * exp(r1 * t) - r1 * exp(r2 * t)) / (r2 - r1)
        } else {
            return 1 - exp(-omega * t) * (1 + omega * t)
        }
    }

    /// The largest value reached, so 1.0 for no overshoot and 1.1 for a 10% overshoot.
    public var peak: Double {
        guard overshoots else { return 1 }
        let omega = stiffness.squareRoot()
        let omegaD = omega * (1 - dampingRatio * dampingRatio).squareRoot()
        // The first maximum of an underdamped spring is at pi / omegaD.
        return value(at: Double.pi / omegaD)
    }

    /// Time after which the spring stays within `tolerance` of its target.
    public func settlingTime(tolerance: Double = 0.01) -> Double {
        let step = 1.0 / 240
        var lastOutside = 0.0
        var t = 0.0
        while t < 10 {
            if abs(value(at: t) - 1) > tolerance { lastOutside = t }
            t += step
        }
        return lastOutside + step
    }
}
