// The four questions (ada-swiftui-design, Step 0):
// - Question: what is my pet about to do while I'm away? The frozen camera
//   frame is the hero: the room, the three lit spots and the pet's stare.
// - Metaphor: a home security monitor. Burn-in timestamps, a REC dot,
//   scanlines and grain; the phone is the monitor.
// - Temperature: playful and calm. A cozy room at night, a sly pet.
// - Stage: the room itself. The feed fills the screen's width; the controls
//   sit on glass on the monitor below it, and nothing about the room shows
//   while a block runs.

import SwiftUI
import TabbiKitCore

/// The app's root: the frozen frame between blocks, the recording screen
/// while a focus block runs, and the tape as soon as one is ready.
///
/// The tape lies over everything rather than sliding up as a sheet: a block
/// that ends goes from the recording screen through a moment of static
/// straight to the tape, never past the home screen, and the tape fades
/// back out to the home screen. Until it has been watched the home screen
/// still shows the room and the wall from before the block (`PetCamStore`).
struct PetCamRoot: View {
    @Environment(StudyStore.self) private var study
    @Environment(PetCamStore.self) private var cam

    var body: some View {
        ZStack {
            Group {
                if cam.reveal != nil || cam.hasTapeWaiting {
                    // Under the tape while it fades in, and in place of the
                    // home screen while a tape waits for the app to come
                    // back: the monitor between two feeds.
                    StaticScreen()
                        .transition(.opacity)
                } else if study.session.phase == .focus, study.session.runState != .idle {
                    RecordingScreen()
                        .transition(.opacity)
                } else {
                    HomeScreen()
                        .transition(.opacity)
                }
            }
            if let record = cam.reveal {
                TapePlayer(record: record) { cam.watched(record) }
                    .id(record.id)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.spring(duration: 0.4), value: study.session.runState)
        .animation(.easeInOut(duration: 0.35), value: cam.reveal?.id)
        .preferredColorScheme(.dark)
        .sensoryFeedback(trigger: study.session.runState) { old, new in
            switch (old, new) {
            case (_, .running): .start
            case (.running, _): .stop
            default: nil
            }
        }
        .sensoryFeedback(.success, trigger: cam.reveal?.id)
    }
}

/// The frozen frame: the room as the corner camera sees it, the pet's
/// tell, the one sealed tap, the dodge line and Start.
struct HomeScreen: View {
    @Environment(StudyStore.self) private var study
    @Environment(PetCamStore.self) private var cam
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showsMethods = false
    @State private var showsWall = false
    @State private var showsPets = false
    @State private var showsTuning = false
    @State private var controlsHeight: CGFloat = 180
    @FocusState private var dodgeFocused: Bool

    private var session: StudySession { study.session }
    private var onBreak: Bool { session.phase.isBreak && session.runState != .idle }

    var body: some View {
        GeometryReader { geometry in
            // The feed keeps the same width, gutter and pixel scale in every
            // mode; when the controls need more room (the Timer's stepper)
            // it crops the empty floor at the bottom instead of shrinking.
            // At the accessibility text sizes the page scrolls instead and
            // Start stays pinned above the home indicator.
            let width = geometry.size.width - 2 * CCTV.gutter
            let picture = FeedView.pictureSize(.wide, width: width, displayScale: displayScale)
            let shown = typeSize.isAccessibilitySize ? picture.height
                : Self.feedHeight(picture: picture.height, room: geometry.size.height - controlsHeight)
            ScrollView {
                VStack(spacing: 0) {
                    feed(width: width, height: shown)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity)
                    controls
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
                }
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if typeSize.isAccessibilitySize, !onBreak {
                    startButton
                        .padding(.horizontal, CCTV.gutter)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .background(CCTV.screen.opacity(0.94).ignoresSafeArea())
                }
            }
        }
        .background(CCTV.screen.ignoresSafeArea())
        .sheet(isPresented: $showsMethods) {
            MethodSheet().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsWall) { MugshotWall() }
        .sheet(isPresented: $showsPets) { PetPicker().presentationDetents([.medium, .large]) }
        #if DEBUG
        .sheet(isPresented: $showsTuning) { TuningPanel().presentationDetents([.medium, .large]) }
        #endif
        .sensoryFeedback(.selection, trigger: cam.pick)
        .sensoryFeedback(.selection, trigger: session.method)
        #if DEBUG
        .overlay(alignment: .bottomTrailing) {
            // UI tests read where the pet will strike, to play a sure catch
            // and a sure miss (`-PetCamTestHooks`, debug builds only).
            if DebugLaunch.arguments.contains("-PetCamTestHooks") {
                Text(verbatim: cam.game.setup.strike.rawValue)
                    .font(.system(size: 2))
                    .opacity(0.02)
                    .accessibilityIdentifier("debug.strike")
            }
        }
        #endif
    }

    /// How much of the feed shows: all of it when it fits above the
    /// controls, else cropped at the bottom (the empty near floor), but
    /// never past the rug; below that the page scrolls.
    static func feedHeight(picture: CGFloat, room: CGFloat) -> CGFloat {
        min(picture, max(room - 4, picture * 0.74)).rounded(.down)
    }

    // MARK: The feed

    private func feed(width: CGFloat, height: CGFloat) -> some View {
        let picture = FeedView.pictureSize(.wide, width: width, displayScale: displayScale)
        return TimelineView(.periodic(from: .now, by: 0.45)) { context in
            let tick = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 2
            FeedView(shot: cam.frozenShot, pet: study.pet, daylight: PetCamScene.isDaylight(context.date),
                     width: width, tick: tick)
        }
        .frame(width: picture.width, height: picture.height)
        // The picture takes no taps and is described by the shown frame
        // below, so nothing of the cropped floor (not even an accessibility
        // frame, which clipping does not cut) covers the controls under it.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .frame(height: height, alignment: .top)
        .clipped()
        .overlay {
            Color.clear
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: "Camera 1, the living room. "
                    + PetCamCaptions.describe(cam.shownSetup, room: cam.shownRoom, petName: study.pet.name)
                    + (cam.shownSetup.wanted.flatMap { cam.shownRoom.object(at: $0) }.map {
                        " The \(PetCamCaptions.name(of: $0.kind).lowercased()) is wanted."
                    } ?? "")))
                .accessibilityAddTraits(.isImage)
        }
        .overlay(alignment: .top) { SpotTargets(size: picture, shownHeight: height) }
        .overlay { Grain().clipped() }
        .overlay {
            // A soft fade into the monitor at the bottom, under the chips.
            LinearGradient(colors: [.clear, CCTV.screen.opacity(0.85)], startPoint: UnitPoint(x: 0.5, y: 0.80),
                           endPoint: .bottom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) { burnIn }
        .overlay(alignment: .bottomLeading) {
            if !typeSize.isAccessibilitySize { chips.padding(12).padding(.bottom, 18) }
        }
        .clipShape(.rect(cornerRadius: CCTV.feedRadius, style: .continuous))
    }

    /// The camera's burn-in: the date and time, the camera, and REC.
    private var burnIn: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(verbatim: CCTV.timestamp(context.date))
                        .font(CCTV.font(.caption))
                        .monospacedDigit()
                }
                Text(verbatim: "CAM 1  LIVING ROOM")
                    .font(CCTV.font(.caption2))
                    .opacity(0.8)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(CCTV.plate, in: .rect(cornerRadius: 3))
            Spacer(minLength: 8)
            RecLabel(text: "LIVE", isRecording: true)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(CCTV.plate, in: .rect(cornerRadius: 3))
        }
        .foregroundStyle(CCTV.burnIn)
        .shadow(color: .black.opacity(0.8), radius: 0, x: 1, y: 1)
        // A camera's burn-in has one size; VoiceOver reads it in full.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .contentShape(.rect)
        .onLongPressGesture(minimumDuration: 0.8) {
            #if DEBUG
            showsTuning = true
            #endif
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Live camera"))
        .accessibilityIdentifier("feed.burnIn")
    }

    /// The method, the pet's points and the wall, floating on the floor.
    private var chips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                MethodButton(showsMethods: $showsMethods)
                Spacer(minLength: 0)
                PointsButton { showsPets = true }
                wallButton
            }
            VStack(alignment: .leading, spacing: 8) {
                MethodButton(showsMethods: $showsMethods)
                HStack(spacing: 8) {
                    PointsButton { showsPets = true }
                    wallButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The largest text sizes: one chip per line.
            VStack(alignment: .leading, spacing: 8) {
                MethodButton(showsMethods: $showsMethods)
                PointsButton { showsPets = true }
                wallButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var wallButton: some View {
        Button { showsWall = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.text.rectangle.fill")
                    .accessibilityHidden(true)
                Text(verbatim: "\(cam.mugshots.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(Text(verbatim: "Mugshot wall, \(cam.mugshots.count)"))
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 12) {
            if typeSize.isAccessibilitySize {
                chips.frame(maxWidth: .infinity, alignment: .leading)
            }
            if onBreak {
                breakControls
            } else {
                if session.method.kind == .timer, session.runState == .idle {
                    TimerLengthPicker(length: study.engine.timer) { study.setTimer($0) }
                }
                dodgeRow
                // At the largest sizes Start is pinned below instead.
                if !typeSize.isAccessibilitySize { startButton }
                cameraLine
            }
            if let award = study.award {
                AwardLine(award: award)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .padding(.horizontal, CCTV.gutter)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .animation(.spring(duration: 0.4), value: study.award)
    }

    /// "What are you avoiding?" and the five-minute dare.
    private var dodgeRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                dodgeField
                dareButton
            }
            VStack(spacing: 8) {
                dodgeField
                dareButton
            }
        }
    }

    private var dodgeField: some View {
        @Bindable var cam = cam
        return TextField(text: $cam.dodge, prompt: Text(verbatim: "What are you avoiding?")
            .foregroundStyle(CCTV.burnIn.opacity(0.45))) {
            Text(verbatim: "What are you avoiding?")
        }
        .font(.body)
        .foregroundStyle(CCTV.burnIn)
        .submitLabel(.done)
        .focused($dodgeFocused)
        .textInputAutocapitalization(.sentences)
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .glassEffect(.regular, in: .capsule)
        .accessibilityHint(Text(verbatim: "Optional. Only the tape and the mugshot show it."))
    }

    private var dareButton: some View {
        Button {
            dodgeFocused = false
            cam.start(study: study, dare: true)
        } label: {
            Text(verbatim: "Just 5 minutes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CCTV.burnIn)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(CCTV.rec.opacity(0.25)).interactive(), in: .capsule)
        .accessibilityHint(Text(verbatim: "Starts now. You can stop after five minutes."))
    }

    private var startButton: some View {
        Button {
            dodgeFocused = false
            cam.start(study: study)
        } label: {
            Text(StudyTimerFormat.primaryAction(session))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(StudyTone.focus.hue(.dark))
    }

    /// Where the camera will hide, or why it will not film this block.
    private var cameraLine: some View {
        let armed = cam.game.arms(plannedLength: session.phaseDuration)
        let minutes = Int((cam.game.minimumBlock / 60).rounded())
        let text = if !armed {
            "Blocks under \(minutes) minutes are not filmed."
        } else if let pick = cam.pick {
            "Camera hidden at the \(PetCamCaptions.name(of: pick).lowercased()). Tap it again to follow the stare."
        } else {
            "Camera follows the stare. Tap a lit spot to hide it there."
        }
        return Text(verbatim: text)
            .font(.footnote)
            .foregroundStyle(CCTV.burnIn.opacity(0.6))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var breakControls: some View {
        VStack(spacing: 12) {
            StudyClock(session: session, size: 44, tint: StudyTone.rest.hue(.dark))
            SessionButtons(tint: StudyTone.rest.hue(.dark))
        }
    }
}

/// The three spots as buttons over the feed, and the viewfinder that shows
/// where the camera will hide: the tapped spot, or the stare.
private struct SpotTargets: View {
    /// The whole picture's size, which the spots are placed in.
    let size: CGSize
    /// How much of it shows (the bottom may be cropped).
    let shownHeight: CGFloat
    @Environment(PetCamStore.self) private var cam

    var body: some View {
        let unit = size.width / CGFloat(PetCamScene.size(of: .wide).width)
        ZStack(alignment: .topLeading) {
            ForEach(PetCamSpot.allCases, id: \.self) { spot in
                let rect = PetCamScene.spotRect(spot)
                let frame = CGRect(x: rect.minX * unit, y: rect.minY * unit, width: rect.width * unit,
                                   height: rect.height * unit)
                let isCamera = cam.cameraSpot == spot
                Button {
                    cam.pick = cam.pick == spot ? nil : spot
                } label: {
                    Viewfinder(label: "CAM \(spot.cameraNumber)", picked: cam.pick == spot, shown: isCamera,
                               labelBelow: frame.minY < 64)
                        .frame(width: frame.width, height: frame.height)
                        .overlay(alignment: .top) {
                            // The stake: the object the wall is missing longest.
                            if cam.shownSetup.wanted == spot {
                                WantedTag()
                                    .padding(.top, unit * 2)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .position(x: frame.midX, y: frame.midY)
                .accessibilityLabel(Text(verbatim: "Hide the camera at the \(PetCamCaptions.name(of: spot).lowercased())"))
                .accessibilityAddTraits(cam.pick == spot ? .isSelected : [])
            }
        }
        .frame(width: size.width, height: min(size.height, shownHeight), alignment: .topLeading)
        .animation(.spring(duration: 0.3), value: cam.cameraSpot)
    }
}

/// The small yellow tag over the WANTED object on the frozen frame.
private struct WantedTag: View {
    var body: some View {
        Text(verbatim: "WANTED")
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .kerning(0.6)
            .foregroundStyle(CCTV.screen)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(CCTV.wanted, in: .rect(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(CCTV.screen.opacity(0.7), lineWidth: 1))
            .rotationEffect(.degrees(-5))
            .shadow(color: .black.opacity(0.6), radius: 0, x: 1, y: 1)
            .fixedSize()
            .accessibilityIdentifier("feed.wanted")
    }
}

/// Four corner brackets and the camera's number: red when the player hid
/// the camera here, pale when it is following the stare.
private struct Viewfinder: View {
    let label: String
    let picked: Bool
    let shown: Bool
    /// Near the top of the picture the label goes under the brackets, clear
    /// of the burn-in.
    var labelBelow = false

    var body: some View {
        let color = picked ? CCTV.rec : CCTV.burnIn
        Corners()
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .square))
            .opacity(shown ? 1 : 0)
            .overlay(alignment: labelBelow ? .bottomLeading : .topLeading) {
                if shown {
                    Text(verbatim: label)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                        .padding(.horizontal, 3)
                        .background(CCTV.screen.opacity(0.65))
                        .fixedSize()
                        // Fully outside the brackets (the label is about
                        // 13 points tall), with air between it and the stroke.
                        .offset(y: labelBelow ? 17 : -17)
                }
            }
            .shadow(color: .black.opacity(0.6), radius: 0, x: 1, y: 1)
    }
}

private struct Corners: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = min(rect.width, rect.height) * 0.24
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                 (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                                 (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
        }
        return path
    }
}

/// The monitor between feeds, under the tape as it fades in. Once the tape
/// covers it the static stops moving, so it costs nothing while the tape
/// plays or a video is being made.
private struct StaticScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var covered = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: covered || reduceMotion)) { context in
            StaticGrain(frame: Int(context.date.timeIntervalSinceReferenceDate / 0.08), amount: 0.4)
        }
        .background(Color(white: 0.14))
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(1))
            covered = true
        }
    }
}

/// A focus block under way: the monitor shows REC and the countdown and
/// nothing of the room, so there is nothing to check until the tape.
struct RecordingScreen: View {
    @Environment(StudyStore.self) private var study
    @Environment(PetCamStore.self) private var cam

    var body: some View {
        let filming = cam.game.active
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                RecLabel(text: filming == nil ? "STANDBY" : "REC", isRecording: filming != nil)
                Spacer(minLength: 8)
                if let filming {
                    Text(verbatim: "CAM \(filming.camera.cameraNumber)")
                        .font(CCTV.font(.caption, weight: .bold))
                        .foregroundStyle(CCTV.burnIn)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            Spacer(minLength: 24)
            StudyClock(session: study.session)
                .padding(.horizontal, 20)
            Text(verbatim: line(filming))
                .font(.subheadline)
                .foregroundStyle(CCTV.burnIn.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 16)
            Spacer(minLength: 24)
            SessionButtons(tint: StudyTone.focus.hue(.dark))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                CCTV.screen
                Grain(amount: 0.06)
                Scanlines(opacity: 0.22)
            }
            .ignoresSafeArea()
        }
    }

    private func line(_ block: PetCamActiveBlock?) -> String {
        guard let block else {
            let minutes = Int((cam.game.minimumBlock / 60).rounded())
            return "The camera only films blocks of \(minutes) minutes or more."
        }
        if block.dare { return "Just 5 minutes. After that you can stop any time." }
        return "Recording. The tape plays when the block is done."
    }
}
