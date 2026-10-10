import SwiftUI
import TabbiKitCore

/// The crash report choice in Settings > About, so a "Don't ask again"
/// answer from the prompt can be seen, changed or taken back. It reads and
/// writes the same value as `CrashReportConsentStore`; an unknown value
/// shows as "Ask after a crash", as the store reads it.
struct CrashReportSettingsSection: View {
    @AppStorage(CrashReportConsentStore.key) private var consent: CrashReportConsent = .ask

    var body: some View {
        Picker("Crash reports", selection: $consent) {
            ForEach(CrashReportConsent.allCases, id: \.self) { choice in
                Text(choice.title).tag(choice)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help("After \(Edition.current.name) closes unexpectedly, ask before sending a crash report, send it without asking, or never send one")
    }
}
