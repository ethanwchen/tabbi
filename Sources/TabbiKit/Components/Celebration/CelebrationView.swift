import SwiftUI
import TabbiKitCore

/// One celebration to play: a particle burst in a style and palette.
///
/// Make a new value (a new `id`) for each real event; `.celebration(_:)`
/// plays a value once when its id changes. Ask a `CelebrationPacer` first, so
/// bursts stay rare enough to feel earned (`CelebrationCenter` does both).
public struct Celebration: Identifiable, Equatable {
    public let id: UUID
    public let tier: CelebrationTier
    public let style: CelebrationStyle
    public let colors: [Color]
    /// Where the burst starts, as a point in the overlaid view.
    public let origin: UnitPoint
    /// When the event happened. A view that appears mid-celebration (the
    /// user switched tabs) picks the burst up where it is instead of
    /// replaying it, and one that appears later shows nothing.
    public let date: Date

    public init(tier: CelebrationTier, style: CelebrationStyle, accent: Color,
                origin: UnitPoint = UnitPoint(x: 0.5, y: 0.6), date: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.date = date
        self.tier = tier
        self.style = style
        self.colors = Self.palette(accent: accent, style: style)
        self.origin = origin
    }

    /// The burst's particles, seeded from the id so a redraw never reshuffles them.
    public var burst: CelebrationBurst {
        let seed = withUnsafeBytes(of: id.uuid) { $0.load(as: UInt64.self) }
        return CelebrationBurst(tier: tier, style: style, seed: seed, paletteSize: colors.count)
    }

    /// The module accent leads, with warm companions from the app palette.
    /// Hearts stay warm; paw prints stay close to the accent, like a trail.
    static func palette(accent: Color, style: CelebrationStyle) -> [Color] {
        let pink = Color(red: 1.00, green: 0.55, blue: 0.70)
        let sky = Color(red: 0.45, green: 0.76, blue: 1.00)
        switch style {
        case .confetti, .sparkles:
            return [accent, Theme.Palette.success, Theme.Palette.warning, pink, sky, .white]
        case .hearts:
            return [accent, pink, Theme.Palette.danger, pink.opacity(0.8)]
        case .pawPrints:
            return [accent, accent.opacity(0.75), .white.opacity(0.9)]
        }
    }
}

/// A celebration drawn at one moment, `elapsed` seconds after it started.
///
/// Pure drawing: the same inputs always give the same frame, which is how
/// snapshots render frame strips. `CelebrationBurstView` animates it.
public struct CelebrationFrame: View {
    private let burst: CelebrationBurst
    private let colors: [Color]
    private let origin: UnitPoint
    private let elapsed: TimeInterval

    public init(_ celebration: Celebration, elapsed: TimeInterval) {
        self.init(burst: celebration.burst, colors: celebration.colors, origin: celebration.origin, elapsed: elapsed)
    }

    init(burst: CelebrationBurst, colors: [Color], origin: UnitPoint, elapsed: TimeInterval) {
        self.burst = burst
        self.colors = colors.isEmpty ? [.white] : colors
        self.origin = origin
        self.elapsed = elapsed
    }

    public var body: some View {
        GeometryReader { proxy in
            let start = CGPoint(x: proxy.size.width * origin.x, y: proxy.size.height * origin.y)
            let shape = UnitShape(path: CelebrationShapes.unitPath(for: burst.style))
            ForEach(burst.particles.indices, id: \.self) { index in
                let particle = burst.particles[index]
                if let state = CelebrationBurst.state(of: particle, at: elapsed) {
                    let side = particle.size * state.scale
                    shape
                        .fill(colors[particle.colorIndex % colors.count])
                        .frame(width: side, height: side)
                        .rotationEffect(.degrees(state.rotation))
                        .opacity(state.opacity)
                        .position(x: start.x + state.x, y: start.y + state.y)
                }
            }
        }
        // Particles fly by the burst's own physics, measured from the top
        // left, so right to left mirrors nothing.
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A celebration playing in real time from `startDate`.
///
/// It draws from a `TimelineView` capped at 60 fps that pauses once the last
/// particle is gone; `.celebration(_:)` also removes it then, so an idle
/// panel costs nothing.
public struct CelebrationBurstView: View {
    public static let frameRate: Double = 60
    private let celebration: Celebration
    private let burst: CelebrationBurst
    private let startDate: Date

    public init(_ celebration: Celebration, startDate: Date) {
        self.celebration = celebration
        self.burst = celebration.burst
        self.startDate = startDate
    }

    public var body: some View {
        let finished = burst.isFinished(at: Date().timeIntervalSince(startDate))
        TimelineView(.animation(minimumInterval: 1 / Self.frameRate, paused: finished)) { context in
            CelebrationFrame(burst: burst, colors: celebration.colors, origin: celebration.origin,
                             elapsed: context.date.timeIntervalSince(startDate))
        }
    }
}

/// The Reduce Motion stand-in for a burst: a soft glow of the accent that
/// brightens and fades in place, with nothing moving.
public struct CelebrationGlow: View {
    /// How long the glow lasts, in seconds.
    public static let duration: TimeInterval = 0.9
    private let color: Color
    private let origin: UnitPoint
    private let elapsed: TimeInterval

    public init(_ celebration: Celebration, elapsed: TimeInterval) {
        self.color = celebration.colors.first ?? .white
        self.origin = celebration.origin
        self.elapsed = elapsed
    }

    public var body: some View {
        // Up in the first third, back down over the rest.
        let progress = min(1, max(0, elapsed / Self.duration))
        let level = progress < 1.0 / 3 ? progress * 3 : (1 - progress) * 1.5
        RadialGradient(colors: [color.opacity(0.32), color.opacity(0)], center: origin,
                       startRadius: 0, endRadius: 140)
            .opacity(level)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

public extension View {
    /// Plays `celebration` over this view each time a new one arrives: a
    /// particle burst, or a soft accent glow under Reduce Motion. It never
    /// blocks input and leaves the hierarchy as soon as it is done.
    func celebration(_ celebration: Celebration?) -> some View {
        modifier(CelebrationOverlay(celebration: celebration))
    }
}

private struct CelebrationOverlay: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let celebration: Celebration?
    @State private var playing: (celebration: Celebration, start: Date)?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let playing {
                    if reduceMotion {
                        TimelineView(.animation(minimumInterval: 1 / LoaderClock.frameRate)) { context in
                            CelebrationGlow(playing.celebration, elapsed: context.date.timeIntervalSince(playing.start))
                        }
                    } else {
                        CelebrationBurstView(playing.celebration, startDate: playing.start)
                    }
                }
            }
            .task(id: celebration?.id) {
                guard let celebration else { return }
                let start = celebration.date
                let length = reduceMotion ? CelebrationGlow.duration : celebration.burst.duration
                let left = length - Date().timeIntervalSince(start)
                guard left > 0 else { return }
                playing = (celebration, start)
                try? await Task.sleep(for: .seconds(left))
                guard !Task.isCancelled, playing?.start == start else { return }
                playing = nil
            }
    }
}

/// A path from `CelebrationShapes` stretched to fill its frame.
///
/// Particles, sparkles and paw prints are drawn as shapes rather than in a
/// `Canvas`: a `Canvas` renders through Metal, and the first one on screen
/// had the renderer set up about 250 MB of graphics memory for as long as
/// it showed (a whole "Thinking" wait, in the paw loader's case).
struct UnitShape: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        path.applying(CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: rect.width, y: rect.height))
    }
}

/// The particle shapes, each a path one point across centred on the origin,
/// so a particle only needs scaling.
enum CelebrationShapes {
    static func unitPath(for style: CelebrationStyle) -> Path {
        switch style {
        case .confetti: confetti
        case .sparkles: sparkle
        case .hearts: heart
        case .pawPrints: pawPrint
        }
    }

    /// A small rounded strip, twice as long as it is wide.
    static let confetti = Path(roundedRect: CGRect(x: -0.5, y: -0.25, width: 1, height: 0.5),
                               cornerSize: CGSize(width: 0.12, height: 0.12), style: .continuous)

    /// A four-pointed star with concave sides.
    static let sparkle: Path = {
        var path = Path()
        let tips = [CGPoint(x: 0, y: -0.5), CGPoint(x: 0.5, y: 0), CGPoint(x: 0, y: 0.5), CGPoint(x: -0.5, y: 0)]
        path.move(to: tips[0])
        for index in 1...4 {
            path.addQuadCurve(to: tips[index % 4], control: .zero)
        }
        path.closeSubpath()
        return path
    }()

    /// Two lobes meeting in a point at the bottom.
    static let heart: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0.42))
        path.addCurve(to: CGPoint(x: -0.5, y: -0.12), control1: CGPoint(x: -0.18, y: 0.28),
                      control2: CGPoint(x: -0.5, y: 0.1))
        path.addArc(center: CGPoint(x: -0.25, y: -0.16), radius: 0.25,
                    startAngle: .degrees(170), endAngle: .degrees(355), clockwise: false)
        path.addArc(center: CGPoint(x: 0.25, y: -0.16), radius: 0.25,
                    startAngle: .degrees(185), endAngle: .degrees(10), clockwise: false)
        path.addCurve(to: CGPoint(x: 0, y: 0.42), control1: CGPoint(x: 0.5, y: 0.1),
                      control2: CGPoint(x: 0.18, y: 0.28))
        path.closeSubpath()
        return path
    }()

    /// A main pad with four toes fanned above it.
    static let pawPrint: Path = {
        var path = Path()
        path.addEllipse(in: CGRect(x: -0.26, y: -0.02, width: 0.52, height: 0.42))
        let toes: [(CGFloat, CGFloat)] = [(-0.36, -0.12), (-0.13, -0.34), (0.13, -0.34), (0.36, -0.12)]
        for (x, y) in toes {
            path.addEllipse(in: CGRect(x: x - 0.1, y: y - 0.12, width: 0.2, height: 0.24))
        }
        return path
    }()
}
