import Foundation

/// The pet's whole persisted state in one versioned JSON document: the
/// profile and the points ledger travel together so a profile is always
/// checked against the items the user actually owns.
public struct PetSave: Hashable, Codable, Sendable {
    /// Bump when the format changes in a way old builds cannot read.
    public static let currentVersion = 1

    public var version: Int
    public var profile: PetProfile
    public var ledger: PetPointsLedger
    /// The shared focus timer's `completedFocusCount` already paid out in
    /// points, so a completed session is credited once, also across
    /// relaunches. Nil until the pet first sees a timer.
    public var creditedFocusCount: Int?

    public init(profile: PetProfile, ledger: PetPointsLedger = PetPointsLedger()) {
        self.version = PetSave.currentVersion
        self.ledger = ledger
        self.profile = profile.restricted(to: ledger)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Decodes a save and re-applies the ownership rule, so a hand-edited
    /// file cannot dress the pet in items it never bought.
    public static func decode(_ data: Data) throws -> PetSave {
        let raw = try JSONDecoder().decode(PetSave.self, from: data)
        var save = PetSave(profile: raw.profile, ledger: raw.ledger)
        save.version = raw.version
        save.creditedFocusCount = raw.creditedFocusCount
        return save
    }

    /// Loads the save at `url`, or returns nil when there is none yet.
    /// A corrupt file throws so the caller can decide not to overwrite it.
    public static func load(from url: URL) throws -> PetSave? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decode(Data(contentsOf: url))
    }

    /// Writes atomically, creating the parent folder if needed.
    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try encoded().write(to: url, options: .atomic)
    }
}
