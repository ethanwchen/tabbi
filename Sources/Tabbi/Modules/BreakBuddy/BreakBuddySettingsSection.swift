import SwiftUI
import TabbiKitCore
import TabbiKit

/// Settings › Pet Coach › Break buddy: whether the pet models a short move
/// at the start of breaks, which moves it may pick, and whether the break
/// card counts glasses of water. Edits go straight to the shared
/// `BreakBuddyController`, which saves them.
struct BreakBuddySettingsSection: View {
    @ObservedObject var buddy: BreakBuddyController

    /// The section's height in the grouped form, which doesn't report its
    /// own; the pane adds it to its fixed height.
    static var height: CGFloat {
        let chipRows = CGFloat((BreakMove.allCases.count + 1) / 2)
        return 230 + chipRows * 40
    }

    var body: some View {
        Section {
            Toggle(String(localized: "Show a break move", bundle: .tabbi),
                   isOn: Binding(get: { buddy.preferences.isOn }, set: { buddy.setOn($0) }))
                .help(switchHelp)
            // Two columns, so every move's name fits whole in any language.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                ForEach(BreakMove.allCases, id: \.self) { move in
                    BreakMoveChip(move: move, isOn: buddy.preferences.isEnabled(move)) {
                        buddy.setMove(move, enabled: !buddy.preferences.isEnabled(move))
                    }
                }
            }
            .padding(.vertical, 2)
            .disabled(!buddy.preferences.isOn)
            Toggle(String(localized: "Count glasses of water", bundle: .tabbi),
                   isOn: Binding(get: { buddy.preferences.tracksWater }, set: { buddy.setTracksWater($0) }))
                .help(String(localized: "Show today's glasses on the break card, with a button to add one", bundle: .tabbi))
                .disabled(!buddy.preferences.isOn)
        } header: {
            Text("Break buddy", bundle: .tabbi)
        } footer: {
            SectionFooter(String(localized: "Your pet picks one move per break and keeps it short. Skipping is always fine, and nothing counts against you. Glasses of water stay on this Mac.", bundle: .tabbi))
        }
    }
}

private extension BreakBuddySettingsSection {
    var switchHelp: String {
        if let name = buddy.petName {
            return String(localized: "At the start of a break, \(name) shows a short move you can copy", bundle: .tabbi)
        }
        return String(localized: "At the start of a break, your pet shows a short move you can copy", bundle: .tabbi)
    }
}

/// One move as a toggleable tile, like the distracting app chips above it.
private struct BreakMoveChip: View {
    let move: BreakMove
    let isOn: Bool
    let toggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: move.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text(move.name)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .transition(.motionPop)
                }
            }
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(isHovered ? 0.22 : 0.15)
                               : Color.primary.opacity(isHovered ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .motion(Motion.snappy, value: isOn)
        .motion(Motion.hover, value: isHovered)
        .help(isOn ? String(localized: "Your pet may suggest this move. Click to turn it off", bundle: .tabbi)
                    : String(localized: "Your pet won't suggest this move. Click to turn it on", bundle: .tabbi))
        .accessibilityLabel(move.name)
        .accessibilityValue(isOn ? String(localized: "On", bundle: .tabbi) : String(localized: "Off", bundle: .tabbi))
    }
}
