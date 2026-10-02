import AppKit
import Combine
import NotchKitCore

/// The Study tab's timer: owns the `StudySession` so a block keeps running
/// while the notch is closed or another tab is showing.
///
/// Like `FocusStore`, time comes from wall-clock dates. A one-shot timer
/// fires at the running phase's end to chime and roll into the next phase,
/// and the view only ticks once a second while the panel is visible. The
/// session is saved on every change so a relaunch picks up where it was.
/// Finished stretches move from the session into the persisted `StudyLog`,
/// which totals the day and holds earned points for the pet ledger.
/// With `NOTCHDECK_DEMO=1` it shows a sample Pomodoro round and a sample
/// day, and never touches sounds or disk.
@MainActor
final class StudyStore: ObservableObject {
    @Published private(set) var session: StudySession
    /// The moment the view measures against; advances every second while visible.
    @Published private(set) var now = Date()
    /// Every logged study stretch and the points not yet credited to the pet.
    @Published private(set) var log: StudyLog

    private let isDemo: Bool
    private let defaults = UserDefaults.standard
    private var isVisible = false
    private var ticker: Timer?
    private var phaseEndTimer: Timer?
    private let logURL: URL?
    /// Set when the log on disk could not be read: new stretches are still
    /// logged in memory, but the file is never overwritten, so nothing is lost.
    private let logIsUnreadable: Bool

    private static let sessionKey = "study.session"

    init(edition: Edition = .current) {
        isDemo = ProcessInfo.processInfo.environment["NOTCHDECK_DEMO"] == "1"
        if isDemo {
            let now = Date()
            session = Self.demoSession(StudySnapshotState.current?.demoMethod ?? .pomodoro, now: now)
            log = Self.demoLog(now: now)
            logURL = nil
            logIsUnreadable = false
            return
        }
        session = defaults.data(forKey: Self.sessionKey)
            .flatMap { try? JSONDecoder().decode(StudySession.self, from: $0) }
            ?? StudySession(method: .pomodoro)
        logURL = Self.logURL(for: edition)
        do {
            log = try logURL.flatMap { try StudyLog.load(from: $0) } ?? StudyLog()
            logIsUnreadable = false
        } catch {
            log = StudyLog()
            logIsUnreadable = true
        }
        // A phase may have ended while the app wasn't running; catch up quietly.
        session.advance(to: Date())
        scheduleSideEffects()
    }

    /// `~/Library/Application Support/<edition>/Study/log.json`.
    static func logURL(for edition: Edition) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("\(edition.name)/Study/log.json")
    }

    var readout: StudyDialReadout { StudyTimerFormat.readout(session, at: now) }
    var progress: Double? { session.progress(at: now) }
    /// Minutes, finished stretches and points logged today.
    var today: StudyDaySummary { log.summary(on: now) }

    /// Call from the panel's `onAppear` / `onDisappear`; the clock ticks
    /// only while it's visible.
    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        catchUp()
        updateTicker()
    }

    /// The big button: start, pause, resume, or end a Flowtime stretch.
    func primaryAction() {
        catchUp()
        if session.isRunning, session.phase == .focus, case .openEnded = session.method.focus {
            change { $0.stopFocus(at: now) }
        } else if session.isRunning {
            change { $0.pause(at: now) }
        } else {
            change { $0.start(at: now) }
        }
    }

    func pause() {
        catchUp()
        change { $0.pause(at: now) }
    }

    func skip() {
        catchUp()
        change { $0.skip(at: now) }
    }

    func reset() {
        catchUp()
        change { $0.reset(at: now) }
    }

    /// Starts over with `kind`'s preset; no-op if it's already the method.
    func choose(_ kind: StudyMethodKind) {
        guard kind != session.method.kind else { return }
        catchUp()
        change { $0.switchMethod(to: .preset(kind), at: now) }
    }

    // MARK: Private

    /// Applies `edit`, then saves and re-arms the phase-end timer and ticker.
    private func change(_ edit: (inout StudySession) -> Void) {
        var updated = session
        edit(&updated)
        guard updated != session else { return }
        session = updated
        scheduleSideEffects()
        updateTicker()
    }

    /// Moves `now` forward and applies phase ends that have passed, chiming
    /// for one that just happened.
    private func catchUp() {
        now = Date()
        let ended = session.advance(to: now)
        guard !ended.isEmpty else { return }
        // Stale ends (the Mac was asleep) stay quiet.
        if !isDemo, let last = ended.last, now.timeIntervalSince(last.endedAt) < 60 {
            Self.playChime()
        }
        scheduleSideEffects()
        updateTicker()
    }

    /// Moves finished stretches into the log, saves the session and the log,
    /// and arms a one-shot timer for the running phase's end.
    private func scheduleSideEffects() {
        guard !isDemo else { return }
        collectLog()
        if let data = try? JSONEncoder().encode(session) { defaults.set(data, forKey: Self.sessionKey) }

        phaseEndTimer?.invalidate()
        phaseEndTimer = nil
        guard let endsAt = session.endsAt else { return }
        let fire = Timer(fire: endsAt, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.catchUp() }
        }
        fire.tolerance = 0.2
        RunLoop.main.add(fire, forMode: .common)
        phaseEndTimer = fire
    }

    /// Ticks once a second, only while the panel is visible and the clock runs.
    private func updateTicker() {
        guard isVisible, session.isRunning, !isDemo else {
            ticker?.invalidate()
            ticker = nil
            return
        }
        guard ticker == nil else { return }
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.catchUp() }
        }
        tick.tolerance = 0.1
        RunLoop.main.add(tick, forMode: .common)
        ticker = tick
    }

    /// Drains the session's phase records into the persisted log.
    private func collectLog() {
        guard !session.log.isEmpty else { return }
        var updated = log
        updated.record(session.takeLog())
        if updated != log {
            log = updated
            if let logURL, !logIsUnreadable { try? log.write(to: logURL) }
        }
    }

    private static func playChime() {
        guard let sound = NSSound(named: "Glass") else { return }
        sound.volume = 0.5
        sound.play()
    }

    /// A believable session part-way through: a Pomodoro on its second
    /// round, a Flowtime stretch counting up, a sprint with cards done, or
    /// another method a bit over a third into its first focus block.
    private static func demoSession(_ kind: StudyMethodKind, now: Date) -> StudySession {
        var session = StudySession(method: .preset(kind))
        switch kind {
        case .pomodoro:
            let start = now.addingTimeInterval(-(30 * 60 + 9 * 60 + 47))
            session.start(at: start)
            session.advance(to: start.addingTimeInterval(30 * 60))
            session.start(at: start.addingTimeInterval(30 * 60))
        case .flowtime:
            session.start(at: now.addingTimeInterval(-(23 * 60 + 12)))
        case .ankiSprint:
            let start = now.addingTimeInterval(-(11 * 60 + 5))
            session.start(at: start)
            session.recordReviewedToday(120, at: start)
            session.recordReviewedToday(157, at: now)
        default:
            if case .duration(let length) = session.method.focus {
                session.start(at: now.addingTimeInterval(-(length * 0.38).rounded()))
            }
        }
        _ = session.takeLog()
        return session
    }

    /// A morning's work: two finished Pomodoros and a short sprint.
    private static func demoLog(now: Date) -> StudyLog {
        let start = Calendar.current.startOfDay(for: now).addingTimeInterval(9 * 3600)
        func stretch(_ method: StudyMethodKind, from minute: Double, minutes: Double, cards: Int? = nil) -> StudyPhaseRecord {
            StudyPhaseRecord(method: method, phase: .focus, startedAt: start.addingTimeInterval(minute * 60),
                             endedAt: start.addingTimeInterval((minute + minutes) * 60),
                             activeDuration: minutes * 60, outcome: .completed, cards: cards)
        }
        var log = StudyLog()
        log.record([stretch(.pomodoro, from: 0, minutes: 25), stretch(.pomodoro, from: 30, minutes: 25),
                    stretch(.ankiSprint, from: 70, minutes: 14, cards: 100)])
        return log
    }
}
