import AppKit
import SwiftUI
import TabbiKitCore
import TabbiKit

/// The scene the overlay shows, observable so a reply can turn the pet
/// around without rebuilding the window.
@MainActor
final class PetCoachOverlayModel: ObservableObject {
    @Published var scene: PetCoachScene
    /// The speech bubble's frame in the overlay's top-left coordinates, or
    /// nil while no bubble shows. Only this area takes clicks.
    var bubbleFrame: CGRect? {
        didSet { if bubbleFrame != oldValue { bubbleFrameChanged?() } }
    }
    /// Lets the window re-check the pointer when the bubble comes or goes.
    var bubbleFrameChanged: (() -> Void)?

    init(scene: PetCoachScene) {
        self.scene = scene
    }
}

/// The overlay's root: the live (clock-driven) coach scene, reporting where
/// its bubble is so the window can stay click-through everywhere else.
private struct PetCoachOverlayRoot: View {
    @ObservedObject var model: PetCoachOverlayModel
    let onReply: (PetCoachReply) -> Void

    var body: some View {
        PetCoachOverlayView(scene: model.scene, date: nil, onReply: onReply)
            .onPreferenceChange(PetCoachBubbleFrameKey.self) { frame in
                MainActor.assumeIsolated { model.bubbleFrame = frame }
            }
    }
}

/// A transparent, click-through window just below the menu bar with its
/// leading edge at the notch's right edge, where the coach's pet walks out.
///
/// It never activates the app or becomes key, so a nudge can't steal focus
/// from what the user is typing. Clicks pass through to the windows below
/// except over the speech bubble: a mouse-moved monitor (which needs no
/// permission, unlike key monitors) turns mouse events on only while the
/// pointer is over the bubble.
@MainActor
final class PetCoachOverlayWindow {
    private let panel: NSPanel
    private let model: PetCoachOverlayModel
    private var monitors: [Any] = []

    init(scene: PetCoachScene, geometry: NotchGeometry, onReply: @escaping (PetCoachReply) -> Void) {
        model = PetCoachOverlayModel(scene: scene)
        let size = PetCoachOverlayView.size(for: scene)
        // AppKit's origin is bottom-left: hang the overlay from the bottom
        // of the menu bar, i.e. the notch's bottom edge.
        let frame = CGRect(
            x: geometry.centerX + geometry.notchSize.width / 2 - PetCoachOverlayView.leadingOverhang(for: scene),
            y: geometry.screenFrame.maxY - geometry.notchSize.height - size.height,
            width: size.width,
            height: size.height
        )
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Over ordinary windows, under the notch panel (main menu + 3), so
        // the pet slips out from beneath the notch.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.contentView = NotchHostingView(rootView: PetCoachOverlayRoot(model: model, onReply: onReply))
        panel.setFrame(frame, display: false)
        model.bubbleFrameChanged = { [weak self] in self?.updateMouseTransparency() }
    }

    func show() {
        panel.orderFrontRegardless()
        let update: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseTransparency() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: update) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            update(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        panel.orderOut(nil)
        panel.close()
    }

    var stroll: PetCoachStroll { model.scene.stroll }

    /// Turns the pet around now, e.g. after the user answered.
    func dismiss(at date: Date) {
        model.scene.stroll.dismiss(at: date)
    }

    /// Takes clicks only while the pointer is over the bubble.
    private func updateMouseTransparency() {
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        // Flip into the view's top-left coordinates.
        let point = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
        let overBubble = model.bubbleFrame?.contains(point) ?? false
        if panel.ignoresMouseEvents == overBubble { panel.ignoresMouseEvents = !overBubble }
    }
}
