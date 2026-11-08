import Foundation
import Observation
import TabbiKitCore

/// Something that follows the study session, such as the Pet Cam. It is
/// told about every change before the notifications and the Live Activity
/// are updated, so both can say what it made of it.
@MainActor
protocol StudyObserver: AnyObject {
    func studyDidChange(_ update: StudyEngine.Update, engine: StudyEngine, at now: Date)
    /// Whether the focus phase under way is being filmed: its end
    /// notification then says the tape is ready, and the Live Activity
    /// shows the camera recording.
    var isFilming: Bool { get }
}

/// The app's one store: runs the `StudyEngine` and carries out what each
/// change means outside it, in order: save, tell the observer, schedule
/// the phase-end notifications, sync the Live Activity, and wake up at the
/// next phase end while the app is open.
@MainActor
@Observable
final class StudyStore {
    private(set) var engine: StudyEngine
    /// The latest points award, for the celebration under the clock.
    private(set) var award: PetStudyAward?
    /// Bumped when a phase runs out while the app is open, for the
    /// success haptic and the pet's celebration.
    private(set) var completions = 0

    @ObservationIgnored private let persistence: StudyPersistence
    @ObservationIgnored private var unreadable: Set<URL>
    @ObservationIgnored private let alerts: PhaseAlertScheduler?
    @ObservationIgnored private let liveActivity: StudyLiveActivity?
    @ObservationIgnored private var phaseEnd: Task<Void, Never>?
    @ObservationIgnored private var clearAward: Task<Void, Never>?
    /// Whether the app is on screen; a phase that runs out while it is not
    /// leaves its done line on the Lock Screen.
    @ObservationIgnored private var isActive = true

    @ObservationIgnored private weak var observer: StudyObserver?

    /// - Parameter live: false in unit tests, which neither notify nor
    ///   start Live Activities.
    /// - Parameter observer: told about every change, starting with the
    ///   phase ends applied at launch.
    init(persistence: StudyPersistence = .standard, live: Bool = true, now: Date = Date(),
         observer: StudyObserver? = nil) {
        self.persistence = persistence
        self.observer = observer
        let loaded = persistence.load()
        engine = loaded.engine
        unreadable = loaded.unreadable
        alerts = live ? PhaseAlertScheduler() : nil
        liveActivity = live ? StudyLiveActivity() : nil
        // A session keeps running while the app is suspended or killed, so
        // launch applies what ended meanwhile, at the real end times.
        apply(at: now, writeAll: true) { $0.catchUp(at: now) }
    }

    var session: StudySession { engine.session }
    var pet: PetProfile { engine.pet }
    var balance: Int { engine.closet.balance }

    // MARK: Actions

    /// Back in the foreground, or a phase end the app was awake for.
    func catchUp(at now: Date = Date()) {
        apply(at: now) { $0.catchUp(at: now) }
    }

    /// Follows the scene: on screen or not. Coming back catches up, which
    /// also clears a done Live Activity now that the app shows the result.
    func setActive(_ active: Bool, at now: Date = Date()) {
        isActive = active
        guard active else { return }
        liveActivity?.clearFinished()
        catchUp(at: now)
    }

    func primaryAction(at now: Date = Date()) {
        if session.runState == .idle { alerts?.requestAuthorizationIfNeeded() }
        apply(at: now) { $0.primaryAction(at: now) }
    }

    func stop(at now: Date = Date()) {
        apply(at: now) { $0.stop(at: now) }
    }

    func choose(_ kind: StudyMethodKind, at now: Date = Date()) {
        apply(at: now) { $0.choose(kind, at: now) }
    }

    func setTimer(_ length: StudyTimerLength, at now: Date = Date()) {
        apply(at: now) { $0.setTimer(length, at: now) }
    }

    /// Another breed for the pet, from the breed picker.
    func setBreed(_ breed: PetBreed, at now: Date = Date()) {
        apply(at: now) { $0.setBreed(breed) }
    }

    #if DEBUG
    /// Debug builds only: the demo pet (Mochi in the Cozy Hoodie and
    /// Beanie, with the demo Closet's points), for screenshots.
    func useDemoPet(at now: Date = Date()) {
        apply(at: now) { $0.useCloset(.demo) }
    }
    #endif

    // MARK: Side effects

    /// Runs `change` on the engine and carries out the rest. `writeAll`
    /// (on launch) writes every file once; after that only what changed.
    private func apply(at now: Date, writeAll: Bool = false,
                       _ change: (inout StudyEngine) -> StudyEngine.Update) {
        let before = engine
        var after = engine
        let update = change(&after)
        engine = after
        if writeAll || after != before {
            try? persistence.save(after, replacing: writeAll ? nil : before, unreadable: unreadable)
        }
        if update.phaseCompleted, update.ended.contains(where: { now.timeIntervalSince($0.endedAt) < 60 }) {
            completions += 1
        }
        if let last = update.awards.last { celebrate(last) }
        observer?.studyDidChange(update, engine: after, at: now)
        let filming = observer?.isFilming ?? false
        alerts?.schedule(PhaseAlert.upcoming(for: after.session, filming: filming), now: now)
        liveActivity?.sync(after.session, pet: after.pet, at: now, finishedAway: !isActive && update.phaseCompleted,
                           filming: filming)
        armPhaseEnd()
    }

    /// Wakes at the running phase's end while the app is open, so the clock
    /// moves on without waiting for a tap. Suspended, the task simply never
    /// runs, and the next `catchUp` does its work.
    private func armPhaseEnd() {
        phaseEnd?.cancel()
        guard let endsAt = session.endsAt else { return }
        phaseEnd = Task { [weak self] in
            let wait = max(endsAt.timeIntervalSinceNow, 0) + 0.05
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.catchUp()
        }
    }

    private func celebrate(_ award: PetStudyAward) {
        self.award = award
        clearAward?.cancel()
        clearAward = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.award = nil
        }
    }
}
