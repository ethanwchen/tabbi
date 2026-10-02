import AppKit
import Combine
import SwiftUI
import NotchKitCore
import NotchKit

/// First-run setup: shown once, before the user has picked a kit, so each
/// audience starts from tabs that fit them. Step one picks a kit; step two
/// asks that kit's onboarding questions, if it has any. Like Settings it is
/// a regular system window, not part of the black notch.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    private var choice: AnyCancellable?
    /// Set once Continue lands. `$settings` publishes before the new value
    /// is stored, so `settings` can't be read to tell yet.
    private var hasChosen = false

    /// - Parameter questionsFor: opens straight on that kit's questions;
    ///   used by snapshots to render the second step.
    init(settings: SettingsStore, questionsFor kitID: String? = nil) {
        self.settings = settings
        let host = NSHostingController(rootView: WelcomeView(questionsFor: kitID).environmentObject(settings))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to \(Edition.current.name)"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        // Continue records the choice; the window goes away once it lands.
        choice = settings.$settings
            .map(\.hasChosenKit)
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.hasChosen = true
                self?.close()
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Brings the window forward; the app is an accessory, so it activates
    /// itself or the window would open behind the frontmost app.
    func present() {
        window?.center()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Closing without Continue keeps the preselected kit, so the window
    /// never comes back to nag.
    func windowWillClose(_ notification: Notification) {
        if !hasChosen, !settings.settings.hasChosenKit {
            settings.chooseKit(settings.settings.kitID)
        }
    }

    /// Renders the window to PNG data for `SnapshotRenderer`, off screen.
    func snapshot() async -> Data? {
        guard let window else { return nil }
        try? await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
        guard let frameView = window.contentView?.superview else { return nil }
        let bounds = frameView.bounds
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        frameView.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}

/// The two setup steps, with a spring between them.
private struct WelcomeView: View {
    @EnvironmentObject private var store: SettingsStore
    /// Starts on the edition's kit, e.g. Medicine for StudyNotch.
    @State private var picked: String?
    /// The kit whose questions are showing; nil on the kit picker.
    @State private var questionsKit: String?

    init(questionsFor kitID: String?) {
        _picked = State(initialValue: kitID)
        _questionsKit = State(initialValue: kitID)
    }

    var body: some View {
        Group {
            if let id = questionsKit, let kit = store.kits[id] {
                KitQuestionsView(kit: kit, back: { questionsKit = nil }) { answers in
                    store.chooseKit(kit.id, answers: answers)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                picker.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 520)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: questionsKit)
    }

    /// App icon, a short pitch, one selectable card per kit, and Continue.
    private var picker: some View {
        let selection = picked ?? store.settings.kitID
        let kit = store.kits[selection]
        return VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: Self.appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text("Welcome to \(Edition.current.name)")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("Pick a kit to start with. A kit is a set of tabs for the notch; you can switch kits or change tabs any time in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 36)
            .padding(.horizontal, 40)

            VStack(spacing: 8) {
                ForEach(store.kits.kits) { kit in
                    KitCard(kit: kit, isSelected: kit.id == selection) { picked = kit.id }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            HStack {
                Text("Open the notch by clicking it or pressing \(store.settings.hotkey.displayString).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Continue") {
                    if kit?.onboarding.isEmpty == false {
                        questionsKit = selection
                    } else {
                        store.chooseKit(selection)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help(kit?.onboarding.isEmpty == false
                      ? "Set up the \(kit?.name ?? "selected") kit"
                      : "Start with the \(kit?.name ?? "selected") kit")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: selection)
    }

    /// The bundle's icon. `swift run` has no bundle, so fall back to the
    /// repo's icon file (the dev and snapshot working directory).
    private static let appIcon: NSImage = Bundle.main.bundleURL.pathExtension == "app"
        ? NSApp.applicationIconImage
        : NSImage(contentsOfFile: "Resources/AppIcon.icns") ?? NSApp.applicationIconImage
}

/// One kit: its symbol, name and summary, and the tabs it turns on.
private struct KitCard: View {
    let kit: KitManifest
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let tabs = kit.layout().enabled
        let tint = kit.accentModule().map { Theme.Palette.accent(for: $0) } ?? .accentColor
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: kit.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
                VStack(alignment: .leading, spacing: 4) {
                    Text(kit.name)
                        .font(.headline)
                    Text(kit.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    TabIcons(modules: tabs)
                        .padding(.top, 2)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .padding(12)
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
        .help("\(kit.name): \(tabs.map(\.title).joined(separator: ", "))")
        .onHover { hovering = $0 }
    }
}

/// A kit's tabs as a row of small tinted symbols.
private struct TabIcons: View {
    let modules: [ModuleID]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(modules) { module in
                Image(systemName: module.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accent(for: module))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Theme.Palette.accent(for: module).opacity(0.16)))
                    .help(module.title)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

/// The kit's onboarding questions. Every question is optional; the tabs
/// row previews what the answers will turn on or off. First-run setup shows
/// it as its second step, and Settings as a sheet when switching kits.
struct KitQuestionsView: View {
    /// The leading button: Back to the kit picker on first run, Cancel in
    /// Settings, where it leaves the current kit as it was.
    enum Dismissal {
        case back, cancel
    }

    let kit: KitManifest
    var dismissal: Dismissal = .back
    let back: () -> Void
    let start: (KitAnswers) -> Void
    @State private var answers: KitAnswers = [:]

    var body: some View {
        let tabs = kit.layout(answers: answers).enabled
        let tint = kit.accentModule().map { Theme.Palette.accent(for: $0) } ?? .accentColor
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
            .help("The tabs \(kit.name) starts with: \(tabs.map(\.title).joined(separator: ", "))")

            HStack {
                switch dismissal {
                case .back:
                    Button("Back", action: back)
                        .controlSize(.large)
                        .help("Pick a different kit")
                case .cancel:
                    Button("Cancel", action: back)
                        .keyboardShortcut(.cancelAction)
                        .controlSize(.large)
                        .help("Keep your current kit and tabs")
                }
                Spacer()
                Button(dismissal == .back ? "Start" : "Switch Kit") { start(answers) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help(dismissal == .back
                          ? "Start with the \(kit.name) kit"
                          : "Switch to \(kit.name) with these answers")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: answers)
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
