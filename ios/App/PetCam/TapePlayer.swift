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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var index = 0
    @State private var cut = true
    @State private var holding = false
    @State private var exporting = false
    @State private var shared: SharedTape?
    @State private var choosingCharge = false
    @State private var exportFailed = false
    @State private var jolt: CGFloat = 0
    @State private var captionHeight: CGFloat = 80
    @State private var finished = false
    @State private var screenSize: CGSize = .zero
    /// When the current still cut in, what its clock reads then, and
    /// whether the pet is mid-blink: a held still keeps the motion a real
    /// camera has.
    @State private var shownAt = Date()
    @State private var clockBase: Date?
    @State private var blinking = false
    /// When the tape began to play, for the UI test's timing hook.
    @State private var playStart: Date?

    private var tape: PetCamTape? { PetCamTape(record: record) }

    var body: some View {
        GeometryReader { geometry in
            let width = pictureWidth(in: geometry.size)
            ScrollView {
                VStack(spacing: 0) {
                    if let tape {
                        progress(tape)
                            .padding(.horizontal, CCTV.gutter)
                            .padding(.top, 8)
                        Spacer(minLength: 10)
                        let still = tape.stills[min(index, tape.stills.count - 1)]
                        TimelineView(.periodic(from: shownAt, by: 0.5)) { context in
                            // The burn-in clock ticks each second and the REC
                            // dot blinks while a still holds.
                            let elapsed = max(0, context.date.timeIntervalSince(shownAt))
                            TapeStillView(record: record, still: Self.blinked(still, blinking), caseNumber: caseNumber, width: width,
                                          publicOnly: false,
                                          clock: (clockBase ?? still.time).addingTimeInterval(elapsed.rounded(.down)),
                                          recLit: reduceMotion || Int(elapsed * 2).isMultiple(of: 2))
                        }
                            .accessibilityIdentifier("tape.picture")
                            .overlay { if cut { Static() } }
                            .offset(x: jolt)
                            .frame(maxWidth: .infinity)
                        captions(tape, current: still)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                        Spacer(minLength: 10)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .top, spacing: 0) { StatusBarBackdrop() }
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
                    // A long caption scrolls under the pinned buttons, never
                    // through them.
                    .background(CCTV.screen.ignoresSafeArea())
            }
        }
        .background(CCTV.screen.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task(id: record.id) { await play() }
        .onDisappear { TapeAudio.shared.stop() }
        .sheet(item: $shared) { file in ShareSheet(items: [file.url]) }
        .sheet(isPresented: $choosingCharge) {
            ChargeChooser(record: record) { include in
                choosingCharge = false
                share(includeDodge: include)
            }
            .presentationDetents([.medium, .large])
        }
        .alert(Text(verbatim: "The video could not be made."), isPresented: $exportFailed) {
            Button(role: .cancel) {} label: { Text("Done", bundle: .tabbi) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: index)
        #if DEBUG
        .overlay(alignment: .bottomLeading) {
            // UI tests read the tape's timing and captions once, rather than
            // polling the screen while it plays (`-PetCamTestHooks`, debug
            // builds only).
            if DebugLaunch.arguments.contains("-PetCamTestHooks"), let tape {
                Text(verbatim: "\(playStart?.timeIntervalSince1970 ?? 0)|" + Self.testHook(tape))
                    .font(.system(size: 2))
                    .opacity(0.02)
                    .accessibilityIdentifier("debug.tape")
            }
        }
        #endif
    }

    /// The widest picture that leaves room above for the progress bar and
    /// below for the tallest caption (the buttons are pinned outside this
    /// space), inside the 16 point gutter; never under half the screen's
    /// width, so at the largest text sizes the picture stays a picture and
    /// the page scrolls the rest of a long caption into view instead.
    private func pictureWidth(in size: CGSize) -> CGFloat {
        let height = size.height - captionHeight - 14 - 8 - 3 - 20
        let widest = size.width - 2 * CCTV.gutter
        return min(widest, max(height * 100 / 160, size.width * 0.5))
    }

    /// Each still's seconds, then each still's spoken caption, split by
    /// bars: "1.8,1.6|HOME ALONE.|CAM 4 WAKES UP." (the hook puts the
    /// moment the tape began to play in front).
    static func testHook(_ tape: PetCamTape) -> String {
        ([tape.stills.map { String(format: "%.2f", $0.duration) }.joined(separator: ",")]
            + tape.stills.map { PetCamCaptions.spoken($0.caption, $0.detail) }).joined(separator: "|")
    }

    /// `still` with the pet's eyes shut, mid-blink.
    private static func blinked(_ still: PetCamTape.Still, _ blinking: Bool) -> PetCamTape.Still {
        var shown = still
        shown.shot.blink = blinking
        return shown
    }

    /// The wall's case number of a catch (1 for the first).
    private var caseNumber: Int? { record.caseNumber ?? cam.caseNumber(of: record) }

    /// Renders every still ahead, off the main actor, at the scale the
    /// player draws it.
    private func prefetch() {
        guard let tape, screenSize.width > 0 else { return }
        let width = pictureWidth(in: screenSize)
        for framing in Set(tape.stills.map(\.shot.framing)) {
            let size = PetCamScene.size(of: framing)
            let scale = FeedView.devicePixels(spriteWidth: size.width, width: width, displayScale: displayScale)
            // With each held still's blink, so it never draws mid-tape.
            let jobs = tape.stills.filter { $0.shot.framing == framing }
                .flatMap { still -> [(shot: PetCamShot, daylight: Bool)] in
                    let daylight = PetCamScene.isDaylight(still.time)
                    guard still.duration > 1.5, still.shot.pet != nil else { return [(still.shot, daylight)] }
                    return [(still.shot, daylight), (Self.blinked(still, true).shot, daylight)]
                }
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
        // Every cut is scheduled from the start on one clock, so a slow
        // frame never pushes the rest of the tape later: it runs as long as
        // the code says.
        let clock = ContinuousClock()
        var next = clock.now + .milliseconds(reduceMotion ? 150 : 600)
        playStart = Date()
        try? await Task.sleep(until: next, clock: clock)
        var clockShown: Date?
        for (position, still) in tape.stills.enumerated() {
            if position > 0, !reduceMotion {
                cut = true
                next += .milliseconds(90)
                try? await Task.sleep(until: next, clock: clock)
            }
            cut = false
            // A still of the same moment carries on the clock where the last
            // one left it, so time never runs back except in a rewind.
            let base = still.stamp == .rewind ? still.time : max(still.time, clockShown ?? still.time)
            clockBase = base
            shownAt = .now
            index = position
            if let cue = still.cue { TapeAudio.shared.play(cue) }
            if still.shake, !reduceMotion { await shake() }
            let end = next + .milliseconds(Int((still.duration * 1000).rounded()))
            if still.duration > 1.5, !reduceMotion, still.shot.pet != nil {
                // One blink, a little past the middle of the hold.
                let blink = next + .milliseconds(Int((still.duration * 550).rounded()))
                try? await Task.sleep(until: blink, clock: clock)
                blinking = true
                try? await Task.sleep(until: blink + .milliseconds(150), clock: clock)
                blinking = false
            }
            try? await Task.sleep(until: end, clock: clock)
            next = end
            clockShown = base.addingTimeInterval(still.duration.rounded(.down))
            if Task.isCancelled { return }
        }
        TapeAudio.shared.stop()
        // Hold the last frame while a share sheet is up or the user chose
        // to keep watching.
        while holding || shared != nil || exporting {
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { return }
        }
        try? await Task.sleep(for: .milliseconds(300))
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

    /// The current still's captions in a fixed reserve of three caption
    /// lines and one line under them at the current text size (laid out
    /// hidden, out of the accessibility tree). The picture is sized from the
    /// reserve alone, so every tape shares one frame on a given phone and
    /// text size; a longer caption grows below it and the page scrolls.
    /// The burn-in stops growing at the second accessibility size, already
    /// twice its default size, so at the largest sizes a playing tape's
    /// caption still sits whole between the picture and the buttons.
    private func captions(_ tape: PetCamTape, current: PetCamTape.Still) -> some View {
        ZStack(alignment: .top) {
            VStack(spacing: 6) {
                // Four lines at the accessibility sizes, where a charge
                // wraps that far; three otherwise.
                Text(verbatim: typeSize.isAccessibilitySize ? "X\nX\nX\nX" : "X\nX\nX")
                    .font(CCTV.font(.title3, weight: .bold))
                Text(verbatim: "X").font(CCTV.font(.subheadline, weight: .medium))
            }
            .padding(.bottom, typeSize.isAccessibilitySize ? 8 : 0)
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { captionHeight = $0 }
            // A hard cut with the picture, as a camera's burn-in changes;
            // a crossfade would overlay two captions for a moment.
            caption(current)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .frame(maxWidth: .infinity)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: PetCamCaptions.spoken(still.caption, still.detail)))
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
            Button {
                // With the player's own words, the player picks the headline
                // (they may be private); without them it exports at once.
                if PetCamCaptions.cleanDodge(record.dodge) != nil {
                    holding = true
                    choosingCharge = true
                } else {
                    share(includeDodge: false)
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

    private func share(includeDodge: Bool) {
        holding = true
        exporting = true
        let record = record, number = caseNumber
        Task {
            do {
                let url = try await TapeExporter.export(record, caseNumber: number, includeDodge: includeDodge)
                exporting = false
                shared = SharedTape(url: url)
            } catch {
                exporting = false
                exportFailed = true
            }
        }
    }
}

/// Which charge goes on the shared video: both headlines, in the clip's
/// own type, neither picked for the player, so the funniest is one tap away
/// and a private task is never posted by accident.
struct ChargeChooser: View {
    let record: PetCamBlockRecord
    let choose: (_ includeDodge: Bool) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(verbatim: "Which charge goes on the video?")
                .font(.headline)
                .foregroundStyle(CCTV.burnIn.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ForEach([true, false], id: \.self) { include in
                if let line = PetCamCaptions.caseLine(record, includeDodge: include) {
                    Button { choose(include) } label: {
                        Text(verbatim: PetCamCaptions.keepingDodgeTogether(line))
                            .font(CCTV.font(.title3, weight: .heavy))
                            .foregroundStyle(CCTV.burnIn)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(CCTV.plate, in: .rect(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(CCTV.burnIn.opacity(0.25), lineWidth: 1))
                    .accessibilityIdentifier(include ? "share.charge.words" : "share.charge.act")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CCTV.gutter)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CCTV.screen.ignoresSafeArea())
        .preferredColorScheme(.dark)
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
    /// The exporter's jolt: the picture knocked sideways inside its frame,
    /// under a burn-in that stays put, as a recorder's text does.
    var jolt: CGFloat = 0
    /// The share clip's burn-in in place of the camera's label ("TABBI CAM
    /// 4  OWNER AWAY 25:00").
    var hud: String?
    /// How far up the picture the stamp's lower edge may sit, as a fraction
    /// of its height: the share clip keeps it out of the band along the
    /// bottom where the feeds draw their own caption and buttons.
    var stampLimit: Double = 1
    /// Draws only the words and their plates, on nothing, so a test can
    /// find where every word of a frame lands.
    var textOnly = false
    /// The time the burn-in shows, when it has ticked on from the still's.
    var clock: Date?
    /// The REC dot's blink: lit or dim.
    var recLit = true

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let picture = FeedView.pictureSize(still.shot.framing, width: width, displayScale: displayScale)
        let center = PetCamScene.petCenter(in: still.shot) ?? (0.5, 0.5)
        Group {
            if textOnly {
                Color.clear
            } else {
                FeedView(shot: still.shot, pet: record.pet, daylight: PetCamScene.isDaylight(still.time), width: width)
            }
        }
            .scaleEffect(zoom, anchor: UnitPoint(x: center.x, y: center.y))
            .offset(x: jolt)
            .frame(width: picture.width, height: picture.height)
            .clipped()
            .overlay {
                if textOnly {
                    EmptyView()
                } else if let grainFrame {
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

    /// The burn-in's text size. A camera burns its text into the picture,
    /// so it grows and shrinks with the picture rather than with Dynamic Type
    /// (a small picture at the largest text sizes never wraps or cuts its
    /// timestamp or stamp); VoiceOver reads it all from the label.
    private var unit: CGFloat { burnInSize ?? min(12, width / 28) }

    /// The stamp keeps to the picture's own scale, whatever size the
    /// burn-in is set at.
    private var stampUnit: CGFloat { min(unit, width / 28) }

    private func font(_ style: Font.TextStyle, _ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size * unit, weight: weight, design: .monospaced)
    }

    private var burnIn: some View {
        let plate = unit * 0.33
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: CCTV.timestamp(clock ?? still.time))
                    .font(font(.caption, 1))
                    .monospacedDigit()
                Text(verbatim: hud ?? still.cameraLabel)
                    .font(font(.caption2, 0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
                    RecLabel(text: "REC", isRecording: true, lit: recLit)
                        .fixedSize()
                        .scaleEffect(unit / 12, anchor: .topTrailing)
                        .frame(width: unit * 4.6, height: unit * 1.3, alignment: .topTrailing)
                }
            }
            .padding(.horizontal, plate * 1.3)
            .padding(.vertical, plate * 0.8)
            .background(CCTV.plate, in: .rect(cornerRadius: plate * 0.8))
        }
        .foregroundStyle(CCTV.burnIn)
        .padding(.horizontal, unit * 0.67)
        .padding(.top, unit * 0.67)
    }

    @ViewBuilder private var stamp: some View {
        switch still.stamp {
        case .caught:
            // Where the pet and the evidence leave room, so the last frame
            // shows suspect, evidence and verdict together.
            GeometryReader { geometry in
                let center = PetCamScene.stampCenter(of: still.shot, pet: record.pet, within: stampLimit)
                // Never wider than the share of the picture the placement
                // planned for, so CAUGHT AGAIN or HABITUAL never runs off the
                // edge; longer words set smaller instead.
                caughtStamp(maxWidth: geometry.size.width * PetCamScene.stampSize.width * 0.88)
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
                .padding(.bottom, unit * 3)
        case .rewind:
            if !textOnly { TrackingBands(seed: grainFrame ?? 3) }
        case nil:
            EmptyView()
        }
    }

    /// The stamp escalates with the object's rap sheet: CAUGHT, CAUGHT
    /// AGAIN, HABITUAL. The case number sits on an opaque plate in heavy
    /// type, so the room never shows through it.
    private func stampFont(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size * stampUnit, weight: weight, design: .monospaced)
    }

    private func caughtStamp(maxWidth: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: record.outcome == .caught ? record.captions.closer : PetCamCaptions.caughtStamp)
                .font(stampFont(3.2))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: maxWidth - stampUnit * 2.7)
            if let caseNumber {
                Text(verbatim: String(format: "CASE %03d", caseNumber))
                    .font(stampFont(1.3, weight: .black))
                    .padding(.horizontal, stampUnit * 0.5)
                    .background(CCTV.screen, in: .rect(cornerRadius: stampUnit / 4))
            }
        }
        .foregroundStyle(CCTV.rec)
        .padding(.horizontal, stampUnit * 1.33)
        .padding(.vertical, stampUnit * 0.67)
        .overlay(RoundedRectangle(cornerRadius: stampUnit / 2, style: .continuous).stroke(CCTV.rec, lineWidth: max(2, stampUnit / 3)))
        .background(CCTV.screen.opacity(0.35), in: .rect(cornerRadius: stampUnit / 2, style: .continuous))
        .rotationEffect(.degrees(-9))
        .shadow(color: .black.opacity(0.5), radius: 0, x: 2, y: 2)
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
            case .sock: "makes off with a sock"
            case .keys: "swats the keys off their spot"
            case .yarn: "bats the ball of yarn"
            case .egg: "swats the egg out of its cup"
            case .banana: "head-shoves the banana off its spot"
            case .pencils: "swats the pencil cup over"
            }
            return "\(name) \(verb)."
        case .caughtMidAct(let kind):
            return kind.isHeld ? "\(name) stares into the camera, holding the \(PetCamCaptions.name(of: kind).lowercased())."
                : "\(name) is caught in mid-air, staring into the camera."
        case .guilty, .mugshot:
            return "\(name) stares into the camera, wearing the evidence."
        case .lensStare: return "\(name) stares straight into the camera."
        case .lieDown: return "\(name) lies on the floor, staring into the camera."
        case .stroll: return "\(name) strolls into the picture."
        case .walkBy: return "\(name) strolls past the camera, wearing the evidence."
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
