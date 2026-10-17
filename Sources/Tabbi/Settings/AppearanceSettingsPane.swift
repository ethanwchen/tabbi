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
            family(.classic, title: String(localized: "Classic", bundle: .tabbi))
            family(.cozy, title: String(localized: "Cozy", bundle: .tabbi))
            family(.sweet, title: String(localized: "Sweet", bundle: .tabbi), footer: footer)
            ResetToDefaultsRow(isAtDefaults: store.settings.themeID == store.defaultTheme,
                               help: String(localized: "Go back to \(ThemeCatalog.resolve(store.defaultTheme).displayName), the theme \(store.activeKit?.name ?? Edition.current.name) starts with", bundle: .tabbi),
                               title: String(localized: "Reset to Default", bundle: .tabbi)) {
                store.settings.themeID = store.defaultTheme
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        // Fits two-line names in every row and, in the longest languages
        // (Arabic, German), the footer with Liquid Glass's extra sentence.
        .frame(width: paneWidth, height: 840)
    }

    /// Five cards to a row in every family, so the cozy row's three line up
    /// with the others and the sweet family's ten pair up by column (each
    /// pastel above its deep or duo partner).
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 5)

    private func family(_ family: ThemeFamily, title: String, footer: String? = nil) -> some View {
        Section {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(ThemeCatalog.all.filter { $0.family == family }) { theme in
                    ThemeChoice(theme: theme, accents: accents, isSelected: theme.id == selected.id) {
                        store.settings.themeID = theme.id
                    }
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
        var text = String(localized: "\(selected.displaySummary) Themes style the open panel; the closed notch stays black.", bundle: .tabbi)
        if selected.controls == .glass {
            text += " " + String(localized: "Glass controls need macOS 26 and fall back to a solid style when Reduce Transparency is on.", bundle: .tabbi)
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
                // Two lines, reserved in every card so a row's previews line
                // up: longer names ("Клубничное молоко") wrap instead of
                // being cut.
                Text(theme.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isSelected)
        .help(String(localized: "\(theme.displayName): \(theme.displaySummary)", bundle: .tabbi))
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
