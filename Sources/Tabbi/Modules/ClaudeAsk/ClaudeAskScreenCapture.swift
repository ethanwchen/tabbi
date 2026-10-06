import AppKit
import CoreGraphics
import ScreenCaptureKit
import TabbiKitCore

/// Takes the screenshot Ask Claude sends with a question, through
/// ScreenCaptureKit. Tabbi's own windows (the notch panel) are left out of
/// the capture, so the open notch never covers what the user wants to ask
/// about and never flickers away and back.
enum ClaudeAskScreenCapture {
    /// A PNG scaled to `ClaudeAskAttachment.maxLongEdge`, ready to stage.
    struct Capture: Sendable {
        let pngData: Data
        let pixelWidth: Int
        let pixelHeight: Int
    }

    enum Failure: Error {
        case noDisplay
        case encoding
    }

    /// True once the user allowed Screen Recording for Tabbi. Checking never
    /// shows a system prompt.
    static var hasAccess: Bool { CGPreflightScreenCaptureAccess() }

    /// Adds Tabbi to the Screen Recording list (asking with the system
    /// prompt the first time), so the user only has to flip its switch.
    @discardableResult
    static func requestAccess() -> Bool { CGRequestScreenCaptureAccess() }

    /// Privacy & Security > Screen & System Audio Recording in System Settings.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    /// Captures the display the pointer is on (where the user just clicked
    /// the notch), without Tabbi's windows or the cursor.
    static func captureDisplay() async throws -> Capture {
        let displayID = await MainActor.run { pointerDisplayID() }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw Failure.noDisplay
        }
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let tabbi = content.applications.filter { $0.processID == ownProcess }
        let filter = SCContentFilter(display: display, excludingApplications: tabbi, exceptingWindows: [])

        let scale = CGFloat(filter.pointPixelScale)
        let size = ClaudeAskAttachment.fittedPixelSize(
            width: Int((filter.contentRect.width * scale).rounded()),
            height: Int((filter.contentRect.height * scale).rounded())
        )
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw Failure.encoding
        }
        return Capture(pngData: png, pixelWidth: image.width, pixelHeight: image.height)
    }

    @MainActor
    private static func pointerDisplayID() -> CGDirectDisplayID? {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

extension ClaudeAskScreenCapture {
    /// A made-up screenshot (a window with a title bar and a few lines of
    /// text on a desktop) for demo and snapshot runs, which never record
    /// the real screen.
    static func demoCapture() -> Capture? {
        let width = 1440, height = 900
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSGradient(starting: NSColor(red: 0.20, green: 0.27, blue: 0.48, alpha: 1),
                   ending: NSColor(red: 0.55, green: 0.38, blue: 0.62, alpha: 1))?
            .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 60)
        let window = NSRect(x: 220, y: 140, width: 1000, height: 620)
        NSColor(white: 0.97, alpha: 1).setFill()
        NSBezierPath(roundedRect: window, xRadius: 20, yRadius: 20).fill()
        NSColor(white: 0.88, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: window.minX, y: window.maxY - 56, width: window.width, height: 36)).fill()
        NSBezierPath(roundedRect: NSRect(x: window.minX, y: window.maxY - 56, width: window.width, height: 56),
                     xRadius: 20, yRadius: 20).fill()
        for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: window.minX + 24 + CGFloat(index) * 28, y: window.maxY - 36, width: 16, height: 16)).fill()
        }
        NSColor(white: 0.80, alpha: 1).setFill()
        for line in 0..<9 {
            let lineWidth = [820, 760, 880, 540, 0, 800, 700, 860, 420][line]
            guard lineWidth > 0 else { continue }
            NSBezierPath(roundedRect: NSRect(x: window.minX + 60, y: window.maxY - 120 - CGFloat(line) * 52,
                                             width: CGFloat(lineWidth), height: 18),
                         xRadius: 9, yRadius: 9).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return Capture(pngData: png, pixelWidth: width, pixelHeight: height)
    }
}
