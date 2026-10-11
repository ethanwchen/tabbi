import SwiftUI
import TabbiKitCore

/// The notch's thin slider: a capsule track, an accent fill and a round
/// knob, drawn in SwiftUI so it renders inside the notch and in snapshots
/// (a system slider would not). The focus sound mixer, the player volume
/// and the playback scrubber all use it.
///
/// `TrackSliderGeometry` keeps the knob on the track at both ends and its
/// center under the pointer. The drag-driven knob and fill never animate,
/// so they follow the pointer exactly; only the hover and drag highlight
/// (a larger knob, a thicker track) springs. The highlight holds for the
/// whole drag, even when the pointer strays off the thin track. Values run
/// left to right in every language, as Tabbi's bars do.
public struct TrackSlider: View {
    /// When the knob shows.
    public enum KnobVisibility: Sendable {
        case always
        /// Only while hovered or dragged, as on the playback scrubber.
        case whileActive
    }

    let value: Double
    let tint: Color
    let idleTint: Color?
    let trackHeight: CGFloat
    let activeTrackHeight: CGFloat
    let knobDiameter: CGFloat
    let knobVisibility: KnobVisibility
    let step: Double
    let help: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let onChange: (Double) -> Void
    let onCommit: ((Double) -> Void)?

    @State private var hovering = false
    @GestureState private var dragging = false

    /// - Parameters:
    ///   - value: The current value, 0...1 (clamped for drawing).
    ///   - tint: The fill, usually the module's accent.
    ///   - idleTint: The fill while neither hovered nor dragged, if it differs.
    ///   - activeTrackHeight: The track's thickness while hovered or dragged;
    ///     the resting `trackHeight` when nil.
    ///   - step: How far VoiceOver's increment and decrement move it.
    ///   - help: The tooltip, which should name the value.
    ///   - onChange: Called with each new value while dragging.
    ///   - onCommit: Called once with the final value when a drag ends.
    public init(value: Double, tint: Color, idleTint: Color? = nil,
                trackHeight: CGFloat = 4, activeTrackHeight: CGFloat? = nil,
                knobDiameter: CGFloat = 8, knobVisibility: KnobVisibility = .always,
                step: Double = 0.1, help: String, accessibilityLabel: String, accessibilityValue: String,
                onChange: @escaping (Double) -> Void, onCommit: ((Double) -> Void)? = nil) {
        self.value = value
        self.tint = tint
        self.idleTint = idleTint
        self.trackHeight = trackHeight
        self.activeTrackHeight = activeTrackHeight ?? trackHeight
        self.knobDiameter = knobDiameter
        self.knobVisibility = knobVisibility
        self.step = step
        self.help = help
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.onChange = onChange
        self.onCommit = onCommit
    }

    /// Hovered or mid-drag.
    var isActive: Bool { hovering || dragging }

    /// How much the knob grows while active.
    static let activeKnobScale: CGFloat = 1.25

    public var body: some View {
        GeometryReader { proxy in
            // Sized for the grown knob, so even that stays on the track.
            let geometry = TrackSliderGeometry(width: proxy.size.width, knobDiameter: knobDiameter * Self.activeKnobScale)
            let height = isActive ? activeTrackHeight : trackHeight
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Palette.surfaceHover)
                    .frame(height: height)
                Capsule()
                    .fill(isActive ? tint : (idleTint ?? tint))
                    .frame(width: geometry.fillWidth(at: value), height: height)
                knob
                    .offset(x: geometry.knobOffset(at: value))
            }
            // The knob and fill follow the value with no animation, so a
            // drag never lags behind the pointer, whatever animates around it.
            .animation(nil, value: value)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { drag in onChange(geometry.fraction(atX: drag.location.x)) }
                    .onEnded { drag in onCommit?(geometry.fraction(atX: drag.location.x)) }
            )
        }
        .fixedLeftToRight()
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: isActive)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: commit(min(value + step, 1))
            case .decrement: commit(max(value - step, 0))
            @unknown default: break
            }
        }
    }

    /// Grows around its own center: the scale comes before the offset, so
    /// it never moves the knob along the track. Its frame is the grown
    /// size, which the geometry places.
    private var knob: some View {
        Circle()
            .fill(Theme.Palette.primaryText)
            .frame(width: knobDiameter, height: knobDiameter)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .scaleEffect(isActive ? Self.activeKnobScale : 1)
            .frame(width: knobDiameter * Self.activeKnobScale, height: knobDiameter * Self.activeKnobScale)
            .opacity(knobVisibility == .always || isActive ? 1 : 0)
    }

    private func commit(_ newValue: Double) {
        onChange(newValue)
        onCommit?(newValue)
    }
}
