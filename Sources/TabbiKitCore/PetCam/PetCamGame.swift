import Foundation

/// The Pet Cam game as a pure value: the room, the frozen frame the home
/// screen shows (`setup`), the block under way, and the log.
///
/// One sealed tap per block. Before Start the home screen shows the room
/// and the pet's stare; the player may tap a spot to hide the camera there,
/// or just press Start and the camera follows the stare. Then nothing about
/// the room is shown until the block resolves:
///
/// - It runs to its planned end (`finish`): the pet strikes where the seed
///   says, the camera either caught it or watched the wrong spot, the room
///   keeps the wreck and gets a new object, and a tape is waiting.
/// - It is stopped (`stop`): one still of the pet frozen mid-sneak, or
///   nothing before the commit point. The frozen frame stays as it was, so
///   stopping never rerolls the tell and finishing never pays worse.
///
/// Every call takes `now`, and every roll comes from the setup's seed, so
/// the whole game replays from its first seed and tests pin each outcome.
/// Points are not paid here: the study engine pays the foundation's points
/// for the same block, exactly as without the camera.
public struct PetCamGame: Codable, Hashable, Sendable {
    public private(set) var room: PetCamRoom
    public private(set) var log: PetCamLog
    /// The frozen frame: the stare and any exception for the next block.
    public private(set) var setup: PetCamSetup
    public private(set) var active: PetCamActiveBlock?
    /// Resolved blocks whose tape or still has not been watched yet,
    /// oldest first.
    public private(set) var unwatched: [String]
    /// The read the next prepared setup uses.
    public var tuning: PetCamTuning
    public var rules: PetCamRules
    /// The species the frozen frame was prepared for (the appetite
    /// exception depends on it).
    public private(set) var species: PetSpecies

    /// A new game: the starter room and a setup from `seed`.
    public init(seed: UInt64, species: PetSpecies = .cat, tuning: PetCamTuning = .standard,
                rules: PetCamRules = .standard, at date: Date) {
        let room = PetCamRoom.starter(at: date)
        self.room = room
        log = PetCamLog()
        setup = PetCamSetup.prepare(seed: seed, room: room, species: species, tuning: tuning, at: date)
        active = nil
        unwatched = []
        self.tuning = tuning
        self.rules = rules
        self.species = species
    }

    /// Whether the next block is the very first.
    public var isFirstBlock: Bool { !log.hasTape }

    /// The shortest focus block that arms the camera.
    public var minimumBlock: TimeInterval { rules.minimumBlock }

    /// Whether a block of `plannedLength` arms the camera (a dare from its
    /// own, shorter floor); open-ended blocks (nil) arm it and are judged by
    /// the time worked at the end.
    public func arms(plannedLength: TimeInterval?, dare: Bool = false) -> Bool {
        guard let plannedLength else { return true }
        return plannedLength + 0.5 >= (dare ? rules.dareBlock : minimumBlock)
    }

    /// How long after a filmed block the dare stays away: "Just 5 minutes"
    /// starts a sitting, so it shows only when no filmed block ended in the
    /// last hour.
    public static let sittingGap: TimeInterval = 3600

    /// Whether "Just 5 minutes" is offered at `date`.
    public func offersDare(at date: Date) -> Bool {
        guard active == nil else { return false }
        guard let last = log.blocks.last(where: { $0.outcome.hasTape }) else { return true }
        return date.timeIntervalSince(last.endedAt) >= Self.sittingGap
    }

    // MARK: Before a block

    /// Draws the frozen frame again from the same seed with the current
    /// tuning and species (after the debug panel changes the read, or the
    /// player picks another breed). The stare comes from the seed, so the
    /// same seed shows the same stare.
    public mutating func reprepare(species: PetSpecies? = nil, at date: Date) {
        guard active == nil else { return }
        if let species { self.species = species }
        setup = PetCamSetup.prepare(seed: setup.seed, room: room, species: self.species, tuning: tuning,
                                    history: log.blocks, at: date)
    }

    /// Arms the camera for a block that just started. `pick` is the tapped
    /// spot, or nil to follow the stare. Returns nil (and changes nothing)
    /// when a block is already armed or `plannedLength` is too short.
    @discardableResult
    public mutating func start(id: String, pick: PetCamSpot?, dodge: String?, dare: Bool,
                               plannedLength: TimeInterval?, pet: PetProfile, at date: Date) -> PetCamActiveBlock? {
        guard active == nil, arms(plannedLength: plannedLength, dare: dare), !log.contains(id) else { return nil }
        if pet.species != species { reprepare(species: pet.species, at: date) }
        let block = PetCamActiveBlock(
            id: id, setup: setup, camera: pick ?? setup.stare, picked: pick != nil,
            dodge: Self.keptDodge(dodge),
            dare: dare, plannedLength: plannedLength, startedAt: date, room: room, pet: pet,
            isFirstBlock: isFirstBlock
        )
        active = block
        return block
    }

    /// The dodge line as typed, trimmed and at most 80 characters; nil
    /// when empty. Captions shorten it further (`cleanDodge`).
    static func keptDodge(_ text: String?) -> String? {
        guard let line = text?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { return nil }
        return String(line.prefix(80))
    }

    // MARK: Resolving

    /// The armed block's focus ran out (or an open-ended one was ended
    /// normally) at `endedAt` after `worked` seconds of focus: the strike
    /// happens, the room keeps it, and the tape is ready. An open-ended
    /// block that ran shorter than the minimum is a stop instead.
    @discardableResult
    public mutating func finish(endedAt: Date, worked: TimeInterval, calendar: Calendar = .current) -> PetCamBlockRecord? {
        guard let block = active else { return nil }
        if block.plannedLength == nil, worked + 0.5 < (block.dare ? rules.dareBlock : rules.minimumBlock) {
            return stop(at: endedAt, worked: worked, calendar: calendar)
        }
        let strike = block.setup.strike
        let outcome: PetCamBlockRecord.Outcome = strike == block.camera ? .caught : .missed
        guard let struck = block.room.object(at: strike) ?? room.object(at: strike) else {
            active = nil
            return nil
        }
        let offense = log.offenses(with: struck.kind) + 1
        let captions = PetCamCaptions.tape(
            outcome: outcome, setup: block.setup, camera: block.camera, strike: strike, struck: struck,
            room: block.room, dodge: block.dodge, history: log.blocks, offense: offense, worked: worked,
            seenKinds: log.seenKinds, at: endedAt, calendar: calendar
        )
        // Never one of the last two tape shapes of the same outcome.
        var recent: [PetCamTape.Shape] = []
        for earlier in log.blocks.reversed() where earlier.outcome == outcome {
            if let shape = earlier.shape.flatMap(PetCamTape.Shape.init(rawValue:)) { recent.append(shape) }
            if recent.count == 2 { break }
        }
        let caught = outcome == .caught
        let record = PetCamBlockRecord(
            id: block.id, setup: block.setup, camera: block.camera, picked: block.picked, dodge: block.dodge,
            dare: block.dare, plannedLength: block.plannedLength, startedAt: block.startedAt, endedAt: endedAt,
            worked: worked, outcome: outcome, strike: strike, struck: struck, room: block.room, pet: block.pet,
            captions: captions, shape: PetCamTape.shape(seed: block.setup.seed, recent: recent).rawValue,
            caseNumber: caught ? log.catchTotal + 1 : nil,
            offense: caught ? offense : nil
        )
        active = nil
        absorb(record)
        return record
    }

    /// The armed block was stopped (or skipped, or its method switched) at
    /// `date` after `worked` seconds of focus. Past the commit point it
    /// leaves one frozen still; before it, nothing. Either way the frozen
    /// frame stays: the same stare and the same seed wait for the next block.
    @discardableResult
    public mutating func stop(at date: Date, worked: TimeInterval, calendar: Calendar = .current) -> PetCamBlockRecord? {
        guard let block = active else { return nil }
        // "Just 5 minutes": a dare stopped once its five minutes are in is a
        // finished block, with the same strike and the whole tape.
        if block.dare, worked + 0.5 >= rules.dareBlock {
            return finish(endedAt: date, worked: worked, calendar: calendar)
        }
        active = nil
        let outcome: PetCamBlockRecord.Outcome = worked + 0.5 >= rules.commitAfter ? .stopped : .cancelled
        let record = PetCamBlockRecord(
            id: block.id, setup: block.setup, camera: block.camera, picked: block.picked, dodge: block.dodge,
            dare: block.dare, plannedLength: block.plannedLength, startedAt: block.startedAt, endedAt: date,
            worked: worked, outcome: outcome, strike: nil, struck: nil, room: block.room, pet: block.pet,
            captions: PetCamCaptions.frozen(setup: block.setup, at: date, calendar: calendar)
        )
        guard log.record(record) else { return nil }
        if outcome == .stopped { unwatched.append(record.id) }
        return record
    }

    /// Applies a resolved block once: logs it, and for a tape wrecks the
    /// struck object, leaves a new one out and prepares the next frozen
    /// frame from the block's seed chain. A block id already in the log
    /// changes nothing, so a record replayed after a crash or reported by a
    /// second device is credited once. Returns whether it was new.
    @discardableResult
    public mutating func absorb(_ record: PetCamBlockRecord) -> Bool {
        guard log.record(record) else { return false }
        guard record.outcome.hasTape, let strike = record.strike else { return true }
        var refill = PetCamRandom(seed: record.setup.seed, stream: "refill")
        // An object that has arrived but never stood in the room comes out
        // at this refill.
        let kinds = arrived
        let present = log.seenKinds.union(room.objects.values.map(\.kind)).union(room.wrecks.map(\.object.kind))
        room.strike(strike, at: record.endedAt, blockID: record.id, random: &refill, catches: log.catchCounts,
                    kinds: kinds, fresh: kinds.filter { !present.contains($0) })
        room.sweep()
        if active == nil, record.setup.seed == setup.seed {
            setup = PetCamSetup.prepare(seed: record.setup.nextSeed, room: room, species: species, tuning: tuning,
                                        history: log.blocks, at: record.endedAt)
        }
        unwatched.append(record.id)
        return true
    }

    /// The kinds that have arrived so far, the six starters first: one more
    /// after every five hours of focus. Nothing shows the way to the next.
    public var arrived: [PetCamObjectKind] { PetCamObjectKind.arrived(afterFocus: log.totalFocus) }

    /// The oldest tape or still not watched yet.
    public var nextUnwatched: PetCamBlockRecord? {
        unwatched.lazy.compactMap { log.block($0) }.first
    }

    public mutating func markWatched(_ id: String) {
        unwatched.removeAll { $0 == id }
    }

    // MARK: Codable

    /// Version 1 is the first Pet Cam save. Fields are only ever added;
    /// a missing one takes its default.
    public static let schema = VersionedJSON(current: 1)

    private enum CodingKeys: String, CodingKey {
        case room, log, setup, active, unwatched, tuning, rules, species
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        room = try container.decode(PetCamRoom.self, forKey: .room)
        log = try container.decodeIfPresent(PetCamLog.self, forKey: .log) ?? PetCamLog()
        setup = try container.decode(PetCamSetup.self, forKey: .setup)
        active = try? container.decodeIfPresent(PetCamActiveBlock.self, forKey: .active)
        unwatched = (try? container.decodeIfPresent([String].self, forKey: .unwatched)) ?? []
        tuning = (try? container.decodeIfPresent(PetCamTuning.self, forKey: .tuning)) ?? .standard
        rules = (try? container.decodeIfPresent(PetCamRules.self, forKey: .rules)) ?? .standard
        species = (try? container.decodeIfPresent(PetSpecies.self, forKey: .species)) ?? .cat
        var fill = PetCamRandom(seed: setup.seed, stream: "fill")
        room.refill(at: setup.preparedAt, random: &fill)
    }
}

/// What a block is worth when it resolves, for the rule that finishing
/// never pays worse than stopping: the foundation's points for the minutes
/// (with the completion bonus) and the reveal it earns.
public struct PetCamPayout: Hashable, Sendable {
    /// The reveal, from nothing up to a tape.
    public enum Reveal: Int, Comparable, Sendable {
        case nothing
        /// One frozen still of the pet mid-sneak.
        case still
        /// A full tape: a catch (with its mugshot) or a miss (with its alibi).
        case tape

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var points: Int
    public var reveal: Reveal

    /// The payout of a block that ended with `outcome` after `worked`.
    public init(outcome: PetCamBlockRecord.Outcome, worked: TimeInterval) {
        let completed = outcome.hasTape
        points = PetPointsRules.points(forMinutes: Int(worked / 60), completed: completed)
        reveal = switch outcome {
        case .caught, .missed: .tape
        case .stopped: .still
        case .cancelled: .nothing
        }
    }

    /// Whether this payout is at least as good as `other` on every count.
    public func isAtLeast(_ other: PetCamPayout) -> Bool {
        points >= other.points && reveal >= other.reveal
    }
}
