import Foundation

/// A calendar day identified by its local `yyyy-MM-dd` string.
///
/// The string form doubles as the on-disk file name and sorts
/// chronologically, so "most recent previous day" is a plain comparison.
public struct PlannerDayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    /// Accepts only well-formed `yyyy-MM-dd` strings that name a real date.
    public init?(rawValue: String) {
        guard rawValue.count == 10, Self.parse(rawValue) != nil else { return nil }
        self.rawValue = rawValue
    }

    /// The day containing `date` in `calendar`'s time zone.
    public init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Midnight at the start of this day in `calendar`'s time zone.
    public func startDate(calendar: Calendar = .current) -> Date {
        let parts = Self.parse(rawValue)!
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))!
    }

    /// The day `days` calendar days after this one (before it when
    /// negative), so stepping across a daylight saving change or a month end
    /// lands on the right date.
    public func adding(days: Int, calendar: Calendar = .current) -> PlannerDayKey {
        let start = startDate(calendar: calendar)
        return PlannerDayKey(date: calendar.date(byAdding: .day, value: days, to: start) ?? start, calendar: calendar)
    }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let key = Self(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid day \(raw)"))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func parse(_ raw: String) -> (year: Int, month: Int, day: Int)? {
        let fields = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0].count == 4, fields[1].count == 2, fields[2].count == 2,
              let year = Int(fields[0]), let month = Int(fields[1]), let day = Int(fields[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: year, month: month, day: day)
        // Rejects impossible dates like 2026-02-30 instead of rolling them over.
        guard components.isValidDate(in: calendar) else { return nil }
        return (year, month, day)
    }
}

/// One checklist entry.
public struct PlannerItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var isDone: Bool
    public let createdAt: Date
    public var completedAt: Date?

    public init(id: UUID = UUID(), title: String, isDone: Bool = false, createdAt: Date, completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

/// A day's ordered checklist. All edits are pure value mutations; persistence
/// lives in `PlannerRepository`.
public struct PlannerDay: Hashable, Codable, Sendable {
    public let date: PlannerDayKey
    public private(set) var items: [PlannerItem]
    /// Whether this day was started ahead of time (tasks added for tomorrow)
    /// and hasn't yet taken in the unfinished items of the day before it.
    /// `PlannerRepository.open` does that once, when the day comes, and
    /// clears the flag.
    public private(set) var isPlannedAhead: Bool

    public init(date: PlannerDayKey, items: [PlannerItem] = [], isPlannedAhead: Bool = false) {
        self.date = date
        self.items = items
        self.isPlannedAhead = isPlannedAhead
    }

    private enum CodingKeys: String, CodingKey {
        case date, items, isPlannedAhead
    }

    /// Lenient about `isPlannedAhead`, which older files don't have.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(PlannerDayKey.self, forKey: .date)
        items = try container.decode([PlannerItem].self, forKey: .items)
        isPlannedAhead = try container.decodeIfPresent(Bool.self, forKey: .isPlannedAhead) ?? false
    }

    public var doneCount: Int { items.lazy.filter(\.isDone).count }

    /// Fraction of items done, 0 when the list is empty.
    public var progress: Double { items.isEmpty ? 0 : Double(doneCount) / Double(items.count) }

    /// Appends a new item. Returns nil (and changes nothing) for blank titles.
    @discardableResult
    public mutating func add(_ title: String, now: Date = Date()) -> PlannerItem? {
        guard let title = Self.normalized(title) else { return nil }
        let item = PlannerItem(title: title, createdAt: now)
        items.append(item)
        return item
    }

    /// Appends a kit's starter tasks, skipping blanks and any title already
    /// on the list (ignoring case), so applying a kit twice never duplicates
    /// them. Returns the items added.
    @discardableResult
    public mutating func addStarterTasks(_ titles: [String], now: Date = Date()) -> [PlannerItem] {
        var seen = Set(items.map { $0.title.lowercased() })
        return titles.compactMap(Self.normalized).compactMap { title in
            guard seen.insert(title.lowercased()).inserted else { return nil }
            return add(title, now: now)
        }
    }

    /// Flips an item's done state, stamping or clearing `completedAt`.
    public mutating func toggle(_ id: PlannerItem.ID, now: Date = Date()) {
        guard let index = index(of: id) else { return }
        items[index].isDone.toggle()
        items[index].completedAt = items[index].isDone ? now : nil
    }

    /// Renames an item. Blank titles are ignored so an item can't vanish into
    /// an empty row; returns whether anything changed.
    @discardableResult
    public mutating func rename(_ id: PlannerItem.ID, to title: String) -> Bool {
        guard let index = index(of: id), let title = Self.normalized(title), items[index].title != title else { return false }
        items[index].title = title
        return true
    }

    public mutating func delete(_ id: PlannerItem.ID) {
        items.removeAll { $0.id == id }
    }

    /// Removes the items in `added` that are still exactly as they were
    /// added (not renamed or checked off), so undoing a kit switch takes
    /// back its starter tasks but never work the user has touched since.
    /// Returns whether anything was removed.
    @discardableResult
    public mutating func removeUntouched(_ added: [PlannerItem]) -> Bool {
        let untouched = Set(added)
        let before = items.count
        items.removeAll { untouched.contains($0) }
        return items.count != before
    }

    /// Moves the items at `offsets` so they land before `destination`, with
    /// the same semantics as SwiftUI's `onMove` / `Array.move(fromOffsets:toOffset:)`.
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let valid = offsets.filteredIndexSet { items.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { items[$0] }
        let insertion = min(max(destination, 0), items.count) - valid.count(in: 0..<min(max(destination, 0), items.count))
        for index in valid.reversed() { items.remove(at: index) }
        items.insert(contentsOf: moving, at: insertion)
    }

    /// Moves one item to sit at `targetIndex` in the resulting list. Handy for
    /// drag-and-drop where the drop target is another row.
    public mutating func move(_ id: PlannerItem.ID, to targetIndex: Int) {
        guard let from = index(of: id) else { return }
        let item = items.remove(at: from)
        items.insert(item, at: min(max(targetIndex, 0), items.count))
    }

    public mutating func clearCompleted() {
        items.removeAll(where: \.isDone)
    }

    /// This day's unfinished items that `other` doesn't list (by id), in
    /// order: what looking back at yesterday offers to move to today.
    public func unfinished(missingFrom other: PlannerDay) -> [PlannerItem] {
        let present = Set(other.items.map(\.id))
        return items.filter { !$0.isDone && !present.contains($0.id) }
    }

    /// Appends `incoming` items as they are (same id, title and creation
    /// date, unfinished), skipping any whose id or title (ignoring case) is
    /// already on the list. Moving yesterday's leftovers to today and a
    /// planned-ahead day taking in the day before both go through here, so
    /// nothing is ever listed twice. Returns the items added.
    @discardableResult
    public mutating func adopt(_ incoming: [PlannerItem]) -> [PlannerItem] {
        var ids = Set(items.map(\.id))
        var titles = Set(items.map { $0.title.lowercased() })
        var added: [PlannerItem] = []
        for item in incoming where ids.insert(item.id).inserted && titles.insert(item.title.lowercased()).inserted {
            var moved = item
            moved.isDone = false
            moved.completedAt = nil
            items.append(moved)
            added.append(moved)
        }
        return added
    }

    /// Takes in the unfinished items of `previous` (the day before) ahead of
    /// what was planned for this day, and marks the day as started. Items
    /// keep their identity and creation date so history stays traceable.
    public mutating func takeCarryOver(from previous: PlannerDay?) {
        let planned = items
        items = []
        if let previous { adopt(previous.items.filter { !$0.isDone }) }
        adopt(planned)
        isPlannedAhead = false
    }

    private func index(of id: PlannerItem.ID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    /// Collapses internal whitespace runs (including pasted newlines) to a
    /// single space; nil when nothing visible remains.
    static func normalized(_ title: String) -> String? {
        let collapsed = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}

public extension PlannerItem {
    /// This checklist item as Today's contribution to the shared task list.
    func provided(by module: ModuleID) -> ProvidedTask {
        ProvidedTask(id: id.uuidString, source: module, title: title, isDone: isDone)
    }
}
