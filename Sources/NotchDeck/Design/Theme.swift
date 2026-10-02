import SwiftUI
import NotchDeckCore

/// The NotchDeck design system. Use these tokens instead of literals so every
/// module feels like part of one product.
///
/// Principles: the notch is hardware-black and calm. Content uses one accent per
/// module, an 4pt spacing grid, rounded SF type, monospaced digits for anything
/// that changes, and springs rather than linear animation.
enum Theme {
    enum Palette {
        static let background = Color.black
        /// Cards and controls sitting on the black notch.
        static let surface = Color.white.opacity(0.07)
        static let surfaceHover = Color.white.opacity(0.12)
        static let stroke = Color.white.opacity(0.08)
        static let primaryText = Color.white
        static let secondaryText = Color.white.opacity(0.62)
        static let tertiaryText = Color.white.opacity(0.38)
        static let success = Color(red: 0.30, green: 0.85, blue: 0.48)
        static let warning = Color(red: 1.00, green: 0.74, blue: 0.28)
        static let danger = Color(red: 1.00, green: 0.38, blue: 0.36)

        /// One accent per module, used for progress, selection, and highlights.
        static func accent(for module: ModuleID) -> Color {
            switch module {
            case .spotify: Color(red: 0.12, green: 0.84, blue: 0.38)
            case .system: Color(red: 0.35, green: 0.78, blue: 1.00)
            case .claudeUsage, .claudeAsk: Color(red: 0.85, green: 0.47, blue: 0.34)
            case .planner: Color(red: 0.66, green: 0.55, blue: 1.00)
            }
        }
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 14
    }

    enum Typography {
        static let title = Font.system(size: 13, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 12, weight: .regular, design: .rounded)
        static let bodyEmphasis = Font.system(size: 12, weight: .medium, design: .rounded)
        static let caption = Font.system(size: 10.5, weight: .medium, design: .rounded)
        /// Large numbers (percentages, timers). Always monospaced digits.
        static let metric = Font.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
        static let metricSmall = Font.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
    }

    enum Motion {
        /// Notch open/close.
        static let notch = Animation.spring(response: 0.42, dampingFraction: 0.80)
        /// Hover, selection, small state changes.
        static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.86)
        /// Content swaps between modules.
        static let content = Animation.spring(response: 0.34, dampingFraction: 0.90)
    }

    enum Layout {
        /// Size of the open notch. Every module panel gets the same canvas so
        /// switching tabs never resizes the notch.
        static let expandedSize = CGSize(width: 560, height: 236)
        /// Horizontal inset for content inside the open notch.
        static let contentInset: CGFloat = 20
        /// Width of each "wing" beside the hardware notch when a module shows a
        /// compact live activity (e.g. album art + equalizer).
        static let compactWingWidth: CGFloat = 34
        /// Extra size when hovering the closed notch.
        static let hoverGrowth = CGSize(width: 16, height: 4)
        static let closedTopRadius: CGFloat = 6
        static let closedBottomRadius: CGFloat = 10
        static let openTopRadius: CGFloat = 12
        static let openBottomRadius: CGFloat = 26
    }
}

/// A rounded card on the notch background.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.m
    @ViewBuilder var content: Content

    var body: some View {
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
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 28
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
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
