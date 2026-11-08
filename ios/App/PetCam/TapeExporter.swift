import AVFoundation
import CoreVideo
import SwiftUI
import TabbiKitCore

/// Exports a tape as a muted vertical video (1080 by 1920, 30 frames a
/// second, H.264, no audio track): each still with its burned-in time,
/// camera, captions and a small Tabbi mark, cut together with a few frames
/// of static. It never mentions studying, and the dodge line appears only
/// when the player opts in.
enum TapeExporter {
    static let size = CGSize(width: 1080, height: 1920)
    static let framesPerSecond: Int32 = 30

    enum ExportError: Error {
        case noTape
        case render
        case writer
    }

    /// Renders and encodes `record`'s tape; returns the file's URL in the
    /// temporary folder.
    @MainActor
    static func export(_ record: PetCamBlockRecord, caseNumber: Int?, includeDodge: Bool) async throws -> URL {
        guard let tape = PetCamTape(record: record), tape.outcome.hasTape else { throw ExportError.noTape }
        var segments: [Segment] = []
        for (index, still) in tape.stills.enumerated() {
            // Grain changes every few frames; the catch's freeze stands still.
            let variants = still.stamp == .caught ? 1 : 3
            var images: [CGImage] = []
            for grain in 0..<variants {
                let card = TapeCard(record: record, still: still, caseNumber: caseNumber, includeDodge: includeDodge,
                                    grainFrame: index * 16 + grain)
                images.append(try render(card))
            }
            // A jolt as a hard hit cuts in: the picture knocked aside and back.
            var jolt: [CGImage] = []
            if still.shake {
                for offset: CGFloat in [26, -20, 12, -6] {
                    jolt.append(try render(TapeCard(record: record, still: still, caseNumber: caseNumber,
                                                    includeDodge: includeDodge, grainFrame: index * 16, offset: offset)))
                }
            }
            segments.append(Segment(images: images, jolt: jolt,
                                    frames: Int((still.duration * Double(framesPerSecond)).rounded())))
        }
        let cut = try render(StaticCard())
        let stamp = Self.fileStamp(record.endedAt)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tabbi-tape-\(stamp).mp4")
        try? FileManager.default.removeItem(at: url)
        try await encode(segments, cut: cut, to: url)
        return url
    }

    struct Segment: @unchecked Sendable {
        let images: [CGImage]
        /// Frames for the jolt at the start, two video frames each.
        let jolt: [CGImage]
        let frames: Int
    }

    @MainActor
    private static func render<Content: View>(_ view: Content) throws -> CGImage {
        let renderer = ImageRenderer(content: view
            .environment(\.displayScale, 1)
            .environment(\.colorScheme, .dark)
            .frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.cgImage else { throw ExportError.render }
        return image
    }

    private static func fileStamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d%02d%02d-%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// Writes the frames: each segment's images in turn (cycling grain),
    /// with three frames of static at every cut.
    private nonisolated static func encode(_ segments: [Segment], cut: CGImage, to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        guard writer.canAdd(input) else { throw ExportError.writer }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError.writer }
        writer.startSession(atSourceTime: .zero)

        var frame: Int64 = 0
        func append(_ image: CGImage) async throws {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { throw ExportError.writer }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw ExportError.writer }
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { throw ExportError.writer }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(origin: .zero, size: size))
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: frame, timescale: framesPerSecond)) else {
                throw writer.error ?? ExportError.writer
            }
            frame += 1
        }
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                for _ in 0..<3 { try await append(cut) }
            }
            for step in 0..<segment.frames {
                if step / 2 < segment.jolt.count {
                    try await append(segment.jolt[step / 2])
                } else {
                    try await append(segment.images[(step / 4) % segment.images.count])
                }
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? ExportError.writer }
    }
}

/// One frame of the shared video: the still, its captions and the mark.
private struct TapeCard: View {
    let record: PetCamBlockRecord
    let still: PetCamTape.Still
    let caseNumber: Int?
    let includeDodge: Bool
    let grainFrame: Int
    /// Pixels the picture is knocked sideways (the jolt of a hard hit).
    var offset: CGFloat = 0

    /// The caption: the catch's charge carries the dodge line only on
    /// opt-in.
    private var caption: String {
        guard still.stamp == .caught else { return still.caption }
        return (includeDodge ? record.captions.charge : record.captions.publicCharge) ?? still.caption
    }

    var body: some View {
        VStack(spacing: 0) {
            TapeStillView(record: record, still: still, caseNumber: caseNumber, width: 1000, publicOnly: !includeDodge,
                          frozen: still.stamp == .caught, grainFrame: still.stamp == .caught ? 0 : grainFrame,
                          burnInSize: 30)
                .offset(x: offset)
                .padding(.top, 70)
            VStack(spacing: 14) {
                Text(verbatim: caption)
                    .font(.system(size: 50, weight: .bold, design: .monospaced))
                    .foregroundStyle(CCTV.burnIn)
                if let detail = still.detail {
                    Text(verbatim: detail)
                        .font(.system(size: 34, weight: .medium, design: .monospaced))
                        .foregroundStyle(CCTV.burnIn.opacity(0.75))
                }
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 50)
            .padding(.top, 34)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Spacer()
                Image(systemName: "pawprint.fill")
                Text(verbatim: "tabbi")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
            }
            .foregroundStyle(CCTV.burnIn.opacity(0.55))
            .padding(.horizontal, 44)
            .padding(.bottom, 34)
        }
        .frame(width: TapeExporter.size.width, height: TapeExporter.size.height)
        .background(CCTV.screen)
    }
}

/// The few frames of static at a cut.
private struct StaticCard: View {
    var body: some View {
        StaticGrain(frame: 7, amount: 0.5)
            .background(Color(white: 0.16))
            .frame(width: TapeExporter.size.width, height: TapeExporter.size.height)
    }
}
