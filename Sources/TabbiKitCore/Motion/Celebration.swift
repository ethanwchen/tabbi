import Foundation

/// How big a celebration is. The smallest tier (a symbol bounce on a
/// finished task) needs no particles, so it isn't listed here; these are the
/// two particle tiers from docs/design/motion.md.
public enum CelebrationTier: String, Sendable, CaseIterable {
    /// A daily goal met or a streak continued: a small burst inside the notch.
    case burst
    /// A streak milestone, a level up or an unlock: a fuller burst, at most
    /// once a day.
    case milestone

    /// How many particles the tier throws.
    public var particleCount: Int {
        switch self {
        case .burst: 36
        case .milestone: 72
        }
    }

    /// The longest a particle of this tier lives, in seconds.
    var lifetimes: ClosedRange<Double> {
        switch self {
        case .burst: 0.9...1.3
        case .milestone: 1.1...1.6
        }
    }

    /// Launch speeds, in points per second.
    var speeds: ClosedRange<Double> {
        switch self {
        case .burst: 300...460
        case .milestone: 340...540
        }
    }

    /// How long after the start the last particle may launch, in seconds.
    var launchSpread: Double {
        switch self {
        case .burst: 0.06
        case .milestone: 0.15
        }
    }
}

/// What a celebration's particles look like. Each one is drawn from paths
/// (no image assets), so it stays sharp at any scale.
public enum CelebrationStyle: String, Sendable, CaseIterable {
    case confetti
    case sparkles
    case hearts
    case pawPrints
}

/// One particle's launch: everything about it that doesn't change over time.
public struct CelebrationParticle: Sendable, Equatable {
    /// The launch direction in radians away from straight up; negative is left.
    public let angle: Double
    /// The launch speed, in points per second.
    public let speed: Double
    /// How long after the burst starts the particle launches, in seconds.
    public let delay: Double
    /// How long the particle lives once launched, in seconds.
    public let lifetime: Double
    /// The rotation at launch, in degrees.
    public let rotation: Double
    /// How fast it turns, in degrees per second.
    public let spin: Double
    /// Its size, in points.
    public let size: Double
    /// Which palette color it takes, in `0..<paletteSize`.
    public let colorIndex: Int
}

/// Where a particle is at one moment, relative to the burst's origin.
public struct CelebrationParticleState: Sendable, Equatable {
    /// Horizontal offset in points; positive is right.
    public let x: Double
    /// Vertical offset in points; positive is down, as on screen.
    public let y: Double
    /// Rotation in degrees.
    public let rotation: Double
    /// 1 while the particle is fresh, fading to 0 over its last 40%.
    public let opacity: Double
    /// Grows from `popScale` to 1 just after launch, so particles pop out.
    public let scale: Double
}

/// A procedural particle burst: a seeded set of particles whose positions
/// are pure functions of elapsed time.
///
/// Nothing mutates per frame, so a view redraws the same picture for the same
/// moment (which frame strips and snapshots rely on), and a burst costs
/// nothing once `duration` has passed. The values follow the research in
/// docs/research/motion.md: a fast launch within 35 degrees of vertical,
/// gravity slowed by strong air drag (a 200 pt/s fall), and lifetimes that
/// keep the whole burst under 1.5 s (burst) or 2 s (milestone).
public struct CelebrationBurst: Sendable, Equatable {
    public static let gravity: Double = 700
    /// Air drag per second; caps the fall at `gravity / drag` (200 pt/s) so
    /// confetti hangs and floats down, fading while it is still in the panel,
    /// instead of dropping out of view like stones.
    public static let drag: Double = 3.5
    /// The widest launch angle either side of vertical, in radians.
    public static let spread: Double = 35 * .pi / 180
    /// A particle's scale at launch.
    public static let popScale: Double = 0.4
    /// How long a particle takes to grow to full size, in seconds.
    public static let popDuration: Double = 0.12
    /// The share of a particle's life spent fading out.
    public static let fadeShare: Double = 0.4

    public let tier: CelebrationTier
    public let style: CelebrationStyle
    public let particles: [CelebrationParticle]

    /// - Parameters:
    ///   - seed: picks the particles; the same seed always gives the same burst.
    ///   - paletteSize: how many colors the view will offer.
    public init(tier: CelebrationTier, style: CelebrationStyle, seed: UInt64, paletteSize: Int) {
        self.tier = tier
        self.style = style
        var random = SplitMix64(seed: seed)
        let colors = max(1, paletteSize)
        let sizes: ClosedRange<Double> = switch style {
        case .confetti: 4...7
        case .sparkles: 5...9
        case .hearts: 6...9
        case .pawPrints: 7...10
        }
        // Confetti tumbles; shapes with a clear "up" only sway a little.
        let spins: ClosedRange<Double> = style == .confetti ? 180...540 : 20...90
        particles = (0..<tier.particleCount).map { index in
            CelebrationParticle(
                angle: random.next(in: -Self.spread...Self.spread),
                speed: random.next(in: tier.speeds),
                delay: random.next(in: 0...tier.launchSpread),
                lifetime: random.next(in: tier.lifetimes),
                rotation: style == .confetti ? random.next(in: 0...360) : random.next(in: -15...15),
                spin: random.next(in: spins) * (random.next(in: 0...1) < 0.5 ? -1 : 1),
                size: random.next(in: sizes),
                colorIndex: index % colors)
        }
    }

    /// When the last particle is gone, in seconds after the start.
    public var duration: TimeInterval {
        particles.map { $0.delay + $0.lifetime }.max() ?? 0
    }

    /// Whether anything is still visible `elapsed` seconds after the start.
    public func isFinished(at elapsed: TimeInterval) -> Bool {
        elapsed >= duration
    }

    /// `particle` at `elapsed` seconds after the burst started, or nil before
    /// it launches and after it has faded out.
    public static func state(of particle: CelebrationParticle, at elapsed: TimeInterval) -> CelebrationParticleState? {
        let t = elapsed - particle.delay
        guard t >= 0, t < particle.lifetime else { return nil }
        // Linear drag (dv/dt = g - kv): the launch speed decays as e^-kt and
        // the fall approaches the terminal speed g/k, so particles float down.
        let travel = (1 - exp(-drag * t)) / drag
        let terminal = gravity / drag
        let x = particle.speed * sin(particle.angle) * travel
        let y = -particle.speed * cos(particle.angle) * travel + terminal * (t - travel)
        let life = t / particle.lifetime
        let fadeStart = 1 - fadeShare
        let fade = life <= fadeStart ? 1 : 1 - smoothstep((life - fadeStart) / fadeShare)
        let pop = min(1, t / popDuration)
        let scale = popScale + (1 - popScale) * (1 - (1 - pop) * (1 - pop))
        return CelebrationParticleState(x: x, y: y, rotation: particle.rotation + particle.spin * t,
                                        opacity: fade, scale: scale)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let v = min(1, max(0, value))
        return v * v * (3 - 2 * v)
    }
}

/// Keeps celebrations rare enough to stay special: at most one particle burst
/// every ten minutes, and one milestone a day.
///
/// A celebration that isn't admitted still deserves its small confirmation
/// (the symbol bounce), so callers fall back to that on `nil`.
public struct CelebrationPacer: Sendable, Equatable {
    /// The shortest gap between two bursts.
    public static let burstInterval: TimeInterval = 10 * 60

    public private(set) var lastBurst: Date?
    public private(set) var lastMilestone: Date?

    public init(lastBurst: Date? = nil, lastMilestone: Date? = nil) {
        self.lastBurst = lastBurst
        self.lastMilestone = lastMilestone
    }

    /// The tier to play for a `requested` celebration at `date`, recording it,
    /// or nil to play none. A milestone always plays the first time in a day
    /// (it is the rarest event, so a recent burst doesn't hold it back); a
    /// second one that day is treated as a burst.
    public mutating func admit(_ requested: CelebrationTier, at date: Date,
                               calendar: Calendar = .current) -> CelebrationTier? {
        if requested == .milestone,
           lastMilestone.map({ !calendar.isDate($0, inSameDayAs: date) }) ?? true {
            lastMilestone = date
            lastBurst = date
            return .milestone
        }
        if let lastBurst, date.timeIntervalSince(lastBurst) < Self.burstInterval,
           date >= lastBurst {
            return nil
        }
        lastBurst = date
        return .burst
    }
}
