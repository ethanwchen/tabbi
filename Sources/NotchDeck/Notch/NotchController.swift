import AppKit
import Combine
import SwiftUI
import NotchDeckCore

/// Owns the notch panel: positions it, tracks the pointer, and translates
/// mouse/keyboard input into NotchViewModel state changes.
@MainActor
final class NotchController {
    let model: NotchViewModel
    let services: AppServices
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var cancellables: Set<AnyCancellable> = []
    private var closeTask: Task<Void, Never>?
    private var hoverOpenTask: Task<Void, Never>?
    private var pointerInside = false
    private var horizontalScroll: CGFloat = 0
    private var hotkey: GlobalHotkey?

    /// Extra room around the open notch for its shadow.
    private static let canvasMargin = CGSize(width: 48, height: 40)

    init(services: AppServices) {
        self.services = services
        let settings = services.settings.settings
        let screen = NotchGeometry.screen(for: settings.preferredDisplay)
        let geometry = screen.map(NotchGeometry.measure) ?? NotchGeometry(
            notchSize: CGSize(width: 190, height: 32), hasHardwareNotch: false,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), centerX: 720
        )
        model = NotchViewModel(geometry: geometry, layout: settings.modules)
        panel = NotchPanel(contentRect: .zero)

        let root = NotchView()
            .environmentObject(model)
            .environmentObject(services)
        panel.contentView = NotchHostingView(rootView: root)
        layoutPanel()
        panel.orderFrontRegardless()

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
    }

    private func pointerMoved() {
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

    private var settings: AppSettings { services.settings.settings }

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
            return false
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

        model.$isPinned
            .removeDuplicates()
            .sink { [weak self] pinned in
                guard let self, !pinned, self.model.isOpen, !self.pointerInside else { return }
                self.scheduleClose()
            }
            .store(in: &cancellables)

        services.settings.$settings
            .map(\.modules)
            .removeDuplicates()
            .sink { [weak self] layout in self?.model.layout = layout }
            .store(in: &cancellables)

        services.settings.$settings
            .map(\.preferredDisplay)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] preference in self?.reposition(on: preference) }
            .store(in: &cancellables)

        services.$hasCompactActivity
            .removeDuplicates()
            .sink { [weak self] active in self?.model.hasCompactActivity = active }
            .store(in: &cancellables)
    }

    /// The global shortcut toggles the notch from anywhere, re-registered
    /// whenever the user records a new one and paused while they record.
    private func observeHotkey() {
        let hotkey = GlobalHotkey { [weak self] in self?.model.toggle() }
        self.hotkey = hotkey
        services.settings.$settings
            .map(\.hotkey)
            .removeDuplicates()
            .combineLatest(services.settings.$isRecordingHotkey.removeDuplicates())
            .sink { [weak self] shortcut, recording in
                if recording {
                    hotkey.unregister()
                } else {
                    self?.services.settings.hotkeyIsRegistered = hotkey.register(shortcut)
                }
            }
            .store(in: &cancellables)
    }

    private func screensChanged() {
        reposition(on: settings.preferredDisplay)
    }

    /// Moves the notch to the screen `preference` resolves to. Closes it first
    /// so it never animates open across two displays.
    private func reposition(on preference: DisplayPreference) {
        guard let screen = NotchGeometry.screen(for: preference) else { return }
        let geometry = NotchGeometry.measure(screen)
        guard geometry != model.geometry else { return }
        model.close()
        model.geometry = geometry
        layoutPanel()
    }
}
