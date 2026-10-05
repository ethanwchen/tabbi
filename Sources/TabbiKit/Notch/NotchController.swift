import AppKit
import Combine
import SwiftUI
import TabbiKitCore

/// Owns the notch panel: positions it, tracks the pointer, and translates
/// mouse/keyboard input into NotchViewModel state changes. The app supplies
/// what the notch shows (`NotchContent`) and the state it follows
/// (`NotchInputs`), so this works for any edition or kit.
@MainActor
public final class NotchController {
    public let model: NotchViewModel
    private let inputs: NotchInputs
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var cancellables: Set<AnyCancellable> = []
    private var closeTask: Task<Void, Never>?
    private var hoverOpenTask: Task<Void, Never>?
    private var pointerInside = false
    private var horizontalScroll: CGFloat = 0
    private var hotkey: GlobalHotkey?
    /// The display the notch is on; nil while no screen qualifies.
    private var displayID: CGDirectDisplayID?
    private var fullscreenAppActive = false
    /// The shortcut brought the notch back over a fullscreen app until it closes.
    private var revealed = false
    private var fullscreenCheckTask: Task<Void, Never>?

    /// Extra room around the open notch for its shadow.
    private static let canvasMargin = CGSize(width: 48, height: 40)

    public init(content: NotchContent, inputs: NotchInputs) {
        self.inputs = inputs
        let settings = inputs.currentSettings()
        Theme.apply(ThemeCatalog.resolve(settings.themeID))
        let screen = NotchGeometry.screen(for: settings.preferredDisplay,
                                          showOnExternalDisplays: settings.showOnExternalDisplays)
        let geometry = screen.map(NotchGeometry.measure) ?? NotchGeometry(
            notchSize: CGSize(width: 190, height: 32), hasHardwareNotch: false,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), centerX: 720
        )
        model = NotchViewModel(geometry: geometry, layout: settings.modules)
        panel = NotchPanel(contentRect: .zero)

        let root = NotchView(content: content)
            .environmentObject(model)
        panel.contentView = NotchHostingView(rootView: root)
        displayID = screen?.displayID
        layoutPanel()
        fullscreenAppActive = detectFullscreenApp()
        updateVisibility()

        installMonitors()
        observeState()
        observeHotkey()
    }

    // MARK: Layout

    private func layoutPanel() {
        let g = model.geometry
        let size = CGSize(
            width: Theme.Layout.expandedSize.width + Self.canvasMargin.width * 2,
            height: Theme.Layout.expandedSize.height + Self.canvasMargin.height
        )
        panel.setFrame(
            CGRect(x: g.centerX - size.width / 2, y: g.screenFrame.maxY - size.height,
                   width: size.width, height: size.height),
            display: true
        )
    }

    /// The visible notch shape in global screen coordinates.
    private var hitRect: CGRect {
        let g = model.geometry
        let size = model.size
        return CGRect(x: g.centerX - size.width / 2, y: g.screenFrame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    // MARK: Input

    private func installMonitors() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) { monitors.append(local) }

        // Clicks elsewhere close the notch.
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.isOpen else { return }
                self.model.close()
            }
        }) { monitors.append(outside) }
        // Global monitors never see our own windows, so clicks in Settings
        // need a local monitor to close the notch the same way.
        if let ownWindows = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.model.isOpen, event.window !== self.panel else { return }
                self.model.close()
            }
            return event
        }) { monitors.append(ownWindows) }

        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) ?? false } ? nil : event
        }) { monitors.append(keys) }

        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleScroll(event) }
            return event
        }) { monitors.append(scroll) }

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            }
            .store(in: &cancellables)

        // A fullscreen app arrives with a Space change or an app switch, so
        // these events are enough; no polling.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.publisher(for: name)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleFullscreenCheck() }
                }
                .store(in: &cancellables)
        }
    }

    private func pointerMoved() {
        guard panel.isVisible else { return }
        let inside = hitRect.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        guard inside != pointerInside else { return }
        pointerInside = inside

        if inside {
            closeTask?.cancel()
            if !model.isOpen {
                if settings.hapticsEnabled {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                if settings.openOnHover { scheduleHoverOpen() }
            }
            model.setHovering(true)
            return
        }
        hoverOpenTask?.cancel()
        if model.isOpen {
            scheduleClose()
        } else {
            model.setHovering(false)
        }
    }

    private var settings: AppSettings { inputs.currentSettings() }

    /// Opens the notch once the pointer has rested on it for `hoverOpenDelay`,
    /// so merely passing over the menu bar doesn't pop it open.
    private func scheduleHoverOpen() {
        hoverOpenTask?.cancel()
        hoverOpenTask = Task { [weak self] in
            try? await Task.sleep(for: AppSettings.hoverOpenDelay)
            guard let self, !Task.isCancelled, self.pointerInside, !self.model.isOpen else { return }
            self.model.open()
        }
    }

    private func scheduleClose() {
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled, !self.pointerInside, !self.model.isPinned else { return }
            self.model.close()
        }
    }

    /// Returns true when the key was consumed.
    private func handleKey(_ event: NSEvent) -> Bool {
        // Keys typed into the Settings window (e.g. the Claude path field) are not ours.
        guard model.isOpen, event.window === panel else { return false }
        let editingText = panel.firstResponder is NSTextView
        switch event.keyCode {
        case 53 where !editingText: // esc (text fields handle it themselves, e.g. to clear)
            model.close()
            return true
        case 123 where !editingText: // left arrow
            model.selectPrevious()
            return true
        case 124 where !editingText: // right arrow
            model.selectNext()
            return true
        default:
            // Number keys 1-9 jump straight to a tab. Read the typed character
            // rather than the key code so numpad digits and other layouts work;
            // with ⌘/⌃/⌥ held the key belongs to someone else.
            guard !editingText,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let characters = event.charactersIgnoringModifiers, characters.count == 1,
                  let number = Int(characters) else { return false }
            return model.select(shortcut: number)
        }
    }

    /// Two-finger horizontal swipe cycles modules.
    private func handleScroll(_ event: NSEvent) {
        guard model.isOpen, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
        if event.phase == .began { horizontalScroll = 0 }
        horizontalScroll += event.scrollingDeltaX
        if horizontalScroll > 60 {
            model.selectPrevious()
            horizontalScroll = -.infinity // one step per gesture
        } else if horizontalScroll < -60 {
            model.selectNext()
            horizontalScroll = .infinity
        }
        if event.phase == .ended || event.phase == .cancelled { horizontalScroll = 0 }
    }

    // MARK: State

    private func observeState() {
        model.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                guard let self else { return }
                if phase == .open {
                    self.panel.makeKey()
                } else if self.panel.isKeyWindow {
                    self.panel.resignKey()
                }
            }
            .store(in: &cancellables)

        // Closing the notch ends a shortcut reveal over a fullscreen app.
        model.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                guard let self, phase != .open, self.revealed else { return }
                self.revealed = false
                self.updateVisibility()
            }
            .store(in: &cancellables)

        model.$isPinned
            .removeDuplicates()
            .sink { [weak self] pinned in
                guard let self, !pinned, self.model.isOpen, !self.pointerInside else { return }
                self.scheduleClose()
            }
            .store(in: &cancellables)

        inputs.settings
            .map(\.modules)
            .removeDuplicates()
            .sink { [weak self] layout in self?.model.layout = layout }
            .store(in: &cancellables)

        inputs.settings
            .map(\.themeID)
            .removeDuplicates()
            .sink { [weak self] id in
                Theme.apply(ThemeCatalog.resolve(id))
                self?.model.themeID = id
            }
            .store(in: &cancellables)

        inputs.settings
            .map { DisplayChoice(preference: $0.preferredDisplay, showOnExternalDisplays: $0.showOnExternalDisplays) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.screensChanged() }
            .store(in: &cancellables)

        inputs.settings
            .map(\.hideInFullscreen)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.updateVisibility() }
            .store(in: &cancellables)

        inputs.preview
            .removeDuplicates()
            .sink { [weak self] item in self?.model.preview = item }
            .store(in: &cancellables)

        // The preview only ticks while it can be seen.
        model.$phase
            .removeDuplicates()
            .sink { [weak self] phase in self?.inputs.previewVisible(phase != .open) }
            .store(in: &cancellables)
    }

    /// The global shortcut toggles the notch from anywhere, re-registered
    /// whenever the user records a new one and paused while they record.
    private func observeHotkey() {
        let hotkey = GlobalHotkey { [weak self] in self?.hotkeyPressed() }
        self.hotkey = hotkey
        inputs.settings
            .map(\.hotkey)
            .removeDuplicates()
            .combineLatest(inputs.isRecordingHotkey.removeDuplicates())
            .sink { [weak self] shortcut, recording in
                if recording {
                    hotkey.unregister()
                } else {
                    self?.inputs.hotkeyRegistered(hotkey.register(shortcut))
                }
            }
            .store(in: &cancellables)
    }

    /// The shortcut also brings the notch back while a fullscreen app hides it.
    private func hotkeyPressed() {
        if !panel.isVisible && displayID != nil && !model.isOpen {
            revealed = true
            updateVisibility()
        }
        model.toggle()
    }

    private func screensChanged() {
        reposition()
        scheduleFullscreenCheck()
    }

    /// Moves the notch to the screen the display settings resolve to. Closes
    /// it first so it never animates open across two displays, and hides it
    /// when no screen qualifies.
    private func reposition() {
        let settings = settings
        let screen = NotchGeometry.screen(for: settings.preferredDisplay,
                                          showOnExternalDisplays: settings.showOnExternalDisplays)
        displayID = screen?.displayID
        defer { updateVisibility() }
        guard let screen else { return }
        let geometry = NotchGeometry.measure(screen)
        guard geometry != model.geometry else { return }
        model.close()
        model.geometry = geometry
        layoutPanel()
    }

    // MARK: Visibility

    /// Shows or hides the panel per `NotchVisibility`. The closed notch's
    /// black shape is drawn by the panel, so hiding it leaves the hardware
    /// notch (or nothing, on a notchless screen) and a fullscreen app untouched.
    private func updateVisibility() {
        let shown = displayID != nil && NotchVisibility.isShown(
            hideInFullscreen: settings.hideInFullscreen,
            fullscreenAppActive: fullscreenAppActive,
            revealed: revealed
        )
        guard shown != panel.isVisible else { return }
        if shown {
            panel.orderFrontRegardless()
        } else {
            model.close()
            model.setHovering(false)
            pointerInside = false
            panel.orderOut(nil)
        }
    }

    /// Checks now and again once the Space switch animation has settled,
    /// since the window list lags behind the notification.
    private func scheduleFullscreenCheck() {
        fullscreenCheckTask?.cancel()
        fullscreenCheckTask = Task { [weak self] in
            for delay in [Duration.zero, .milliseconds(700)] {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                let active = self.detectFullscreenApp()
                guard active != self.fullscreenAppActive else { continue }
                self.fullscreenAppActive = active
                self.updateVisibility()
            }
        }
    }

    /// Reads on-screen window bounds and levels (no Screen Recording
    /// permission needed) and asks `NotchVisibility` whether one covers the
    /// notch's display.
    private func detectFullscreenApp() -> Bool {
        guard let displayID,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let windows = list.compactMap { info -> NotchVisibility.Window? in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { return nil }
            return NotchVisibility.Window(ownerPID: pid, layer: layer,
                                          alpha: info[kCGWindowAlpha as String] as? Double ?? 1, bounds: bounds)
        }
        return NotchVisibility.isFullscreenAppActive(windows: windows, displayBounds: CGDisplayBounds(displayID),
                                                     ownPID: ProcessInfo.processInfo.processIdentifier)
    }
}

/// The display settings that decide which screen the notch is on.
private struct DisplayChoice: Equatable {
    var preference: DisplayPreference
    var showOnExternalDisplays: Bool
}
