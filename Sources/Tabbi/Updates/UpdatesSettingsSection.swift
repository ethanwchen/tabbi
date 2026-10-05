import SwiftUI
import TabbiKitCore

/// The update controls in Settings > About: "Check for Updates…", the
/// automatic checks switch, and, when this copy cannot update itself, why.
/// Demo and snapshot runs show the controls as a release build would.
struct UpdatesSettingsSection: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        VStack(spacing: 12) {
            Button("Check for Updates…", action: updater.checkForUpdates)
                .disabled(!updater.canCheckForUpdates && !updater.policy.isPreview)
                .help(updater.policy.explanation(appName: Edition.current.name)
                      ?? "Look for a newer version of \(Edition.current.name) now")
            if updater.isAvailable || updater.policy.isPreview {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                    .toggleStyle(.checkbox)
                    .help("Check once a day and offer new versions as they come out")
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
