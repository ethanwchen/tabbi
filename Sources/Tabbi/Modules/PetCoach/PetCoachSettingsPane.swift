import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TabbiKitCore
import TabbiKit

extension SettingsPane {
    /// Settings › Pet Coach, offered while the Closet (the pet's module) is on.
    @MainActor static func petCoach(_ coach: PetCoachController) -> SettingsPane {
        SettingsPane(id: "coach", title: "Pet Coach", symbol: "pawprint",
                     view: AnyView(PetCoachSettingsPane(coach: coach)))
    }
}

/// Settings › Pet Coach: whether the pet nudges during focus, and which apps
/// count as distracting. Suggestions are opt-in chips; any other app can be
/// added from the Applications folder. Edits go straight to
/// `PetCoachController`, which saves them.
struct PetCoachSettingsPane: View {
    @ObservedObject var coach: PetCoachController

    var body: some View {
        Form {
            nudgesSection
            appsSection
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 500, height: height)
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: height)
    }

    /// The grouped form doesn't report its content height, so add up the
    /// rows that come and go; the window follows the pane's size.
    private var height: CGFloat {
        let chipRows = (CoachAppList.suggestedDistracting.count + 2) / 3
        return 284 + CGFloat(chipRows) * 40 + CGFloat(coach.apps.addedDistracting.count) * 36
    }

    // MARK: Nudges

    private var nudgesSection: some View {
        Section {
            Toggle("Nudge me during focus", isOn: Binding(get: { coach.nudgesOn }, set: { coach.setNudgesOn($0) }))
                .help("Let your pet walk out of the notch when you drift during a focus phase")
        } header: {
            Text("Nudges")
        } footer: {
            Footer("Only while a focus phase runs, at most a few times an hour. Your pet checks how long since you last typed or moved the pointer, and which app is in front. Nothing else, and no permissions.")
        }
    }

    // MARK: Distracting apps

    private var appsSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(CoachAppList.suggestedDistracting) { app in
                    AppChip(name: app.name, bundleID: app.bundleID,
                            isOn: coach.apps.isDistracting(app.bundleID)) {
                        coach.toggleDistracting(app.bundleID)
                    }
                }
            }
            .padding(.vertical, 2)

            ForEach(coach.apps.addedDistracting, id: \.self) { bundleID in
                AddedAppRow(bundleID: bundleID) { coach.toggleDistracting(bundleID) }
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("Distracting apps")
                Spacer()
                Button {
                    chooseApp()
                } label: {
                    Label("Add App…", systemImage: "plus")
                }
                .controlSize(.small)
                .help("Pick any app from your Applications folder")
            }
        } footer: {
            Footer("Time in these apps counts as drifting. Websites can't be told apart, since that would need Screen Recording, so pick apps rather than sites.")
        }
        .disabled(!coach.nudgesOn)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Add a Distracting App"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
            panel.urls.forEach(coach.addDistractingApp(at:))
        }
    }
}

/// An installed app's name and icon by bundle id, through Launch Services.
/// Bundle id lookups there ignore case, so the coach's lowercased ids work.
private struct InstalledApp {
    let name: String
    let icon: NSImage?

    init(bundleID: String, fallbackName: String? = nil) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            name = fallbackName ?? bundleID
            icon = nil
        }
    }
}

/// A suggested distracting app as a toggleable tile, like Focus' sound chips.
private struct AppChip: View {
    let name: String
    let bundleID: String
    let isOn: Bool
    let toggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        let app = InstalledApp(bundleID: bundleID, fallbackName: name)
        Button(action: toggle) {
            HStack(spacing: 6) {
                AppIcon(icon: app.icon)
                Text(name)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .transition(.motionPop)
                }
            }
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(isHovered ? 0.22 : 0.15)
                               : Color.primary.opacity(isHovered ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: isOn)
        .animation(.spring(response: 0.2, dampingFraction: 0.9), value: isHovered)
        .help(isOn ? "Stop counting \(name) as distracting" : "Count time in \(name) as drifting")
    }
}

/// A distracting app the user added, with a remove button.
private struct AddedAppRow: View {
    let bundleID: String
    let remove: () -> Void

    var body: some View {
        let app = InstalledApp(bundleID: bundleID)
        HStack(spacing: 8) {
            AppIcon(icon: app.icon)
            Text(app.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(bundleID)
            Spacer(minLength: 8)
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Stop counting \(app.name) as distracting")
        }
    }
}

/// The app's own icon, or a neutral placeholder for an app that isn't installed.
private struct AppIcon: View {
    let icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// Explanatory text under a section, matching the other panes' footers.
private struct Footer: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
