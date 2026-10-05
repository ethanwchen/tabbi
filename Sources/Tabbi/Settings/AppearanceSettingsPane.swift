import SwiftUI
import TabbiKitCore
import TabbiKit

/// Picks the theme of the open notch. Every choice is a live miniature of
/// the panel drawn with the user's own tab accents, and picking one restyles
/// the notch right away (the controller follows `settings.themeID`).
struct AppearanceSettingsPane: View {
    @EnvironmentObject private var store: SettingsStore

    private var selected: AppTheme { ThemeCatalog.resolve(store.settings.themeID) }

    /// The enabled tabs' accents, in tab order, so previews look like this
    /// user's notch.
    private var accents: [ModuleAccent] {
        store.settings.modules.enabled.map { store.catalog.descriptor(for: $0).accent }
    }

    var body: some View {
        Form {
            family(.classic, title: "Classic")
            family(.cozy, title: "Cozy", footer: footer)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: paneWidth, height: 400)
    }

    private func family(_ family: ThemeFamily, title: String, footer: String? = nil) -> some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                let themes = ThemeCatalog.all.filter { $0.family == family }
                ForEach(themes) { theme in
                    ThemeChoice(theme: theme, accents: accents, isSelected: theme.id == selected.id) {
                        store.settings.themeID = theme.id
                    }
                }
                // Keeps the cozy row's three cards the same width as the
                // classic row's five.
                ForEach(themes.count..<5, id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text(title)
        } footer: {
            if let footer {
                SectionFooter(footer)
            }
        }
    }

    private var footer: String {
        var text = "\(selected.summary) Themes style the open panel; the closed notch stays black."
        if selected.controls == .glass {
            text += " Glass controls need macOS 26 and fall back to a solid style when Reduce Transparency is on."
        }
        return text
    }
}

/// One theme in the picker: its miniature, name, and a selection ring.
private struct ThemeChoice: View {
    let theme: AppTheme
    let accents: [ModuleAccent]
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    private let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ThemePreview(theme: theme, accents: accents)
                    .frame(height: 68)
                    .padding(3)
                    .overlay {
                        shape.strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(hovering ? 0.28 : 0.12),
                                           lineWidth: isSelected ? 2 : 1)
                    }
                    .scaleEffect(hovering && !isSelected ? 1.03 : 1)
                Text(theme.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isSelected)
        .help("\(theme.name): \(theme.summary)")
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
