import Foundation
import Observation
import TabbiKitCore

/// Runs the Pet Cam game beside the study session.
///
/// The study engine owns the clock and the points, exactly as in the
/// foundation; this store only listens. Start arms the camera for the
/// focus block about to begin (the one sealed tap: a spot, or the stare),
/// and when that block's focus phase ends the store resolves it: run to its
/// end (or a Flowtime stretch ended normally) is a tape, cut short is the
/// frozen still. Blocks are matched by the moment their focus began, so a
/// block that ended while the app was killed is resolved on the next launch,
/// at its real end time, and credited once by its block id.
@MainActor
@Observable
final class PetCamStore: StudyObserver {
    private(set) var game: PetCamGame
    /// The spot tapped on the frozen frame; nil follows the stare.
    var pick: PetCamSpot?
    /// "What are you avoiding?", for this block only.
    var dodge = ""
    /// The oldest tape or still not watched yet, which the app shows as
    /// soon as it is on screen.
    private(set) var reveal: PetCamBlockRecord?

    @ObservationIgnored private let persistence: PetCamPersistence
    @ObservationIgnored private var unreadable: Bool
    @ObservationIgnored private var isActive = true

    init(persistence: PetCamPersistence = .standard, now: Date = Date(), seed: UInt64? = nil) {
        self.persistence = persistence
        let loaded = persistence.load()
        unreadable = loaded.unreadable
        game = loaded.game ?? PetCamGame(seed: seed ?? UInt64.random(in: .min ... .max), at: now)
        #if DEBUG
        DebugLaunch.apply(to: &game, at: now)
        #endif
        if loaded.game == nil { save() }
        refreshReveal()
    }

    // MARK: Reading

    /// The oldest block that resolved but whose tape (or still) has not
    /// been watched. Until it is, the home screen keeps the room, the
    /// frozen frame and the wall as they were before that block, so
    /// nothing on it gives the tape away.
    private var unseen: PetCamBlockRecord? { game.nextUnwatched }

    /// Whether a tape or still is waiting to be watched, even while the app
    /// is away and the reveal itself waits: the root then shows static
    /// rather than the home screen, so coming back to the app goes straight
    /// to the tape, never past the home screen.
    var hasTapeWaiting: Bool { unseen != nil }

    /// The room the home screen shows.
    var shownRoom: PetCamRoom { unseen?.room ?? game.room }

    /// The frozen frame the home screen shows.
    var shownSetup: PetCamSetup { unseen?.setup ?? game.setup }

    /// The frozen frame the home screen draws.
    var frozenShot: PetCamShot { PetCamShot.frozenFrame(room: shownRoom, setup: shownSetup) }

    /// The camera that films the block under way, by its number; nil when
    /// no block is armed.
    var filmingCamera: Int? { game.active?.camera.cameraNumber }

    var isFilming: Bool { game.active != nil }

    /// The camera's spot for the next block: the tap, or the stare.
    var cameraSpot: PetCamSpot { pick ?? shownSetup.stare }

    /// Blocks watched so far (the wall only files what was seen).
    private var seen: [PetCamBlockRecord] {
        let waiting = Set(game.unwatched)
        return game.log.blocks.filter { !waiting.contains($0.id) }
    }

    /// The catches, newest first: the mugshots on the wall.
    var mugshots: [PetCamBlockRecord] { seen.filter { $0.outcome == .caught }.reversed() }

    /// Every tape watched, newest first: the wall's case log, catches and
    /// cold cases (misses) alike.
    var cases: [PetCamBlockRecord] { seen.filter(\.outcome.hasTape).reversed() }

    /// The objects the pet has been caught with at least once.
    var caughtKinds: Set<PetCamObjectKind> { Set(mugshots.compactMap(\.struck?.kind)) }

    /// How many times each object was caught, among the tapes watched.
    var caughtCounts: [PetCamObjectKind: Int] {
        var counts: [PetCamObjectKind: Int] = [:]
        for record in mugshots { if let kind = record.struck?.kind { counts[kind, default: 0] += 1 } }
        return counts
    }

    /// A catch's case number on the wall (1 for the first), counting every
    /// catch however it was filed; nil for anything else.
    func caseNumber(of record: PetCamBlockRecord) -> Int? {
        guard record.outcome == .caught else { return nil }
        return record.caseNumber ?? (game.log.mugshots.firstIndex { $0.id == record.id } ?? 0) + 1
    }

    // MARK: Actions

    /// Starts (or resumes, or pauses) the session from the home screen.
    /// An idle focus block long enough for the camera is armed first, with
    /// the tap or the stare and the dodge line, at the same moment the
    /// session starts, which is how its end is recognized later.
    func start(study: StudyStore, dare: Bool = false, now: Date = Date()) {
        let session = study.session
        if session.runState == .idle, session.phase == .focus,
           game.arms(plannedLength: session.phaseDuration, dare: dare) {
            game.start(id: UUID().uuidString, pick: pick, dodge: dodge, dare: dare,
                       plannedLength: session.phaseDuration, pet: study.pet, at: now)
            pick = nil
            dodge = ""
            save()
        }
        study.primaryAction(at: now)
    }

    /// Follows the scene, so a tape that came in while the app was away
    /// waits until it is on screen.
    func setActive(_ active: Bool) {
        isActive = active
        refreshReveal()
    }

    /// The tape or still was watched (to its end, or closed).
    func watched(_ record: PetCamBlockRecord) {
        game.markWatched(record.id)
        save()
        refreshReveal()
    }

    /// The pet changed breed: the frozen frame is drawn again for it (the
    /// appetite exception depends on the species).
    func petChanged(_ pet: PetProfile, now: Date = Date()) {
        guard game.species != pet.species else { return }
        game.reprepare(species: pet.species, at: now)
        save()
    }

    // MARK: StudyObserver

    func studyDidChange(_ update: StudyEngine.Update, engine: StudyEngine, at now: Date) {
        guard let active = game.active else { return }
        let ended = update.ended.first {
            $0.phase == .focus && abs($0.startedAt.timeIntervalSince(active.startedAt)) < 1.5
        }
        if let ended {
            resolve(outcome: ended.outcome, endedAt: ended.endedAt, worked: ended.activeDuration)
        } else if engine.session.phase != .focus || engine.session.runState == .idle {
            // The block's focus is no longer under way but its end was not
            // in this update (a session restored from older data): settle
            // it from the study log, or as a cancel when it never ran.
            let entry = engine.log.entries.last { abs($0.startedAt.timeIntervalSince(active.startedAt)) < 1.5 }
            if let entry {
                resolve(outcome: entry.completed ? .completed : .abandoned, endedAt: entry.endedAt,
                        worked: TimeInterval(entry.minutes * 60))
            } else {
                game.stop(at: now, worked: 0)
                save()
            }
        }
    }

    private func resolve(outcome: StudyPhaseOutcome, endedAt: Date, worked: TimeInterval) {
        switch outcome {
        case .completed, .stopped: game.finish(endedAt: endedAt, worked: worked)
        case .skipped, .abandoned: game.stop(at: endedAt, worked: worked)
        }
        save()
        refreshReveal()
    }

    private func refreshReveal() {
        let next = isActive ? game.nextUnwatched : nil
        if next?.id != reveal?.id { reveal = next }
    }

    private func save() {
        guard !unreadable else { return }
        try? persistence.save(game)
    }

    // MARK: Debug

    #if DEBUG
    /// The debug tuning panel's edits: the read for the next frozen frame,
    /// drawn again at once so the change shows.
    func setTuning(_ tuning: PetCamTuning, now: Date = Date()) {
        game.tuning = tuning
        game.reprepare(at: now)
        save()
    }

    /// One-minute blocks that arm the camera, for playing whole loops fast.
    func setQuickBlocks(_ quick: Bool) {
        game.rules = quick ? .quickTest : .standard
        save()
    }

    /// A fresh room and history, keeping the tuning.
    func resetGame(now: Date = Date()) {
        let tuning = game.tuning, rules = game.rules
        game = PetCamGame(seed: UInt64.random(in: .min ... .max), species: game.species, tuning: tuning, rules: rules,
                          at: now)
        pick = nil
        save()
        refreshReveal()
    }

    /// Shows a logged tape again (from the panel).
    func replay(_ record: PetCamBlockRecord) {
        reveal = record
    }
    #endif
}

/// Application Support/Tabbi/petcam.json: the whole game, versioned
/// (`PetCamGame.schema`). A file that exists but cannot be read is never
/// overwritten, so a newer build's game survives a downgrade.
struct PetCamPersistence {
    let url: URL

    static var standard: PetCamPersistence {
        PetCamPersistence(url: StudyPersistence.standard.folder.appendingPathComponent("petcam.json"))
    }

    func load() -> (game: PetCamGame?, unreadable: Bool) {
        guard let data = try? Data(contentsOf: url) else { return (nil, false) }
        do {
            return (try PetCamGame.schema.decode(PetCamGame.self, from: data), false)
        } catch {
            return (nil, true)
        }
    }

    func save(_ game: PetCamGame) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PetCamGame.schema.encode(game).write(to: url, options: .atomic)
    }
}

#if DEBUG
/// Launch arguments for tests and screenshots, debug builds only:
/// `-PetCamQuickBlocks` (one-minute blocks arm the camera) and
/// `-PetCamSeed <hex>` (the first frozen frame of a fresh game).
enum DebugLaunch {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func apply(to game: inout PetCamGame, at now: Date) {
        if let text = value(after: "-PetCamSeed"), let seed = PetCamSeed.parse(text), game.log.blocks.isEmpty,
           game.active == nil {
            game = PetCamGame(seed: seed, species: game.species, tuning: game.tuning, rules: game.rules, at: now)
        }
        if arguments.contains("-PetCamQuickBlocks") { game.rules = .quickTest }
    }
}
#endif
