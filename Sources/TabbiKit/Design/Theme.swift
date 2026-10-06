import os
import SwiftUI
import TabbiKitCore

/// The Tabbi design system. Use these tokens instead of literals so every
/// module feels like part of one product.
///
/// Principles: the notch is hardware-black and calm. Content uses one accent per
/// module, an 4pt spacing grid, rounded SF type, monospaced digits for anything
/// that changes, and springs rather than linear animation.
public enum Theme {
    /// The active theme. Every token below reads it, so one call to `apply`
    /// restyles the whole app; views that are already on screen redraw when
    /// their root is re-keyed by the theme id (`NotchViewModel.themeID`).
    public static var current: AppTheme { state.withLock { $0 } }

    /// Makes `theme` the active theme. Call it before re-keying the views.
    public static func apply(_ theme: AppTheme) {
        state.withLock { $0 = theme }
    }

    private static let state = OSAllocatedUnfairLock(initialState: ThemeCatalog.midnight)

    /// Colors of the active theme. The panel body is opaque black in every
    /// theme, so the open notch stays continuous with the hardware cutout.
    public enum Palette {
        public static var background: Color { Color(current.palette.background) }
        /// A soft color rising from the bottom of the open panel, nil when
        /// the theme keeps it flat.
        public static var glow: Color? { current.palette.glow.map(Color.init) }
        /// Cards and controls sitting on the black notch.
        public static var surface: Color { Color(current.palette.surface) }
        public static var surfaceHover: Color { Color(current.palette.surfaceHover) }
        public static var stroke: Color { Color(current.palette.stroke) }
        public static var primaryText: Color { Color(current.palette.primaryText) }
        public static var secondaryText: Color { Color(current.palette.secondaryText) }
        public static var tertiaryText: Color { Color(current.palette.tertiaryText) }
        public static var success: Color { Color(current.palette.success) }
        public static var warning: Color { Color(current.palette.warning) }
        public static var danger: Color { Color(current.palette.danger) }

        /// One accent per module, used for progress, selection, and
        /// highlights, as the active theme treats it (muted, vivid, pastel).
        /// Modules pass their own descriptor's accent; shared views look it
        /// up through the `moduleCatalog` environment value.
        public static func accent(_ accent: ModuleAccent) -> Color {
            Color(current.accent(accent))
        }
    }

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
    }

    public enum Radius {
        public static let s: CGFloat = 6
        public static let m: CGFloat = 10
        public static let l: CGFloat = 14
    }

    /// Type in the active theme's family (SF Pro Rounded or SF Pro).
    public enum Typography {
        public static var title: Font { font(13, .semibold) }
        public static var body: Font { font(12, .regular) }
        public static var bodyEmphasis: Font { font(12, .medium) }
        public static var caption: Font { font(10.5, .medium) }
        /// Large numbers (percentages, timers). Always monospaced digits.
        public static var metric: Font { font(22, .semibold).monospacedDigit() }
        public static var metricSmall: Font { font(13, .semibold).monospacedDigit() }

        /// The active theme's design, for type outside the scale above.
        public static var design: Font.Design {
            current.typeface == .rounded ? .rounded : .default
        }

        private static func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
            .system(size: size, weight: weight, design: design)
        }
    }

    /// Shorthands for the motion system (`Motion`, docs/design/motion.md),
    /// which follows the theme: gentle themes slow the springs and drop
    /// some bounce.
    public enum Motion {
        /// Hover, selection, small state changes.
        public static var snappy: Animation { TabbiKit.Motion.snappy }
        /// Content swaps between modules.
        public static var content: Animation { TabbiKit.Motion.content }
    }

    public enum Layout {
        /// Size of the open notch. Every module panel gets the same canvas so
        /// switching tabs never resizes the notch.
        public static let expandedSize = CGSize(width: 560, height: 236)
        /// Horizontal inset for content inside the open notch.
        public static let contentInset: CGFloat = 20
        /// Width of each "wing" beside the hardware notch when a module shows a
        /// compact live activity (e.g. album art + equalizer).
        public static let compactWingWidth: CGFloat = 34
        /// Extra size when hovering the closed notch.
        public static let hoverGrowth = CGSize(width: 16, height: 4)
        public static let closedTopRadius: CGFloat = 6
        public static let closedBottomRadius: CGFloat = 10
        public static let openTopRadius: CGFloat = 12
        public static let openBottomRadius: CGFloat = 26
    }
}

/// A rounded card on the notch background.
public struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.m
    @ViewBuilder var content: Content

    public init(padding: CGFloat = Theme.Spacing.m, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .surfaceBackground(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
    }
}

/// A circular icon button with a hover state.
public struct IconButton: View {
    let symbol: String
    var size: CGFloat = 28
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    public init(symbol: String, size: CGFloat = 28, help: String = "", action: @escaping () -> Void) {
        self.symbol = symbol
        self.size = size
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(Theme.Palette.primaryText)
                .frame(width: size, height: size)
                .controlBackground(Circle(), hovering: hovering)
                .contentShape(Circle())
        }
        .buttonStyle(.tactile)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

public extension ModuleDescriptor {
    /// The module's accent as a SwiftUI color.
    var accentColor: Color { Theme.Palette.accent(accent) }
}

public extension Color {
    /// A theme color in sRGB.
    init(_ color: ThemeColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.opacity)
    }
}

public extension View {
    /// The background of a small floating control (icon buttons, the tab
    /// bar's selection) in the active theme: the palette's surface, or
    /// Liquid Glass where the theme asks for it and the system allows it
    /// (see `ControlMaterial`). Content never gets glass.
    func controlBackground(_ shape: some Shape, hovering: Bool = false, tint: Color? = nil) -> some View {
        modifier(ControlBackground(shape: shape, hovering: hovering, tint: tint))
    }
}

public extension View {
    /// The background of a content surface (`Card`) in the active theme:
    /// the flat palette surface with a hairline stroke, or frosted glass
    /// when the theme's `surfaces` is `.glass` (see `GlassSheen`).
    func surfaceBackground(_ shape: some InsettableShape) -> some View {
        modifier(SurfaceBackground(shape: shape))
    }
}

public extension EnvironmentValues {
    /// False where Liquid Glass can't be drawn, such as `ImageRenderer`
    /// snapshots, so glass controls show their material fallback instead.
    @Entry var drawsLiquidGlass = true
}

private struct ControlBackground<S: Shape>: ViewModifier {
    let shape: S
    let hovering: Bool
    let tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.drawsLiquidGlass) private var drawsLiquidGlass

    private var glassAvailable: Bool {
        guard drawsLiquidGlass else { return false }
        if #available(macOS 26, *) { return true } else { return false }
    }

    func body(content: Content) -> some View {
        let material = ControlMaterial.resolve(Theme.current.controls, glassAvailable: glassAvailable,
                                               reduceTransparency: reduceTransparency)
        switch material {
        case .glass:
            if #available(macOS 26, *) {
                content.glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                solid(content)
            }
        case .material where drawsLiquidGlass:
            content.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(fill)
                }
            }
            .overlay(rim)
        case .material:
            // Snapshots can't draw materials either: a lit rim on the solid
            // fill stands in for the glass.
            solid(content).overlay(rim)
        case .opaque:
            solid(content)
        }
    }

    private var fill: Color {
        tint ?? (hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface)
    }

    /// The light catching the top edge of a glass control.
    private var rim: some View {
        shape.stroke(LinearGradient(colors: [Color(GlassSheen.standard.rimTop), Color(GlassSheen.standard.rimBottom)],
                                    startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            .allowsHitTesting(false)
    }

    private func solid(_ content: Content) -> some View {
        content.background(shape.fill(fill))
    }
}

private struct SurfaceBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.drawsLiquidGlass) private var drawsLiquidGlass

    func body(content: Content) -> some View {
        switch Theme.current.surfaces {
        case .flat:
            content
                .background(shape.fill(Theme.Palette.surface))
                .overlay(shape.strokeBorder(Theme.Palette.stroke, lineWidth: 0.5))
        case .glass:
            glass(content)
        }
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        let live = drawsLiquidGlass && !reduceTransparency
        if #available(macOS 26, *), live {
            content
                .background(GlassSheenView(shape: shape))
                .glassEffect(.regular, in: shape)
                .overlay(GlassRim(shape: shape))
        } else if live {
            content
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        GlassSheenView(shape: shape)
                    }
                }
                .overlay(GlassRim(shape: shape))
        } else {
            // Snapshots and Reduce Transparency: the drawn sheen alone.
            content
                .background(GlassSheenView(shape: shape))
                .overlay(GlassRim(shape: shape))
        }
    }
}

/// The painted light of a glass surface: a top-lit fill and a soft glint
/// near the top-leading corner.
private struct GlassSheenView<S: Shape>: View {
    let shape: S

    var body: some View {
        let sheen = GlassSheen.standard
        shape
            .fill(LinearGradient(colors: [Color(sheen.fillTop), Color(sheen.fillBottom)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                shape.fill(EllipticalGradient(colors: [Color(sheen.glint), Color(sheen.glint.opacity(0))],
                                              center: UnitPoint(x: 0.15, y: 0),
                                              startRadiusFraction: 0, endRadiusFraction: 0.55))
            )
            .allowsHitTesting(false)
    }
}

/// The rim of a glass surface, lit from above.
private struct GlassRim<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        let sheen = GlassSheen.standard
        shape
            .strokeBorder(LinearGradient(colors: [Color(sheen.rimTop), Color(sheen.rimBottom)],
                                         startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            .allowsHitTesting(false)
    }
}
