import SwiftUI
import TabbiKitCore
import TabbiKit

/// A method's info popover, drawn inside the notch in place of the timer:
/// the name, rhythm and evidence badge on top, then how to do it beside
/// what the evidence does and doesn't show.
struct StudyMethodInfoView: View {
    let method: StudyMethod
    /// Whether the session already uses this method.
    let isCurrent: Bool
    /// Starts a fresh session with this method.
    let use: () -> Void
    let close: () -> Void

    var body: some View {
        let info = method.info
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Text(info.name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                if !method.nameIsRhythm {
                    Text(method.rhythmLabel)
                        .font(Theme.Typography.title)
                        .foregroundStyle(studyAccent)
                        .monospacedDigit()
                }
                StudyEvidenceBadge(level: info.evidenceLevel)
                Spacer(minLength: Theme.Spacing.s)
                if !isCurrent {
                    StudyCapsuleButton(title: "Use \(info.name)", help: "Start a fresh session with \(info.name)",
                                       action: use)
                }
                IconButton(symbol: "xmark", help: "Close") { close() }
            }
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                section("How to", info.howTo, font: Theme.Typography.body, color: Theme.Palette.primaryText)
                    .frame(maxWidth: .infinity)
                section("Evidence", info.evidence, font: Theme.Typography.caption, color: Theme.Palette.secondaryText)
                    .frame(width: 196)
                    .help(StudyMethodInfo.footnote)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func section(_ title: String, _ text: String, font: Font, color: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// How well supported a method is, as a small tinted capsule.
struct StudyEvidenceBadge: View {
    let level: StudyEvidenceLevel

    var body: some View {
        Text(level.label)
            .font(Theme.Typography.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 18)
            .background(Capsule().fill(tint.opacity(0.14)))
            .help("Evidence: \(level.label.lowercased())")
    }

    private var tint: Color {
        switch level {
        case .strong: Theme.Palette.success
        case .mixed: Theme.Palette.warning
        case .weak: Theme.Palette.secondaryText
        }
    }
}

/// A small (i) that opens a method's info popover.
struct StudyInfoButton: View {
    let method: StudyMethodKind
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.tertiaryText)
                .frame(width: 20, height: 20)
                .background(Circle().fill(hovering ? Theme.Palette.surfaceHover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("How \(StudyMethodInfo.info(for: method).name) works")
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
    }
}

/// A compact accent-outlined capsule for a secondary action.
struct StudyCapsuleButton: View {
    let title: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(studyAccent)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(height: 24)
                .background(Capsule().fill(studyAccent.opacity(hovering ? 0.24 : 0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
    }
}

/// The Study module's one accent.
var studyAccent: Color { StudyModule.descriptor.accentColor }
