import SwiftUI
import TabbiKitCore
import TabbiKit

/// What Party shows before it talks to the server (`PartyAgeCheck`): the
/// month and year the user was born, asked once and without hinting at the
/// answer, beside links to the Terms and Privacy Policy. Answered under 13,
/// it says when Party opens instead, with no way to answer again.
struct PartyAgeCheckView: View {
    @ObservedObject var store: PartyStore
    let tooYoungUntil: Date?

    var body: some View {
        if let tooYoungUntil {
            tooYoung(until: tooYoungUntil)
        } else {
            PartyAgeQuestion(store: store)
        }
    }

    private func tooYoung(until date: Date) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PartyStyle.accent)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .fill(PartyStyle.accent.opacity(0.16)))
            VStack(spacing: Theme.Spacing.xxs) {
                Text("Party isn't available yet")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text("Party is for people \(PartyAgeCheck.minimumAge) and older. It opens here in \(PartyAgeCheck.opensText(date)).")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "When were you born?" with a month and a year menu, both starting
/// blank so no answer is suggested, and Continue once both are picked.
private struct PartyAgeQuestion: View {
    @ObservedObject var store: PartyStore
    @State private var month: Int?
    @State private var year: Int?

    private static let months = PartyAgeCheck.monthNames()

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            VStack(spacing: Theme.Spacing.xxs) {
                Text("When were you born?")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text("Party asks once before you join. Your answer stays on this Mac.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: Theme.Spacing.s) {
                PartyAgeMenu(title: month.map { Self.months[$0 - 1] } ?? "Month", isPlaceholder: month == nil, width: 112,
                             help: "The month you were born") {
                    ForEach(Array(Self.months.enumerated()), id: \.offset) { index, name in
                        Button(name) { month = index + 1 }
                    }
                }
                PartyAgeMenu(title: year.map(String.init) ?? "Year", isPlaceholder: year == nil, width: 72,
                             help: "The year you were born") {
                    ForEach(PartyAgeCheck.birthYears(at: Date()), id: \.self) { value in
                        Button(String(value)) { year = value }
                    }
                }
                // Quiet until both are picked; prominent once it can join.
                PartyPillButton(title: "Continue", isProminent: month != nil && year != nil,
                                help: month == nil || year == nil ? "Pick a month and a year first" : "Join Party") {
                    guard let month, let year else { return }
                    store.answerAge(birthMonth: month, year: year)
                }
            }
            Text(LocalizedStringKey(PartySetup.agreement))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .tint(PartyStyle.accent)
                .help("Opens on tabbinotch.com")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

/// A menu that looks like the Party pills: the picked value, or a quiet
/// placeholder, with a chevron.
private struct PartyAgeMenu<Items: View>: View {
    let title: String
    let isPlaceholder: Bool
    let width: CGFloat
    let help: String
    @ViewBuilder let items: () -> Items
    @State private var hovering = false

    var body: some View {
        Menu {
            items()
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(isPlaceholder ? Theme.Palette.secondaryText : Theme.Palette.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
            .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xxs)
            .frame(width: width, height: 24)
            .background(Capsule().fill(hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}
