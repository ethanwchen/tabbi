import SwiftUI
import TabbiKitCore

/// The tape: five to seven stills with hard cuts and burned-in captions,
/// under twenty seconds, which plays by itself and closes by itself. A
/// catch ends on the freeze with the CAUGHT stamp and the charge; a miss
/// ends on the wreck it did not see. A block stopped early shows its one
/// frozen still. With the ringer on it plays the tape's own sounds.
///
/// The feed, its captions and the buttons always fit on one screen: the
/// buttons are pinned at the bottom, the caption area is as tall as the
/// tape's longest caption at the current text size, and the feed takes
/// what is left (so it shrinks at the largest text sizes rather than
/// cutting a caption off), centered in the space above the buttons.
struct TapePlayer: View {
    let record: PetCamBlockRecord
    /// Called when the tape is over (or closed); without it the player
    /// dismisses its own presentation.
    var onFinish: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(PetCamStore.self) private var cam
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var index = 0
    @State private var cut = true
    @State private var holding = false
    @State private var exporting = false
    @State private var shared: SharedTape?
    @State private var includeDodge = false
    @State private var exportFailed = false
    @State private var jolt: CGFloat = 0
    @State private var captionHeight: CGFloat = 80
    @State private var buttonsHeight: CGFloat = 60
    @State private var finished = false
    @State private var screenSize: CGSize = .zero

    private var tape: PetCamTape? { PetCamTape(record: record) }

    var body: some View {
        GeometryReader { geometry in
            let width = pictureWidth(in: geometry.size)
            VStack(spacing: 0) {
                if let tape {
                    progress(tape)
                        .padding(.horizontal, CCTV.gutter)
                        .padding(.top, 8)
                    Spacer(minLength: 10)
                    let still = tape.stills[min(index, tape.stills.count - 1)]
                    TapeStillView(record: record, still: still, caseNumber: caseNumber, width: width, publicOnly: false,
                                  frozen: still.stamp == .caught)
                        .overlay { if cut { Static() } }
                        .offset(x: jolt)
                        .frame(maxWidth: .infinity)
                    captions(tape, current: still)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                    Spacer(minLength: 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                screenSize = geometry.size
                prefetch()
            }
            .onChange(of: width) { prefetch() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let tape {
                buttons(tape)
                    .padding(.horizontal, CCTV.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { buttonsHeight = $0 }
            }
        }
        .background(CCTV.screen.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task(id: record.id) { await play() }
        .onDisappear { TapeAudio.shared.stop() }
        .sheet(item: $shared) { file in ShareSheet(items: [file.url]) }
        .alert(Text(verbatim: "The video could not be made."), isPresented: $exportFailed) {
            Button(role: .cancel) {} label: { Text("Done", bundle: .tabbi) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: index)
    }

    /// The widest picture that leaves room above for the progress bar and
    /// below for the tallest caption (the buttons are pinned outside this
    /// space), inside the 16 point gutter.
    private func pictureWidth(in size: CGSize) -> CGFloat {
        let height = size.height - captionHeight - 14 - 8 - 3 - 20
        return max(min(size.width - 2 * CCTV.gutter, height * 100 / 160), 120)
    }

    /// The wall's case number of a catch (1 for the first).
    private var caseNumber: Int? { cam.caseNumber(of: record) }

    /// Renders every still ahead, off the main actor, at the scale the
    /// player draws it.
    private func prefetch() {
        guard let tape, screenSize.width > 0 else { return }
        let width = pictureWidth(in: screenSize)
        for framing in Set(tape.stills.map(\.shot.framing)) {
            let size = PetCamScene.size(of: framing)
            let scale = FeedView.devicePixels(spriteWidth: size.width, width: width, displayScale: displayScale)
            let jobs = tape.stills.filter { $0.shot.framing == framing }
                .map { (shot: $0.shot, daylight: PetCamScene.isDaylight($0.time)) }
            FeedCache.shared.prefetch(jobs, pet: record.pet, scale: scale)
        }
    }

    /// A moment of static as the monitor switches to the tape, then the
    /// stills, each for its own time, with a split second of static at
    /// each cut and its sound; then it closes on its own.
    private func play() async {
        guard let tape else {
            finish()
            return
        }
        TapeAudio.shared.start()
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 600))
        for (position, still) in tape.stills.enumerated() {
            if position > 0, !reduceMotion {
                cut = true
                try? await Task.sleep(for: .milliseconds(90))
            }
            cut = false
            index = position
            if let cue = still.cue { TapeAudio.shared.play(cue) }
            if still.shake, !reduceMotion { await shake() }
            try? await Task.sleep(for: .seconds(still.shake && !reduceMotion ? still.duration - 0.3 : still.duration))
            if Task.isCancelled { return }
        }
        TapeAudio.shared.stop()
        // Hold the last frame while a share sheet is up or the user chose
        // to keep watching.
        while holding || shared != nil || exporting {
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { return }
        }
        try? await Task.sleep(for: .milliseconds(500))
        if !Task.isCancelled { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        TapeAudio.shared.stop()
        if let onFinish { onFinish() } else { dismiss() }
    }

    /// The camera jolts: a few quick knocks either way that settle.
    private func shake() async {
        for offset: CGFloat in [9, -7, 4, -2, 0] {
            withAnimation(.spring(duration: 0.06, bounce: 0)) { jolt = offset }
            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    private func progress(_ tape: PetCamTape) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(tape.stills.enumerated()), id: \.offset) { position, still in
                Capsule()
                    .fill(position <= index ? CCTV.burnIn : CCTV.burnIn.opacity(0.22))
                    .frame(height: 3)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.spring(duration: 0.3), value: index)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "Still \(index + 1) of \(tape.stills.count)"))
    }

    /// The current still's captions over every still's captions laid out
    /// hidden (out of sight and out of the accessibility tree), so the area
    /// is always as tall as the longest and the feed never jumps between cuts.
    private func captions(_ tape: PetCamTape, current: PetCamTape.Still) -> some View {
        ZStack(alignment: .top) {
            ForEach(Array(tape.stills.enumerated()), id: \.offset) { _, still in
                caption(still).hidden()
            }
            // A hard cut with the picture, as a camera's burn-in changes;
            // a crossfade would overlay two captions for a moment.
            caption(current)
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { captionHeight = $0 }
    }

    private func caption(_ still: PetCamTape.Still) -> some View {
        VStack(spacing: 6) {
            Text(verbatim: PetCamCaptions.keepingDodgeTogether(still.caption))
                .font(CCTV.font(.title3, weight: .bold))
                .foregroundStyle(CCTV.burnIn)
            if let detail = still.detail {
                Text(verbatim: detail)
                    .font(CCTV.font(.subheadline, weight: .medium))
                    .foregroundStyle(CCTV.burnIn.opacity(0.75))
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tape.caption")
    }

    private func buttons(_ tape: PetCamTape) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { buttonRow(tape) }
            VStack(spacing: 10) { buttonRow(tape) }
        }
    }

    @ViewBuilder private func buttonRow(_ tape: PetCamTape) -> some View {
        if tape.outcome.hasTape {
            Menu {
                Button {
                    includeDodge = false
                    share()
                } label: { Text(verbatim: "Share video") }
                if record.dodge != nil {
                    Button {
                        includeDodge = true
                        share()
                    } label: { Text(verbatim: "Share with what I was avoiding") }
                }
            } label: {
                HStack(spacing: 8) {
                    if exporting {
                        ProgressView().tint(CCTV.burnIn)
                    } else {
                        Image(systemName: "square.and.arrow.up").accessibilityHidden(true)
                    }
                    Text(verbatim: "Share")
                        .font(.headline)
                        .fixedSize()
                }
                .foregroundStyle(CCTV.burnIn)
                .frame(maxWidth: .infinity, minHeight: 52)
            } primaryAction: {
                includeDodge = false
                share()
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .disabled(exporting)
            .accessibilityHint(Text(verbatim: "Makes a video of this tape"))
        }
        Button {
            finish()
        } label: {
            Text("Done", bundle: .tabbi)
                .font(.headline)
                .fixedSize()
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(CCTV.burnIn)
    }

    private func share() {
        holding = true
        exporting = true
        let record = record, number = caseNumber, include = includeDodge
        Task {
            do {
                let url = try await TapeExporter.export(record, caseNumber: number, includeDodge: include)
                exporting = false
                shared = SharedTape(url: url)
            } catch {
                exporting = false
                exportFailed = true
            }
        }
    }
}

struct SharedTape: Identifiable {
    let url: URL
    var id: URL { url }
}

/// One still as the camera burned it: the picture, the timestamp, the
/// camera and REC, the stamp of a catch or a stop, grain and scanlines.
/// The tape player and the video exporter both draw it.
struct TapeStillView: View {
    let record: PetCamBlockRecord
    let still: PetCamTape.Still
    let caseNumber: Int?
    /// Points available across.
    let width: CGFloat
    /// For a shared video: the charge without the dodge line.
    let publicOnly: Bool
    /// The catch's freeze: the grain stops and the stamp lands.
    var frozen = false
    /// The grain's frame, for the exporter (the live player animates it).
    var grainFrame: Int?
    /// Fixed text sizes for the exporter's 1080 by 1920 frame; nil follows
    /// Dynamic Type.
    var burnInSize: CGFloat?
    /// The exporter's push-in on the pet (1 is none); the burn-in stays put.
    var zoom: CGFloat = 1

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let picture = FeedView.pictureSize(still.shot.framing, width: width, displayScale: displayScale)
        let center = PetCamScene.petCenter(in: still.shot) ?? (0.5, 0.5)
        FeedView(shot: still.shot, pet: record.pet, daylight: PetCamScene.isDaylight(still.time), width: width)
            .scaleEffect(zoom, anchor: UnitPoint(x: center.x, y: center.y))
            .frame(width: picture.width, height: picture.height)
            .clipped()
            .overlay {
                if let grainFrame {
                    StaticGrain(frame: grainFrame)
                } else if !frozen {
                    Grain()
                }
            }
            .overlay(alignment: .top) { burnIn.dynamicTypeSize(...DynamicTypeSize.large) }
            .overlay { stamp.dynamicTypeSize(...DynamicTypeSize.large) }
            .frame(width: picture.width, height: picture.height)
            .clipShape(.rect(cornerRadius: burnInSize == nil ? CCTV.feedRadius : 0, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(still.cameraLabel). " + Self.describe(still, pet: record.pet.name)))
    }

    private func font(_ style: Font.TextStyle, _ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        burnInSize.map { .system(size: size * $0, weight: weight, design: .monospaced) } ?? CCTV.font(style, weight: weight)
    }

    private var burnIn: some View {
        let plate = burnInSize.map { $0 * 0.3 } ?? 4
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: CCTV.timestamp(still.time))
                    .font(font(.caption, 1))
                    .monospacedDigit()
                Text(verbatim: still.cameraLabel)
                    .font(font(.caption2, 0.85))
                    .opacity(0.85)
            }
            .padding(.horizontal, plate * 1.3)
            .padding(.vertical, plate * 0.8)
            .background(CCTV.plate, in: .rect(cornerRadius: plate * 0.8))
            Spacer(minLength: 8)
            Group {
                if still.stamp == .rewind {
                    HStack(spacing: 5) {
                        Image(systemName: "backward.fill")
                        Text(verbatim: "REW")
                    }
                    .font(font(.caption, 1, weight: .bold))
                    .accessibilityHidden(true)
                } else if still.stamp == nil || still.stamp == .caught {
                    RecLabel(text: "REC", isRecording: true)
                        .scaleEffect(burnInSize.map { $0 / 12 } ?? 1, anchor: .topTrailing)
                        .frame(width: burnInSize.map { $0 * 4.6 }, height: burnInSize.map { $0 * 1.3 },
                               alignment: .topTrailing)
                }
            }
            .padding(.horizontal, plate * 1.3)
            .padding(.vertical, plate * 0.8)
            .background(CCTV.plate, in: .rect(cornerRadius: plate * 0.8))
        }
        .foregroundStyle(CCTV.burnIn)
        .padding(.horizontal, burnInSize.map { $0 * 0.8 } ?? 8)
        .padding(.top, burnInSize.map { $0 * 0.8 } ?? 8)
    }

    @ViewBuilder private var stamp: some View {
        switch still.stamp {
        case .caught:
            // Where the pet and the evidence leave room, so the last frame
            // shows suspect, evidence and verdict together.
            GeometryReader { geometry in
                let center = PetCamScene.stampCenter(of: still.shot, pet: record.pet)
                caughtStamp
                    .position(x: geometry.size.width * center.x, y: geometry.size.height * center.y)
            }
            .transition(.scale(scale: 1.6).combined(with: .opacity))
        case .frozen:
            Text(verbatim: "STOPPED")
                .font(font(.title, 2.4, weight: .heavy))
                .foregroundStyle(CCTV.standby)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(CCTV.standby, lineWidth: 3))
                .rotationEffect(.degrees(-7))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, burnInSize.map { $0 * 3 } ?? 36)
        case .rewind:
            TrackingBands(seed: grainFrame ?? 3)
        case nil:
            EmptyView()
        }
    }

    private var caughtStamp: some View {
        VStack(spacing: 4) {
            Text(verbatim: PetCamCaptions.caughtStamp)
                .font(font(.largeTitle, 3.2, weight: .heavy))
            if let caseNumber {
                Text(verbatim: String(format: "CASE %03d", caseNumber))
                    .font(font(.headline, 1.3, weight: .bold))
            }
        }
        .foregroundStyle(CCTV.rec)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(CCTV.rec, lineWidth: 4))
        .background(CCTV.screen.opacity(0.35), in: .rect(cornerRadius: 6, style: .continuous))
        .rotationEffect(.degrees(-9))
        .shadow(color: .black.opacity(0.5), radius: 0, x: 2, y: 2)
        .fixedSize()
    }

    /// What a still shows, in words, for VoiceOver.
    static func describe(_ still: PetCamTape.Still, pet name: String) -> String {
        let spot: (PetCamSpot) -> String = { "the \(PetCamCaptions.name(of: $0).lowercased())" }
        guard let pose = still.shot.pet else {
            if case .wreck(let target, _) = still.shot.framing,
               let wreck = still.shot.wrecks.last(where: { $0.spot == target }) {
                return "The \(PetCamCaptions.name(of: wreck.object.kind).lowercased()) lies wrecked on the floor."
            }
            return "Nobody in the picture."
        }
        switch pose {
        case .stare(let target): return "\(name) sits on the rug, staring at \(spot(target))."
        case .sneak: return "\(name) creeps along the floor."
        case .swipe: return "\(name) raises a paw."
        case .act(let kind):
            let verb = switch kind {
            case .mug: "swats the mug off its spot"
            case .fishbowl: "paws at the fish in the bowl"
            case .donut: "chomps the donut"
            case .tissues: "shreds the tissues"
            case .plant: "digs in the plant pot"
            case .vase: "head-shoves the vase off its spot"
            }
            return "\(name) \(verb)."
        case .caughtMidAct(let kind):
            return kind.isEaten ? "\(name) stares into the camera, mouth full of donut."
                : "\(name) is caught in mid-air, staring into the camera."
        case .lensStare: return "\(name) stares straight into the camera."
        case .lieDown: return "\(name) lies on the floor, staring into the camera."
        case .stroll: return "\(name) strolls into the picture."
        }
    }
}

/// The bright bands that roll through a tape while it rewinds.
private struct TrackingBands: View {
    let seed: Int

    var body: some View {
        Canvas { context, size in
            var roll = PetCamRandom(seed: UInt64(truncatingIfNeeded: seed), stream: "tracking")
            for _ in 0..<3 {
                let y = (roll.unit() * size.height).rounded(.down)
                let height = (4 + roll.unit() * 10).rounded(.down)
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: height)),
                             with: .color(.white.opacity(0.16)))
                context.fill(Path(CGRect(x: 0, y: y + height, width: size.width, height: 2)),
                             with: .color(.black.opacity(0.35)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A split second of static between two stills.
private struct Static: View {
    var body: some View {
        StaticGrain(frame: Int(Date().timeIntervalSinceReferenceDate * 20), amount: 0.55)
            .background(Color(white: 0.18))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Grain for one given frame, so the exporter can draw it frame by frame.
struct StaticGrain: View {
    let frame: Int
    var amount = 0.10

    var body: some View {
        Canvas { canvas, size in
            var roll = PetCamRandom(seed: UInt64(truncatingIfNeeded: frame), stream: "grain")
            let dot = max((size.width / 400).rounded(), 1)
            for _ in 0..<Int(size.width * size.height / 260) {
                let x = (roll.unit() * size.width).rounded(.down), y = (roll.unit() * size.height).rounded(.down)
                canvas.fill(Path(CGRect(x: x, y: y, width: dot, height: dot)),
                            with: .color(roll.unit() > 0.5 ? .white.opacity(amount) : .black.opacity(amount * 1.6)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The system share sheet for a finished video.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
