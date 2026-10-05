import SwiftUI
import TabbiKitCore
import TabbiKit

/// A kit's tabs as a row of small tinted symbols.
struct TabIcons: View {
    let modules: [ModuleID]
    @Environment(\.moduleCatalog) private var catalog

    var body: some View {
        HStack(spacing: 4) {
            ForEach(modules.map(catalog.descriptor(for:))) { module in
                Image(systemName: module.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(module.accentColor)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(module.accentColor.opacity(0.16)))
                    .help(module.title)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

/// The kit's onboarding questions. Every question is optional; the tabs
/// row previews what the answers will turn on or off. Settings shows it as
/// a sheet when switching kits (first-run setup asks them in the notch).
struct KitQuestionsView: View {
    let kit: KitManifest
    /// Cancel: leaves the current kit as it was.
    let cancel: () -> Void
    let start: (KitAnswers) -> Void
    @State private var answers: KitAnswers

    /// - Parameter answers: the answers to start from, e.g. when the user
    ///   comes back from the import review to change them.
    init(kit: KitManifest, answers: KitAnswers = [:],
         cancel: @escaping () -> Void, start: @escaping (KitAnswers) -> Void) {
        self.kit = kit
        self.cancel = cancel
        self.start = start
        _answers = State(initialValue: answers)
    }
    @Environment(\.moduleCatalog) private var catalog

    var body: some View {
        let tabs = kit.layout(catalog: catalog, answers: answers).enabled
        let tint = kit.accentModule(catalog: catalog).map { catalog.descriptor(for: $0).accentColor } ?? .accentColor
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: kit.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.gradient))
                Text("Set up \(kit.name)")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("A few quick questions so your tabs and starter tasks fit you. Skip any you like.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 36)
            .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 20) {
                ForEach(kit.onboarding) { question in
                    QuestionSection(question: question, picked: answers[question.id] ?? []) { id in
                        answers[question.id] = question.selecting(id, in: answers[question.id] ?? [])
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            HStack(spacing: 8) {
                Text("Your tabs")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TabIcons(modules: tabs)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .help("The tabs \(kit.name) starts with: \(tabs.map { catalog.descriptor(for: $0).title }.joined(separator: ", "))")

            HStack {
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                    .help("Keep your current kit and tabs")
                Spacer()
                Button("Switch Kit") { start(answers) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("Switch to \(kit.name) with these answers")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .motion(Theme.Motion.snappy, value: answers)
    }
}

/// One question: its prompt and a row of answer tiles.
private struct QuestionSection: View {
    let question: KitQuestion
    let picked: Set<String>
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(question.prompt)
                    .font(.headline)
                if question.allowsMultiple {
                    Text("Pick any")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 8) {
                ForEach(question.options) { option in
                    AnswerTile(answer: option, isSelected: picked.contains(option.id)) { select(option.id) }
                }
            }
        }
    }
}

/// A selectable answer: its symbol over its label, styled like the kit cards.
private struct AnswerTile: View {
    let answer: KitAnswer
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: answer.symbol ?? "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(height: 20)
                // Two lines tall either way, so the symbols line up across
                // tiles, with a one-line label centered in that space.
                ZStack {
                    Text(" \n ").hidden()
                    Text(answer.label)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .font(.callout)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.08 : (hovering ? 0.06 : 0.03)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                                  lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Clear \"\(answer.label)\"" : answer.label)
        .onHover { hovering = $0 }
    }
}
