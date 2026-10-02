import SwiftUI
import NotchDeckCore

struct PlannerPanel: View {
    @ObservedObject var store: PlannerStore

    var body: some View {
        ModulePlaceholder(module: .planner, detail: "Your daily checklist is coming soon")
    }
}
