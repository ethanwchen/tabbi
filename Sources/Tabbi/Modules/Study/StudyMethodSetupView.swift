import SwiftUI
import TabbiKitCore
import TabbiKit

/// Onboarding's study method step: the kit's methods as one-tap tiles on
/// the left, and on the right what the hovered (or chosen) method asks of
/// you and how well it is supported, so the pick is an informed one. A tap
/// sets the Study timer's method right away.
struct StudyMethodSetupView: View {
    @ObservedObject var store: StudyStore
    @State private var hovered: StudyMethodKind?

    var body: some View {
        let methods = store.methods
        let current = store.session.method.kind
        let shown = methods.first { $0.kind == (hovered ?? current) } ?? store.session.method
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Grid(horizontalSpacing: Theme.Spacing.xs, verticalSpacing: Theme.Spacing.xs) {
                ForEach(Array(stride(from: 0, to: methods.count, by: 2)), id: \.self) { start in
                    GridRow {
                        ForEach(methods[start..<min(start + 2, methods.count)]) { method in
                            StudyMethodTile(method: method, isCurrent: method.kind == current, info: nil, action: { choose(method.kind) },
                                            showsRhythm: false,
                                            hovered: { hovered = $0 ? method.kind : (hovered == method.kind ? nil : hovered) })
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            StudyMethodSummaryCard(method: shown, isCurrent: shown.kind == current)
                .frame(width: 232)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .motion(Theme.Motion.snappy, value: current)
    }

    private func choose(_ kind: StudyMethodKind) {
        withMotion(Theme.Motion.snappy) { store.choose(kind) }
    }
}

/// One method in brief: name, rhythm and evidence on top, then how to do it.
private struct StudyMethodSummaryCard: View {
    let method: StudyMethod
    let isCurrent: Bool

    var body: some View {
        let info = method.info
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(info.name)
                        .foregroundStyle(Theme.Palette.primaryText)
                    if !method.nameIsRhythm {
                        Text(method.rhythmLabel)
                            .foregroundStyle(studyAccent)
                            .monospacedDigit()
                    }
                    Spacer(minLength: Theme.Spacing.xs)
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(studyAccent)
                            .help("The Study timer starts with \(info.name)")
                    }
                }
                .font(Theme.Typography.bodyEmphasis)
                .lineLimit(1)
                // As many whole sentences as fit, never a cut-off one.
                ViewThatFits(in: .vertical) {
                    ForEach(info.howToSentencePrefixes.reversed(), id: \.self) { text in
                        Text(text)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .help(info.howTo)
                StudyEvidenceBadge(level: info.evidenceLevel)
                    .help("\(info.evidence) \(StudyMethodInfo.footnote)")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
