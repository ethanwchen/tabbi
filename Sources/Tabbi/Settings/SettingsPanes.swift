import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import TabbiKitCore
import TabbiKit

/// Width shared by every pane so the window only animates its height.
let paneWidth: CGFloat = 500

// MARK: General

/// The app-wide name, first in General so it is easy to find. Saves as the
/// user types; Party shows it to friends and Tabbi greets the user with it.
private struct YourNameRow: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.moduleCatalog) private var catalog

    var body: some View {
        LabeledContent {
            TextField(String(localized: "Your name", bundle: .tabbi), text: name, prompt: Text("Your name", bundle: .tabbi))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(width: 160)
                .help(String(localized: "Your name, up to \(DisplayName.maxLength) characters", bundle: .tabbi))
        } label: {
            Text("Your name", bundle: .tabbi)
            // Editions without Party (the App Store) only greet with it.
            Text(catalog.contains(PartyModule.descriptor.id)
                 ? String(localized: "Shown to friends in Party and used to greet you.", bundle: .tabbi)
                 : String(localized: "Used to greet you.", bundle: .tabbi))
        }
    }

    /// Kept as typed, capped at the length every use allows.
    private var name: Binding<String> {
        Binding(
            get: { store.settings.displayName },
            set: { store.settings.displayName = String($0.prefix(DisplayName.maxLength)) }
        )
    }
}

struct GeneralSettingsPane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.accountSync) private var account
    @State private var screens = DisplayOption.connectedScreens()
    @State private var showsMore = false

    var body: some View {
        Form {
            Section {
                YourNameRow()
                if let account {
                    AccountSettingsRow(account: account)
                }
            }

            Section {
                Toggle(String(localized: "Launch at login", bundle: .tabbi), isOn: launchAtLogin)
                    .disabled(!store.loginItem.isAvailable && store.integratesWithSystem)
                    .help(String(localized: "Start \(Edition.current.name) automatically when you log in", bundle: .tabbi))
                if let caption = launchAtLoginCaption {
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Picker(selection: $store.settings.notchMode) {
                    ForEach(NotchMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    Text("Notch", bundle: .tabbi)
                    Text(notchModeCaption)
                }
                .help(String(localized: "Choose when the notch is drawn. The shortcut always opens it.", bundle: .tabbi))
                Picker(String(localized: "Panel size", bundle: .tabbi), selection: $store.settings.panelSize) {
                    ForEach(PanelSize.allCases, id: \.self) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .help(String(localized: "Choose how big the open notch is. Every tab uses the same size.", bundle: .tabbi))
                Toggle(isOn: $store.settings.openOnHover) {
                    Text("Open on hover", bundle: .tabbi)
                    Text("Opens the notch when the pointer rests on it.", bundle: .tabbi)
                }
                .help(String(localized: "Open the notch after hovering it briefly", bundle: .tabbi))
                Toggle(isOn: $store.settings.notchPreview.isEnabled) {
                    Text("Show live activity", bundle: .tabbi)
                    Text("Meetings, music and timers beside the closed notch.", bundle: .tabbi)
                }
                .help(String(localized: "Show a small live preview beside the closed notch", bundle: .tabbi))
                Toggle(isOn: $store.settings.hideInFullscreen) {
                    Text("Hide in fullscreen", bundle: .tabbi)
                    Text("Steps aside while a video, game or app is fullscreen.", bundle: .tabbi)
                }
                .help(String(localized: "Hide the notch while an app is fullscreen on its display. The shortcut still opens it.", bundle: .tabbi))
            }

            ShortcutSection()

            Section {
                MoreOptionsToggle(isExpanded: $showsMore)
            }

            if showsMore {
                moreOptions
            }

            ResetToDefaultsRow(isAtDefaults: store.usesGeneralDefaults,
                               help: String(localized: "Put General back the way a new install has it. Launch at login stays as it is.", bundle: .tabbi),
                               reset: store.resetGeneral) {
                // Command-Q itself lives in the hidden app menu, so it
                // also works while the notch is open.
                Button(String(localized: "Quit \(Edition.current.name)", bundle: .tabbi)) { NSApp.terminate(nil) }
                    .help(String(localized: "Quit \(Edition.current.name) and close the notch until you open it again (\u{2318}Q)", bundle: .tabbi))
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(!showsMore)
        .frame(width: paneWidth, height: showsMore ? 846 : 726)
        .motion(Motion.snappy, value: showsMore)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = DisplayOption.connectedScreens()
        }
        // Login Items may have changed in System Settings meanwhile.
        .onAppear { store.refreshLaunchAtLogin() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshLaunchAtLogin()
        }
    }

    @ViewBuilder
    private var moreOptions: some View {
        FeedbackSection()

        Section {
            Toggle(isOn: $store.settings.showOnExternalDisplays) {
                Text("Show on external displays", bundle: .tabbi)
                Text("When off, the notch hides while the lid is closed.", bundle: .tabbi)
            }
            .help(String(localized: "Allow the notch on displays other than the built-in one", bundle: .tabbi))
            Picker(String(localized: "Show notch on", bundle: .tabbi), selection: $store.settings.preferredDisplay) {
                Text("Built-in display", bundle: .tabbi).tag(DisplayPreference.builtIn)
                Text("Main display", bundle: .tabbi).tag(DisplayPreference.main)
                let options = DisplayOption.specificOptions(screens: screens, selected: store.settings.preferredDisplay)
                if !options.isEmpty {
                    Divider()
                    ForEach(options) { option in
                        Text(option.name).tag(option.preference)
                    }
                }
            }
            .disabled(!store.settings.showOnExternalDisplays)
            .help(String(localized: "Choose which display shows the notch. It falls back to the built-in display when this one is disconnected.", bundle: .tabbi))
        } header: {
            Text("Display", bundle: .tabbi)
        }

        PrivacySection()

        LiveActivitySection()
    }

    /// Routes through the store so the toggle only flips once macOS accepted it.
    private var launchAtLogin: Binding<Bool> {
        Binding(get: { store.settings.launchAtLogin }, set: { store.setLaunchAtLogin($0) })
    }

    /// Says what the chosen mode does, and in Hidden mode how to get back.
    private var notchModeCaption: String {
        switch store.settings.notchMode {
        case .alwaysVisible: String(localized: "Always drawn around the hardware notch.", bundle: .tabbi)
        case .showOnHover: String(localized: "Appears when the pointer reaches the top center.", bundle: .tabbi)
        case .hidden: String(localized: "Out of sight. Press \(store.settings.hotkey.displayString) to open it.", bundle: .tabbi)
        }
    }

    private var launchAtLoginCaption: String? {
        if let error = store.launchAtLoginError { return error }
        guard store.integratesWithSystem else { return nil }
        if !store.loginItem.isAvailable {
            return String(localized: "Available when \(Edition.current.name) runs as an app bundle.", bundle: .tabbi)
        }
        if store.launchAtLoginNeedsApproval {
            return String(localized: "Allow \(Edition.current.name) in System Settings › General › Login Items.", bundle: .tabbi)
        }
        return nil
    }
}

/// A connected screen the user can pin the notch to.
struct DisplayOption: Identifiable, Equatable {
    let id: UInt32
    let name: String

    var preference: DisplayPreference { .specific(id) }

    static func connectedScreens() -> [DisplayOption] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return DisplayOption(id: number.uint32Value, name: screen.localizedName)
        }
    }

    /// Specific-screen choices: every connected screen, plus the saved screen
    /// when it is disconnected so the picker never shows an empty selection.
    static func specificOptions(screens: [DisplayOption], selected: DisplayPreference) -> [DisplayOption] {
        guard case .specific(let id) = selected, !screens.contains(where: { $0.id == id }) else { return screens }
        return screens + [DisplayOption(id: id, name: String(localized: "Disconnected display", bundle: .tabbi))]
    }
}

/// Explanatory text under a grouped section, aligned with the section's rows.
/// A grouped `Form` trails its footers, so a wrapped footer would otherwise
/// set its later lines flush right; this keeps every line leading, inset to
/// line up with the section's header and its rows' text.
struct SectionFooter: View {
    let text: AttributedString
    init(_ text: String) { self.text = AttributedString(text) }
    init(_ text: AttributedString) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            // Grouped forms align footers to the trailing edge, which leaves
            // a wrapped second line hanging on the right.
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            // Lines the text up with the section header and row titles.
            .padding(.horizontal, 10)
    }
}

/// The row that keeps settings few people need out of sight until asked for.
struct MoreOptionsToggle: View {
    @Binding var isExpanded: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack {
                Text("More options", bundle: .tabbi)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isExpanded ? String(localized: "Hide the less common settings", bundle: .tabbi) : String(localized: "Show the less common settings", bundle: .tabbi))
    }
}

/// The last row of a Settings section: puts that section back to its
/// defaults, says so for a moment afterwards, and stays disabled while there
/// is nothing to reset. A pane can put one quiet action of its own at the
/// leading edge (General's Quit), so the pane ends in one footer row.
struct ResetToDefaultsRow<Leading: View>: View {
    let isAtDefaults: Bool
    let help: String
    let title: String
    let reset: () -> Void
    let leading: Leading
    @State private var didReset = false

    init(isAtDefaults: Bool, help: String, title: String = String(localized: "Reset to Defaults", bundle: .tabbi),
         reset: @escaping () -> Void, @ViewBuilder leading: () -> Leading) {
        self.isAtDefaults = isAtDefaults
        self.help = help
        self.title = title
        self.reset = reset
        self.leading = leading()
    }

    var body: some View {
        Section {
            HStack {
                leading
                Spacer()
                if didReset {
                    Label(String(localized: "Back to defaults", bundle: .tabbi), systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                Button(title) {
                    reset()
                    didReset = true
                }
                .disabled(isAtDefaults)
                .help(isAtDefaults ? String(localized: "Everything here is already at its default", bundle: .tabbi) : help)
            }
            .motion(Motion.snappy, value: didReset)
        }
        .task(id: didReset) {
            guard didReset else { return }
            try? await Task.sleep(for: .seconds(3))
            didReset = false
        }
    }
}

extension ResetToDefaultsRow where Leading == EmptyView {
    init(isAtDefaults: Bool, help: String, title: String = String(localized: "Reset to Defaults", bundle: .tabbi), reset: @escaping () -> Void) {
        self.init(isAtDefaults: isAtDefaults, help: help, title: title, reset: reset) { EmptyView() }
    }
}

// MARK: Tabs

struct ModulesSettingsPane: View {
    let moduleOptions: ModuleOptions
    @EnvironmentObject private var store: SettingsStore
    /// The module whose own settings are open in a sheet.
    @State private var options: SettingsPane?

    var body: some View {
        Form {
            KitSection()

            Section {
                // One Form row that draws its own rows: a grouped Form ignores
                // `onMove` on macOS, so the list handles the drag itself.
                TabReorderList(layout: $store.settings.modules) { module in
                    tabRow(module)
                }
                // Header shortcuts (the Closet's paw) sit last and don't drag:
                // the notch always draws them at the far right.
                ForEach(store.settings.modules.headerShortcuts) { module in
                    tabRow(module)
                }
            } header: {
                Text("Your tabs", bundle: .tabbi)
            } footer: {
                SectionFooter(String(localized: "Drag to reorder, or select a tab and press Option-Up or Option-Down. At least one tab stays.", bundle: .tabbi))
            }

            Section {
                let available = store.settings.modules.available
                if available.isEmpty {
                    Text("Every module is already a tab.", bundle: .tabbi)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(available) { module in
                        LibraryRow(module: store.catalog.descriptor(for: module), layout: $store.settings.modules)
                    }
                }
            } header: {
                Text("Add more", bundle: .tabbi)
            }
        }
        .formStyle(.grouped)
        .motion(Motion.snappy, value: store.settings.modules)
        // Scrolls: the library grows with every module Tabbi ships.
        .frame(width: paneWidth, height: 560)
        // One sheet for the whole form: in a Form, a modifier on a row lands on every row.
        .sheet(isPresented: Binding(get: { options != nil }, set: { if !$0 { options = nil } })) {
            if let options {
                ModuleOptionsSheet(pane: options) { self.options = nil }
            }
        }
    }

    private func tabRow(_ module: ModuleID) -> some View {
        TabRow(module: store.catalog.descriptor(for: module), layout: $store.settings.modules,
               hasOptions: moduleOptions(module) != nil) {
            options = moduleOptions(module)
        }
    }
}

/// A module's own settings over the Tabs pane, with a Done button.
struct ModuleOptionsSheet: View {
    let pane: SettingsPane
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(pane.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            pane.view
            Divider()
            HStack {
                Spacer()
                Button(String(localized: "Done", bundle: .tabbi), action: done)
                    .keyboardShortcut(.defaultAction)
                    .help(String(localized: "Close \(pane.title) settings", bundle: .tabbi))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}

/// Picks the kit (a premade set of tabs), resets to its defaults, and
/// imports kits shared as JSON files (see docs/kits.md).
private struct KitSection: View {
    @EnvironmentObject private var store: SettingsStore
    /// Reset also restores what modules take from the kit (Focus: the focus
    /// sound), so their state counts toward "already at defaults".
    @Environment(\.modulesUseKitDefaults) private var modulesUseKitDefaults
    @Environment(\.runSetup) private var runSetup
    @State private var modulesMatchKit = true
    /// The outcome of the last import or removal, shown under the buttons.
    @State private var message: (text: String, isWarning: Bool)?
    /// The kit sheet: a picked kit's onboarding questions, or an imported
    /// kit's questions and then what it will change. Nothing switches, and
    /// an import isn't saved, until the user confirms.
    @State private var sheet: KitSheet?
    @State private var showsMore = false

    private var usesKitDefaults: Bool {
        store.usesKitDefaults && (store.activeKit == nil || modulesMatchKit)
    }

    var body: some View {
        Section {
            Picker(selection: kitSelection) {
                ForEach(store.kits.kits) { kit in
                    Label(kit.name, systemImage: kit.symbol).tag(kit.id)
                }
            } label: {
                Text("Kit", bundle: .tabbi)
                if let summary = store.activeKit?.summary, !summary.isEmpty {
                    Text(summary)
                }
            }
            .help(String(localized: "Switching kits replaces your tabs with the kit's", bundle: .tabbi))

            if let message {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(message.text, systemImage: message.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(message.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if !message.isWarning, let undo = store.lastKitSwitch {
                        Button(String(localized: "Undo", bundle: .tabbi), action: undoSwitch)
                            .help(undo.switchedKit
                                  ? String(localized: "Go back to the tabs and kit you had before \(undo.kitName)", bundle: .tabbi)
                                  : String(localized: "Take back this import of \(undo.kitName)", bundle: .tabbi))
                    }
                }
            }

            MoreOptionsToggle(isExpanded: $showsMore)
            if showsMore {
                HStack(spacing: 8) {
                    Button(String(localized: "Import Kit…", bundle: .tabbi), action: importKit)
                        .help(String(localized: "Add a kit someone shared as a .json file; you see what it changes first", bundle: .tabbi))
                    if store.canRemoveActiveKit {
                        Button(String(localized: "Remove Kit", bundle: .tabbi), role: .destructive, action: removeKit)
                            .help(String(localized: "Delete this imported kit and go back to the default kit", bundle: .tabbi))
                    }
                    if let runSetup {
                        Button(String(localized: "Run Setup Again", bundle: .tabbi)) {
                            // Setup runs in the notch; Settings steps aside.
                            NSApp.keyWindow?.close()
                            runSetup()
                        }
                        .help(String(localized: "Pick a kit, your tabs and what they need again, in the notch", bundle: .tabbi))
                    }
                    Spacer()
                    Button(String(localized: "Reset to Kit Defaults", bundle: .tabbi), action: store.resetToKitDefaults)
                        .disabled(usesKitDefaults)
                        .help(usesKitDefaults
                              ? String(localized: "Your setup already matches \(store.activeKit?.name ?? String(localized: "the kit", bundle: .tabbi))", bundle: .tabbi)
                              : String(localized: "Restore the tabs, previews and focus sound \(store.activeKit?.name ?? String(localized: "the kit", bundle: .tabbi)) ships with", bundle: .tabbi))
                }
            }

        } footer: {
            SectionFooter(String(localized: "A kit is a ready-made set of tabs. Switching replaces your tabs and adds its starter tasks to Today.", bundle: .tabbi))
        }
        .onReceive(store.activeKit.map(modulesUseKitDefaults) ?? Just(true).eraseToAnyPublisher()) {
            modulesMatchKit = $0
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
                .frame(width: 520)
        }
    }

    @ViewBuilder
    private func sheetContent(_ current: KitSheet) -> some View {
        switch current.step {
        case .questions:
            KitQuestionsView(kit: current.kit, answers: current.answers, cancel: { sheet = nil }) { answers in
                if current.candidate == nil {
                    sheet = nil
                    switchKit(to: current.kit.id, answers: answers)
                } else {
                    sheet = current.reviewing(answers)
                }
            }
        case .review:
            if let candidate = current.candidate {
                KitImportReviewView(
                    candidate: candidate,
                    preview: store.preview(of: candidate.kit, answers: current.answers),
                    issues: store.issues(of: candidate.kit),
                    isActiveKit: candidate.kit.id == store.settings.kitID,
                    back: candidate.kit.onboarding.isEmpty ? nil : { sheet = current.askingAgain },
                    cancel: { sheet = nil },
                    addOnly: { install(candidate, switchingWith: nil) },
                    apply: { install(candidate, switchingWith: current.answers) }
                )
            }
        }
    }

    /// Picking a kit with onboarding questions asks them first; the picker
    /// keeps showing the current kit until the user confirms.
    private var kitSelection: Binding<String> {
        Binding(get: { store.activeKit?.id ?? store.settings.kitID }, set: { id in
            message = nil
            guard id != store.settings.kitID, let kit = store.kits[id] else { return }
            if kit.onboarding.isEmpty {
                switchKit(to: id, answers: [:])
            } else {
                sheet = KitSheet(kit: kit)
            }
        })
    }

    private func switchKit(to id: String, answers: KitAnswers) {
        store.switchKit(to: id, answers: answers)
        message = (String(localized: "Switched to \(store.activeKit?.name ?? String(localized: "the kit", bundle: .tabbi)).", bundle: .tabbi), false)
    }

    /// Reads and checks the picked file, then shows the kit's questions (if
    /// any) and what it changes; nothing is saved before the user confirms.
    private func importKit() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import a Kit", bundle: .tabbi)
        panel.prompt = String(localized: "Import", bundle: .tabbi)
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let open: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            message = nil
            do {
                sheet = KitSheet(candidate: try store.inspectKit(from: url))
            } catch {
                message = ("\(error)", true)
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: open)
        } else {
            open(panel.runModal())
        }
    }

    /// Saves a reviewed import and, with `answers`, switches to it.
    private func install(_ candidate: KitImportCandidate, switchingWith answers: KitAnswers?) {
        sheet = nil
        let kit = candidate.kit
        do {
            try store.installKit(candidate, switchingWith: answers)
            let note: String
            switch (answers != nil, kit.id == store.settings.kitID) {
            case (true, _): note = candidate.overwritesFile ? String(localized: "Updated \(kit.name) and applied it.", bundle: .tabbi) : String(localized: "Imported \(kit.name) and switched to it.", bundle: .tabbi)
            case (false, true): note = String(localized: "Updated \(kit.name); your tabs are unchanged.", bundle: .tabbi)
            case (false, false): note = String(localized: "Imported \(kit.name). Pick it under Kit to use it.", bundle: .tabbi)
            }
            message = (note, false)
        } catch {
            message = (String(localized: "Couldn't import \(kit.name): \(String(describing: error))", bundle: .tabbi), true)
        }
    }

    private func removeKit() {
        let name = store.activeKit?.name ?? String(localized: "The kit", bundle: .tabbi)
        do {
            try store.removeActiveKit()
            message = (String(localized: "Removed \(name).", bundle: .tabbi), false)
        } catch {
            message = (String(localized: "Couldn't remove \(name): \(error.localizedDescription)", bundle: .tabbi), true)
        }
    }

    private func undoSwitch() {
        let undone = store.lastKitSwitch
        store.undoKitSwitch()
        if let undone, !undone.switchedKit {
            message = (String(localized: "Took back the import of \(undone.kitName).", bundle: .tabbi), false)
        } else {
            message = (String(localized: "Back to \(store.activeKit?.name ?? String(localized: "your previous kit", bundle: .tabbi)).", bundle: .tabbi), false)
        }
    }
}

/// The kit sheet's content: the kit, the import it came from (nil when the
/// user picked an installed kit), and which step shows.
private struct KitSheet: Identifiable {
    enum Step {
        case questions
        /// What the import changes for `answers`.
        case review
    }

    let kit: KitManifest
    var candidate: KitImportCandidate?
    var step: Step
    /// The answers picked so far, which the questions start from when the
    /// user goes back from the review.
    var answers: KitAnswers = [:]
    /// Stays the same across steps, so moving between them keeps the sheet up.
    let id = UUID()

    init(kit: KitManifest) {
        self.kit = kit
        step = .questions
    }

    /// An import shows its questions first when it has any.
    init(candidate: KitImportCandidate) {
        kit = candidate.kit
        self.candidate = candidate
        step = candidate.kit.onboarding.isEmpty ? .review : .questions
    }

    func reviewing(_ answers: KitAnswers) -> KitSheet {
        var next = self
        next.step = .review
        next.answers = answers
        return next
    }

    var askingAgain: KitSheet {
        var next = self
        next.step = .questions
        return next
    }
}

/// A module's icon tile in the Tabs pane, in its accent color.
private struct ModuleIcon: View {
    let module: ModuleDescriptor

    var body: some View {
        Image(systemName: module.symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(module.accentColor.gradient)
            )
    }
}

/// One of the user's tabs: drag to reorder, open its own settings, or
/// remove it to the library. A header shortcut says where it shows instead
/// of offering a drag handle.
private struct TabRow: View {
    let module: ModuleDescriptor
    @Binding var layout: ModuleLayout
    let hasOptions: Bool
    let openOptions: () -> Void

    var body: some View {
        let canRemove = layout.canDisable(module.id)
        let isHeaderShortcut = module.headerShortcut != nil
        HStack(spacing: 10) {
            DragHandle(isHidden: isHeaderShortcut)
            ModuleIcon(module: module)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                if isHeaderShortcut {
                    Text("A button at the far right of the tab bar", bundle: .tabbi)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if hasOptions {
                Button(String(localized: "Options…", bundle: .tabbi), action: openOptions)
                    .controlSize(.small)
                    .help(String(localized: "\(module.title) settings", bundle: .tabbi))
            }
            RemoveTabButton(title: module.title, canRemove: canRemove) { layout.remove(module.id) }
        }
        .contentShape(Rectangle())
    }
}

/// The grip at the start of a tab row. The whole row drags; the grip says so
/// with an open hand on hover. The paw's row keeps the space but no grip.
private struct DragHandle: View {
    let isHidden: Bool
    @State private var isHovering = false

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isHovering ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .frame(width: 16, height: 24)
            .contentShape(Rectangle())
            .opacity(isHidden ? 0 : 1)
            .onHover { inside in
                guard !isHidden, inside != isHovering else { return }
                isHovering = inside
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .onDisappear { if isHovering { NSCursor.pop() } }
            .help(isHidden ? "" : String(localized: "Drag to reorder", bundle: .tabbi))
            .accessibilityHidden(true)
    }
}

/// The user's tabs as rows that reorder by dragging (mouse or trackpad), by
/// Option-Up and Option-Down on the selected row, and by VoiceOver's Move up
/// and Move down actions. While a row is lifted the others slide aside live
/// and an outline marks where it will land; the move is saved on release,
/// so the notch's tab bar follows at once.
private struct TabReorderList<Row: View>: View {
    @Binding var layout: ModuleLayout
    @ViewBuilder let row: (ModuleID) -> Row
    @EnvironmentObject private var store: SettingsStore
    @State private var drag: (module: ModuleID, geometry: RowReorderDrag)?
    @FocusState private var focused: ModuleID?

    /// Every row is this tall, so a drag maps the pointer onto slots.
    private static var rowHeight: CGFloat { 36 }
    private static var space: String { "TabReorderList" }

    var body: some View {
        let tabs = layout.tabs
        VStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, module in
                let isLifted = drag?.module == module
                row(module)
                    .frame(height: Self.rowHeight)
                    .padding(.horizontal, 4)
                    .background(rowBackground(isLifted: isLifted, isFocused: focused == module))
                    .overlay(alignment: .bottom) {
                        if drag == nil, index < tabs.count - 1 {
                            Divider()
                                .padding(.horizontal, 4)
                                // Full width like the Form's own separators,
                                // which a Divider in a row would inset to the title.
                                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        }
                    }
                    .offset(y: CGFloat(drag?.geometry.offset(at: index) ?? 0))
                    .zIndex(isLifted ? 1 : 0)
                    .animation(isLifted ? nil : Motion.snappy, value: drag?.geometry)
                    .gesture(reorderGesture(for: module, at: index, count: tabs.count))
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focused, equals: module)
                    .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
                        guard press.modifiers.contains(.option) else { return .ignored }
                        step(module, by: press.key == .upArrow ? -1 : 1)
                        return .handled
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityAction(named: Text("Move up", bundle: .tabbi)) { step(module, by: -1) }
                    .accessibilityAction(named: Text("Move down", bundle: .tabbi)) { step(module, by: 1) }
            }
        }
        .background(alignment: .top) { dropIndicator }
        .coordinateSpace(name: Self.space)
        .padding(.horizontal, -4)
    }

    /// An outline over the slot the lifted row lands in on release.
    @ViewBuilder
    private var dropIndicator: some View {
        if let geometry = drag?.geometry, geometry.movesRow {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.08)))
                .frame(height: Self.rowHeight)
                .offset(y: CGFloat(geometry.target) * Self.rowHeight)
                .transition(.opacity)
        }
    }

    private func rowBackground(isLifted: Bool, isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isLifted ? AnyShapeStyle(.background) : AnyShapeStyle(Color.accentColor.opacity(isFocused ? 0.12 : 0)))
            .shadow(color: .black.opacity(isLifted ? 0.25 : 0), radius: 6, y: 2)
    }

    private func reorderGesture(for module: ModuleID, at index: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag?.module != module {
                    drag = (module, RowReorderDrag(from: index, count: count, rowHeight: Double(Self.rowHeight)))
                    focused = module
                    NSCursor.closedHand.push()
                }
                drag?.geometry.translation = value.translation.height
            }
            .onEnded { _ in
                guard let finished = drag else { return }
                NSCursor.pop()
                withMotion(Motion.snappy) {
                    // Clear the offsets and apply the move together so rows settle in one motion.
                    drag = nil
                    if finished.geometry.movesRow {
                        layout.moveTab(finished.module, to: finished.geometry.target)
                    }
                }
            }
    }

    private func step(_ module: ModuleID, by offset: Int) {
        guard layout.canMoveTab(module, by: offset) else { return }
        withMotion(Motion.snappy) { layout.moveTab(module, by: offset) }
        let title = store.catalog.descriptor(for: module).title
        let position = (layout.tabs.firstIndex(of: module) ?? 0) + 1
        AccessibilityNotification.Announcement(String(localized: "\(title) moved to position \(position) of \(layout.tabs.count)", bundle: .tabbi)).post()
    }
}

/// The quiet minus at the end of a tab row; it turns red on hover so the
/// list doesn't read as a column of buttons.
private struct RemoveTabButton: View {
    let title: String
    let canRemove: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(isHovering && canRemove ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.borderless)
        .disabled(!canRemove)
        .onHover { isHovering = $0 }
        .accessibilityLabel(String(localized: "Remove \(title)", bundle: .tabbi))
        .help(canRemove ? String(localized: "Remove \(title) from the notch; it goes back to Add more", bundle: .tabbi) : String(localized: "At least one tab must stay", bundle: .tabbi))
    }
}

/// A module in the Add more library: what it is, in one line, and a button
/// that makes it the last tab.
private struct LibraryRow: View {
    let module: ModuleDescriptor
    @Binding var layout: ModuleLayout

    var body: some View {
        HStack(spacing: 10) {
            ModuleIcon(module: module)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                Text(module.summary ?? module.category.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(module.summary ?? module.category.title)
            }
            Spacer(minLength: 8)
            Button(String(localized: "Add", bundle: .tabbi)) { layout.add(module.id) }
                .controlSize(.small)
                .help(String(localized: "Add \(module.title) as the last tab in the notch", bundle: .tabbi))
        }
    }
}

// MARK: Feedback

/// Haptics, the celebration sound and the animation pace, under General's
/// More options. Turning haptics or the sound on plays it once, so the
/// switch previews what it adds.
struct FeedbackSection: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section {
            Toggle(isOn: $store.settings.hapticsEnabled) {
                Text("Haptic feedback", bundle: .tabbi)
                Text("A light trackpad tap at the notch edge and on celebrations.", bundle: .tabbi)
            }
            .help(String(localized: "Tap the trackpad when the pointer reaches the notch or a celebration plays", bundle: .tabbi))
            .onChange(of: store.settings.hapticsEnabled) { _, isOn in
                // Turning it on taps once, so you feel what you picked.
                if isOn { CelebrationCenter.perform(.levelChange) }
            }
            Toggle(isOn: $store.settings.celebrationSoundEnabled) {
                Text("Celebration sound", bundle: .tabbi)
                Text("A soft sound when you unlock an item or reach a streak.", bundle: .tabbi)
            }
            .help(String(localized: "Play a soft sound with celebrations that have no sound of their own", bundle: .tabbi))
            .onChange(of: store.settings.celebrationSoundEnabled) { _, isOn in
                // Turning it on plays the sound once, as a preview.
                if isOn, let sound = CelebrationSound.cue(for: .burst, isEnabled: true, eventHasSound: false) {
                    CelebrationCenter.play(sound)
                }
            }
            Toggle(isOn: $store.settings.weeklyRecapEnabled) {
                Text("Weekly recap", bundle: .tabbi)
                Text("A card with your week in the notch every Sunday evening.", bundle: .tabbi)
            }
            .help(String(localized: "Show a recap of your week the first time you open the notch after Sunday 6 pm", bundle: .tabbi))
            Picker(selection: $store.settings.motionPace) {
                ForEach(MotionPace.allCases, id: \.self) { pace in
                    Text(pace.title).tag(pace)
                }
            } label: {
                Text("Animations", bundle: .tabbi)
                Text(motionCaption)
            }
            .help(String(localized: "Choose how lively the notch's animations are", bundle: .tabbi))
        } header: {
            Text("Feedback", bundle: .tabbi)
        }
    }

    /// What the chosen pace feels like, or why it barely matters while
    /// Reduce Motion is on.
    private var motionCaption: String {
        guard reduceMotion, store.settings.motionPace != .instant else { return store.settings.motionPace.caption }
        return String(localized: "Reduce Motion is on, so changes fade instead of moving.", bundle: .tabbi)
    }
}

// MARK: Privacy

/// Where the notch shows besides your own screen, under General's More
/// options. Both are off by default, so nothing disappears unexpectedly.
struct PrivacySection: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        Section {
            Toggle(isOn: $store.settings.hideFromScreenCapture) {
                Text("Hide from screen sharing", bundle: .tabbi)
                Text("Only you see the notch, not your audience or recordings.", bundle: .tabbi)
            }
            .help(String(localized: "Keep the notch out of screen sharing, recordings and screenshots, for example while presenting in class", bundle: .tabbi))
            Toggle(isOn: $store.settings.hideInMissionControl) {
                Text("Hide in Mission Control", bundle: .tabbi)
                Text("Steps aside while Mission Control shows your spaces.", bundle: .tabbi)
            }
            .help(String(localized: "Hide the notch while Mission Control is open", bundle: .tabbi))
        } header: {
            Text("Privacy", bundle: .tabbi)
        }
    }
}

// MARK: Live activity

/// What the closed notch's live activity shows, under General's More options.
private struct LiveActivitySection: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        Section {
            Picker(String(localized: "Switch every", bundle: .tabbi), selection: $store.settings.notchPreview.interval) {
                ForEach(TickerInterval.allCases) { interval in
                    Text(interval.title).tag(interval)
                }
            }
            .help(String(localized: "How long each item stays before the next one", bundle: .tabbi))
            ForEach(TickerKind.all(in: store.catalog)) { kind in
                let moduleOn = kind.module.map(store.settings.modules.isEnabled) ?? true
                let title = kind.title(in: store.catalog)
                Toggle(title, isOn: Binding(
                    get: { store.settings.notchPreview.isEnabled(kind) },
                    set: { store.settings.notchPreview.setEnabled(kind, $0) }
                ))
                .disabled(!moduleOn)
                .help(moduleOn
                    ? String(localized: "Show this in the live activity", bundle: .tabbi)
                    : String(localized: "Add \(kind.module.map { store.catalog.descriptor(for: $0).title } ?? String(localized: "its module", bundle: .tabbi)) in Tabs to include this", bundle: .tabbi))
            }
        } header: {
            Text("Live activity", bundle: .tabbi)
        } footer: {
            SectionFooter(String(localized: "Items with nothing to show are skipped.", bundle: .tabbi))
        }
        .disabled(!store.settings.notchPreview.isEnabled)
    }
}

// MARK: Shortcuts

/// The global shortcut, with the open notch's fixed keys in its footer.
private struct ShortcutSection: View {
    @EnvironmentObject private var store: SettingsStore
    @StateObject private var recorder = HotkeyRecorder()

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    if store.settings.hotkey != .default, !recorder.isRecording {
                        Button {
                            store.settings.hotkey = .default
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: "Restore \(Hotkey.default.displayString)", bundle: .tabbi))
                    }
                    HotkeyRecorderField(
                        hotkey: store.settings.hotkey,
                        recorder: recorder,
                        onRecordingChange: { store.isRecordingHotkey = $0 },
                        onRecord: { store.settings.hotkey = $0 }
                    )
                }
            } label: {
                Text("Open and close the notch", bundle: .tabbi)
                Text("Works from any app. On Today, type right away to add a task.", bundle: .tabbi)
            }
            if let status {
                Label(status.text, systemImage: status.symbol)
                    .font(.callout)
                    .foregroundStyle(status.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
        } header: {
            Text("Shortcut", bundle: .tabbi)
        } footer: {
            SectionFooter(String(localized: "In the open notch, arrow keys or a two-finger swipe switch tabs, 1-9 jump to a tab, and Esc or a swipe up closes. On the closed notch, swipe down or middle-click to see the next live activity.", bundle: .tabbi))
        }
        .onDisappear { recorder.stop() }
    }

    private var status: (text: String, symbol: String, isWarning: Bool)? {
        switch recorder.rejection {
        case .needsModifier:
            return (String(localized: "Add Control or Option so the shortcut doesn't get in the way of typing.", bundle: .tabbi), "exclamationmark.triangle.fill", true)
        case .unsupportedKey:
            return (String(localized: "That key can't be part of a shortcut. Try a letter, number, or Space.", bundle: .tabbi), "exclamationmark.triangle.fill", true)
        default:
            break
        }
        if !recorder.isRecording, !store.hotkeyIsRegistered {
            return (String(localized: "\(store.settings.hotkey.displayString) is already used by another app. Record a different shortcut.", bundle: .tabbi),
                    "exclamationmark.triangle.fill", true)
        }
        return nil
    }
}

// MARK: Claude

/// Where the claude CLI is, under Connections' More options: AI Usage and
/// Ask AI (with Claude Code as the AI) find it by themselves almost always.
struct ClaudeLocationSection: View {
    @EnvironmentObject private var store: SettingsStore
    /// The text being edited; committed on Return, focus loss, Choose, or Validate
    /// so trimming and `~` expansion never fight the user mid-typing.
    @State private var draft = ""
    @State private var check: ClaudePathCheck?
    /// Bumped by Validate so the check re-runs even when the path is unchanged.
    @State private var attempt = 0
    @FocusState private var fieldFocused: Bool

    /// With `TABBI_DEMO=1` the pane shows a sample result and never runs the CLI.
    private static var isDemo: Bool { RunMode.current.isDemo }

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    if store.settings.claudePathOverride != nil {
                        Button {
                            draft = ""
                            commit()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: "Detect claude automatically", bundle: .tabbi))
                    }
                    TextField(String(localized: "Path", bundle: .tabbi), text: $draft, prompt: Text("Detect automatically", bundle: .tabbi))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: 240)
                        .focused($fieldFocused)
                        .onSubmit(commit)
                        .help(String(localized: "Full path to the claude binary. Leave empty to detect it automatically.", bundle: .tabbi))
                    Button(String(localized: "Choose…", bundle: .tabbi), action: choose)
                        .help(String(localized: "Pick the claude binary in Finder", bundle: .tabbi))
                }
            } label: {
                Text("Location", bundle: .tabbi)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                statusView
                Spacer(minLength: 8)
                Button(String(localized: "Validate", bundle: .tabbi)) {
                    commit()
                    attempt += 1
                }
                .disabled(check == nil)
                .help(String(localized: "Check that this claude runs and report its version", bundle: .tabbi))
            }
        } header: {
            Text("Claude location", bundle: .tabbi)
        } footer: {
            SectionFooter(String(localized: "With Claude Code as your AI, Ask AI and AI Usage run your own signed-in claude CLI; \(Edition.current.name) never reads your credentials. Set this only if claude isn't found automatically.", bundle: .tabbi))
        }
        .onAppear { draft = Self.displayPath(store.settings.claudePathOverride) }
        .onChange(of: fieldFocused) { _, focused in
            if !focused { commit() }
        }
        .task(id: CheckRequest(path: store.settings.claudePathOverride, attempt: attempt)) {
            check = nil
            check = await Self.run(override: store.settings.claudePathOverride)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if let check {
            let status = Self.status(for: check)
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title)
                    Text(status.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } icon: {
                Image(systemName: check.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(check.isSuccess ? Color.green : Color.orange)
            }
            .help(status.detail)
        } else {
            Label {
                Text("Checking…", bundle: .tabbi)
                    .foregroundStyle(.secondary)
            } icon: {
                Spinner()
            }
        }
    }

    private func commit() {
        store.settings.claudePathOverride = draft
        draft = Self.displayPath(store.settings.claudePathOverride)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose the claude CLI"
        panel.prompt = "Use"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        let current = store.settings.claudePathOverride.map { URL(fileURLWithPath: $0) }
        panel.directoryURL = current?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
        let apply: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            draft = url.path
            commit()
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: apply)
        } else {
            apply(panel.runModal())
        }
    }

    private struct CheckRequest: Equatable {
        let path: String?
        let attempt: Int
    }

    private static func run(override: String?) async -> ClaudePathCheck {
        if isDemo {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return .found(path: override ?? "\(home)/.local/bin/claude", version: "2.1.4", isOverride: override != nil)
        }
        return await Task.detached(priority: .userInitiated) { ClaudePathCheck.run(override: override) }.value
    }

    private static func displayPath(_ path: String?) -> String {
        path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? ""
    }

    private static func status(for check: ClaudePathCheck) -> (title: String, detail: String) {
        switch check {
        case let .found(path, version, isOverride):
            let title = version.map { "Claude Code \($0)" } ?? "Claude Code"
            return (title, (isOverride ? "Using " : "Found automatically at ") + displayPath(path))
        case .missing(let path):
            return ("Nothing at this path", "\(displayPath(path)) doesn't exist.")
        case .notExecutable(let path):
            return ("Can't run this file", "\(displayPath(path)) isn't an executable program.")
        case .notClaude(let path):
            return ("Not Claude Code", "\(displayPath(path)) didn't report a Claude Code version.")
        case .notFound:
            return ("claude wasn't found", "Install Claude Code, or choose where it is.")
        }
    }
}

// MARK: About

struct AboutSettingsPane: View {
    private static let repository = URL(string: "https://github.com/ethanwchen/tabbi")!

    var body: some View {
        VStack(spacing: 0) {
            AppGlyph()
                .padding(.bottom, 16)
            Text(Edition.current.name)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(versionText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)
            Text("A cozy everyday companion: a cat in your notch, with your tabs one click away.", bundle: .tabbi)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.top, 12)
            HStack(spacing: 12) {
                Link(destination: Self.repository) {
                    Label(String(localized: "View on GitHub", bundle: .tabbi), systemImage: "arrow.up.right.square")
                }
                .help(Self.repository.absoluteString)
            }
            .padding(.top, 20)
            Link(destination: SupportContact.mailURL) {
                Label(SupportContact.reportLine, systemImage: "envelope")
            }
            .help(String(localized: "Email the \(Edition.current.name) team about a bug, a person in Party or anything else", bundle: .tabbi))
            .padding(.top, 8)
            Link(destination: Feedback.url) {
                Label(FeedbackLink.title, systemImage: "lightbulb")
            }
            .help(String(localized: "Opens the Suggest page with your app version, macOS version and edition filled in", bundle: .tabbi))
            .padding(.top, 8)
            #if !APPSTORE
            UpdatesSettingsSection()
                .padding(.top, 16)
            CrashReportSettingsSection()
                .padding(.top, 12)
            #endif
            Text("Released under the MIT License.", bundle: .tabbi)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 20)
            HStack(spacing: 12) {
                Link("Privacy Policy", destination: SupportContact.privacyURL)
                    .help(SupportContact.privacyURL.absoluteString)
                Link("Terms of Use", destination: SupportContact.termsURL)
                    .help(SupportContact.termsURL.absoluteString)
            }
            .font(.caption)
            .padding(.top, 4)
        }
        .padding(32)
        .frame(width: paneWidth)
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return String(localized: "Development build", bundle: .tabbi) }
        let build = info?["CFBundleVersion"] as? String
        return build.map { String(localized: "Version \(version) (\($0))", bundle: .tabbi) } ?? String(localized: "Version \(version)", bundle: .tabbi)
    }
}

/// The app icon. `swift run` has no bundle, so it falls back to the repo's
/// icon file (the dev and snapshot working directory).
private struct AppGlyph: View {
    private static let icon: NSImage = Bundle.main.bundleURL.pathExtension == "app"
        ? NSApp.applicationIconImage
        : NSImage(contentsOfFile: "Resources/AppIcon.icns") ?? NSApp.applicationIconImage

    var body: some View {
        // The icon's art fills about 80% of its canvas, so a 100 pt image shows an 80 pt icon.
        Image(nsImage: Self.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: 100, height: 100)
            .padding(-10)
            .accessibilityHidden(true)
    }
}
