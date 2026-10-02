import AppKit
import Combine
import SwiftUI

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
    private var pointerInside = false
    private var horizontalScroll: CGFloat = 0

    /// Extra room around the open notch for its shadow.
    private static let canvasMargin = CGSize(width: 48, height: 40)

    init(services: AppServices) {
        self.services = services
        let screen = NotchGeometry.preferredScreen()
        let geometry = screen.map(NotchGeometry.measure) ?? NotchGeometry(
            notchSize: CGSize(width: 190, height: 32), hasHardwareNotch: false,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), centerX: 720
        )
        model = NotchViewModel(geometry: geometry)
        panel = NotchPanel(contentRect: .zero)

        let root = NotchView()
            .environmentObject(model)
            .environmentObject(services)
        panel.contentView = NotchHostingView(rootView: root)
        layoutPanel()
        panel.orderFrontRegardless()

        installMonitors()
        observeState()
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
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            model.setHovering(true)
        } else if model.isOpen {
            scheduleClose()
        } else {
            model.setHovering(false)
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
        guard model.isOpen else { return false }
        let editingText = panel.firstResponder is NSTextView
        switch event.keyCode {
        case 53: // esc
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

        services.$hasCompactActivity
            .removeDuplicates()
            .sink { [weak self] active in self?.model.hasCompactActivity = active }
            .store(in: &cancellables)
    }

    private func screensChanged() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        model.geometry = NotchGeometry.measure(screen)
        layoutPanel()
    }
}
