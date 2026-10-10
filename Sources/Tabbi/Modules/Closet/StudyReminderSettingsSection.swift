import SwiftUI
import TabbiKitCore
import TabbiKit

/// Settings › Pet Coach › Daily reminder: one switch and a time. Turning
/// the switch on is what asks macOS for notification permission; if the
/// user said no there, a row points to System Settings instead of failing
/// silently.
struct StudyReminderSettingsSection: View {
    @ObservedObject var reminder: StudyReminderScheduler

    /// The section's height in the grouped form, which doesn't report its
    /// own; the pane adds it to its fixed height.
    static func height(blocked: Bool) -> CGFloat {
        blocked ? 196 : 156
    }

    var body: some View {
        Section {
            Toggle("Remind me to study", isOn: Binding(get: { reminder.isEnabled },
                                                       set: { reminder.setEnabled($0) }))
                .help("A gentle nudge from \(name) on days you haven't studied yet")
            DatePicker("Time", selection: $reminder.time, displayedComponents: .hourAndMinute)
                .disabled(!reminder.isEnabled)
                .help("When the reminder can come, in your Mac's time zone")
            if reminder.isBlocked {
                HStack {
                    Label("Notifications are off for Tabbi", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open System Settings") { reminder.openNotificationSettings() }
                        .controlSize(.small)
                        .help("Allow Tabbi's notifications in System Settings")
                }
            }
        } header: {
            Text("Daily reminder")
        } footer: {
            SectionFooter("\"\(name) misses you. 10 minutes?\" At most once a day, and only if you haven't studied or met your goal yet. Focus modes silence it.")
        }
    }

    private var name: String {
        let name = reminder.petName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Tabbi" : name
    }
}
