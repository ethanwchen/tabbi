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
            .safeAreaInset(edge: .top, spacing: 0) { StatusBarBackdrop() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if typeSize.isAccessibilitySize, !onBreak {
                    startButton
                        .padding(.horizontal, CCTV.gutter)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .background {
                            // Opaque under the button, with a short fade above
                            // it, so nothing scrolls through half-sliced.
                            VStack(spacing: 0) {
                                LinearGradient(colors: [CCTV.screen.opacity(0), CCTV.screen], startPoint: .top,
                                               endPoint: .bottom)
                                    .frame(height: 40)
                                CCTV.screen
                            }
                            .padding(.top, -40)
                            .ignoresSafeArea()
                        }
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

    /// "What are you avoiding?", and the five-minute dare when it would
    /// start a sitting (no filmed block ended in the last hour).
    private var dodgeRow: some View {
        TimelineView(.everyMinute) { context in
            if cam.game.offersDare(at: context.date) {
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
            } else {
                dodgeField
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
        .glassEffect(.regular.interactive(), in: .capsule)
        .overlay(Capsule().strokeBorder(StudyTone.focus.hue(.dark).opacity(0.85), lineWidth: 1.5))
        .accessibilityHint(Text(verbatim: "Starts now. Stop any time after five minutes and the tape still plays."))
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
        .buttonStyle(SolidCapsuleStyle(fill: StudyTone.focus.hue(.dark)))
    }

    /// What is on the frame, in words ("Eyeing the plant. The mug is
    /// WANTED."), then where the camera hides when the player moved it, and
    /// on the first two blocks how to move it. It describes the frame and
    /// never states the rule; the tapes do the teaching.
    private var cameraLine: some View {
        let armed = cam.game.arms(plannedLength: session.phaseDuration)
        let minutes = Int((cam.game.minimumBlock / 60).rounded())
        let setup = cam.shownSetup, room = cam.shownRoom
        func object(_ spot: PetCamSpot) -> String {
            room.object(at: spot).map { PetCamCaptions.name(of: $0.kind).lowercased() } ?? "nothing"
        }
        var frame = "Eyeing the \(object(setup.stare))."
        if let tell = setup.tell {
            frame += tell.exception == .appetite ? " The \(object(tell.spot)) smells too good."
                : " The \(object(tell.spot)) is wobbling."
        } else if let wanted = setup.wanted {
            frame += " The \(object(wanted)) is WANTED."
        }
        let control: String? = if let pick = cam.pick {
            "Camera hidden at the \(PetCamCaptions.name(of: pick).lowercased())."
        } else if cam.game.log.blocks.isEmpty {
            // The very first block states the premise, not the control.
            "While you're out, your pet wrecks something. Hide the camera where it will strike."
        } else if cam.game.log.blocks.count < 2 {
            "Tap another spot to hide the camera there."
        } else {
            nil
        }
        return VStack(spacing: 2) {
            if armed {
                Text(verbatim: frame)
                    .foregroundStyle(CCTV.burnIn.opacity(0.85))
                if let control { Text(verbatim: control).foregroundStyle(CCTV.burnIn.opacity(0.55)) }
            } else {
                Text(verbatim: "Blocks under \(minutes) minutes are not filmed.")
                    .foregroundStyle(CCTV.burnIn.opacity(0.6))
            }
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.hint")
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
                    Viewfinder(label: "CAM \(spot.cameraNumber)", armed: isCamera, labelBelow: frame.minY < 64,
                               wanted: cam.shownSetup.wanted == spot)
                        .frame(width: frame.width, height: frame.height)
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

/// Four corner brackets and the camera's number on every spot, marking the
/// three places a camera can hide: bright on the armed one (the tapped spot,
/// or the stare), faint on the other two. They replace the light halos,
/// which turned the room to mush.
private struct Viewfinder: View {
    let label: String
    let armed: Bool
    /// Near the top of the picture the label goes under the brackets, clear
    /// of the burn-in.
    var labelBelow = false
    /// The stake, tagged at the brackets' other corner, outside them, so it
    /// never sits on the object.
    var wanted = false

    var body: some View {
        Corners()
            .stroke(CCTV.burnIn, style: StrokeStyle(lineWidth: 2, lineCap: .square))
            // Only the brackets dim on a spot that is not armed; every label
            // keeps the same dark chip, so it reads on any wall.
            .opacity(armed ? 1 : 0.35)
            .shadow(color: .black.opacity(0.6), radius: 0, x: 1, y: 1)
            .overlay(alignment: labelBelow ? .bottomLeading : .topLeading) {
                Text(verbatim: label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(CCTV.burnIn)
                    .padding(.horizontal, 3)
                    .background(CCTV.screen.opacity(0.65))
                    .fixedSize()
                    .opacity(armed ? 1 : 0.6)
                    // Fully outside the brackets (the label is about
                    // 13 points tall), with air between it and the stroke.
                    .offset(y: labelBelow ? 17 : -17)
            }
            .overlay(alignment: labelBelow ? .bottomTrailing : .topTrailing) {
                if wanted {
                    WantedTag()
                        .offset(y: labelBelow ? 17 : -17)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// The screen's black behind the status bar, so a page scrolled at the
/// largest text sizes never runs under the clock. It takes no room: the
/// fill reaches up into the safe area from a zero-height inset.
struct StatusBarBackdrop: View {
    var body: some View {
        Color.clear
            .frame(height: 0)
            .background(CCTV.screen)
            .accessibilityHidden(true)
    }
}

/// A plain filled capsule, without the glass rim: Start.
struct SolidCapsuleStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(fill.opacity(configuration.isPressed ? 0.8 : 1), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
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

/// A focus block under way: the player's own words as the case title
/// ("RE: MY TAX RETURN"), a still tile for the hidden camera on lens-cap
/// black, and the countdown. Nothing of the room shows and nothing changes
/// but the clock and the REC dot, so there is nothing to check until the
/// tape. The Lock Screen never shows the words: other people see it.
struct RecordingScreen: View {
    @Environment(StudyStore.self) private var study
    @Environment(PetCamStore.self) private var cam

    var body: some View {
        let filming = cam.game.active
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(spacing: 18) {
                if let filming {
                    if let dodge = PetCamCaptions.cleanDodge(filming.dodge) {
                        Text(verbatim: "RE: \(dodge)")
                            .font(CCTV.font(.title3, weight: .heavy))
                            .foregroundStyle(CCTV.burnIn)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("recording.case")
                    }
                    CameraTile(block: filming)
                } else {
                    RecLabel(text: "STANDBY", isRecording: false)
                    Text(verbatim: "The camera only films blocks of \(Int((cam.game.minimumBlock / 60).rounded())) minutes or more.")
                        .font(.subheadline)
                        .foregroundStyle(CCTV.burnIn.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                StudyClock(session: study.session)
                if filming?.dare == true {
                    Text(verbatim: "Just 5 minutes. Stop any time after that and the tape still plays.")
                        .font(.subheadline)
                        .foregroundStyle(CCTV.burnIn.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 24)
            SessionButtons(tint: StudyTone.focus.hue(.dark))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                CCTV.screen
                Scanlines(opacity: 0.22)
            }
            .ignoresSafeArea()
        }
    }
}

/// The hidden camera's last frame: its view of its spot as it stood when
/// the block started, at night levels under frozen grain, with its name
/// burned in. Only the REC dot moves (and not under Reduce Motion), so the
/// block has nothing to check.
private struct CameraTile: View {
    let block: PetCamActiveBlock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let camera = block.camera
        let picture = FeedView.pictureSize(.spot(camera), width: tileWidth, displayScale: displayScale)
        FeedView(shot: PetCamShot(framing: .spot(camera), objects: block.room.objects, wrecks: block.room.wrecks),
                 pet: block.pet, daylight: false, width: tileWidth)
            // A landscape band around the object: from a sixth of the way
            // down, half the picture's height.
            .offset(y: -picture.height / 6)
            .frame(width: picture.width, height: picture.height / 2, alignment: .top)
            .clipped()
            .overlay { StaticGrain(frame: 3, amount: 0.14) }
            .overlay(alignment: .topLeading) { burnIn(camera).dynamicTypeSize(...DynamicTypeSize.large) }
            .clipShape(.rect(cornerRadius: CCTV.feedRadius, style: .continuous))
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tileWidth = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Recording on camera \(camera.cameraNumber), the \(PetCamCaptions.name(of: camera).lowercased())"))
            .accessibilityIdentifier("recording.camera")
    }

    @Environment(\.displayScale) private var displayScale
    @State private var tileWidth: CGFloat = 320

    private func burnIn(_ camera: PetCamSpot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let lit = reduceMotion || Int(context.date.timeIntervalSinceReferenceDate) % 2 == 0
                    Circle()
                        .fill(CCTV.rec)
                        .frame(width: 9, height: 9)
                        .opacity(lit ? 1 : 0.2)
                }
                Text(verbatim: "REC")
                    .font(CCTV.font(.caption, weight: .bold))
            }
            Text(verbatim: "CAM \(camera.cameraNumber), \(PetCamCaptions.name(of: camera))")
                .font(CCTV.font(.caption2, weight: .semibold))
                .opacity(0.8)
        }
        .foregroundStyle(CCTV.burnIn)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(CCTV.plate, in: .rect(cornerRadius: 6))
        .padding(10)
    }
}
