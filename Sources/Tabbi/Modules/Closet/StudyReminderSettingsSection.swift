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
            Toggle(String(localized: "Remind me to study", bundle: .tabbi), isOn: Binding(get: { reminder.isEnabled },
                                                       set: { reminder.setEnabled($0) }))
                .help(String(localized: "A gentle nudge from \(name) on days you haven't studied yet", bundle: .tabbi))
            DatePicker(String(localized: "Time", bundle: .tabbi), selection: $reminder.time, displayedComponents: .hourAndMinute)
                .disabled(!reminder.isEnabled)
                .help(String(localized: "When the reminder can come, in your Mac's time zone", bundle: .tabbi))
            if reminder.isBlocked {
                HStack {
                    Label(String(localized: "Notifications are off for Tabbi", bundle: .tabbi), systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "Open System Settings", bundle: .tabbi)) { reminder.openNotificationSettings() }
                        .controlSize(.small)
                        .help(String(localized: "Allow Tabbi's notifications in System Settings", bundle: .tabbi))
                }
            }
        } header: {
            Text("Daily reminder", bundle: .tabbi)
        } footer: {
            SectionFooter(String(localized: "\"\(name) misses you. 10 minutes?\" At most once a day, and only if you haven't studied or met your goal yet. Focus modes silence it.", bundle: .tabbi))
        }
    }

    private var name: String {
        let name = reminder.petName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Tabbi" : name
    }
}
