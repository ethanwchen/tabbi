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

    var body: some View {
        LabeledContent {
            TextField("Your name", text: name, prompt: Text("Your name"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(width: 160)
                .help("Your name, up to \(DisplayName.maxLength) characters")
        } label: {
            Text("Your name")
            Text("Shown to friends in Party and used to greet you.")
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
                Toggle("Launch at login", isOn: launchAtLogin)
                    .disabled(!LaunchAtLogin.isAvailable && store.integratesWithSystem)
                    .help("Start \(Edition.current.name) automatically when you log in")
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
                    Text("Notch")
                    Text(notchModeCaption)
                }
                .help("Choose when the notch is drawn. The shortcut always opens it.")
                Picker("Panel size", selection: $store.settings.panelSize) {
                    ForEach(PanelSize.allCases, id: \.self) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .help("Choose how big the open notch is. Every tab uses the same size.")
                Toggle(isOn: $store.settings.openOnHover) {
                    Text("Open on hover")
                    Text("Opens the notch when the pointer rests on it.")
                }
                .help("Open the notch after hovering it briefly")
                Toggle(isOn: $store.settings.notchPreview.isEnabled) {
                    Text("Show live activity")
                    Text("Meetings, music and timers beside the closed notch.")
                }
                .help("Show a small live preview beside the closed notch")
                Toggle(isOn: $store.settings.hideInFullscreen) {
                    Text("Hide in fullscreen")
                    Text("Steps aside while a video, game or app is fullscreen.")
                }
                .help("Hide the notch while an app is fullscreen on its display. The shortcut still opens it.")
            }

            ShortcutSection()

            Section {
                MoreOptionsToggle(isExpanded: $showsMore)
            }

            if showsMore {
                moreOptions
            }

            ResetToDefaultsRow(isAtDefaults: store.usesGeneralDefaults,
                               help: "Put General back the way a new install has it. Launch at login stays as it is.",
                               reset: store.resetGeneral)

            Section {
                HStack {
                    Text("Closes the notch until you open \(Edition.current.name) again.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    // Command-Q itself lives in the hidden app menu, so it
                    // also works while the notch is open.
                    Button("Quit \(Edition.current.name)") { NSApp.terminate(nil) }
                        .help("Quit \(Edition.current.name) (\u{2318}Q)")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(!showsMore)
        .frame(width: paneWidth, height: showsMore ? 896 : 776)
        .motion(Motion.snappy, value: showsMore)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = DisplayOption.connectedScreens()
        }
    }

    @ViewBuilder
    private var moreOptions: some View {
        Section {
            Toggle(isOn: $store.settings.hapticsEnabled) {
                Text("Haptic feedback")
                Text("A light trackpad tap at the notch edge and on celebrations.")
            }
            .help("Tap the trackpad when the pointer reaches the notch or a celebration plays")
            Toggle(isOn: $store.settings.celebrationSoundEnabled) {
                Text("Celebration sound")
                Text("A soft sound when you unlock an item or reach a streak.")
            }
            .help("Play a soft sound with celebrations that have no sound of their own")
        } header: {
            Text("Feedback")
        }

        Section {
            Toggle(isOn: $store.settings.showOnExternalDisplays) {
                Text("Show on external displays")
                Text("When off, the notch hides while the lid is closed.")
            }
            .help("Allow the notch on displays other than the built-in one")
            Picker("Show notch on", selection: $store.settings.preferredDisplay) {
                Text("Built-in display").tag(DisplayPreference.builtIn)
                Text("Main display").tag(DisplayPreference.main)
                let options = DisplayOption.specificOptions(screens: screens, selected: store.settings.preferredDisplay)
                if !options.isEmpty {
                    Divider()
                    ForEach(options) { option in
                        Text(option.name).tag(option.preference)
                    }
                }
            }
            .disabled(!store.settings.showOnExternalDisplays)
            .help("Choose which display shows the notch. It falls back to the built-in display when this one is disconnected.")
        } header: {
            Text("Display")
        }

        LiveActivitySection()
    }

    /// Routes through the store so the toggle only flips once macOS accepted it.
    private var launchAtLogin: Binding<Bool> {
        Binding(get: { store.settings.launchAtLogin }, set: { store.setLaunchAtLogin($0) })
    }

    /// Says what the chosen mode does, and in Hidden mode how to get back.
    private var notchModeCaption: String {
        switch store.settings.notchMode {
        case .alwaysVisible: "Always drawn around the hardware notch."
        case .showOnHover: "Appears when the pointer reaches the top center."
        case .hidden: "Out of sight. Press \(store.settings.hotkey.displayString) to open it."
        }
    }

    private var launchAtLoginCaption: String? {
        if let error = store.launchAtLoginError { return error }
        guard store.integratesWithSystem else { return nil }
        if !LaunchAtLogin.isAvailable {
            return "Available when \(Edition.current.name) runs as an app bundle."
        }
        if LaunchAtLogin.needsApproval {
            return "Allow \(Edition.current.name) in System Settings › General › Login Items."
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
        return screens + [DisplayOption(id: id, name: "Disconnected display")]
    }
}

/// Explanatory text under a grouped section, aligned with the section's rows.
struct SectionFooter: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("More options")
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
        .help(isExpanded ? "Hide the less common settings" : "Show the less common settings")
    }
}

/// The last row of a Settings section: puts that section back to its
/// defaults, says so for a moment afterwards, and stays disabled while there
/// is nothing to reset.
struct ResetToDefaultsRow: View {
    let isAtDefaults: Bool
    let help: String
    var title = "Reset to Defaults"
    let reset: () -> Void
    @State private var didReset = false

    var body: some View {
        Section {
            HStack {
                if didReset {
                    Label("Back to defaults", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                Spacer()
                Button(title) {
                    reset()
                    didReset = true
                }
                .disabled(isAtDefaults)
                .help(isAtDefaults ? "Everything here is already at its default" : help)
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
                Text("Your tabs")
            } footer: {
                SectionFooter("Drag to reorder, or select a tab and press Option-Up or Option-Down. At least one tab stays.")
            }

            Section {
                let available = store.settings.modules.available
                if available.isEmpty {
                    Text("Every module is already a tab.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(available) { module in
                        LibraryRow(module: store.catalog.descriptor(for: module), layout: $store.settings.modules)
                    }
                }
            } header: {
                Text("Add more")
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
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
                    .help("Close \(pane.title) settings")
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
                Text("Kit")
                if let summary = store.activeKit?.summary, !summary.isEmpty {
                    Text(summary)
                }
            }
            .help("Switching kits replaces your tabs with the kit's")

            if let message {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(message.text, systemImage: message.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(message.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if !message.isWarning, let undo = store.lastKitSwitch {
                        Button("Undo", action: undoSwitch)
                            .help(undo.switchedKit
                                  ? "Go back to the tabs and kit you had before \(undo.kitName)"
                                  : "Take back this import of \(undo.kitName)")
                    }
                }
            }

            MoreOptionsToggle(isExpanded: $showsMore)
            if showsMore {
                HStack(spacing: 8) {
                    Button("Import Kit…", action: importKit)
                        .help("Add a kit someone shared as a .json file; you see what it changes first")
                    if store.canRemoveActiveKit {
                        Button("Remove Kit", role: .destructive, action: removeKit)
                            .help("Delete this imported kit and go back to the default kit")
                    }
                    if let runSetup {
                        Button("Run Setup Again") {
                            // Setup runs in the notch; Settings steps aside.
                            NSApp.keyWindow?.close()
                            runSetup()
                        }
                        .help("Pick a kit, your tabs and what they need again, in the notch")
                    }
                    Spacer()
                    Button("Reset to Kit Defaults", action: store.resetToKitDefaults)
                        .disabled(usesKitDefaults)
                        .help(usesKitDefaults
                              ? "Your setup already matches \(store.activeKit?.name ?? "the kit")"
                              : "Restore the tabs, previews and focus sound \(store.activeKit?.name ?? "the kit") ships with")
                }
            }

        } footer: {
            SectionFooter("A kit is a ready-made set of tabs. Switching replaces your tabs and adds its starter tasks to Today.")
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
        message = ("Switched to \(store.activeKit?.name ?? "the kit").", false)
    }

    /// Reads and checks the picked file, then shows the kit's questions (if
    /// any) and what it changes; nothing is saved before the user confirms.
    private func importKit() {
        let panel = NSOpenPanel()
        panel.title = "Import a Kit"
        panel.prompt = "Import"
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
            case (true, _): note = candidate.overwritesFile ? "Updated \(kit.name) and applied it." : "Imported \(kit.name) and switched to it."
            case (false, true): note = "Updated \(kit.name); your tabs are unchanged."
            case (false, false): note = "Imported \(kit.name). Pick it under Kit to use it."
            }
            message = (note, false)
        } catch {
            message = ("Couldn't import \(kit.name): \(error)", true)
        }
    }

    private func removeKit() {
        let name = store.activeKit?.name ?? "The kit"
        do {
            try store.removeActiveKit()
            message = ("Removed \(name).", false)
        } catch {
            message = ("Couldn't remove \(name): \(error.localizedDescription)", true)
        }
    }

    private func undoSwitch() {
        let undone = store.lastKitSwitch
        store.undoKitSwitch()
        if let undone, !undone.switchedKit {
            message = ("Took back the import of \(undone.kitName).", false)
        } else {
            message = ("Back to \(store.activeKit?.name ?? "your previous kit").", false)
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
                    Text("A button at the far right of the tab bar")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if hasOptions {
                Button("Options…", action: openOptions)
                    .controlSize(.small)
                    .help("\(module.title) settings")
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
            .help(isHidden ? "" : "Drag to reorder")
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
                    .accessibilityAction(named: "Move up") { step(module, by: -1) }
                    .accessibilityAction(named: "Move down") { step(module, by: 1) }
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
        AccessibilityNotification.Announcement("\(title) moved to position \(position) of \(layout.tabs.count)").post()
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
        .accessibilityLabel("Remove \(title)")
        .help(canRemove ? "Remove \(title) from the notch; it goes back to Add more" : "At least one tab must stay")
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
            Button("Add") { layout.add(module.id) }
                .controlSize(.small)
                .help("Add \(module.title) as the last tab in the notch")
        }
    }
}

// MARK: Live activity

/// What the closed notch's live activity shows, under General's More options.
private struct LiveActivitySection: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        Section {
            Picker("Switch every", selection: $store.settings.notchPreview.interval) {
                ForEach(TickerInterval.allCases) { interval in
                    Text(interval.title).tag(interval)
                }
            }
            .help("How long each item stays before the next one")
            ForEach(TickerKind.all(in: store.catalog)) { kind in
                let moduleOn = kind.module.map(store.settings.modules.isEnabled) ?? true
                let title = kind.title(in: store.catalog)
                Toggle(title, isOn: Binding(
                    get: { store.settings.notchPreview.isEnabled(kind) },
                    set: { store.settings.notchPreview.setEnabled(kind, $0) }
                ))
                .disabled(!moduleOn)
                .help(moduleOn
                    ? "Include \(title.lowercased()) in the live activity"
                    : "Add \(kind.module.map { store.catalog.descriptor(for: $0).title } ?? "its module") in Tabs to include this")
            }
        } header: {
            Text("Live activity")
        } footer: {
            SectionFooter("Items with nothing to show are skipped.")
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
                        .help("Restore \(Hotkey.default.displayString)")
                    }
                    HotkeyRecorderField(
                        hotkey: store.settings.hotkey,
                        recorder: recorder,
                        onRecordingChange: { store.isRecordingHotkey = $0 },
                        onRecord: { store.settings.hotkey = $0 }
                    )
                }
            } label: {
                Text("Open and close the notch")
                Text("Works from any app. On Today, type right away to add a task.")
            }
            if let status {
                Label(status.text, systemImage: status.symbol)
                    .font(.callout)
                    .foregroundStyle(status.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
        } header: {
            Text("Shortcut")
        } footer: {
            SectionFooter("In the open notch, arrow keys or a two-finger swipe switch tabs, 1-9 jump to a tab and Esc closes.")
        }
        .onDisappear { recorder.stop() }
    }

    private var status: (text: String, symbol: String, isWarning: Bool)? {
        switch recorder.rejection {
        case .needsModifier:
            return ("Add Control or Option so the shortcut doesn't get in the way of typing.", "exclamationmark.triangle.fill", true)
        case .unsupportedKey:
            return ("That key can't be part of a shortcut. Try a letter, number, or Space.", "exclamationmark.triangle.fill", true)
        default:
            break
        }
        if !recorder.isRecording, !store.hotkeyIsRegistered {
            return ("\(store.settings.hotkey.displayString) is already used by another app. Record a different shortcut.",
                    "exclamationmark.triangle.fill", true)
        }
        return nil
    }
}

// MARK: Claude

/// Where the claude CLI is, under Connections' More options: Claude Usage
/// and Ask Claude find it by themselves almost always.
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
                        .help("Detect claude automatically")
                    }
                    TextField("Path", text: $draft, prompt: Text("Detect automatically"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: 240)
                        .focused($fieldFocused)
                        .onSubmit(commit)
                        .help("Full path to the claude binary. Leave empty to detect it automatically.")
                    Button("Choose…", action: choose)
                        .help("Pick the claude binary in Finder")
                }
            } label: {
                Text("Location")
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                statusView
                Spacer(minLength: 8)
                Button("Validate") {
                    commit()
                    attempt += 1
                }
                .disabled(check == nil)
                .help("Check that this claude runs and report its version")
            }
        } header: {
            Text("Claude location")
        } footer: {
            SectionFooter("Claude tabs run your own signed-in claude CLI; \(Edition.current.name) never reads your credentials. Set this only if claude isn't found automatically.")
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
                Text("Checking…")
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
    private static let repository = URL(string: "https://github.com/ethanwchen/notchdeck")!

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
            Text("A cozy everyday companion: a cat in your notch, with your tabs one click away.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.top, 12)
            HStack(spacing: 12) {
                Link(destination: Self.repository) {
                    Label("View on GitHub", systemImage: "arrow.up.right.square")
                }
                .help(Self.repository.absoluteString)
            }
            .padding(.top, 20)
            Link(destination: SupportContact.mailURL) {
                Label(SupportContact.reportLine, systemImage: "envelope")
            }
            .help("Email the \(Edition.current.name) team about a bug, a person in Party or anything else")
            .padding(.top, 8)
            UpdatesSettingsSection()
                .padding(.top, 16)
            Text("Released under the MIT License.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 20)
        }
        .padding(32)
        .frame(width: paneWidth)
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
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
