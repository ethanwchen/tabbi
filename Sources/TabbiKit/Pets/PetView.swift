import AppKit
import SwiftUI
import TabbiKitCore

/// Draws a `PetPlayer`'s pet as crisp pixel art, redrawing only when the
/// frame changes.
///
/// The view is a fixed square of `PetComposer.frameSize` sprite pixels, so
/// placement never jumps between frames (hops and peeks happen inside it).
/// Each frame is rendered at an integer device-pixel scale and drawn with
/// interpolation off, keeping edges sharp on any display.
///
/// On screen the pet plays in a layer of its own (`PetAnimationView`), so a
/// frame change swaps one picture instead of updating and laying out the
/// whole notch. Drawn into an image (`rendersToImage`), it is plain SwiftUI.
///
/// Under Reduce Motion the pet holds still: it shows one pose per state
/// (resting, asleep, typing, an alert with its bubble) and only changes
/// when the state does.
public struct PetView: View {
    @ObservedObject var player: PetPlayer
    /// Points per sprite pixel. 1 makes a 32 pt pet, which reads clearly
    /// beside the notch; use 0.75 for a 24 pt pet.
    var pixelSize: CGFloat = 1

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rendersToImage) private var rendersToImage

    public init(player: PetPlayer, pixelSize: CGFloat = 1) {
        self.player = player
        self.pixelSize = pixelSize
    }

    private var side: CGFloat { CGFloat(PetComposer.frameSize) * pixelSize }

    public var body: some View {
        Group {
            if rendersToImage {
                TimelineView(player.schedule(still: reduceMotion)) { context in
                    if let frame = reduceMotion ? player.stillFrame(at: context.date) : player.frame(at: context.date) {
                        PetFrameView(frame: frame, palette: player.palette, pixelSize: pixelSize,
                                     displayScale: displayScale)
                    }
                }
            } else {
                PetLayer(player: player, revision: player.revision, pixelSize: pixelSize, still: reduceMotion)
            }
        }
        .frame(width: side, height: side)
        .accessibilityElement()
        .accessibilityLabel("\(player.profile.name), \(player.profile.breed.displayName)")
    }
}

public extension EnvironmentValues {
    /// True while views are drawn into an image (`ImageRenderer`: snapshots,
    /// an exported recap card), which can't draw AppKit views, so pets draw
    /// with SwiftUI there.
    @Entry var rendersToImage = false
}

/// Hosts a `PetAnimationView`; `revision` changes with every event, so the
/// view restarts its schedule when the pet's plans change.
private struct PetLayer: NSViewRepresentable {
    let player: PetPlayer
    let revision: Int
    let pixelSize: CGFloat
    let still: Bool

    func makeNSView(context: Context) -> PetAnimationView { PetAnimationView() }

    func updateNSView(_ view: PetAnimationView, context: Context) {
        view.play(player, revision: revision, pixelSize: pixelSize, still: still)
    }
}

/// Plays a pet by swapping its layer's picture at each frame change, on a
/// timer of its own that follows `PetPlayer.schedule`.
///
/// With a `TimelineView` every frame change was a SwiftUI update of the
/// whole notch plus a window layout pass, about 4 ms of CPU, so the Party
/// tab's six pets kept the notch near 4% CPU. A layer swap costs a small
/// fraction of that. The timer only runs while the view is in a visible
/// window.
final class PetAnimationView: NSView {
    private weak var player: PetPlayer?
    private var revision = -1
    private var pixelSize: CGFloat = 1
    private var still = false
    private var dates: AnyIterator<Date>?
    private var timer: Timer?
    private let sprite = CALayer()
    private let bubble = CALayer()
    private var occlusionObserver: NSObjectProtocol?

    /// How late a frame change may come, so the system can coalesce the
    /// wakeups of several pets. Well below one frame of the fastest clip.
    private static let tolerance: TimeInterval = 0.01

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        for layer in [sprite, bubble] {
            layer.magnificationFilter = .nearest
            layer.contentsGravity = .resize
            self.layer?.addSublayer(layer)
        }
        bubble.contents = PetSpeechBubble.image
        bubble.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit {
        timer?.invalidate()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    /// Whether nobody can see `window` (closed behind a full-screen app,
    /// say), so the pet holds still. Tests replace it, since windows in a
    /// test process never report themselves visible.
    var isVisible: (NSWindow) -> Bool = { $0.occlusionState.contains(.visible) }

    /// Whether a frame change is scheduled; false off screen and while the
    /// picture holds.
    var isAnimating: Bool { timer != nil }

    func play(_ player: PetPlayer, revision: Int, pixelSize: CGFloat, still: Bool) {
        guard player !== self.player || revision != self.revision
            || pixelSize != self.pixelSize || still != self.still else { return }
        self.player = player
        self.revision = revision
        self.pixelSize = pixelSize
        self.still = still
        restart()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restart() }
            }
        }
        restart()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        restart()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = bounds
        CATransaction.commit()
    }

    /// Draws the frame for now and follows a fresh schedule, or stops while
    /// nobody can see the pet.
    private func restart() {
        timer?.invalidate()
        timer = nil
        dates = nil
        guard let player, let window, isVisible(window) else { return }
        let dates = player.schedule(still: still).entries(from: Date(), mode: .normal)
        self.dates = dates
        if let now = dates.next() { draw(at: now) }
        scheduleNext()
    }

    private func scheduleNext() {
        guard let date = dates?.next() else { return }
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.draw(at: date)
                self?.scheduleNext()
            }
        }
        timer.tolerance = Self.tolerance
        // Common modes keep the pet moving while a menu or a drag tracks events.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func draw(at date: Date) {
        guard let player else { return }
        let frame = still ? player.stillFrame(at: date) : player.frame(at: date)
        // Whole device pixels per sprite pixel, as in `PetFrameView`.
        let backingScale = window?.backingScaleFactor ?? 2
        let scale = max(1, Int((pixelSize * backingScale).rounded()))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.contents = frame.flatMap { PetRenderer.shared.image(for: $0.canvas, palette: player.palette, scale: scale) }
        if let anchor = frame?.bubbleAnchor {
            // The tail tip sits one sprite pixel up and right of the anchor;
            // layers count y up from the bottom.
            let size = CGSize(width: CGFloat(PetSpeechBubble.width) * pixelSize,
                              height: CGFloat(PetSpeechBubble.height) * pixelSize)
            bubble.frame = CGRect(x: CGFloat(anchor.x + 1) * pixelSize,
                                  y: bounds.height - CGFloat(anchor.y) * pixelSize,
                                  width: size.width, height: size.height)
            bubble.isHidden = false
        } else {
            bubble.isHidden = true
        }
        CATransaction.commit()
    }
}

/// One composed frame plus its speech bubble.
private struct PetFrameView: View {
    let frame: PetFrame
    let palette: PetPalette
    let pixelSize: CGFloat
    let displayScale: CGFloat

    var body: some View {
        let side = CGFloat(frame.canvas.width) * pixelSize
        // Render with whole device pixels per sprite pixel; the frame below
        // then maps them 1:1 whenever pixelSize × displayScale is whole.
        let scale = max(1, Int((pixelSize * displayScale).rounded()))
        ZStack(alignment: .topLeading) {
            if let image = PetRenderer.shared.image(for: frame.canvas, palette: palette, scale: scale) {
                Image(decorative: image, scale: CGFloat(scale) / pixelSize)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: side, height: side)
            }
            if let anchor = frame.bubbleAnchor {
                // The tail tip sits one sprite pixel up and right of the anchor.
                PetSpeechBubble(pixelSize: pixelSize)
                    .offset(x: CGFloat(anchor.x + 1) * pixelSize,
                            y: CGFloat(anchor.y - PetSpeechBubble.height) * pixelSize)
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
    }
}

/// A pixel-art "!" speech bubble drawn on the pet's own pixel grid, so it is
/// as crisp as the sprite. Its tail tip is the bottom-left pixel. Cream,
/// not white, to match the warm pet palette.
private struct PetSpeechBubble: View {
    let pixelSize: CGFloat

    /// `C` cream, `K` ink, `.` transparent.
    private static let rows = [
        ".CCCCCCC.",
        "CCCCKCCCC",
        "CCCCKCCCC",
        "CCCCKCCCC",
        "CCCCCCCCC",
        "CCCCKCCCC",
        ".CCCCCCC.",
        "CC.......",
        "C........",
    ]
    static let width = rows[0].count
    static let height = rows.count

    private static let cream = Color(red: 1.0, green: 0.96, blue: 0.88)
    private static let ink = Color(red: 0.24, green: 0.15, blue: 0.10)

    /// The bubble at one image pixel per sprite pixel, for `PetAnimationView`
    /// to scale up without smoothing.
    static let image: CGImage? = {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        for (y, row) in rows.enumerated() {
            for (x, character) in row.enumerated() {
                let color: Color
                switch character {
                case "C": color = cream
                case "K": color = ink
                default: continue
                }
                context.setFillColor(NSColor(color).cgColor)
                // Bitmap rows count up from the bottom.
                context.fill(CGRect(x: x, y: height - 1 - y, width: 1, height: 1))
            }
        }
        return context.makeImage()
    }()

    var body: some View {
        Canvas { context, _ in
            // One path per color, so fractional pixel sizes never show seams
            // between neighboring cells.
            var cream = Path(), ink = Path()
            for (y, row) in Self.rows.enumerated() {
                for (x, character) in row.enumerated() {
                    let cell = CGRect(x: CGFloat(x) * pixelSize, y: CGFloat(y) * pixelSize,
                                      width: pixelSize, height: pixelSize)
                    switch character {
                    case "C": cream.addRect(cell)
                    case "K": ink.addRect(cell)
                    default: break
                    }
                }
            }
            context.fill(cream, with: .color(Self.cream))
            context.fill(ink, with: .color(Self.ink))
        }
        .frame(width: CGFloat(Self.width) * pixelSize, height: CGFloat(Self.height) * pixelSize)
    }
}
