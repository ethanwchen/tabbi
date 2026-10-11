import Foundation

/// The pet's little adventure during a long focus block: partway through it
/// trots off from beside the closed notch, and it comes back as the block
/// ends, so its return is part of the finish moment. The timer keeps
/// showing while it is away. Under Reduce Motion the pet just stays.
///
/// Everything is a pure function of the shared focus clock, so the notch,
/// the snapshots and the tests all agree on where the pet is.
public struct PetAdventure: Hashable, Sendable {
    /// Focus blocks shorter than this keep the pet home.
    public static let minimumFocus: TimeInterval = 15 * 60
    /// How long the walk off (and the walk back) takes.
    public static let walkDuration: TimeInterval = 3
    /// The part of the block that passes before the pet leaves, picked per
    /// block in this range so the departure feels spontaneous.
    public static let departureRange: ClosedRange<Double> = 0.3...0.5

    /// When the pet starts walking off.
    public let departsAt: Date
    /// When it starts walking back; it is home as the block ends.
    public let returnsAt: Date
    /// When the block ends.
    public let endsAt: Date

    /// Where the pet is.
    public enum Phase: Hashable, Sendable {
        case home
        /// Walking off; `progress` runs 0 to 1.
        case leaving(progress: Double)
        case away
        /// Walking back; `progress` runs 0 to 1.
        case returning(progress: Double)

        /// Whether the pet is out of its usual spot (walking or away).
        public var isOut: Bool { self != .home }

        /// How far along the path out the pet is: 0 at home, 1 out of
        /// sight, in between while it walks.
        public var distance: Double {
            switch self {
            case .home: 0
            case .leaving(let progress): progress
            case .away: 1
            case .returning(let progress): 1 - progress
            }
        }
    }

    /// An adventure at these moments: for snapshots and tests. `plan(for:)`
    /// is how the app gets one.
    public init(departsAt: Date, returnsAt: Date, endsAt: Date) {
        self.departsAt = departsAt
        self.returnsAt = returnsAt
        self.endsAt = endsAt
    }

    /// The adventure for a focus clock, or nil when the pet stays home: not
    /// a running focus countdown, a block shorter than `minimumFocus`, or
    /// Reduce Motion on. A paused block has none, so the pet comes home.
    public static func plan(for focus: ProvidedFocus?, reduceMotion: Bool) -> PetAdventure? {
        guard !reduceMotion, let focus, focus.phase == .focus,
              case .countdown(let endsAt) = focus.clock,
              let length = focus.phaseLength, length >= minimumFocus else { return nil }
        let start = endsAt.addingTimeInterval(-length)
        let fraction = departureFraction(seed: endsAt)
        return PetAdventure(departsAt: start.addingTimeInterval(length * fraction),
                            returnsAt: endsAt.addingTimeInterval(-walkDuration),
                            endsAt: endsAt)
    }

    /// Where the pet is at `now` for a focus clock.
    public static func phase(for focus: ProvidedFocus?, at now: Date, reduceMotion: Bool) -> Phase {
        plan(for: focus, reduceMotion: reduceMotion)?.phase(at: now) ?? .home
    }

    /// Where the pet is at `now` in this adventure.
    public func phase(at now: Date) -> Phase {
        let walk = Self.walkDuration
        if now < departsAt || now >= endsAt { return .home }
        if now < departsAt.addingTimeInterval(walk) {
            return .leaving(progress: now.timeIntervalSince(departsAt) / walk)
        }
        if now < returnsAt { return .away }
        return .returning(progress: min(1, now.timeIntervalSince(returnsAt) / walk))
    }

    /// Whether the closed notch says the pet is out exploring at `now`:
    /// from the moment it sets off until it starts back, so its return
    /// reads as part of the finish.
    public func isExploring(at now: Date) -> Bool {
        switch phase(at: now) {
        case .leaving, .away: true
        case .home, .returning: false
        }
    }

    /// The next moment the phase changes after `now`, so a view can schedule
    /// one redraw instead of polling. Nil once the adventure is over.
    public func nextChange(after now: Date) -> Date? {
        [departsAt, departsAt.addingTimeInterval(Self.walkDuration), returnsAt, endsAt].first { $0 > now }
    }

    /// The adventure that just came to its end as the focus clock moved from
    /// `old` to `new`, or nil. It ends when `old` had one (`plan(for:)`) and
    /// the same clock then finished that block (its finished count went up)
    /// with the pet already on its way back. A block stopped or skipped
    /// early, a paused one, or one under Reduce Motion had no adventure to
    /// finish, so it writes nothing into the journal.
    public static func finished(from old: ProvidedFocus?, to new: ProvidedFocus?, at now: Date,
                                reduceMotion: Bool) -> PetAdventure? {
        guard let old, let new, old.source == new.source,
              new.completedFocusCount > old.completedFocusCount,
              let adventure = plan(for: old, reduceMotion: reduceMotion),
              now >= adventure.returnsAt else { return nil }
        return adventure
    }

    /// A stable fraction in `departureRange` for a block, from its end time,
    /// so the same block always leaves at the same moment across redraws.
    static func departureFraction(seed: Date) -> Double {
        let bits = PetJournal.mix(UInt64(bitPattern: Int64(seed.timeIntervalSinceReferenceDate.rounded())))
        let unit = Double(bits >> 11) / Double(1 << 53)
        return departureRange.lowerBound + unit * (departureRange.upperBound - departureRange.lowerBound)
    }
}

/// The pet's adventure journal: a short line for each adventure, such as
/// "Mochi explored the bookshelf", that the Closet can show.
///
/// Lines rotate like a shuffled deck: no line repeats until every line has
/// been used, the order changes from deck to deck, and a new deck never
/// starts with the line the last one ended on. The order is seeded, so it
/// is the same on every launch and in tests.
public struct PetJournal: Hashable, Codable, Sendable {
    /// The most entries kept; older ones fall off.
    public static let maxEntries = 30

    /// One adventure. `line` is the stable id of its line (`lines`), so the
    /// text can be reworded and the pet renamed without touching the save.
    public struct Entry: Hashable, Codable, Sendable {
        public let line: String
        public let date: Date

        public init(line: String, date: Date) {
            self.line = line
            self.date = date
        }

        /// The line with the pet's name, or nil for a line this build no
        /// longer knows.
        public func text(petName: String) -> String? {
            PetJournal.phrase(for: line).map { "\(petName) \($0)" }
        }
    }

    /// Every line, by stable id. Short, cute and varied: places, small
    /// finds, and friends made.
    public static let lines: [(id: String, phrase: String)] = [
        ("bookshelf", "explored the bookshelf"),
        ("windowsill", "napped on a sunny windowsill"),
        ("butterfly", "chased a butterfly"),
        ("leaf", "found a perfect leaf"),
        ("pigeon", "made friends with a pigeon"),
        ("puddle", "splashed in a puddle"),
        ("cloud", "watched a cloud shaped like a fish"),
        ("garden", "sniffed every flower in the garden"),
        ("sock", "rescued a lost sock"),
        ("acorn", "brought back a shiny acorn"),
        ("library", "snuck into the library"),
        ("snail", "raced a snail and let it win"),
        ("pebble", "collected a smooth pebble"),
        ("rooftop", "climbed onto the rooftop"),
        ("bakery", "visited the bakery"),
        ("rainbow", "spotted a tiny rainbow"),
        ("box", "explored a cardboard box"),
        ("bird", "learned a song from a bird"),
        ("park", "went around the park twice"),
        ("feather", "found a soft feather"),
    ]

    public private(set) var entries: [Entry]
    /// The line ids used in the current deck, in order.
    public private(set) var deck: [String]
    /// How many decks were finished, which reshuffles the next one.
    public private(set) var decksFinished: Int
    /// Seeds the order; set once per pet.
    public let seed: UInt64

    public init(seed: UInt64 = 0) {
        self.entries = []
        self.deck = []
        self.decksFinished = 0
        self.seed = seed
    }

    /// The line id the next adventure gets.
    public var nextLine: String {
        let ids = Self.lines.map(\.id)
        var remaining = ids.filter { !deck.contains($0) }
        if remaining.isEmpty { remaining = ids }
        // A fresh deck never repeats the line the last one ended on.
        if deck.isEmpty, let last = entries.last?.line, remaining.count > 1 {
            remaining.removeAll { $0 == last }
        }
        let roll = Self.mix(seed &+ UInt64(decksFinished) &* 0x9E37_79B9 &+ UInt64(deck.count))
        return remaining[Int(roll % UInt64(remaining.count))]
    }

    /// Writes the next adventure into the journal and returns it.
    @discardableResult
    public mutating func record(at date: Date) -> Entry {
        let entry = Entry(line: nextLine, date: date)
        deck.append(entry.line)
        if deck.count == Self.lines.count {
            deck = []
            decksFinished += 1
        }
        entries.append(entry)
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
        return entry
    }

    /// The newest adventure, for the Closet.
    public var latest: Entry? { entries.last }

    static func phrase(for id: String) -> String? {
        lines.first { $0.id == id }?.phrase
    }

    /// SplitMix64's finalizer: spreads a seed into well mixed bits.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    // Forgiving decoding: a deck with ids this build doesn't know drops
    // them, so a newer build's save still loads.
    private enum CodingKeys: String, CodingKey { case entries, deck, decksFinished, seed }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seed = try container.decodeIfPresent(UInt64.self, forKey: .seed) ?? 0
        entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        let known = Set(Self.lines.map(\.id))
        var seen: Set<String> = []
        deck = (try container.decodeIfPresent([String].self, forKey: .deck) ?? [])
            .filter { known.contains($0) && seen.insert($0).inserted }
        if deck.count >= Self.lines.count { deck = [] }
        decksFinished = max(0, try container.decodeIfPresent(Int.self, forKey: .decksFinished) ?? 0)
    }
}

// MARK: - Saving

extension PetJournal {
    /// The journal's file format. Version 1 is the first.
    public static let schema = VersionedJSON(current: 1)

    /// A short journal for demos: a few adventures over the last days, the
    /// newest an hour before `now`.
    public static func demo(now: Date) -> PetJournal {
        var journal = PetJournal(seed: 5)
        for hoursAgo in [50.0, 26, 1] {
            journal.record(at: now.addingTimeInterval(-hoursAgo * 3600))
        }
        return journal
    }

    /// The journal at `url`, or nil when there is none yet. A corrupt file
    /// throws so the caller can decide not to overwrite it.
    public static func load(from url: URL) throws -> PetJournal? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> PetJournal {
        try schema.decode(PetJournal.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try Self.schema.encode(self, using: encoder)
    }

    /// Writes atomically, creating the parent folder if needed.
    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded().write(to: url, options: .atomic)
    }
}
