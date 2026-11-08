import Foundation

/// One of the three lit spots in the Pet Cam room, each a piece of furniture
/// with one object on it. The room is seen from a high corner camera, so
/// the spots sit to the pet's left, behind it and to its right, and a stare
/// at one of them reads at a glance.
public enum PetCamSpot: String, Codable, CaseIterable, Hashable, Sendable {
    /// The kitchen counter along the left wall.
    case counter
    /// The low bookcase against the back wall.
    case shelf
    /// The side table under the lamp, on the right.
    case table

    /// The camera number the spot's hidden camera burns into its tape.
    /// The corner camera that films the whole room is CAM 1.
    public var cameraNumber: Int {
        switch self {
        case .counter: 2
        case .shelf: 3
        case .table: 4
        }
    }
}

/// Something left out on a spot for the pet to find. Each kind has its own
/// wreck art and its own off-screen sound (in `captions.json`), so a miss
/// still tells you what happened before you see it.
public enum PetCamObjectKind: String, Codable, CaseIterable, Hashable, Sendable {
    case mug
    case plant
    case fishbowl
    case vase
    case tissues
    /// The one the pet eats: it leaves crumbs, not a wreck to step around.
    case donut

    /// Whether the pet eats it rather than knocking it over.
    public var isEaten: Bool { self == .donut }
}

/// An object on a spot. `placedAt` is when it was left out, which the
/// callback captions count from ("MUG, LEFT OUT 3 DAYS AGO"), and `serial`
/// tells two mugs apart in the room's history.
public struct PetCamObject: Codable, Hashable, Sendable {
    public var kind: PetCamObjectKind
    public var placedAt: Date
    public var serial: Int

    public init(kind: PetCamObjectKind, placedAt: Date, serial: Int) {
        self.kind = kind
        self.placedAt = placedAt
        self.serial = serial
    }
}

/// What a strike left behind. Wrecks stay in the room, drawn on the floor
/// under their spot, until newer ones sweep them out of view; the block
/// log keeps every strike for the callbacks.
public struct PetCamWreck: Codable, Hashable, Sendable {
    public var object: PetCamObject
    public var spot: PetCamSpot
    public var wreckedAt: Date
    /// The block that caused it, so a wreck is made once per block id.
    public var blockID: String
    /// Which of its spot's places on the floor it lies in, kept from the
    /// moment it lands so wrecks never shuffle between blocks.
    public var slot: Int

    public init(object: PetCamObject, spot: PetCamSpot, wreckedAt: Date, blockID: String, slot: Int = 0) {
        self.object = object
        self.spot = spot
        self.wreckedAt = wreckedAt
        self.blockID = blockID
        self.slot = slot
    }

    private enum CodingKeys: String, CodingKey { case object, spot, wreckedAt, blockID, slot }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(object: try container.decode(PetCamObject.self, forKey: .object),
                  spot: try container.decode(PetCamSpot.self, forKey: .spot),
                  wreckedAt: try container.decode(Date.self, forKey: .wreckedAt),
                  blockID: try container.decode(String.self, forKey: .blockID),
                  slot: try container.decodeIfPresent(Int.self, forKey: .slot) ?? 0)
    }
}

/// The room the camera watches: one object on each spot and every wreck so
/// far. It only changes when a block resolves, so it drifts over days of
/// play instead of reshuffling, and absence never decays it.
public struct PetCamRoom: Codable, Hashable, Sendable {
    /// One entry per spot, in `PetCamSpot.allCases` order. A spot whose
    /// object a newer build added (an unknown kind) decodes as empty and is
    /// refilled, so an older build never fails on a newer room.
    public private(set) var objects: [PetCamSpot: PetCamObject]
    /// The wrecks on the floor, oldest first: at most
    /// `visibleWrecksPerSpot` per spot.
    public private(set) var wrecks: [PetCamWreck]
    /// The next object's serial.
    public private(set) var nextSerial: Int

    /// How many wrecks per spot stay on the floor; an older one is swept
    /// away (the block log still remembers it).
    public static let visibleWrecksPerSpot = 2

    public init(objects: [PetCamSpot: PetCamObject], wrecks: [PetCamWreck] = [], nextSerial: Int? = nil) {
        self.objects = objects
        self.wrecks = Self.swept(wrecks)
        let used = objects.values.map(\.serial) + wrecks.map(\.object.serial)
        self.nextSerial = max(nextSerial ?? 0, (used.max() ?? -1) + 1)
    }

    /// The room on day one: a mug on the counter, a plant on the shelf and a
    /// fishbowl on the side table, the trio from the pitch.
    public static func starter(at date: Date) -> PetCamRoom {
        PetCamRoom(objects: [
            .counter: PetCamObject(kind: .mug, placedAt: date, serial: 0),
            .shelf: PetCamObject(kind: .plant, placedAt: date, serial: 1),
            .table: PetCamObject(kind: .fishbowl, placedAt: date, serial: 2),
        ])
    }

    public func object(at spot: PetCamSpot) -> PetCamObject? { objects[spot] }

    /// The wrecks on the floor under `spot`, oldest first.
    public func visibleWrecks(at spot: PetCamSpot) -> [PetCamWreck] {
        wrecks.filter { $0.spot == spot }
    }

    /// `wrecks` in order with only the newest `visibleWrecksPerSpot` of
    /// each spot.
    private static func swept(_ wrecks: [PetCamWreck]) -> [PetCamWreck] {
        let ordered = wrecks.sorted { $0.wreckedAt != $1.wreckedAt ? $0.wreckedAt < $1.wreckedAt : $0.blockID < $1.blockID }
        var kept: [PetCamWreck] = []
        for wreck in ordered.reversed() where kept.filter({ $0.spot == wreck.spot }).count < visibleWrecksPerSpot {
            kept.append(wreck)
        }
        return kept.reversed()
    }

    /// Whether the block with `id` already wrecked something here.
    public func hasWreck(from blockID: String) -> Bool {
        wrecks.contains { $0.blockID == blockID }
    }

    /// The pet strikes `spot` at `date` in block `blockID`: the object there
    /// becomes a wreck on the floor and a new object is left out in its
    /// place, picked by `random` from the kinds not already in the room (and
    /// never the kind just wrecked), so three different things always wait.
    /// Applying the same block twice changes nothing.
    @discardableResult
    public mutating func strike(_ spot: PetCamSpot, at date: Date, blockID: String,
                                random: inout PetCamRandom) -> PetCamWreck? {
        guard !hasWreck(from: blockID) else { return nil }
        let struck = objects[spot]
        var wreck: PetCamWreck?
        if let struck {
            // The new wreck takes the place on the floor the one that stays
            // is not using.
            let staying = wrecks.filter { $0.spot == spot }.suffix(Self.visibleWrecksPerSpot - 1).map(\.slot)
            let slot = (0..<Self.visibleWrecksPerSpot).first { !staying.contains($0) } ?? 0
            let made = PetCamWreck(object: struck, spot: spot, wreckedAt: date, blockID: blockID, slot: slot)
            wrecks = Self.swept(wrecks + [made])
            wreck = made
        }
        let inRoom = Set(objects.filter { $0.key != spot }.values.map(\.kind))
        let choices = PetCamObjectKind.allCases.filter { !inRoom.contains($0) && $0 != struck?.kind }
        let pool = choices.isEmpty ? PetCamObjectKind.allCases : choices
        let kind = pool[Int(random.next() % UInt64(pool.count))]
        objects[spot] = PetCamObject(kind: kind, placedAt: date, serial: nextSerial)
        nextSerial += 1
        return wreck
    }

    /// Fills any empty spot (after decoding an unknown kind) so every block
    /// has three objects to choose from.
    public mutating func refill(at date: Date, random: inout PetCamRandom) {
        for spot in PetCamSpot.allCases where objects[spot] == nil {
            let inRoom = Set(objects.values.map(\.kind))
            let pool = PetCamObjectKind.allCases.filter { !inRoom.contains($0) }
            let kind = pool.isEmpty ? .mug : pool[Int(random.next() % UInt64(pool.count))]
            objects[spot] = PetCamObject(kind: kind, placedAt: date, serial: nextSerial)
            nextSerial += 1
        }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case spots, wrecks, nextSerial
    }

    private struct SpotEntry: Codable {
        var spot: PetCamSpot
        var object: PetCamObject
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decodeIfPresent(PetCamLossyList<SpotEntry>.self, forKey: .spots)?.elements ?? []
        var objects: [PetCamSpot: PetCamObject] = [:]
        for entry in entries where objects[entry.spot] == nil { objects[entry.spot] = entry.object }
        let wrecks = try container.decodeIfPresent(PetCamLossyList<PetCamWreck>.self, forKey: .wrecks)?.elements ?? []
        self.init(objects: objects, wrecks: wrecks,
                  nextSerial: try container.decodeIfPresent(Int.self, forKey: .nextSerial))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let entries = PetCamSpot.allCases.compactMap { spot in objects[spot].map { SpotEntry(spot: spot, object: $0) } }
        try container.encode(entries, forKey: .spots)
        try container.encode(wrecks, forKey: .wrecks)
        try container.encode(nextSerial, forKey: .nextSerial)
    }
}

/// A JSON array decoded element by element, dropping elements this build
/// cannot read (a kind or outcome a newer build added) instead of failing
/// the whole document. That is what keeps the Pet Cam files additive.
struct PetCamLossyList<Element: Decodable>: Decodable {
    var elements: [Element]

    private struct Skip: Decodable {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try container.decode(Skip.self)
            }
        }
        self.elements = elements
    }
}
