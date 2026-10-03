import SwiftUI
import TabbiKitCore

/// The NotchDeck design system. Use these tokens instead of literals so every
/// module feels like part of one product.
///
/// Principles: the notch is hardware-black and calm. Content uses one accent per
/// module, an 4pt spacing grid, rounded SF type, monospaced digits for anything
/// that changes, and springs rather than linear animation.
public enum Theme {
    public enum Palette {
        public static let background = Color.black
        /// Cards and controls sitting on the black notch.
        public static let surface = Color.white.opacity(0.07)
        public static let surfaceHover = Color.white.opacity(0.12)
        public static let stroke = Color.white.opacity(0.08)
        public static let primaryText = Color.white
        public static let secondaryText = Color.white.opacity(0.62)
        public static let tertiaryText = Color.white.opacity(0.38)
        public static let success = Color(red: 0.30, green: 0.85, blue: 0.48)
        public static let warning = Color(red: 1.00, green: 0.74, blue: 0.28)
        public static let danger = Color(red: 1.00, green: 0.38, blue: 0.36)

        /// One accent per module, used for progress, selection, and
        /// highlights. Modules pass their own descriptor's accent; shared
        /// views look it up through the `moduleCatalog` environment value.
        public static func accent(_ accent: ModuleAccent) -> Color {
            Color(red: accent.red, green: accent.green, blue: accent.blue)
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

    public enum Typography {
        public static let title = Font.system(size: 13, weight: .semibold, design: .rounded)
        public static let body = Font.system(size: 12, weight: .regular, design: .rounded)
        public static let bodyEmphasis = Font.system(size: 12, weight: .medium, design: .rounded)
        public static let caption = Font.system(size: 10.5, weight: .medium, design: .rounded)
        /// Large numbers (percentages, timers). Always monospaced digits.
        public static let metric = Font.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
        public static let metricSmall = Font.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
    }

    public enum Motion {
        /// Notch open/close.
        public static let notch = Animation.spring(response: 0.42, dampingFraction: 0.80)
        /// Hover, selection, small state changes.
        public static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.86)
        /// Content swaps between modules.
        public static let content = Animation.spring(response: 0.34, dampingFraction: 0.90)
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
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .strokeBorder(Theme.Palette.stroke, lineWidth: 0.5)
            )
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
                .background(Circle().fill(hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
    }
}

public extension ModuleDescriptor {
    /// The module's accent as a SwiftUI color.
    var accentColor: Color { Theme.Palette.accent(accent) }
}
