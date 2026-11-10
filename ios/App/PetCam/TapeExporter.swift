import AVFoundation
import CoreVideo
import SwiftUI
import TabbiKitCore

/// Exports a tape's share clip (`PetCamTape.clip`) as a vertical video
/// (1080 by 1920, 30 frames a second, H.264 with an AAC sound track) of
/// about five seconds that loops. It opens on the strike with its sound,
/// cuts to the eye contact with a push-in, slams the stamp in with a
/// two-frame flash and a jolt by about 3.5 seconds, holds a moment with the
/// grain still moving, and ends on the tape rewinding, so the loop reads as
/// a rewind. Every word sits in one band at the top, the case as the
/// headline and each beat's caption under it, clear of where the feeds
/// draw (`TapeCard`), and "TABBI CAM 4  OWNER AWAY 25:00" is burned into
/// every frame. The sound is the tape's own
/// (`TapeSound`), mastered to -14 LUFS with its true peak under -1 dBTP; no
/// music. It never mentions studying, and the dodge line appears only when
/// the player opts in.
enum TapeExporter {
    static let size = CGSize(width: 1080, height: 1920)
    static let framesPerSecond: Int32 = 30
    /// Static frames at a cut between cameras, and in-between frames (two
    /// video frames each) between two stills of one camera.
    static let cutFrames = 3
    static let tweenCount = 3

    enum ExportError: Error {
        case noTape
        case render
        case writer
    }

    /// One run of frames: images shown in turn, each for some frames.
    struct Segment: @unchecked Sendable {
        var images: [CGImage]
        /// Video frames per image, the last image held for the rest.
        var framesEach: [Int]
        var frames: Int
        /// Cycles the last `cycle` images (grain) once the rest have played.
        var cycle = 1
        var cue: PetCamTape.Cue?
    }

    /// Renders and encodes `record`'s share clip; returns the file's URL in
    /// the temporary folder.
    @MainActor
    static func export(_ record: PetCamBlockRecord, caseNumber: Int?, includeDodge: Bool) async throws -> URL {
        guard let clip = PetCamTape.clip(record) else { throw ExportError.noTape }
        let headline = PetCamCaptions.caseLine(record, includeDodge: includeDodge) ?? ""
        func card(_ still: PetCamTape.Still, grain: Int, offset: CGFloat = 0, zoom: CGFloat = 1,
                  flash: Bool = false) throws -> CGImage {
            try render(TapeCard(record: record, still: still, caseNumber: caseNumber, headline: headline,
                                grainFrame: grain, offset: offset, zoom: zoom, flash: flash))
        }
        var segments: [Segment] = []
        let cut = try render(StaticCard())
        for (index, still) in clip.enumerated() {
            if index > 0 {
                let tweens = PetCamTape.tweens(from: clip[index - 1], to: still, count: tweenCount)
                if !tweens.isEmpty {
                    var images: [CGImage] = []
                    for shot in tweens {
                        var between = still
                        between.shot = shot
                        between.caption = clip[index - 1].caption
                        between.detail = clip[index - 1].detail
                        images.append(try card(between, grain: index * 16 + 9))
                    }
                    segments.append(Segment(images: images, framesEach: images.map { _ in 2 }, frames: images.count * 2))
                } else if still.shot.framing != clip[index - 1].shot.framing, still.stamp != .rewind {
                    segments.append(Segment(images: [cut], framesEach: [cutFrames], frames: cutFrames))
                }
            }
            let frames = Int((still.duration * Double(framesPerSecond)).rounded())
            var images: [CGImage] = [], each: [Int] = []
            if still.stamp == .caught {
                // The stamp slams in: a two-frame flash, then a shake.
                images.append(try card(still, grain: index * 16, flash: true))
                each.append(2)
                for offset: CGFloat in [24, -18, 10, -4] {
                    images.append(try card(still, grain: index * 16 + 1, offset: offset))
                    each.append(2)
                }
            } else if still.shake {
                // A jolt as a hard hit cuts in: knocked aside and back.
                for offset: CGFloat in [26, -20, 12, -6] {
                    images.append(try card(still, grain: index * 16, offset: offset))
                    each.append(2)
                }
            }
            let zoom: CGFloat = still.punchIn ? 1.22 : 1
            if still.punchIn {
                // Eye contact: the camera pushes in on the pet and holds.
                for step in 1...6 {
                    let eased = 1 - pow(1 - CGFloat(step) / 7, 2)
                    images.append(try card(still, grain: index * 16 + step, zoom: 1 + (zoom - 1) * eased))
                    each.append(2)
                }
            }
            // The grain keeps moving on every still, the stamp's hold too.
            for grain in 0..<3 {
                images.append(try card(still, grain: index * 16 + 8 + grain, zoom: zoom))
                each.append(4)
            }
            segments.append(Segment(images: images, framesEach: each, frames: frames, cycle: 3, cue: still.cue))
        }
        let stamp = Self.fileStamp(record.endedAt)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tabbi-tape-\(stamp).mp4")
        try? FileManager.default.removeItem(at: url)
        try await encode(segments, sound: Loudness.master(Self.soundTrack(segments)), to: url)
        return url
    }

    /// The whole sound track, before mastering: hiss under everything and
    /// each still's cue as it cuts in.
    nonisolated static func soundTrack(_ segments: [Segment]) -> [Float] {
        let total = segments.reduce(0) { $0 + $1.frames }
        let perFrame = TapeSound.sampleRate / Double(framesPerSecond)
        var track = TapeSound.hiss(seconds: Double(total) / Double(framesPerSecond) + 0.1)
        var frame = 0
        for segment in segments {
            if let cue = segment.cue {
                let start = Int(Double(frame) * perFrame)
                for (index, value) in TapeSound.samples(cue).enumerated() where start + index < track.count {
                    track[start + index] += value
                }
            }
            frame += segment.frames
        }
        return track
    }

    @MainActor
    static func render<Content: View>(_ view: Content) throws -> CGImage {
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

    /// Writes the frames and the sound, the sound kept a little ahead of
    /// the picture so the writer can interleave them.
    private nonisolated static func encode(_ segments: [Segment], sound: [Float], to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: TapeSound.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
        ])
        audio.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        guard writer.canAdd(input), writer.canAdd(audio) else { throw ExportError.writer }
        writer.add(input)
        writer.add(audio)
        guard writer.startWriting() else { throw writer.error ?? ExportError.writer }
        writer.startSession(atSourceTime: .zero)

        var pcm = AudioStreamBasicDescription(
            mSampleRate: TapeSound.sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked, mBytesPerPacket: 2,
            mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &pcm, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard let format else { throw ExportError.writer }
        let samples = sound.map { Int16(($0 * Float(Int16.max)).rounded()) }
        var written = 0
        let chunk = 4096
        /// Waits for `track` to take more, or throws the moment the writer
        /// fails or stalls for ten seconds, so an export never waits forever
        /// (the player then says the video could not be made).
        func ready(_ track: AVAssetWriterInput) async throws {
            let since = Date()
            while !track.isReadyForMoreMediaData {
                if writer.status == .failed || writer.status == .cancelled { throw writer.error ?? ExportError.writer }
                if Date().timeIntervalSince(since) > 10 {
                    writer.cancelWriting()
                    throw ExportError.writer
                }
                try await Task.sleep(for: .milliseconds(5))
            }
        }

        func appendSound(through seconds: Double) async throws {
            let until = seconds.isFinite ? min(samples.count, Int(seconds * TapeSound.sampleRate)) : samples.count
            while written < until {
                try await ready(audio)
                let count = min(chunk, samples.count - written)
                let bytes = count * 2
                var block: CMBlockBuffer?
                CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
                                                   blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                                                   offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
                guard let block else { throw ExportError.writer }
                try samples[written..<(written + count)].withUnsafeBytes { raw in
                    guard let base = raw.baseAddress,
                          CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0,
                                                        dataLength: bytes) == noErr else { throw ExportError.writer }
                }
                var buffer: CMSampleBuffer?
                CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                    allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: count,
                    presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: CMTimeScale(TapeSound.sampleRate)),
                    packetDescriptions: nil, sampleBufferOut: &buffer)
                guard let buffer, audio.append(buffer) else { throw writer.error ?? ExportError.writer }
                written += count
            }
        }

        var frame: Int64 = 0
        func append(_ image: CGImage) async throws {
            try await appendSound(through: Double(frame) / Double(framesPerSecond) + 0.5)
            try await ready(input)
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
        for segment in segments {
            // The lead-in images play once each; then the last `cycle`
            // images take turns (grain) for the rest of the segment.
            let lead = segment.images.count - segment.cycle
            var shown = 0
            for (index, image) in segment.images.prefix(lead).enumerated() where shown < segment.frames {
                for _ in 0..<min(segment.framesEach[index], segment.frames - shown) {
                    try await append(image)
                    shown += 1
                }
            }
            var turn = 0
            while shown < segment.frames {
                let index = lead + turn % segment.cycle
                for _ in 0..<min(segment.framesEach[index], segment.frames - shown) {
                    try await append(segment.images[index])
                    shown += 1
                }
                turn += 1
            }
        }
        try await appendSound(through: .infinity)
        input.markAsFinished()
        audio.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? ExportError.writer }
    }
}

/// One frame of the shared video. Every word sits in the part of the frame
/// the feeds leave alone: below the top 200 pixels (their tabs), above the
/// bottom 280 (their caption and buttons) and left of the last 120 (their
/// like and share column). The charge is the headline at the top, the
/// beat's caption right under it, changing with each beat, and the picture
/// below them runs off the bottom edge, so the band the feeds cover holds
/// only floor. The picture is centered on the words, not on the frame.
struct TapeCard: View {
    let record: PetCamBlockRecord
    let still: PetCamTape.Still
    let caseNumber: Int?
    let headline: String
    let grainFrame: Int
    /// Pixels the picture is knocked sideways inside its frame (the jolt of
    /// a hard hit); the words never move.
    var offset: CGFloat = 0
    /// The push-in on eye contact (1 is none).
    var zoom: CGFloat = 1
    /// The white flash as the stamp lands.
    var flash = false
    /// Only the words and their plates, on nothing (for the layout test).
    var textOnly = false

    /// Where every word must land, in the 1080 by 1920 frame.
    static let wordsArea = CGRect(x: 60, y: 200, width: 900, height: 1440)
    /// Points across the picture is drawn in (it snaps to 900, ten times
    /// the wide shot).
    static let pictureWidth: CGFloat = 900
    static let pictureTop: CGFloat = 500
    static let headlineSize: CGFloat = 48
    /// The beat's caption, at least 70% of the headline.
    static let captionSize: CGFloat = 34
    static let captionHeight: CGFloat = 84
    /// How far the stamp's tilt carries its corner below the box it is
    /// planned in.
    static let stampTilt: CGFloat = 40
    static let bandTop: CGFloat = 218
    static let bandBottom: CGFloat = 484

    /// The beat's words: the freeze's is the case's line under the stamp,
    /// the rest what each still says, with its sound or callback after.
    var caption: String {
        let words = still.stamp == .caught ? [still.detail ?? still.caption] : [still.caption, still.detail]
        return PetCamCaptions.keepingDodgeTogether(words.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
    }

    var body: some View {
        let picture = FeedView.pictureSize(still.shot.framing, width: Self.pictureWidth, displayScale: 1)
        let words = Self.wordsArea
        ZStack(alignment: .topLeading) {
            textOnly ? Color.clear : CCTV.screen
            TapeStillView(record: record, still: still, caseNumber: caseNumber, width: Self.pictureWidth,
                          publicOnly: true, frozen: false, grainFrame: grainFrame, burnInSize: 38, zoom: zoom,
                          jolt: offset, hud: PetCamCaptions.clipHUD(camera: still.cameraLabel, worked: record.worked),
                          stampLimit: Double((words.maxY - Self.stampTilt - Self.pictureTop) / picture.height),
                          textOnly: textOnly)
                .overlay { if flash, !textOnly { Color.white.opacity(0.85) } }
                .position(x: words.midX, y: Self.pictureTop + picture.height / 2)
            VStack(spacing: 10) {
                Text(verbatim: PetCamCaptions.keepingDodgeTogether(headline))
                    .font(.system(size: Self.headlineSize, weight: .heavy, design: .monospaced))
                    .foregroundStyle(CCTV.burnIn)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                Text(verbatim: caption)
                    .font(.system(size: Self.captionSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(CCTV.burnIn.opacity(0.8))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.captionHeight, alignment: .top)
            }
            .multilineTextAlignment(.center)
            .frame(width: words.width, height: Self.bandBottom - Self.bandTop)
            .position(x: words.midX, y: (Self.bandTop + Self.bandBottom) / 2)
        }
        .frame(width: TapeExporter.size.width, height: TapeExporter.size.height)
        .clipped()
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
