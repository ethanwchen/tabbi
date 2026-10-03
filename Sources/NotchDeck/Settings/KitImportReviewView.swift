import SwiftUI
import NotchKitCore

/// What an imported kit will do, shown before it is saved or applied:
/// the tabs it turns on and off, the permissions those tabs ask for, the
/// starter tasks Today gets, whether the closed notch changes, what this
/// build skips, and which earlier import it replaces. Settings shows it
/// after the kit's onboarding questions, so it reflects the answers.
struct KitImportReviewView: View {
    let candidate: KitImportCandidate
    let preview: KitChangePreview
    /// What the kit uses that this build skips.
    let issues: [KitIssue]
    /// True when the kit is the active one, so applying it is an update.
    let isActiveKit: Bool
    /// Back to the questions when the kit has any; nil shows Cancel.
    let back: (() -> Void)?
    let cancel: () -> Void
    /// Saves the kit without changing the user's tabs.
    let addOnly: () -> Void
    /// Saves the kit and switches to it.
    let apply: () -> Void
    @Environment(\.moduleCatalog) private var catalog

    private var kit: KitManifest { candidate.kit }

    var body: some View {
        let tint = kit.accentModule(catalog: catalog).map { catalog.descriptor(for: $0).accentColor } ?? .accentColor
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: kit.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.gradient))
                Text(isActiveKit ? "Update \(kit.name)" : "Import \(kit.name)")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text(kit.summary.isEmpty ? "Check what this kit changes before you switch to it." : kit.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 36)
            .padding(.horizontal, 40)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
                if candidate.overwritesFile {
                    row("Replaces", warning: true) {
                        Text(replacementNote)
                    }
                }
                row("Tabs") {
                    VStack(alignment: .leading, spacing: 4) {
                        TabIcons(modules: preview.tabs)
                        if let change = tabChange {
                            Text(change).foregroundStyle(.secondary)
                        }
                    }
                }
                if !preview.newPermissions.isEmpty {
                    row("Permissions") {
                        Text("New tabs may ask for \(list(preview.newPermissions.map(\.title))).")
                    }
                }
                row("Today") {
                    Text(starterTasksNote)
                        .foregroundStyle(preview.starterTasks.isEmpty ? .secondary : .primary)
                }
                if preview.changesNotchPreviews {
                    row("Closed notch") {
                        Text("Shows the previews this kit picks.")
                    }
                }
                if !issues.isEmpty {
                    row("Skipped", warning: true) {
                        Text(issues.map(\.description).joined(separator: " "))
                    }
                }
            }
            .font(.callout)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Text("Switching keeps your other settings, and you can undo it under Kit in Settings.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            HStack(spacing: 8) {
                if let back {
                    Button("Back", action: back)
                        .controlSize(.large)
                        .help("Change your answers")
                }
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                    .help(isActiveKit ? "Keep the kit as it was" : "Don't import \(kit.name)")
                Spacer()
                Button(isActiveKit ? "Keep My Tabs" : "Add Only", action: addOnly)
                    .controlSize(.large)
                    .help(isActiveKit
                          ? "Save the update without changing your tabs"
                          : "Add \(kit.name) to your kits without switching; pick it later under Current kit")
                Button(isActiveKit ? "Apply Update" : "Switch Kit", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help(isActiveKit
                          ? "Save the update and set your tabs up the way it does"
                          : "Add \(kit.name) and switch to it")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    /// One labeled row: the label in the leading column, the value beside it.
    private func row(_ label: String, warning: Bool = false, @ViewBuilder value: () -> some View) -> some View {
        GridRow {
            HStack(spacing: 4) {
                if warning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Text(label)
                    .foregroundStyle(.secondary)
            }
            .gridColumnAlignment(.trailing)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var replacementNote: String {
        if let change = candidate.versionChange {
            return "Updates \(change), replacing the copy you imported before."
        }
        return "Replaces the \(candidate.replaces?.name ?? kit.name) kit you imported before."
    }

    private var tabChange: String? {
        let on = preview.turnsOn.map { catalog.descriptor(for: $0).title }
        let off = preview.turnsOff.map { catalog.descriptor(for: $0).title }
        let parts = [on.isEmpty ? nil : "Turns on \(list(on)).", off.isEmpty ? nil : "Turns off \(list(off))."]
        let text = parts.compactMap { $0 }.joined(separator: " ")
        return text.isEmpty ? (preview.tabs.isEmpty ? nil : "Your tabs stay on.") : text
    }

    private var starterTasksNote: String {
        switch preview.starterTasks.count {
        case 0: "Adds no tasks."
        case 1: "Adds \"\(preview.starterTasks[0])\"."
        default: "Adds \(preview.starterTasks.count) starter tasks: \(list(preview.starterTasks.map { "\"\($0)\"" }))."
        }
    }

    private func list(_ items: [String]) -> String {
        ListFormatter.localizedString(byJoining: items)
    }
}
