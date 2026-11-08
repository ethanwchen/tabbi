import SwiftUI
import TabbiKitCore

/// The tape: four to six stills with hard cuts and burned-in captions,
/// under twenty seconds, which plays by itself and closes by itself. A
/// catch ends on the freeze with the CAUGHT stamp and the charge; a miss
/// ends on the alibi. A block stopped early shows its one frozen still.
struct TapePlayer: View {
    let record: PetCamBlockRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(PetCamStore.self) private var cam
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var index = 0
    @State private var cut = false
    @State private var holding = false
    @State private var exporting = false
    @State private var shared: SharedTape?
    @State private var includeDodge = false
    @State private var exportFailed = false
    @State private var jolt: CGFloat = 0

    private var tape: PetCamTape? { PetCamTape(record: record) }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    if let tape {
                        progress(tape)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 10)
                        let still = tape.stills[min(index, tape.stills.count - 1)]
                        TapeStillView(record: record, still: still, caseNumber: caseNumber,
                                      width: pictureWidth(in: geometry.size), publicOnly: false,
                                      frozen: still.stamp == .caught)
                            .overlay { if cut { Static() } }
                            .offset(x: jolt)
                            .frame(maxWidth: .infinity)
                        captions(still)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                        Spacer(minLength: 12)
                        buttons(tape)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear {
                screenSize = geometry.size
                prefetch()
            }
        }
        .background(CCTV.screen.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task(id: record.id) { await play() }
        .sheet(item: $shared) { file in ShareSheet(items: [file.url]) }
        .alert(Text(verbatim: "The video could not be made."), isPresented: $exportFailed) {
            Button(role: .cancel) {} label: { Text("Done", bundle: .tabbi) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: index)
    }

    /// The picture leaves room for the captions and buttons below it; at
    /// the accessibility text sizes it keeps the full width and the page
    /// scrolls.
    private func pictureWidth(in size: CGSize) -> CGFloat {
        typeSize.isAccessibilitySize ? size.width : min(size.width, (size.height - 230) * 100 / 160)
    }

    /// The wall's case number of a catch (1 for the first).
    private var caseNumber: Int? {
        guard record.outcome == .caught else { return nil }
        return (cam.game.log.mugshots.firstIndex { $0.id == record.id } ?? 0) + 1
    }

    @Environment(\.displayScale) private var displayScale
    @State private var screenSize: CGSize = .zero

    /// Renders every still ahead, off the main actor, at the scale the
    /// player draws it.
    private func prefetch() {
        guard let tape, screenSize.width > 0 else { return }
        for framing in Set(tape.stills.map(\.shot.framing)) {
            let size = PetCamScene.size(of: framing)
            let scale = FeedView.devicePixels(spriteWidth: size.width, width: pictureWidth(in: screenSize),
                                              displayScale: displayScale)
            let jobs = tape.stills.filter { $0.shot.framing == framing }
                .map { (shot: $0.shot, daylight: PetCamScene.isDaylight($0.time)) }
            FeedCache.shared.prefetch(jobs, pet: record.pet, scale: scale)
        }
    }

    /// Steps through the stills, each for its own time, with a split
    /// second of static at each cut, then closes on its own.
    private func play() async {
        guard let tape else {
            dismiss()
            return
        }
        for (position, still) in tape.stills.enumerated() {
            if position > 0, !reduceMotion {
                cut = true
                try? await Task.sleep(for: .milliseconds(90))
                cut = false
            }
            index = position
            if still.shake, !reduceMotion { await shake() }
            try? await Task.sleep(for: .seconds(still.shake && !reduceMotion ? still.duration - 0.3 : still.duration))
            if Task.isCancelled { return }
        }
        // Hold the last frame while a share sheet is up or the user chose
        // to keep watching.
        while holding || shared != nil || exporting {
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { return }
        }
        try? await Task.sleep(for: .milliseconds(500))
        if !Task.isCancelled { dismiss() }
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

    private func captions(_ still: PetCamTape.Still) -> some View {
        VStack(spacing: 6) {
            Text(verbatim: still.caption)
                .font(CCTV.font(.title3, weight: .bold))
                .foregroundStyle(CCTV.burnIn)
            if let detail = detailText(still) {
                Text(verbatim: detail)
                    .font(CCTV.font(.subheadline, weight: .medium))
                    .foregroundStyle(CCTV.burnIn.opacity(0.75))
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .id(index)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tape.caption")
    }

    private func detailText(_ still: PetCamTape.Still) -> String? { still.detail }

    private func buttons(_ tape: PetCamTape) -> some View {
        HStack(spacing: 12) {
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
                .accessibilityHint(Text(verbatim: "Makes a muted video of this tape"))
            }
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .tabbi)
                    .font(.headline)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(CCTV.burnIn)
        }
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

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let picture = FeedView.pictureSize(still.shot.framing, width: width, displayScale: displayScale)
        FeedView(shot: still.shot, pet: record.pet, daylight: PetCamScene.isDaylight(still.time), width: width)
            .overlay {
                if let grainFrame {
                    StaticGrain(frame: grainFrame)
                } else if !frozen {
                    Grain()
                }
            }
            .overlay { Scanlines() }
            .overlay(alignment: .top) { burnIn.dynamicTypeSize(...DynamicTypeSize.large) }
            .overlay { stamp.dynamicTypeSize(...DynamicTypeSize.large) }
            .frame(width: picture.width, height: picture.height)
            .clipShape(.rect(cornerRadius: burnInSize == nil ? 6 : 0, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(still.cameraLabel). " + Self.describe(still, pet: record.pet.name)))
    }

    private func font(_ style: Font.TextStyle, _ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        burnInSize.map { .system(size: size * $0, weight: weight, design: .monospaced) } ?? CCTV.font(style, weight: weight)
    }

    private var burnIn: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: CCTV.timestamp(still.time))
                    .font(font(.caption, 1))
                    .monospacedDigit()
                Text(verbatim: still.cameraLabel)
                    .font(font(.caption2, 0.85))
                    .opacity(0.85)
            }
            Spacer(minLength: 8)
            if still.stamp == nil || still.stamp == .caught {
                RecLabel(text: "REC", isRecording: true)
                    .scaleEffect(burnInSize.map { $0 / 12 } ?? 1, anchor: .topTrailing)
            }
        }
        .foregroundStyle(CCTV.burnIn)
        .shadow(color: .black.opacity(0.8), radius: 0, x: 1, y: 1)
        .padding(.horizontal, burnInSize.map { $0 * 1.2 } ?? 12)
        .padding(.top, burnInSize.map { $0 * 1.0 } ?? 10)
    }

    @ViewBuilder private var stamp: some View {
        switch still.stamp {
        case .caught:
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
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, burnInSize.map { $0 * 3 } ?? 36)
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
        case nil:
            EmptyView()
        }
    }

    /// What a still shows, in words, for VoiceOver.
    static func describe(_ still: PetCamTape.Still, pet name: String) -> String {
        let spot: (PetCamSpot) -> String = { "the \(PetCamCaptions.name(of: $0).lowercased())" }
        guard let pose = still.shot.pet else { return "Nobody in the picture." }
        switch pose {
        case .stare(let target): return "\(name) sits on the rug, staring at \(spot(target))."
        case .sneak: return "\(name) creeps along the floor."
        case .swipe: return "\(name) raises a paw."
        case .midAct: return "\(name) swats something off its spot."
        case .lensStare: return "\(name) stares straight into the camera."
        case .lieDown: return "\(name) lies on the floor, staring into the camera."
        case .stroll: return "\(name) strolls into the picture."
        }
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
            let dot = max(size.width / 400, 1)
            for _ in 0..<Int(size.width * size.height / 260) {
                let x = roll.unit() * size.width, y = roll.unit() * size.height
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
