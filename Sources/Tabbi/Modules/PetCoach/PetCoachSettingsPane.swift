import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TabbiKitCore
import TabbiKit

extension SettingsPane {
    /// Settings › Pet Coach, offered while the Closet (the pet's module) is on.
    @MainActor static func petCoach(_ coach: PetCoachController, reminder: StudyReminderScheduler,
                                    breakBuddy: BreakBuddyController) -> SettingsPane {
        SettingsPane(id: "coach", title: String(localized: "Pet Coach", bundle: .tabbi), symbol: "pawprint",
                     view: AnyView(PetCoachSettingsPane(coach: coach, reminder: reminder, breakBuddy: breakBuddy)))
    }
}

/// Settings › Pet Coach: whether the pet nudges during focus, and which apps
/// count as distracting. Suggestions are opt-in chips; any other app can be
/// added from the Applications folder. Edits go straight to
/// `PetCoachController`, which saves them. The break buddy's moves
/// (`BreakBuddySettingsSection`) and the daily study reminder, in the pet's
/// voice (`StudyReminderSettingsSection`), sit below.
struct PetCoachSettingsPane: View {
    @ObservedObject var coach: PetCoachController
    @ObservedObject var reminder: StudyReminderScheduler
    let breakBuddy: BreakBuddyController

    var body: some View {
        Form {
            nudgesSection
            appsSection
            BreakBuddySettingsSection(buddy: breakBuddy)
            StudyReminderSettingsSection(reminder: reminder)
        }
        .formStyle(.grouped)
        .frame(width: 500, height: height)
        .motion(Motion.content, value: height)
    }

    /// The tallest the pane grows: past it, the form scrolls, so the window
    /// fits a small screen.
    static let maxHeight: CGFloat = 640

    /// The grouped form doesn't report its content height, so add up the
    /// rows that come and go; the window follows the pane's size. The form
    /// scrolls rather than clipping when a language's longer footers need
    /// more room than this guess, or the guess passes `maxHeight`.
    private var height: CGFloat {
        let chipRows = (CoachAppList.suggestedDistracting.count + 2) / 3
        let content = 284 + CGFloat(chipRows) * 40 + CGFloat(coach.apps.addedDistracting.count) * 36
            + BreakBuddySettingsSection.height
            + StudyReminderSettingsSection.height(blocked: reminder.isBlocked)
        return min(content, Self.maxHeight)
    }

    // MARK: Nudges

    private var nudgesSection: some View {
        Section {
            Toggle(String(localized: "Nudge me during focus", bundle: .tabbi), isOn: Binding(get: { coach.nudgesOn }, set: { coach.setNudgesOn($0) }))
                .help(String(localized: "Let your pet walk out of the notch when you drift during a focus phase", bundle: .tabbi))
        } header: {
            Text("Nudges", bundle: .tabbi)
        } footer: {
            SectionFooter(String(localized: "Only while a focus phase runs, at most a few times an hour. Your pet checks how long since you last typed or moved the pointer, and which app is in front. Nothing else, and no permissions.", bundle: .tabbi))
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
                Text("Distracting apps", bundle: .tabbi)
                Spacer()
                Button {
                    chooseApp()
                } label: {
                    Label(String(localized: "Add App…", bundle: .tabbi), systemImage: "plus")
                }
                .controlSize(.small)
                .help(String(localized: "Pick any app from your Applications folder", bundle: .tabbi))
            }
        } footer: {
            SectionFooter(String(localized: "Time in these apps counts as drifting. Websites can't be told apart, since that would need Screen Recording, so pick apps rather than sites.", bundle: .tabbi))
        }
        .disabled(!coach.nudgesOn)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Add a Distracting App", bundle: .tabbi)
        panel.prompt = String(localized: "Add", bundle: .tabbi)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        withMotion(Motion.content) {
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
        .motion(Motion.snappy, value: isOn)
        .motion(Motion.hover, value: isHovered)
        .help(isOn ? String(localized: "Stop counting \(name) as distracting", bundle: .tabbi)
                    : String(localized: "Count time in \(name) as drifting", bundle: .tabbi))
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
            .help(String(localized: "Stop counting \(app.name) as distracting", bundle: .tabbi))
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
