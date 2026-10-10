import AppKit
import SwiftUI
import TabbiKit
import TabbiKitCore

/// Hosts a `SpotifyEqualizerView` for the closed notch's right wing.
struct SpotifyEqualizerBars: NSViewRepresentable {
    let isPlaying: Bool
    let tint: Color

    func makeNSView(context: Context) -> SpotifyEqualizerView { SpotifyEqualizerView() }

    func updateNSView(_ view: SpotifyEqualizerView, context: Context) {
        view.tint = NSColor(tint).cgColor
        view.setPlaying(isPlaying, animated: !context.environment.accessibilityReduceMotion)
    }
}

/// The equalizer's bars as layers that Core Animation moves by itself.
///
/// While music plays, each bar runs a repeating keyframe animation of
/// `SpotifyEqualizer.loop`, which the render server plays at up to 30 fps
/// with no work in the app. Drawn through a `TimelineView` instead, each
/// frame was a SwiftUI update of the notch: about 3% CPU and 500 context
/// switches a second for as long as a track played, in the wing that shows
/// all day. Pausing springs the bars down to their resting heights.
final class SpotifyEqualizerView: NSView {
    static let barWidth: CGFloat = 3
    static let maxHeight: CGFloat = 14
    static let spacing = Theme.Spacing.xxs
    static let width = CGFloat(SpotifyEqualizer.barCount) * barWidth
        + CGFloat(SpotifyEqualizer.barCount - 1) * spacing
    /// How long the bars' motion runs before it repeats.
    static let loopDuration: TimeInterval = 30
    static let frameRate: Float = 30
    static let animationKey = "equalizer"

    private(set) var bars: [CALayer] = []
    private(set) var isPlaying = false
    var tint: CGColor? {
        didSet { bars.forEach { $0.backgroundColor = tint } }
    }

    /// The bars' keyframes, the same for every view, built once.
    private static let loops: [[NSNumber]] = (0..<SpotifyEqualizer.barCount).map { bar in
        SpotifyEqualizer.loop(bar: bar, duration: loopDuration, frameRate: Double(frameRate))
            .map { NSNumber(value: Double(maxHeight) * $0) }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        let resting = SpotifyEqualizer.restingLevels()
        bars = resting.indices.map { index in
            let bar = CALayer()
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.cornerRadius = Self.barWidth / 2
            bar.cornerCurve = .continuous
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.maxHeight * resting[index])
            layer?.addSublayer(bar)
            return bar
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.width, height: Self.maxHeight) }

    /// Clicks and the tooltip belong to the notch around the bars.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Bottom-aligned and centered, as the SwiftUI drawing lays them out.
        let left = (bounds.width - Self.width) / 2
        let bottom = (bounds.height - Self.maxHeight) / 2
        for (index, bar) in bars.enumerated() {
            bar.position = CGPoint(x: left + CGFloat(index) * (Self.barWidth + Self.spacing) + Self.barWidth / 2,
                                   y: bottom)
        }
        CATransaction.commit()
    }

    /// Starts the repeating animation, or springs the bars down to rest.
    /// Nothing happens while the state stays the same, so SwiftUI updates
    /// of the wing never restart the motion.
    func setPlaying(_ playing: Bool, animated: Bool) {
        guard playing != isPlaying else { return }
        isPlaying = playing
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let resting = SpotifyEqualizer.restingLevels()
        for (index, bar) in bars.enumerated() {
            if playing {
                bar.add(Self.loopAnimation(bar: index), forKey: Self.animationKey)
            } else {
                // Spring down from wherever the bar is now.
                let from = bar.presentation()?.bounds.height ?? bar.bounds.height
                bar.removeAnimation(forKey: Self.animationKey)
                let to = Self.maxHeight * resting[index]
                bar.bounds.size.height = to
                if animated, let spring = Self.restSpring {
                    let animation = CASpringAnimation(keyPath: "bounds.size.height")
                    animation.mass = 1
                    animation.stiffness = spring.stiffness
                    animation.damping = spring.damping
                    animation.fromValue = from
                    animation.toValue = to
                    animation.duration = animation.settlingDuration
                    bar.add(animation, forKey: "rest")
                }
            }
        }
        CATransaction.commit()
    }

    private static func loopAnimation(bar: Int) -> CAAnimation {
        let animation = CAKeyframeAnimation(keyPath: "bounds.size.height")
        animation.values = loops[bar]
        animation.calculationMode = .linear
        animation.duration = loopDuration
        animation.repeatCount = .infinity
        // The keyframes are 30 fps; more frames would only cost the render server.
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: frameRate, preferred: frameRate)
        return animation
    }

    /// The snappy spring at the theme's and the user's pace; nil at the
    /// Instant pace.
    private static var restSpring: SpringSpec? {
        Motion.pace.adjusted(Theme.current.motion.adjusted(MotionTokens.snappy))
    }
}
