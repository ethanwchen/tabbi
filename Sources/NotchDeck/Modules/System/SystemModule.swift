import SwiftUI
import NotchKitCore

/// System: live CPU, GPU and memory. The monitor only samples while the panel is open.
@MainActor
final class SystemModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .system)
    private let monitor: SystemMonitor

    init(monitor: SystemMonitor) {
        self.monitor = monitor
    }

    func makePanel() -> AnyView {
        AnyView(SystemPanel(monitor: monitor))
    }
}
