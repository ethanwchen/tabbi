import SwiftUI
import TabbiKitCore

/// Picks the study method, with each method's rhythm as on the Mac.
/// Choosing one while a session runs starts over on it, and the time
/// studied so far is banked like a Stop.
struct MethodSheet: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(StudyEngine.menu.methods(custom: store.engine.custom, timer: store.engine.timer), id: \.kind) { method in
                    row(method)
                }
            }
            .navigationTitle(Text("Choose a method", bundle: .tabbi))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .tabbi) }
                }
            }
        }
    }

    private func row(_ method: StudyMethod) -> some View {
        let isCurrent = method.kind == store.session.method.kind
        return Button {
            store.choose(method.kind)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(StudyMethodInfo.info(for: method.kind).displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(method.rhythmLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
