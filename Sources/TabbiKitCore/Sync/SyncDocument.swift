import Foundation

/// What one Mac has added to the shared points: lifetime earned and spent.
///
/// Each Mac only ever grows its own tally, so merging two copies takes the
/// larger of each number and the account's points are the sum over Macs.
/// That way points earned on two Macs while offline add up instead of one
/// Mac's total replacing the other's.
public struct SyncTally: Codable, Hashable, Sendable {
    public var earned: Int
    public var spent: Int

    public init(earned: Int = 0, spent: Int = 0) {
        self.earned = max(0, earned)
        self.spent = max(0, spent)
    }

    /// The larger of each counter, so a merge never loses points.
    public func merged(with other: SyncTally) -> SyncTally {
        SyncTally(earned: max(earned, other.earned), spent: max(spent, other.spent))
    }
}

/// The pet's look as last chosen on any Mac, with when it was chosen, so
/// the newest choice wins a merge.
public struct SyncedPet: Codable, Hashable, Sendable {
    public var profile: PetProfile
    public var updatedAt: Date

    public init(profile: PetProfile, updatedAt: Date) {
        self.profile = profile
        self.updatedAt = updatedAt
    }

    /// The later of the two. Equal times pick the same side on every Mac
    /// (by the profile's JSON), so all copies converge.
    public func merged(with other: SyncedPet) -> SyncedPet {
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt ? self : other }
        return sortKey >= other.sortKey ? self : other
    }

    private var sortKey: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(profile)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

/// The one document Sign in with Apple keeps per account: the pet, its
/// points and unlocks, and the study days behind the streak. Calendar data,
/// activity details, Claude data and settings never go in here.
///
/// Merging is a join: it is commutative, associative and idempotent, so
/// Macs that merge in any order end up with the same document, and no Mac's
/// progress is lost. Counters and sets only grow (per-Mac tallies by max,
/// unlocks and study days by union, the longest streak by max); the pet's
/// look is last-writer-wins by its timestamp.
public struct SyncDocument: Codable, Hashable, Sendable {
    /// The stored format. Bump with a migration step when it changes.
    public static let schema = VersionedJSON(current: 1)

    /// How many recent study days are kept: enough for any current streak
    /// over a year long, while the document stays small.
    public static let keptStudyDays = 400

    /// Nil until a Mac with a pet has synced.
    public var pet: SyncedPet?
    /// Points per Mac, keyed by each Mac's sync device id.
    public var tallies: [String: SyncTally]
    /// Item ids bought on any Mac. Kept as strings so an item from a newer
    /// build survives a round trip through an older one.
    public var unlocks: Set<String>
    /// Local days (`YYYY-MM-DD`) with focus time on any Mac.
    public private(set) var studyDays: Set<String>
    /// The longest streak ever reached, including days since trimmed.
    public private(set) var longestStreak: Int

    public init(
        pet: SyncedPet? = nil,
        tallies: [String: SyncTally] = [:],
        unlocks: Set<String> = [],
        studyDays: Set<String> = [],
        longestStreak: Int = 0
    ) {
        self.pet = pet
        self.tallies = tallies
        self.unlocks = unlocks
        let days = Set(studyDays.filter { SyncDays.date(of: $0) != nil })
        self.studyDays = days
        self.longestStreak = max(0, longestStreak, SyncDays.longestRun(in: days))
        trimStudyDays()
    }

    /// An empty document, as the server holds before any Mac pushed.
    public static let empty = SyncDocument()

    // MARK: Merge

    public func merged(with other: SyncDocument) -> SyncDocument {
        let pet: SyncedPet? = switch (self.pet, other.pet) {
        case let (mine?, theirs?): mine.merged(with: theirs)
        case let (mine, theirs): mine ?? theirs
        }
        return SyncDocument(
            pet: pet,
            tallies: tallies.merging(other.tallies) { $0.merged(with: $1) },
            unlocks: unlocks.union(other.unlocks),
            studyDays: studyDays.union(other.studyDays),
            longestStreak: max(longestStreak, other.longestStreak)
        )
    }

    // MARK: Points

    /// Earned points over all Macs.
    public var earned: Int { tallies.values.reduce(0) { $0 + $1.earned } }
    /// Spent points over all Macs.
    public var spent: Int { tallies.values.reduce(0) { $0 + $1.spent } }

    /// The account's ledger: every Mac's points and every unlock this build
    /// knows.
    public var ledger: PetPointsLedger {
        PetPointsLedger(earned: earned, spent: spent, purchased: Set(unlocks.compactMap(PetItem.init(id:))))
    }

    // MARK: Streak

    /// Days in a row with focus time, ending on `today` or the day before
    /// (a streak stays up until a whole day is missed).
    public func currentStreak(today: String) -> Int {
        SyncDays.currentRun(in: studyDays, today: today)
    }

    /// Adds days with focus time.
    public mutating func addStudyDays(_ days: some Sequence<String>) {
        studyDays.formUnion(days.filter { SyncDays.date(of: $0) != nil })
        longestStreak = max(longestStreak, SyncDays.longestRun(in: studyDays))
        trimStudyDays()
    }

    private mutating func trimStudyDays() {
        guard studyDays.count > Self.keptStudyDays else { return }
        studyDays = Set(studyDays.sorted().suffix(Self.keptStudyDays))
    }

    // MARK: Local state

    /// This document with one Mac's local pet folded in: its look (when it
    /// changed after the synced one), its share of the points and its
    /// unlocks. `device` is this Mac's sync id.
    ///
    /// Call it on the document the save last adopted (`.empty` before the
    /// first sync): the Mac's tally is what its ledger holds beyond the
    /// other Macs' tallies in here, so after adopting a merged ledger only
    /// what it earned or spent since counts as its own. Merge the result
    /// with the server's copy afterwards, never before.
    public func recording(_ save: PetSave, changedAt: Date?, device: String) -> SyncDocument {
        var others = tallies
        others[device] = nil
        let othersEarned = others.values.reduce(0) { $0 + $1.earned }
        let othersSpent = others.values.reduce(0) { $0 + $1.spent }
        let mine = SyncTally(earned: save.ledger.earned - othersEarned, spent: save.ledger.spent - othersSpent)

        var local = SyncDocument(
            tallies: [device: mine],
            unlocks: Set(save.ledger.purchased.map(\.id))
        )
        if let changedAt { local.pet = SyncedPet(profile: save.profile, updatedAt: changedAt) }
        return merged(with: local)
    }

    /// The local pet save updated to this document: the synced look (or the
    /// local one when nothing synced yet), the account's ledger, and the
    /// local focus credit bookkeeping kept as it was.
    public func applied(to save: PetSave) -> PetSave {
        var updated = PetSave(profile: pet?.profile ?? save.profile, ledger: ledger)
        updated.version = save.version
        updated.creditedFocusCount = save.creditedFocusCount
        updated.creditedFocusSource = save.creditedFocusSource
        return updated
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case pet, tallies, unlocks, studyDays, longestStreak
    }

    /// Lenient: a missing or unreadable field falls back to empty, so one
    /// bad value never throws away the rest of the account's progress.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tallies = (try? container.decodeIfPresent([String: SyncTally].self, forKey: .tallies)) ?? nil
        let unlocks = (try? container.decodeIfPresent([String].self, forKey: .unlocks)) ?? nil
        let days = (try? container.decodeIfPresent([String].self, forKey: .studyDays)) ?? nil
        let longest = (try? container.decodeIfPresent(Int.self, forKey: .longestStreak)) ?? nil
        self.init(
            pet: (try? container.decodeIfPresent(SyncedPet.self, forKey: .pet)) ?? nil,
            tallies: tallies ?? [:],
            unlocks: Set(unlocks ?? []),
            studyDays: Set(days ?? []),
            longestStreak: longest ?? 0
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(pet, forKey: .pet)
        try container.encode(tallies, forKey: .tallies)
        try container.encode(unlocks.sorted(), forKey: .unlocks)
        try container.encode(studyDays.sorted(), forKey: .studyDays)
        try container.encode(longestStreak, forKey: .longestStreak)
    }

    /// The document as stored on the server, with its `schemaVersion`.
    public func encoded() throws -> Data {
        try Self.schema.encode(self, using: Self.encoder)
    }

    public static func decode(_ data: Data) throws -> SyncDocument {
        try schema.decode(SyncDocument.self, from: data, using: decoder)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Day arithmetic on `YYYY-MM-DD` strings. The strings are local days of
/// whichever Mac recorded them, so they are compared as plain dates in UTC.
enum SyncDays {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    static func date(of day: String) -> Date? {
        let parts = day.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth)),
              string(of: date) == day
        else { return nil }
        return date
    }

    static func string(of date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func previous(_ day: String) -> String? {
        date(of: day).flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }.map(string(of:))
    }

    /// The run of consecutive days ending on `today`, or on the day before.
    static func currentRun(in days: Set<String>, today: String) -> Int {
        guard var day = days.contains(today) ? today : previous(today), days.contains(day) else { return 0 }
        var run = 0
        while days.contains(day) {
            run += 1
            guard let earlier = previous(day) else { break }
            day = earlier
        }
        return run
    }

    /// The longest run of consecutive days.
    static func longestRun(in days: Set<String>) -> Int {
        var longest = 0
        var run = 0
        var last: String?
        for day in days.sorted() {
            run = last.map { previous(day) == $0 } == true ? run + 1 : 1
            longest = max(longest, run)
            last = day
        }
        return longest
    }
}
