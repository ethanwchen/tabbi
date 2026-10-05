import SwiftUI
import TabbiKitCore

/// A miniature open notch drawn in `theme`: the black body with the theme's
/// glow (spread over the whole body so it reads at this size), a tab bar
/// with a few module accents, and a card with a timer.
///
/// It reads the theme it is given, never `Theme.current`, so a picker can
/// show every theme side by side (Settings' Appearance pane, onboarding).
public struct ThemePreview: View {
    let theme: AppTheme
    let accents: [ModuleAccent]

    /// `accents` are the module accents to sample, in tab order; the first
    /// is the selected tab. Only the first four are drawn.
    public init(theme: AppTheme, accents: [ModuleAccent]) {
        self.theme = theme
        self.accents = accents.isEmpty ? [ModuleAccent(red: 0.40, green: 0.62, blue: 1.00)] : accents
    }

    private var palette: ThemePalette { theme.palette }
    private var lead: Color { Color(theme.accent(accents[0])) }
    private var design: Font.Design { theme.typeface == .rounded ? .rounded : .default }
    private let shape = UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 12,
                                              bottomTrailingRadius: 12, topTrailingRadius: 5, style: .continuous)

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            tabBar
            card
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                shape.fill(Color(palette.background))
                if let glow = palette.glow {
                    shape.fill(LinearGradient(colors: [.clear, Color(glow)], startPoint: .top, endPoint: .bottom))
                }
            }
        }
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
    }

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(Array(accents.prefix(4).enumerated()), id: \.offset) { index, accent in
                let color = Color(theme.accent(accent))
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .padding(.vertical, 3)
                    .padding(.horizontal, index == 0 ? 6 : 3)
                    .background {
                        if index == 0 {
                            Capsule().fill(Color(palette.surfaceHover))
                                .overlay {
                                    if theme.controls == .glass {
                                        Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.5)
                                    }
                                }
                        }
                    }
            }
            Spacer(minLength: 0)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("25:00")
                .font(.system(size: 11, weight: .semibold, design: design).monospacedDigit())
                .foregroundStyle(Color(palette.primaryText))
                .lineLimit(1)
            Capsule()
                .fill(Color(palette.surfaceHover))
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(lead).frame(width: proxy.size.width * 0.62)
                    }
                }
            Capsule()
                .fill(Color(palette.tertiaryText))
                .frame(width: 30, height: 2)
        }
        .padding(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(palette.surface)))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color(palette.stroke), lineWidth: 0.5))
    }
}
