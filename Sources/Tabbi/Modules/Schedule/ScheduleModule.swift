import SwiftUI
import TabbiKitCore
import TabbiKit

extension ModuleID {
    static let schedule: ModuleID = "schedule"
}

/// Schedule: today's calendar and planned blocks on a timeline, with what is
/// on now and what is free. Opt in from Add More; no kit turns it on.
@MainActor
final class ScheduleModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .schedule, title: "Schedule", symbol: "calendar.day.timeline.left",
        summary: "Your day on a timeline, with the free time in between.", category: .productivity,
        accent: ModuleAccent(red: 1.00, green: 0.50, blue: 0.42), permissions: [.calendars]
    )
    /// Internal so app tests can check what Schedule shows.
    let store: ScheduleStore

    init(context: ModuleContext) {
        store = ScheduleStore(runMode: context.runMode)
    }

    func makePanel() -> AnyView {
        AnyView(SchedulePanel(store: store))
    }
}
