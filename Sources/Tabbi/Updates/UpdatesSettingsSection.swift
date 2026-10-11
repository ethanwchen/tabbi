import SwiftUI
import TabbiKitCore

/// The update controls in Settings > About: "Check for Updates…", the
/// automatic checks switch, and, when this copy cannot update itself, why.
/// Demo and snapshot runs show the controls as a release build would.
struct UpdatesSettingsSection: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        VStack(spacing: 12) {
            Button(String(localized: "Check for Updates…", bundle: .tabbi), action: updater.checkForUpdates)
                .disabled(!updater.canCheckForUpdates && !updater.policy.isPreview)
                .help(updater.policy.explanation(appName: Edition.current.name)
                      ?? "Look for a newer version of \(Edition.current.name) now")
            if updater.isAvailable || updater.policy.isPreview {
                Toggle(String(localized: "Check for updates automatically", bundle: .tabbi), isOn: $updater.automaticallyChecksForUpdates)
                    .toggleStyle(.checkbox)
                    .help(String(localized: "Check once a day and offer new versions as they come out", bundle: .tabbi))
            } else if let explanation = updater.policy.explanation(appName: Edition.current.name) {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
    }
}
