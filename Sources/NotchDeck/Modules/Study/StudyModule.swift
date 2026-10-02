import SwiftUI
import NotchKitCore

/// Study: study timer and methods (preview panel until the feature lands).
@MainActor
final class StudyModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .study)

    func makePanel() -> AnyView {
        AnyView(StudyPanel())
    }
}
