import SwiftUI
import TabbiKitCore
import TabbiKit

/// Reports a friend or party member to the Tabbi team: a reason, an
/// optional note, and an offer to block them as well. It covers the panel
/// while open, so the person stays in view and nothing else competes.
struct PartyReportCard: View {
    let profile: PartyProfile
    @ObservedObject var store: PartyStore
    var focus: FocusState<PartyField?>.Binding
    @State private var reason: PartyReportReason?
    @State private var note = ""
    @State private var alsoBlock = true

    private var isSending: Bool { store.pending == .report }

    var body: some View {
        Card(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                header
                reasons
                PartyNoteField(text: $note, focus: focus)
                Spacer(minLength: 0)
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Cards are translucent; the panel underneath must not show through.
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
            .fill(Theme.Palette.background))
        .onExitCommand { store.cancelReport() }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            PartyPet(profile: profile)
            VStack(alignment: .leading, spacing: 0) {
                Text("Report \(profile.name)")
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text("The Tabbi team reviews it. \(profile.name) isn't told.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            .lineLimit(1)
        }
    }

    private var reasons: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(PartyReportReason.allCases, id: \.self) { option in
                PartyChoiceChip(title: option.title, isSelected: reason == option,
                                help: "Report \(profile.name) for \(option.title.lowercased())") {
                    reason = option
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.s) {
            PartyCheckbox(title: "Also block \(profile.name)", isOn: $alsoBlock,
                          help: "Hide each other everywhere in Party. You can unblock in Party options.")
            Spacer(minLength: Theme.Spacing.s)
            PartyTextButton(title: "Cancel", isBusy: isSending, help: "Close without reporting (Esc)") {
                store.cancelReport()
            }
            PartyPillButton(title: "Send Report", isProminent: true, isBusy: isSending || reason == nil, height: 20,
                            help: reason == nil ? "Pick a reason first" : "Send this report to the Tabbi team") {
                guard let reason else { return }
                store.sendReport(reason: reason, note: note, alsoBlock: alsoBlock)
            }
        }
    }
}

/// A one-line note field, limited to what the server keeps.
private struct PartyNoteField: View {
    @Binding var text: String
    var focus: FocusState<PartyField?>.Binding
    @State private var hovering = false

    var body: some View {
        let isFocused = focus.wrappedValue == .reportNote
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text("Add a note (optional)")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
            // Hidden until used: AppKit-backed fields don't render in
            // snapshots, and the placeholder above stands in for them.
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.primaryText)
                .focused(focus, equals: .reportNote)
                .opacity(isFocused || !text.isEmpty ? 1 : 0)
                .onChange(of: text) { _, new in
                    if new.count > PartyReport.noteLimit { text = String(new.prefix(PartyReport.noteLimit)) }
                }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(hovering || isFocused ? Theme.Palette.surfaceHover : Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .strokeBorder(isFocused ? PartyStyle.accent.opacity(0.5) : Theme.Palette.stroke,
                              lineWidth: isFocused ? 1 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = .reportNote }
        .onHover { hovering = $0 }
        .help("What happened, in a sentence or two")
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isFocused)
    }
}

/// One option of a small single choice, as a capsule that fills when picked.
private struct PartyChoiceChip: View {
    let title: String
    let isSelected: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(isSelected ? Theme.Palette.background
                                 : hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Theme.Spacing.s)
                .frame(height: 20)
                .background(Capsule().fill(isSelected ? PartyStyle.accent
                                           : hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isSelected)
    }
}

/// A small checkbox with its label, both clickable.
private struct PartyCheckbox: View {
    let title: String
    @Binding var isOn: Bool
    let help: String
    @State private var hovering = false

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? PartyStyle.accent : Theme.Palette.tertiaryText)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isOn)
    }
}

/// The Report and Block items in a friend's or party member's right-click
/// menu.
struct PartyModerationMenu: View {
    let profile: PartyProfile
    @ObservedObject var store: PartyStore

    var body: some View {
        Divider()
        Button("Report \(profile.name)…") { store.beginReport(profile) }
        Button("Block \(profile.name)", role: .destructive) { store.block(profile) }
    }
}
