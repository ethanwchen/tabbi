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
    private var swipe = TabSwipe()
    private var previewSwipe = TickerSwipe()
    private var hotkey: GlobalHotkey?
    /// The display the notch is on; nil while no screen qualifies.
    private var displayID: CGDirectDisplayID?
    private var fullscreenAppActive = false
    /// The shortcut brought the notch back over a fullscreen app until it closes.
    private var revealed = false
    private var fullscreenCheckTask: Task<Void, Never>?
    /// The pointer is reaching for a `.showOnHover` notch.
    private var pointerNear = false
    /// Whether the panel is meant to be on screen. It stays ordered in for
    /// the length of the fade out, so `panel.isVisible` lags behind this.
    private var isShown = false

    /// Extra room around the open notch, so the open spring's stretch past
    /// its final size is never cut off by the panel's edge.
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
        model.panelSize = settings.panelSize
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

    /// Sizes the transparent panel for the current open size. It grows
    /// before a larger canvas springs open and only shrinks when `shrink`
    /// says so (a screen change), so giving the canvas back is never cut
    /// off mid-animation. Pointer events outside the shape pass through.
    private func layoutPanel(shrink: Bool = true) {
        let g = model.geometry
        var size = CGSize(
            width: model.openSize.width + Self.canvasMargin.width * 2,
            height: model.openSize.height + Self.canvasMargin.height
        )
        if !shrink {
            size.width = max(size.width, panel.frame.width)
            size.height = max(size.height, panel.frame.height)
        }
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

        // A middle-click on the closed notch shows the next live activity.
        if let middle = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown, handler: { [weak self] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.buttonNumber == 2, event.window === self.panel, !self.model.isOpen else { return false }
                self.cyclePreview()
                return true
            }
            return consumed ? nil : event
        }) { monitors.append(middle) }

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
        updatePointerNear()
        guard isShown else { return }
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

    /// The hardware notch's rect (or where it would be on a notchless
    /// screen) in screen coordinates, which the hover zone grows from.
    private var closedNotchRect: CGRect {
        let g = model.geometry
        return CGRect(x: g.centerX - g.notchSize.width / 2, y: g.screenFrame.maxY - g.notchSize.height,
                      width: g.notchSize.width, height: g.notchSize.height)
    }

    /// Brings a `.showOnHover` notch out when the pointer reaches the
    /// top-center hot zone and puts it away once the pointer leaves it and
    /// the drawn shape.
    private func updatePointerNear() {
        let near = settings.notchMode == .showOnHover && NotchVisibility.isPointerNear(
            NSEvent.mouseLocation,
            hoverZone: NotchVisibility.hoverZone(closedNotch: closedNotchRect),
            drawnShape: isShown ? hitRect : nil
        )
        guard near != pointerNear else { return }
        pointerNear = near
        updateVisibility()
    }

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
        case 53 where model.isEnlarged: // esc gives a larger canvas back first, even while typing
            model.requestOpenSize(nil)
            return true
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
            // Number keys 1-9 jump straight to a tab and a header module's
            // letter (P for the pet) opens it. Read the typed character rather
            // than the key code so numpad digits and other layouts work; with
            // ⌘/⌃/⌥ held the key belongs to someone else.
            guard !editingText,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let characters = event.charactersIgnoringModifiers, characters.count == 1 else { return false }
            if let number = Int(characters) { return model.select(shortcut: number) }
            return model.select(headerKey: characters)
        }
    }

    /// A two-finger horizontal swipe moves one tab; on the closed notch a
    /// swipe down shows the next live activity.
    private func handleScroll(_ event: NSEvent) {
        guard model.isOpen || (pointerInside && model.preview != nil) else { return }
        let phase: TabSwipe.Phase
        if !event.momentumPhase.isEmpty {
            phase = .momentum
        } else if event.phase.contains(.began) {
            phase = .began
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            phase = .ended
        } else {
            phase = event.phase.isEmpty ? .none : .changed
        }
        guard model.isOpen else {
            // With natural scrolling the content follows the fingers, so a
            // positive delta is a swipe down; otherwise it is inverted.
            let down = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
            if previewSwipe.feed(deltaX: event.scrollingDeltaX, fingersDown: down, phase: phase) { cyclePreview() }
            return
        }
        switch swipe.feed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, phase: phase) {
        case .previous: model.selectPrevious()
        case .next: model.selectNext()
        case nil: break
        }
    }

    /// Shows the next live activity with a light tick, and gives an
    /// open-on-hover notch its full wait again so cycling doesn't open it.
    private func cyclePreview() {
        guard inputs.cyclePreview() else { return }
        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        if settings.openOnHover, pointerInside { scheduleHoverOpen() }
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

        // Closing the notch ends a shortcut reveal (over a fullscreen app, or
        // of a notch the mode hides) and puts a hover or hidden notch away.
        model.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                guard let self, phase != .open else { return }
                self.revealed = false
                // Published before the change lands, so read `isOpen` next turn.
                Task { @MainActor in self.updateVisibility() }
            }
            .store(in: &cancellables)

        model.$requestedOpenSize
            .removeDuplicates()
            .sink { [weak self] _ in
                // Published before the change lands, so read the new size next turn.
                Task { @MainActor in self?.layoutPanel(shrink: false) }
            }
            .store(in: &cancellables)

        inputs.settings
            .map(\.panelSize)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] size in
                guard let self else { return }
                self.model.panelSize = size
                // An open notch springs to its new size, so the panel only
                // grows then; a closed one fits the new size right away.
                self.layoutPanel(shrink: !self.model.isOpen)
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
            .map(\.notchMode)
            .removeDuplicates()
            .sink { [weak self] mode in self?.model.notchMode = mode }
            .store(in: &cancellables)

        inputs.settings
            .map(\.hotkey)
            .removeDuplicates()
            .sink { [weak self] hotkey in self?.model.hotkey = hotkey }
            .store(in: &cancellables)

        inputs.settings
            .map { VisibilityChoice(hideInFullscreen: $0.hideInFullscreen, mode: $0.notchMode) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // `$settings` publishes before the change lands, so read the
                // new settings next turn. The pointer is re-tested under the
                // new mode, so a stale hover state never lingers.
                Task { @MainActor in
                    self?.updatePointerNear()
                    self?.updateVisibility()
                }
            }
            .store(in: &cancellables)

        inputs.settings
            .map { PrivacyChoice(hideFromScreenCapture: $0.hideFromScreenCapture,
                                 hideInMissionControl: $0.hideInMissionControl) }
            .removeDuplicates()
            .sink { [weak self] choice in
                self?.panel.applyPrivacy(hideFromScreenCapture: choice.hideFromScreenCapture,
                                         hideInMissionControl: choice.hideInMissionControl)
            }
            .store(in: &cancellables)

        inputs.preview
            .removeDuplicates()
            .sink { [weak self] item in self?.model.preview = item }
            .store(in: &cancellables)

        inputs.takeover
            .removeDuplicates()
            .sink { [weak self] active in self?.model.showsTakeover = active }
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

    /// The shortcut also brings the notch back while a fullscreen app or the
    /// notch mode hides it.
    private func hotkeyPressed() {
        if !isShown && displayID != nil && !model.isOpen {
            revealed = true
            updateVisibility()
        }
        model.toggle(fromKeyboard: true)
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
            mode: settings.notchMode,
            hideInFullscreen: settings.hideInFullscreen,
            fullscreenAppActive: fullscreenAppActive,
            revealed: revealed,
            pointerNear: pointerNear,
            isOpen: model.isOpen
        )
        guard shown != isShown else { return }
        isShown = shown
        if shown {
            if !panel.isVisible { panel.alphaValue = 0 }
            panel.orderFrontRegardless()
            fade(to: 1)
        } else {
            model.close()
            model.setHovering(false)
            pointerInside = false
            panel.ignoresMouseEvents = true
            fade(to: 0) { [weak self] in
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    /// Fades the panel in or out, or jumps straight there under Reduce Motion.
    private func fade(to alpha: CGFloat, completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }

    /// Long enough to read as the notch arriving, short enough that the
    /// pointer never waits for it.
    private static let fadeDuration: TimeInterval = 0.18

    /// Checks now and twice more as the Space switch animation settles,
    /// since the window list lags behind the notification (mid-animation it
    /// can still show the old Space's windows).
    private func scheduleFullscreenCheck() {
        fullscreenCheckTask?.cancel()
        fullscreenCheckTask = Task { [weak self] in
            for delay in [Duration.zero, .milliseconds(700), .milliseconds(800)] {
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

/// The settings that decide whether the closed notch is drawn.
private struct VisibilityChoice: Equatable {
    var hideInFullscreen: Bool
    var mode: NotchMode
}

/// The settings that keep the notch out of screen captures and Mission Control.
private struct PrivacyChoice: Equatable {
    var hideFromScreenCapture: Bool
    var hideInMissionControl: Bool
}
