import AppKit
import SwiftUI
import NotchDeckCore

/// Width shared by every pane so the window only animates its height.
private let paneWidth: CGFloat = 500

// MARK: General

struct GeneralSettingsPane: View {
    @EnvironmentObject private var store: SettingsStore
    @State private var screens = DisplayOption.connectedScreens()

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: launchAtLogin)
                    .disabled(!LaunchAtLogin.isAvailable && store.integratesWithSystem)
                    .help("Start NotchDeck automatically when you log in")
                if let caption = launchAtLoginCaption {
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Startup")
            }

            Section {
                Toggle(isOn: $store.settings.openOnHover) {
                    Text("Open on hover")
                    Text("Opens the notch when the pointer rests on it, without clicking.")
                }
                .help("Open the notch after hovering it briefly")
                Toggle(isOn: $store.settings.hapticsEnabled) {
                    Text("Haptic feedback")
                    Text("A light trackpad tap when the pointer reaches the notch.")
                }
                .help("Tap the trackpad when the pointer reaches the notch")
            } header: {
                Text("Behavior")
            }

            Section {
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
                .help("Choose which display shows the notch")
            } header: {
                Text("Display")
            } footer: {
                SectionFooter("Falls back to the main display when the chosen one is disconnected.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: paneWidth, height: 388)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = DisplayOption.connectedScreens()
        }
    }

    /// Routes through the store so the toggle only flips once macOS accepted it.
    private var launchAtLogin: Binding<Bool> {
        Binding(get: { store.settings.launchAtLogin }, set: { store.setLaunchAtLogin($0) })
    }

    private var launchAtLoginCaption: String? {
        if let error = store.launchAtLoginError { return error }
        guard store.integratesWithSystem else { return nil }
        if !LaunchAtLogin.isAvailable {
            return "Available when NotchDeck runs as an app bundle."
        }
        if LaunchAtLogin.needsApproval {
            return "Allow NotchDeck in System Settings › General › Login Items."
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
private struct SectionFooter: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Modules

struct ModulesSettingsPane: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        Form {
            Section {
                ForEach(store.settings.modules.order) { module in
                    ModuleRow(module: module, layout: $store.settings.modules)
                }
                .onMove { source, destination in
                    store.settings.modules.move(fromOffsets: source, toOffset: destination)
                }
            } header: {
                Text("Tabs")
            } footer: {
                SectionFooter("Drag to reorder. The notch's tab bar, arrow keys, and swipes follow this order. At least one module stays on.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: paneWidth, height: 336)
    }
}

private struct ModuleRow: View {
    let module: ModuleID
    @Binding var layout: ModuleLayout

    var body: some View {
        let enabled = layout.isEnabled(module)
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
            Image(systemName: module.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.Palette.accent(for: module).gradient)
                )
                .saturation(enabled ? 1 : 0)
                .opacity(enabled ? 1 : 0.6)
            Text(module.title)
                .foregroundStyle(enabled ? .primary : .secondary)
            Spacer()
            Toggle("Show \(module.title)", isOn: Binding(
                get: { enabled },
                set: { layout.setEnabled(module, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(enabled && !layout.canDisable(module))
            .help(enabled && !layout.canDisable(module)
                  ? "At least one module must stay on"
                  : (enabled ? "Hide \(module.title) from the notch" : "Show \(module.title) in the notch"))
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: enabled)
    }
}

// MARK: Shortcuts

struct ShortcutsSettingsPane: View {
    @EnvironmentObject private var store: SettingsStore
    @StateObject private var recorder = HotkeyRecorder()

    var body: some View {
        Form {
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
                        HotkeyRecorderField(hotkey: store.settings.hotkey, recorder: recorder) {
                            store.settings.hotkey = $0
                        }
                    }
                } label: {
                    Text("Open and close the notch")
                    Text("Works from any app.")
                }
                if let status {
                    Label(status.text, systemImage: status.symbol)
                        .font(.callout)
                        .foregroundStyle(status.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            } header: {
                Text("Global shortcut")
            } footer: {
                SectionFooter("Click the shortcut, then press a new combination with Control or Option. Esc cancels.")
            }

            Section {
                LabeledContent("Switch tabs") { KeyCaps(["←", "→"]) }
                LabeledContent("Close") { KeyCaps(["Esc"]) }
            } header: {
                Text("In the open notch")
            } footer: {
                SectionFooter("Two-finger swipes on the trackpad switch tabs too.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: paneWidth, height: 324)
        .onChange(of: recorder.isRecording) { _, recording in
            store.isRecordingHotkey = recording
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

/// Keys drawn as small key caps, for documenting fixed shortcuts.
private struct KeyCaps: View {
    let keys: [String]
    init(_ keys: [String]) { self.keys = keys }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22, minHeight: 20)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }
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
            Text("NotchDeck")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(versionText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)
            Text("Your MacBook notch, turned into a small deck of things you check all day.")
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

/// The app mark: a black screen corner with the notch and a lit tab, drawn
/// in code because the app ships without an asset catalog.
private struct AppGlyph: View {
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
            NotchShape(topRadius: 4, bottomRadius: 10)
                .fill(.black)
                .frame(width: 44, height: 16)
            HStack(spacing: 4) {
                ForEach([ModuleID.spotify, .system, .planner], id: \.self) { module in
                    Capsule()
                        .fill(Theme.Palette.accent(for: module))
                        .frame(width: 12, height: 4)
                }
            }
            .padding(.top, 40)
        }
        .frame(width: 80, height: 80)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}
