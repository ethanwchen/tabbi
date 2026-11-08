import SwiftUI
import TabbiKitCore

@main
struct TabbiPhoneApp: App {
    @State private var study: StudyStore
    @State private var cam: PetCamStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The UI tests start every run on a fresh install's state.
        if ProcessInfo.processInfo.arguments.contains("-TabbiResetState") {
            StudyPersistence.standard.reset()
        }
        // The camera listens from the first moment, so a block that ended
        // while the app was closed is resolved by the launch catch-up.
        let cam = PetCamStore()
        let study = StudyStore(observer: cam)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TabbiDemoPet") { study.useDemoPet() }
        #endif
        cam.petChanged(study.pet)
        _cam = State(initialValue: cam)
        _study = State(initialValue: study)
    }

    var body: some Scene {
        WindowGroup {
            PetCamRoot()
                .environment(study)
                .environment(cam)
                // TabbiKitCore picks the strings' language from the user's
                // preferred languages (L10n); views lay out to match it.
                .environment(\.layoutDirection, L10n.isRightToLeft ? .rightToLeft : .leftToRight)
        }
        .onChange(of: scenePhase) { _, phase in
            // Phases end while the app is suspended; catch up on return,
            // then show any tape that came in meanwhile.
            study.setActive(phase == .active)
            cam.setActive(phase == .active)
        }
    }
}
