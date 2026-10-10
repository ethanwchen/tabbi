import AppKit
import Combine
import CoreImage
import ImageIO
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers
import TabbiKitCore
import TabbiKit

/// Records the App Store preview's footage from the running app:
///
///     TABBI_DEMO=1 swift run Tabbi --record <folder> --part opening|story
///                                  [--edition <id>] [--tabs <id,id,...>]
///
/// The real notch (`NotchView` with the app's modules, live demo stores,
/// ticking clocks and springs) plays a scripted storyboard in a window kept
/// behind the desktop, so nothing shows on the Mac's display. ScreenCaptureKit
/// records that one window as the window server draws it (Screen Recording
/// permission for the terminal that runs it), and each frame lands in
/// `<folder>/frame-NNNN.png` (transparent around the notch) next to
/// `frames.json`, which lists every frame's time in seconds, the
/// storyboard's beats and the recording's length. The stream only sends a frame when something
/// changed, so a frame lasts until the next one's time. That lets
/// `docs/appstore/make-media.swift` lay the footage on its stage and time
/// its captions. No pointer is drawn: the storyboard's clicks are the
/// app's own actions, so every move on screen is the app's.
///
/// The preview cuts from the first minutes of a Pomodoro to its last
/// seconds, so it is two recordings: `opening` (run with
/// `TABBI_DEMO_FOCUS_LEFT=1126`, so the notch opens on the Timer at 18:42,
/// ticking) and `story` (run with `TABBI_DEMO_FOCUS_LEFT=5`, so the block
/// ends about 3 s in, on camera, then every other tab in the store layout).
/// Record from a release build (`swift run -c release`): in a debug build
/// closing the notch stalls for about 2 s while the pet's clips are built,
/// and the clock freezes on camera.
@MainActor
enum PreviewRecorder {
    static let flag = "--record"
    static let framesPerSecond = 30.0

    /// One storyboard step: at `time` seconds, `action` runs, and a beat
    /// named `beat` (if any) starts, for captions to follow.
    struct Step {
        let time: TimeInterval
        var beat: String?
        let action: () -> Void
    }

    static func run(outputDirectory: URL, part: String, kitID: String, tabs: ModuleLayout?) async {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let services = AppServices(settings: .ephemeral(catalog: ModuleList.catalog(for: .current), kitID: kitID))
        if let tabs { services.settings.settings.modules = tabs }
        services.settings.settings.panelSize = .large
        // Beside the closed notch the pet only, as the storyboard has it,
        // so the demo calendar's meeting never takes its place.
        let catalog = services.settings.catalog
        services.settings.settings.notchPreview.disabledKinds = Set(TickerKind.all(in: catalog)).subtracting([.pet])
        Theme.apply(ThemeCatalog.resolve(services.settings.settings.themeID))

        // A 14"/16" MacBook Pro notch, as in the snapshots.
        let geometry = NotchGeometry(
            notchSize: CGSize(width: 185, height: 32), hasHardwareNotch: true,
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), centerX: 864
        )
        let model = NotchViewModel(geometry: geometry, layout: services.settings.settings.modules)
        model.panelSize = .large
        let inputs = ModuleViews.notchInputs(services: services)
        var cancellables: Set<AnyCancellable> = []
        inputs.preview.sink { model.preview = $0 }.store(in: &cancellables)
        // The closed notch's activity shows exactly while the notch is closed,
        // as `NotchController` does it.
        model.$phase.removeDuplicates().sink { inputs.previewVisible($0 != .open) }.store(in: &cancellables)

        // The open notch plus room for the open spring's overshoot, the size
        // of the app's own notch window.
        let size = CGSize(width: model.openSize.width + 96, height: model.openSize.height + 40)
        let host = NSHostingView(rootView: NotchView(content: ModuleViews.notchContent(services: services))
            .environmentObject(model)
            .environment(\.drawsLiquidGlass, false)
            .frame(width: size.width, height: size.height, alignment: .top))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.contentView = host
        // Behind the desktop picture: drawn by the window server, so it can
        // be recorded, but never seen on the Mac's display.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.setFrameOrigin(NSPoint(x: 0, y: 0))
        window.orderFrontRegardless()

        let steps = storyboard(part, model: model, services: services)
        // Let the modules start and load before the first frame.
        try? await Task.sleep(for: .seconds(part == "story" ? 1.5 : 3))
        let writer = FrameWriter(folder: outputDirectory)
        let stream: SCStream
        do {
            stream = try await startStream(of: window, size: size, writer: writer)
        } catch {
            print("Cannot record the notch window: \(error.localizedDescription). Give the terminal Screen Recording permission.")
            exit(1)
        }
        writer.start()
        let start = Date()
        var beats: [[String: Any]] = []
        for step in steps {
            let wait = start.addingTimeInterval(step.time).timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            step.action()
            if let beat = step.beat { beats.append(["name": beat, "time": step.time]) }
        }
        try? await stream.stopCapture()
        let times = writer.finish()
        let manifest: [String: Any] = [
            "part": part, "fps": framesPerSecond, "scale": scale,
            "notch": ["width": geometry.notchSize.width, "height": geometry.notchSize.height],
            "size": ["width": size.width, "height": size.height],
            "frames": times, "beats": beats, "length": steps.last?.time ?? 0,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: outputDirectory.appendingPathComponent("frames.json"))
        }
        print("\(times.count) frames in \(outputDirectory.path)")
        cancellables.removeAll()
    }

    /// Pixels per point of the recorded frames.
    private static let scale: CGFloat = 2

    /// Starts recording `window` alone, at 30 fps and `scale`, into `writer`.
    private static func startStream(of window: NSWindow, size: CGSize, writer: FrameWriter) async throws -> SCStream {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let shared = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width * scale)
        configuration.height = Int(size.height * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.backgroundColor = .clear
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: shared),
                              configuration: configuration, delegate: nil)
        try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
        try await stream.startCapture()
        return stream
    }

    /// The App Store preview's storyboard (`research/screenshots.md`), as the
    /// app's own actions. The last step's time is the recording's length.
    private static func storyboard(_ part: String, model: NotchViewModel, services: AppServices) -> [Step] {
        let today = services.modules.module(TodayModule.self)?.store
        let music = services.modules.module(NowPlayingModule.self)?.controller
        // Plain calls, as the app's clicks make them: the views animate.
        func open(_ id: ModuleID) { model.open(id) }
        func close() { model.close() }
        switch part {
        case "opening":
            // Closed notch, then the panel springs open on the ticking Timer.
            return [
                Step(time: 0, beat: "closed") {},
                Step(time: 0.5, beat: "timer") { open(.study) },
                Step(time: 4.0) {},
            ]
        default:
            let reading = today?.day.items.first { !$0.isDone }
            return [
                // The block ends on camera (TABBI_DEMO_FOCUS_LEFT), the
                // panel closes and the pet celebrates beside the notch.
                Step(time: 0, beat: "finish") { model.open(.study) },
                Step(time: 3.6) { close() },
                Step(time: 6.0, beat: "closet") { open(.closet) },
                Step(time: 10.0, beat: "today") { open(.planner) },
                Step(time: 11.3) {
                    if let reading { withMotion(Theme.Motion.snappy) { today?.toggle(reading.id) } }
                },
                // The demo plan takes about 1.5 s to arrive.
                Step(time: 13.0, beat: "tomorrow") { today?.show(.tomorrow) },
                Step(time: 13.4) { today?.planTomorrow() },
                // The demo track starts out liked; the like comes off out of
                // view, so the heart fills on camera.
                Step(time: 14.5) { if music?.status.playback?.track?.isFavorite == true { music?.toggleFavorite() } },
                Step(time: 16.1, beat: "music") { open(.spotify) },
                Step(time: 17.5) { music?.toggleFavorite() },
                Step(time: 18.9, beat: "flashcards") { open(.anki) },
                Step(time: 21.4, beat: "end") { close() },
                Step(time: 23.9) {},
            ]
        }
    }
}

/// Writes the stream's complete frames to PNG, numbered in order, with
/// their times since `start()`. Frames before `start()` are dropped.
private final class FrameWriter: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "preview.frames", qos: .userInitiated)
    private let folder: URL
    private let context = CIContext(options: [.outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any])
    /// Touched only on `queue`.
    private var times: [Double] = []
    private var startedAt: TimeInterval?

    init(folder: URL) { self.folder = folder }

    func start() {
        let now = CACurrentMediaTime()
        queue.sync { startedAt = now }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let startedAt, let pixels = buffer.imageBuffer,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue
        else { return }
        let time = buffer.presentationTimeStamp.seconds - startedAt
        guard time >= 0 else { return }
        let image = CIImage(cvPixelBuffer: pixels)
        let url = folder.appendingPathComponent(String(format: "frame-%04d.png", times.count))
        guard let cgImage = context.createCGImage(image, from: image.extent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return }
        times.append(time)
    }

    /// Every frame's time, once the last one is on disk.
    func finish() -> [Double] {
        queue.sync { times }
    }
}
