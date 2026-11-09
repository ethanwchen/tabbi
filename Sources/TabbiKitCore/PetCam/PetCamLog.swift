import Foundation

/// When the camera arms, and when an early stop still counts. Data, so the
/// debug build can run whole loops in a minute.
///
/// One floor: any block of `minimumBlock` (five minutes) or more is filmed.
/// A normal block stopped early leaves the frozen still once it ran past
/// `commitAfter`; a dare stopped after its floor plays its whole tape, as
/// "Just 5 minutes" promises.
public struct PetCamRules: Codable, Hashable, Sendable {
    /// The shortest planned block that gets a camera and a tape.
    public var minimumBlock: TimeInterval
    /// A stop before this much focus is a cancel: no still, nothing kept.
    public var commitAfter: TimeInterval

    public init(minimumBlock: TimeInterval = 5 * 60, commitAfter: TimeInterval = 5 * 60) {
        self.minimumBlock = max(minimumBlock, 0)
        self.commitAfter = max(commitAfter, 0)
    }

    public static let standard = PetCamRules()

    /// Debug builds only: one-minute blocks arm the camera and a stop after
    /// ten seconds still counts, so a full loop takes a minute in a test.
    public static let quickTest = PetCamRules(minimumBlock: 60, commitAfter: 10)

    // Forgiving decoding: an older save's first-block rule is simply gone.
    private enum CodingKeys: String, CodingKey { case minimumBlock, commitAfter }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = PetCamRules.standard
        self.init(minimumBlock: (try? container.decode(TimeInterval.self, forKey: .minimumBlock)) ?? standard.minimumBlock,
                  commitAfter: (try? container.decode(TimeInterval.self, forKey: .commitAfter)) ?? standard.commitAfter)
    }
}

/// A block under way with the camera armed. Nothing about it is shown
/// until it resolves.
public struct PetCamActiveBlock: Codable, Hashable, Sendable {
    public var id: String
    public var setup: PetCamSetup
    /// Where the camera hides: the spot tapped, or the stare when the
    /// player just pressed Start.
    public var camera: PetCamSpot
    /// Whether the player tapped a spot rather than following the stare.
    public var picked: Bool
    /// "What are you avoiding?", only ever shown in the tape and on the
    /// mugshot, never on the Lock Screen.
    public var dodge: String?
    /// Started from the "Just 5 minutes" dare.
    public var dare: Bool
    /// The focus length the method planned; nil for open-ended Flowtime.
    public var plannedLength: TimeInterval?
    public var startedAt: Date
    /// The room as the block began (objects and the wrecks in view), which
    /// the tape draws.
    public var room: PetCamRoom
    /// The pet as it looked, so an old mugshot keeps its outfit.
    public var pet: PetProfile
    /// Whether this is the first block ever (it may be shorter).
    public var isFirstBlock: Bool

    public init(id: String, setup: PetCamSetup, camera: PetCamSpot, picked: Bool, dodge: String?, dare: Bool,
                plannedLength: TimeInterval?, startedAt: Date, room: PetCamRoom, pet: PetProfile, isFirstBlock: Bool) {
        self.id = id
        self.setup = setup
        self.camera = camera
        self.picked = picked
        self.dodge = dodge
        self.dare = dare
        self.plannedLength = plannedLength
        self.startedAt = startedAt
        self.room = room
        self.pet = pet
        self.isFirstBlock = isFirstBlock
    }
}

/// One resolved block: everything its tape (or still) needs to replay
/// exactly, and what it did to the room. The log keeps one per block id.
public struct PetCamBlockRecord: Codable, Hashable, Sendable, Identifiable {
    public enum Outcome: String, Codable, Hashable, Sendable {
        /// The camera was where the pet struck: a tape and a mugshot.
        case caught
        /// The camera watched the wrong spot: a tape of the alibi.
        case missed
        /// Stopped after the commit point: one frozen still, no tape.
        case stopped
        /// Stopped before the commit point: nothing to show.
        case cancelled

        /// Whether the block played a tape.
        public var hasTape: Bool { self == .caught || self == .missed }
    }

    /// The version of this record's shape; fields are only ever added.
    public static let currentVersion = 1

    public var id: String
    public var version: Int
    public var setup: PetCamSetup
    public var camera: PetCamSpot
    public var picked: Bool
    public var dodge: String?
    public var dare: Bool
    public var plannedLength: TimeInterval?
    public var startedAt: Date
    public var endedAt: Date
    /// Focus that actually ran, excluding pauses.
    public var worked: TimeInterval
    public var outcome: Outcome
    /// Where the pet struck; nil when the block did not finish.
    public var strike: PetCamSpot?
    /// The object it got; nil when the block did not finish.
    public var struck: PetCamObject?
    public var room: PetCamRoom
    public var pet: PetProfile
    /// The words the tape burns in, chosen when the block resolved, so a
    /// replay reads the same however much history comes after it.
    public var captions: PetCamCaptionSet
    /// The tape's shape (`PetCamTape.Shape`), chosen when the block
    /// resolved so it differs from the last tapes of the same outcome; nil
    /// for a block without a tape.
    public var shape: Int?
    /// A catch's case number on the wall (1 for the first catch ever); nil
    /// for anything else, or a record from before it was kept.
    public var caseNumber: Int?
    /// A catch's count on its object's rap sheet (1 the first time the pet
    /// is caught with that kind); nil for anything else.
    public var offense: Int?

    public init(id: String, setup: PetCamSetup, camera: PetCamSpot, picked: Bool, dodge: String?, dare: Bool,
                plannedLength: TimeInterval?, startedAt: Date, endedAt: Date, worked: TimeInterval, outcome: Outcome,
                strike: PetCamSpot?, struck: PetCamObject?, room: PetCamRoom, pet: PetProfile, captions: PetCamCaptionSet,
                shape: Int? = nil, caseNumber: Int? = nil, offense: Int? = nil) {
        self.id = id
        version = Self.currentVersion
        self.setup = setup
        self.camera = camera
        self.picked = picked
        self.dodge = dodge
        self.dare = dare
        self.plannedLength = plannedLength
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.worked = worked
        self.outcome = outcome
        self.strike = strike
        self.struck = struck
        self.room = room
        self.pet = pet
        self.captions = captions
        self.shape = shape
        self.caseNumber = caseNumber
        self.offense = offense
    }

    /// The rap-sheet tier of a catch: 1 the first time with its object,
    /// 2 the second and third, 3 from the fourth on.
    public var tier: Int { PetCamBlockRecord.tier(offense ?? 1) }

    public static func tier(_ offense: Int) -> Int { offense >= 4 ? 3 : offense >= 2 ? 2 : 1 }
}

/// Every resolved block, one per block id, oldest first.
///
/// The log is the Pet Cam's sync-ready history: versioned, additive (an
/// unknown field is ignored and a record this build cannot read is
/// dropped, never the file), and credited once per block id, so a block
/// that a Mac and a phone both report, or that is replayed after a crash,
/// changes the room and the wall exactly once. `merge` is a union by id,
/// which is commutative and idempotent.
public struct PetCamLog: Codable, Hashable, Sendable {
    public private(set) var blocks: [PetCamBlockRecord]
    /// The ids in `blocks`, for the once-per-id check.
    private var ids: Set<String>
    /// Every kind's catch count (kinds never caught are absent), kept as
    /// blocks are recorded so a long history stays cheap to ask.
    public private(set) var catchCounts: [PetCamObjectKind: Int]
    /// How many catches there are in all.
    public private(set) var catchTotal: Int

    public init(blocks: [PetCamBlockRecord] = []) {
        self.blocks = []
        ids = []
        catchCounts = [:]
        catchTotal = 0
        for block in blocks { record(block) }
    }

    public func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    public func block(_ id: String) -> PetCamBlockRecord? {
        guard ids.contains(id) else { return nil }
        return blocks.last { $0.id == id }
    }

    /// Adds `block` unless its id is already logged. Returns whether it
    /// was added, which is the one place a block gets credited.
    @discardableResult
    public mutating func record(_ block: PetCamBlockRecord) -> Bool {
        guard ids.insert(block.id).inserted else { return false }
        if block.outcome == .caught {
            catchTotal += 1
            if let kind = block.struck?.kind { catchCounts[kind, default: 0] += 1 }
        }
        // Blocks almost always resolve in order, so look from the end.
        var index = blocks.endIndex
        while index > blocks.startIndex, Self.precedes(block, blocks[index - 1]) { index -= 1 }
        blocks.insert(block, at: index)
        return true
    }

    /// Adds every block of `other` this log does not have yet.
    public mutating func merge(_ other: PetCamLog) {
        for block in other.blocks { record(block) }
    }

    /// Resolution order: by end time, then id, so two devices sort alike.
    private static func precedes(_ a: PetCamBlockRecord, _ b: PetCamBlockRecord) -> Bool {
        a.endedAt != b.endedAt ? a.endedAt < b.endedAt : a.id < b.id
    }

    /// The catches, oldest first: the mugshot wall.
    public var mugshots: [PetCamBlockRecord] { blocks.filter { $0.outcome == .caught } }

    /// How many times the pet has been caught with `kind`: its rap sheet.
    public func offenses(with kind: PetCamObjectKind) -> Int { catchCounts[kind] ?? 0 }

    /// Blocks that played a tape.
    public var tapes: [PetCamBlockRecord] { blocks.filter { $0.outcome.hasTape } }

    /// Whether a tape was ever made (the first block may be shorter).
    public var hasTape: Bool { blocks.contains { $0.outcome.hasTape } }

    // MARK: Codable

    /// Version 1 is the first Pet Cam log. Add a step for any change that
    /// is not purely additive; never edit one that has shipped.
    public static let schema = VersionedJSON(current: 1)

    private enum CodingKeys: String, CodingKey { case blocks }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(blocks: try container.decodeIfPresent(PetCamLossyList<PetCamBlockRecord>.self, forKey: .blocks)?
            .elements ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(blocks, forKey: .blocks)
    }
}

