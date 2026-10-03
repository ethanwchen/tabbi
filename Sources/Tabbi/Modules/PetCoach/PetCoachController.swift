import AppKit
import Combine
import TabbiKitCore
import TabbiKit

/// Runs the study pet's coach: while a focus phase runs it samples how long
/// the user has been idle and which app is in front, feeds `PetCoach`, and
/// plays each nudge in a `PetCoachOverlayWindow`.
///
/// Permission-free by design (see docs/studynotch/research.md): idle time
/// comes from `CGEventSource` (only the time since the last event, never
/// its content) and the app from `NSWorkspace`. No Accessibility, Screen
/// Recording, or Input Monitoring. Sampling only happens during a focus
/// phase; breaks, pauses, and no timer cost nothing.
///
/// The focus timer comes from the shared `ProviderSnapshot`, so the coach
/// works with whichever module runs the timer. Pausing and resuming go
/// through closures `ClosetModule` provides. Coach state (cooldowns, snooze,
/// app lists) persists next to the pet's save. With `TABBI_DEMO=1` the
/// coach never samples, nudges, or writes.
///
/// It also backs Settings › Pet Coach: the nudges switch and the user's
/// distracting apps, published so the pane follows them.
@MainActor
final class PetCoachController: ObservableObject {
    private let profile: () -> PetProfile
    private let kitLines: () -> [PetCoachMessage]
    private let screen: () -> NSScreen?
    private let pauseTimer: () -> Void
    private let resumeTimer: () -> Void
    private let isDemo: Bool
    private let saveURL: URL?
    /// Set when the save on disk could not be read: run on defaults, but
    /// never overwrite the file.
    private let saveIsUnreadable: Bool

    private var save: PetCoachSave {
        didSet {
            // Samples rewrite the coach state every few seconds; only tell
            // views when what Settings shows changes.
            if save.apps != oldValue.apps || save.nudgesOn != oldValue.nudgesOn { objectWillChange.send() }
        }
    }
    private var timer: ProvidedFocus?
    private var isRunning = false
    private var focusSubscription: AnyCancellable?
    private var awardSubscription: AnyCancellable?
    private var sampler: Timer?
    private var overlay: PetCoachOverlayWindow?
    private var overlayCloser: Timer?

    init(
        storage: EditionStorage,
        runMode: RunMode,
        profile: @escaping () -> PetProfile,
        lines: @escaping () -> [PetCoachMessage] = { PetCoachMessages.standard },
        screen: @escaping () -> NSScreen?,
        pauseTimer: @escaping () -> Void,
        resumeTimer: @escaping () -> Void
    ) {
        self.profile = profile
        kitLines = lines
        self.screen = screen
        self.pauseTimer = pauseTimer
        self.resumeTimer = resumeTimer
        isDemo = runMode.isDemo
        saveURL = isDemo ? nil : Self.saveURL(in: storage)
        var unreadable = false
        var save = PetCoachSave()
        if isDemo {
            // A realistic Settings pane: two suggestions and one added app.
            save.apps.markDistracting("com.apple.MobileSMS")
            save.apps.markDistracting("com.hnc.Discord")
            save.apps.markDistracting("com.apple.news")
        }
        if let saveURL {
            do {
                save = try PetCoachSave.load(from: saveURL) ?? PetCoachSave()
            } catch {
                unreadable = true
            }
        }
        self.save = save
        saveIsUnreadable = unreadable
    }

    /// What the pet can say: the standard lines plus the active kit's.
    /// Read on every nudge, so switching kits changes the flavor at once.
    var lines: [PetCoachMessage] { kitLines() }

    /// `~/Library/Application Support/<edition>/Pet/coach.json`.
    static func saveURL(in storage: EditionStorage) -> URL {
        storage.file("coach.json", in: "Pet")
    }

    /// Follows the shared focus timer (`ProviderSnapshot.focus`).
    func follow(focus: AnyPublisher<ProvidedFocus?, Never>) {
        focusSubscription = focus
            .removeDuplicates()
            .sink { [weak self] timer in
                MainActor.assumeIsolated { self?.focusChanged(timer) }
            }
    }

    /// Celebrates each study award the pet's closet credits.
    func follow(awards: AnyPublisher<PetStudyAward, Never>) {
        awardSubscription = awards.sink { [weak self] award in
            MainActor.assumeIsolated { self?.celebrate(award) }
        }
    }

    /// Turns the coach on, with the pet's module.
    func start() {
        // Developer hook: `TABBI_COACH_PREVIEW=1` plays one nudge right
        // away, to check the real overlay window without waiting minutes.
        // `=celebrate` plays a level-up celebration and `=glance` the
        // silent look instead.
        switch ProcessInfo.processInfo.environment["TABBI_COACH_PREVIEW"] {
        case "1":
            present(PetCoachNudge(kind: .distraction, message: PetCoachMessages.messages(for: .distraction, in: lines).last!),
                    at: Date().addingTimeInterval(1))
        case "celebrate":
            present(.celebration(PetStudyAward(completedSessions: 1, minutes: 25, points: 35, unlocked: [.accessory(.beanie)])),
                    stroll: PetCoachStroll(startedAt: Date().addingTimeInterval(1), talkDuration: PetCoach.celebrationDuration))
        case "glance":
            glance(at: Date().addingTimeInterval(1))
        default:
            break
        }
        guard !isDemo, !isRunning else { return }
        isRunning = true
        updateSampling()
    }

    /// Turns the coach off and sends the pet home at once.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        updateSampling()
        closeOverlay()
    }

    // MARK: Settings

    var nudgesOn: Bool { save.nudgesOn }
    var apps: CoachAppList { save.apps }

    func setNudgesOn(_ on: Bool) {
        guard on != save.nudgesOn else { return }
        save.nudgesOn = on
        updateSampling()
        persist()
        if !on { closeOverlay() }
    }

    func toggleDistracting(_ bundleID: String) {
        save.apps.toggleDistracting(bundleID)
        persist()
    }

    /// Adds the app at `url` (an `.app` picked in Settings) as distracting.
    func addDistractingApp(at url: URL) {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier, !save.apps.isDistracting(bundleID) else { return }
        save.apps.markDistracting(bundleID)
        persist()
    }

    // MARK: Sampling

    private func focusChanged(_ timer: ProvidedFocus?) {
        self.timer = timer
        updateSampling()
    }

    /// Samples every few seconds during a focus phase with nudges on, and
    /// not at all otherwise. Leaving focus takes one last sample, which ends
    /// any distraction or idle episode in the coach; switching nudges or the
    /// coach off ends them without one, so switching back on starts fresh.
    private func updateSampling() {
        let focusing = isRunning && save.nudgesOn && PetCoachStudyState(timer) == .focusing
        if focusing, sampler == nil {
            let sampler = Timer(timeInterval: PetCoach.sampleInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            sampler.tolerance = 1
            RunLoop.main.add(sampler, forMode: .common)
            self.sampler = sampler
        } else if !focusing, let sampler {
            sampler.invalidate()
            self.sampler = nil
            if isRunning, save.nudgesOn {
                sample()
            } else {
                save.coach.endEpisodes()
            }
        }
    }

    private func sample() {
        let anyInput = CGEventType(rawValue: ~0)!
        let input = PetCoachInput(
            now: Date(),
            idleSeconds: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput),
            frontmost: save.apps.category(of: NSWorkspace.shared.frontmostApplication?.bundleIdentifier),
            timer: timer
        )
        let before = save.coach
        let decision = save.coach.evaluate(input, lines: lines)
        if save.coach != before { persist() }
        switch decision {
        case .none:
            break
        case .lookOver:
            glance(at: input.now)
        case .nudge(let nudge):
            if nudge.pausesTimer { pauseTimer() }
            present(nudge, at: input.now)
        }
    }

    // MARK: Overlay

    /// Sends the pet out to celebrate points just earned: a happy hop with
    /// a heart and the points, plus what they unlock on a level-up. Plays
    /// whenever the coach is on, nudges or not, since it never interrupts.
    func celebrate(_ award: PetStudyAward) {
        guard isRunning else { return }
        present(.celebration(award), stroll: PetCoachStroll(startedAt: Date(), talkDuration: PetCoach.celebrationDuration))
    }

    /// The silent look: the pet peeks out of the notch's edge and back.
    /// Never over a bubble that's still up.
    private func glance(at now: Date) {
        guard overlay == nil else { return }
        present(PetCoachScene(profile: profile(), glanceAt: now))
    }

    private func present(_ nudge: PetCoachNudge, at now: Date) {
        present(.nudge(nudge), stroll: PetCoachStroll(startedAt: now))
    }

    private func present(_ line: PetCoachLine, stroll: PetCoachStroll) {
        present(PetCoachScene(profile: profile(), stroll: stroll, line: line))
    }

    private func present(_ scene: PetCoachScene) {
        // One pet on screen at a time; a newer line replaces an old one.
        closeOverlay()
        guard let screen = screen() else { return }
        let stroll = scene.stroll
        let overlay = PetCoachOverlayWindow(scene: scene, geometry: .measure(screen)) { [weak self] reply in
            self?.answer(reply)
        }
        overlay.show()
        self.overlay = overlay
        scheduleClose(at: stroll.endsAt)
    }

    private func answer(_ reply: PetCoachReply) {
        let now = Date()
        save.coach.handle(reply, at: now)
        if reply == .snooze { persist() }
        if reply.pausesTimer { pauseTimer() }
        if reply.resumesTimer { resumeTimer() }
        overlay?.dismiss(at: now)
        if let endsAt = overlay?.stroll.endsAt { scheduleClose(at: endsAt) }
    }

    /// Closes the overlay once the pet is back under the notch.
    private func scheduleClose(at date: Date) {
        overlayCloser?.invalidate()
        let closer = Timer(fire: date.addingTimeInterval(0.1), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeOverlay() }
        }
        RunLoop.main.add(closer, forMode: .common)
        overlayCloser = closer
    }

    private func closeOverlay() {
        overlayCloser?.invalidate()
        overlayCloser = nil
        overlay?.close()
        overlay = nil
    }

    private func persist() {
        guard let saveURL, !saveIsUnreadable else { return }
        try? save.write(to: saveURL)
    }
}
