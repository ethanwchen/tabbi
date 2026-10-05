import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Custom method's lengths, drawn inside the notch in place of the
/// timer: focus and break steppers, and a long break that can be switched
/// on with its own length and spacing. Edits apply at once; a Custom
/// session under way keeps its round and clock.
struct StudyCustomEditor: View {
    @ObservedObject var store: StudyStore
    let close: () -> Void

    var body: some View {
        let rhythm = store.custom
        let isCurrent = store.session.method.kind == .custom
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Text("Custom")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text(rhythm.method.rhythmLabel)
                    .font(Theme.Typography.title)
                    .foregroundStyle(studyAccent)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(isCurrent ? "Changes apply right away" : "Your own rhythm")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                if !isCurrent {
                    StudyCapsuleButton(title: "Use Custom", help: "Start a fresh session with these lengths") {
                        store.choose(.custom)
                        close()
                    }
                }
                IconButton(symbol: "xmark", help: "Done") { close() }
            }
            HStack(spacing: Theme.Spacing.s) {
                lengthCard("Focus", field: .focus, rhythm: rhythm, help: "How long each study block runs")
                lengthCard("Break", field: .shortBreak, rhythm: rhythm, help: "The pause after each block")
                longBreakCard(rhythm)
                    .frame(width: 208)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Theme.Motion.content, value: rhythm)
    }

    private func lengthCard(_ title: String, field: StudyCustomRhythm.Field, rhythm: StudyCustomRhythm,
                            help: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    // As tall as the long break's switch, so the three captions line up.
                    .frame(height: 20)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
                    Text("\(rhythm[field])")
                        .font(Theme.Typography.metric)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .contentTransition(.numericText())
                    Text("min")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                StudyStepper(field: field, rhythm: rhythm, noun: title.lowercased(), set: store.setCustom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .help(help)
    }

    private func longBreakCard(_ rhythm: StudyCustomRhythm) -> some View {
        let isOn = rhythm.hasLongBreak
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text("Long break")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                    Spacer(minLength: 0)
                    StudyCapsuleToggle(title: isOn ? "On" : "Off", symbol: "cup.and.saucer", isOn: isOn,
                                       help: isOn ? "Turn the long break off" : "Take a longer break every few rounds") {
                        store.setCustom(rhythm.withLongBreak(!isOn))
                    }
                }
                Spacer(minLength: 0)
                Group {
                    longBreakRow("\(rhythm.longBreakMinutes) min", field: .longBreak, rhythm: rhythm, noun: "long break")
                    longBreakRow(rhythm.longBreakEvery == 2 ? "Every other round" : "Every \(rhythm.longBreakEvery) rounds",
                                 field: .longBreakEvery, rhythm: rhythm, noun: "rounds between long breaks")
                }
                .disabled(!isOn)
                .opacity(isOn ? 1 : 0.4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .help(isOn ? "A \(rhythm.longBreakMinutes) min break replaces every \(ordinal(rhythm.longBreakEvery)) break"
                   : "No long break: every break is \(rhythm.breakMinutes) min")
    }

    private func longBreakRow(_ label: String, field: StudyCustomRhythm.Field, rhythm: StudyCustomRhythm,
                              noun: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(label)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Palette.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
            Spacer(minLength: Theme.Spacing.xs)
            StudyStepper(field: field, rhythm: rhythm, noun: noun, set: store.setCustom)
        }
    }

    private func ordinal(_ number: Int) -> String {
        switch number {
        case 2: "2nd"
        case 3: "3rd"
        default: "\(number)th"
        }
    }
}

/// Minus and plus buttons that move one field of the Custom rhythm by its
/// step, each dimmed at the end of the field's range.
private struct StudyStepper: View {
    let field: StudyCustomRhythm.Field
    let rhythm: StudyCustomRhythm
    /// What the buttons change, for their tooltips.
    let noun: String
    let set: (StudyCustomRhythm) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            button(-1, symbol: "minus", help: "Shorter \(noun)")
            button(1, symbol: "plus", help: "Longer \(noun)")
        }
    }

    private func button(_ steps: Int, symbol: String, help: String) -> some View {
        let enabled = rhythm.canStep(field, by: steps)
        let tip = field == .longBreakEvery ? (steps < 0 ? "Fewer \(noun)" : "More \(noun)")
                                           : "\(help) (\(field.step) min)"
        return IconButton(symbol: symbol, size: 22, help: tip) {
            withAnimation(Theme.Motion.snappy) { set(rhythm.stepped(field, by: steps)) }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// A small pencil on the method card that opens the Custom lengths.
struct StudyEditButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.tertiaryText)
                .frame(width: 20, height: 20)
                .background(Circle().fill(hovering ? Theme.Palette.surfaceHover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Edit the Custom focus and break lengths")
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
    }
}
