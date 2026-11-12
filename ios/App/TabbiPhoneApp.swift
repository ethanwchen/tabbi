import SwiftUI
import TabbiKitCore

@main
struct TabbiPhoneApp: App {
    @State private var store: StudyStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The UI tests start every run on a fresh install's state.
        if ProcessInfo.processInfo.arguments.contains("-TabbiResetState") {
            StudyPersistence.standard.reset()
        }
        _store = State(initialValue: StudyStore())
    }

    var body: some Scene {
        WindowGroup {
            TimerScreen()
                .environment(store)
                // TabbiKitCore picks the strings' language from the user's
                // preferred languages (L10n); views lay out to match it.
                .environment(\.layoutDirection, L10n.isRightToLeft ? .rightToLeft : .leftToRight)
        }
        .onChange(of: scenePhase) { _, phase in
            // Phases end while the app is suspended; catch up on return.
            store.setActive(phase == .active)
        }
    }
}
