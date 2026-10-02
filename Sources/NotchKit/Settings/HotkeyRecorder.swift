import AppKit
import SwiftUI
import NotchKitCore

/// Captures the next key combination typed into the Settings window.
///
/// Uses a local `NSEvent` monitor, so it only sees keys while Settings is the
/// key window and needs no Accessibility permission. Recording stops when a
/// shortcut is accepted, on Esc, or when the window loses focus. While it
/// records, the app should suspend its global hotkey, which `start` reports
/// through `onRecordingChange` so this type needs no app settings store.
@MainActor
public final class HotkeyRecorder: ObservableObject {
    @Published public private(set) var isRecording = false
    /// Modifiers currently held, shown live while recording.
    @Published public private(set) var heldModifiers: Hotkey.Modifiers = []
    /// Why the last key press was refused, cleared on the next press.
    @Published public private(set) var rejection: Hotkey.Recording?

    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var onRecord: ((Hotkey) -> Void)?
    private var onRecordingChange: ((Bool) -> Void)?

    public init() {}

    /// Starts recording. `onRecordingChange` is called with `true` now and
    /// `false` when recording stops; `onRecord` gets the accepted shortcut.
    public func start(onRecordingChange: @escaping (Bool) -> Void, onRecord: @escaping (Hotkey) -> Void) {
        guard !isRecording else { return }
        self.onRecordingChange = onRecordingChange
        self.onRecord = onRecord
        isRecording = true
        onRecordingChange(true)
        heldModifiers = Hotkey.Modifiers(NSEvent.modifierFlags)
        rejection = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            // Local monitors run on the main thread.
            MainActor.assumeIsolated { self?.consume(event) ?? false } ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    public func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        onRecord = nil
        isRecording = false
        onRecordingChange?(false)
        onRecordingChange = nil
        heldModifiers = []
        rejection = nil
    }

    /// Swallows every key while recording so nothing reaches the focused control.
    private func consume(_ event: NSEvent) -> Bool {
        let modifiers = Hotkey.Modifiers(event.modifierFlags)
        if event.type == .flagsChanged {
            heldModifiers = modifiers
            return true
        }
        // Holding a key down repeats; only the first press counts.
        guard !event.isARepeat else { return true }
        switch Hotkey.record(keyCode: UInt32(event.keyCode), modifiers: modifiers) {
        case .recorded(let hotkey):
            let onRecord = onRecord
            stop()
            onRecord?(hotkey)
        case .cancelled:
            stop()
        case let refusal:
            rejection = refusal
            NSSound.beep()
        }
        return true
    }
}

extension Hotkey.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }
}

/// The clickable shortcut field: shows the current shortcut as key caps and
/// switches to a highlighted recording state when clicked.
public struct HotkeyRecorderField: View {
    let hotkey: Hotkey
    @ObservedObject var recorder: HotkeyRecorder
    let onRecordingChange: (Bool) -> Void
    let onRecord: (Hotkey) -> Void
    @State private var hovering = false

    public init(
        hotkey: Hotkey,
        recorder: HotkeyRecorder,
        onRecordingChange: @escaping (Bool) -> Void,
        onRecord: @escaping (Hotkey) -> Void
    ) {
        self.hotkey = hotkey
        self.recorder = recorder
        self.onRecordingChange = onRecordingChange
        self.onRecord = onRecord
    }

    public var body: some View {
        Button {
            if recorder.isRecording {
                recorder.stop()
            } else {
                recorder.start(onRecordingChange: onRecordingChange, onRecord: onRecord)
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(recorder.isRecording ? .secondary : .primary)
                .frame(minWidth: 112)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: recorder.isRecording ? 2 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: recorder.isRecording)
        .help(recorder.isRecording ? "Press a new shortcut, or Esc to cancel" : "Click to record a new shortcut")
        .accessibilityLabel("Shortcut \(hotkey.displayString)")
    }

    private var label: String {
        guard recorder.isRecording else { return hotkey.displayString }
        let held = recorder.heldModifiers.symbols
        return held.isEmpty ? "Type shortcut" : held + "…"
    }

    private var borderColor: Color {
        if recorder.isRecording { return .accentColor }
        return Color(nsColor: hovering ? .tertiaryLabelColor : .separatorColor)
    }
}
