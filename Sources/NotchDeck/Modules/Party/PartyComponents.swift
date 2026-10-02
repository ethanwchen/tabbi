import AppKit
import SwiftUI
import NotchKitCore
import NotchKit

/// Small building blocks shared by the Party panel's stage and friends card.
enum PartyStyle {
    static var accent: Color { Theme.Palette.accent(for: .party) }

    /// `ImageRenderer` (used by `--snapshot`) draws AppKit-backed views such
    /// as `ScrollView` and a visible `TextField` blank, so snapshots get
    /// static stand-ins.
    static let isSnapshot = CommandLine.arguments.contains("--snapshot")

    /// The dot beside a status: accent while studying, amber on a break,
    /// green when around, gray when away.
    static func color(for status: PartyStatus) -> Color {
        switch status {
        case .studying: accent
        case .onBreak: Theme.Palette.warning
        case .idle: Theme.Palette.success
        case .offline: Theme.Palette.tertiaryText
        }
    }

    /// "K7QW-2MZD": codes read and dictate more easily in groups of four.
    static func display(code: String) -> String {
        guard code.count > 6 else { return code }
        let split = code.index(code.startIndex, offsetBy: code.count / 2)
        return code[..<split] + "-" + code[split...]
    }
}

/// A pet drawn from a server profile (or my own); offline people's pets doze.
struct PartyPet: View {
    let pet: PetProfile
    var asleep = false
    /// Points per sprite pixel; 1 and 1.5 land on whole device pixels at 2x.
    var pixelSize: CGFloat = 1
    @StateObject private var player: PetPlayer

    init(pet: PetProfile, asleep: Bool = false, pixelSize: CGFloat = 1) {
        self.pet = pet
        self.asleep = asleep
        self.pixelSize = pixelSize
        _player = StateObject(wrappedValue: PetPlayer(profile: pet, asleep: asleep))
    }

    init(profile: PartyProfile, asleep: Bool = false, pixelSize: CGFloat = 1) {
        self.init(pet: PartyPetAppearance.pet(for: profile), asleep: asleep, pixelSize: pixelSize)
    }

    var body: some View {
        PetView(player: player, pixelSize: pixelSize)
            .onChange(of: pet) { _, pet in player.update(profile: pet) }
            .onChange(of: asleep) { _, asleep in player.send(asleep ? .sleep : .wake) }
    }
}

/// A capsule button in the Party accent; `isProminent` fills it for the
/// panel's main call to action. Dims and ignores clicks while busy.
struct PartyPillButton: View {
    let title: String
    var symbol: String?
    var isProminent = false
    var isBusy = false
    var height: CGFloat = 24
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let accent = PartyStyle.accent
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                }
                Text(title).font(Theme.Typography.caption)
            }
            .foregroundStyle(isProminent ? Theme.Palette.background : accent)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xxs)
            .frame(height: height)
            .background(Capsule().fill(isProminent ? accent.opacity(hovering ? 1 : 0.9)
                                       : accent.opacity(hovering ? 0.28 : 0.16)))
            .contentShape(Capsule())
            .opacity(isBusy ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
        .animation(Theme.Motion.snappy, value: isBusy)
    }
}

/// Quiet text button for secondary actions such as Leave.
struct PartyTextButton: View {
    let title: String
    var isBusy = false
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Theme.Spacing.s)
                .frame(height: 20)
                .background(Capsule().fill(hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
                .contentShape(Capsule())
                .opacity(isBusy ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
    }
}

/// A code in monospaced type with a copy button that confirms with a check.
struct PartyCopyCode: View {
    let code: String
    let help: String
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            copied = true
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text(PartyStyle.display(code: code))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Palette.primaryText)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(copied ? Theme.Palette.success : PartyStyle.accent)
                    .frame(width: 10)
                    .contentTransition(.symbolEffect(.replace))
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 20)
            .background(Capsule().fill(hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
        .animation(Theme.Motion.snappy, value: copied)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// Which code field has the keyboard, so the notch stays open while typing.
enum PartyField: Hashable {
    case friendCode
    case partyCode
}

/// A one-line field for a friend or party code: Return submits, Esc clears.
/// It's cleared after a well-formed code is submitted; a malformed one
/// stays so the store's notice can explain it.
struct PartyCodeField: View {
    let placeholder: String
    let symbol: String
    let length: Int
    let field: PartyField
    var focus: FocusState<PartyField?>.Binding
    let help: String
    let submit: (String) -> Void
    @State private var text = ""
    @State private var hovering = false

    var body: some View {
        let isFocused = focus.wrappedValue == field
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isFocused ? PartyStyle.accent : Theme.Palette.tertiaryText)
                .frame(width: 12)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                // Hidden until used: AppKit-backed fields don't render in
                // snapshots, and the placeholder above stands in for them.
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Palette.primaryText)
                    .focused(focus, equals: field)
                    .opacity(isFocused || !text.isEmpty ? 1 : 0)
                    .onSubmit(send)
                    .onExitCommand {
                        if text.isEmpty { focus.wrappedValue = nil } else { text = "" }
                    }
            }
            if !text.isEmpty {
                Button(action: send) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(PartyStyle.accent)
                }
                .buttonStyle(.plain)
                .help("Submit")
                .transition(.opacity)
            }
        }
        .padding(.leading, Theme.Spacing.s)
        .padding(.trailing, Theme.Spacing.xs)
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
        .onTapGesture { focus.wrappedValue = field }
        .onHover { hovering = $0 }
        .help(help)
        .animation(Theme.Motion.snappy, value: hovering)
        .animation(Theme.Motion.snappy, value: isFocused)
        .animation(Theme.Motion.snappy, value: text.isEmpty)
    }

    private func send() {
        let draft = text
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        submit(draft)
        if PartyCode.normalize(draft, length: length) != nil { text = "" }
    }
}
