import SwiftUI
import NotchDeckCore

struct SystemPanel: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        ModulePlaceholder(module: .system, detail: "CPU and GPU stats are coming soon")
    }
}
