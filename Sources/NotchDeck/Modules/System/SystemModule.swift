import SwiftUI
import NotchKitCore

/// System: live CPU, GPU and memory. The monitor only samples while the panel is open.
@MainActor
final class SystemModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .system, title: "System", symbol: "cpu", category: .system,
        accent: ModuleAccent(red: 0.35, green: 0.78, blue: 1.00)
    )
    private let monitor = SystemMonitor()

    init(context: ModuleContext) {}

    func makePanel() -> AnyView {
        AnyView(SystemPanel(monitor: monitor))
    }
}
