import Foundation

/// The user's tab bar: which modules are shown and in what order.
///
/// Every module in the catalog always has a slot in `order`, so a module that
/// ships in a future version (and is missing from saved data) is appended at
/// the end, switched off: users choose their tabs (usually through a kit),
/// and an update must not add tabs they never asked for. At least one module
/// always stays enabled so the notch never opens onto an empty panel.
public struct ModuleLayout: Equatable, Sendable {
    /// Every known module, in the user's order.
    public private(set) var order: [ModuleID]
    /// Modules the user turned off.
    public private(set) var disabled: Set<ModuleID>

    /// Every module in `catalog`, in canonical order, all switched on: the
    /// last resort when no saved layout or kit says otherwise.
    public init(catalog: ModuleCatalog) {
        self.init(order: catalog.ids, disabled: [], catalog: catalog)
    }

    /// Builds a layout from possibly stale or partial data: ids not in
    /// `catalog` and duplicates are dropped, missing modules are appended
    /// switched off, and if that would leave nothing enabled the first module is
    /// re-enabled.
    public init(order: [ModuleID], disabled: Set<ModuleID>, catalog: ModuleCatalog) {
        var seen = Set<ModuleID>()
        var normalized = order.filter { catalog.contains($0) && seen.insert($0).inserted }
        let missing = catalog.ids.filter { !seen.contains($0) }
        normalized += missing
        var disabled = disabled.intersection(normalized).union(missing)
        if normalized.allSatisfy(disabled.contains), let first = normalized.first {
            disabled.remove(first)
        }
        self.order = normalized
        self.disabled = disabled
    }

    /// Restores a layout from raw identifiers, ignoring ones `catalog` doesn't know.
    public init(orderRawValues: [String], disabledRawValues: [String], catalog: ModuleCatalog) {
        self.init(
            order: orderRawValues.map(ModuleID.init(rawValue:)),
            disabled: Set(disabledRawValues.map(ModuleID.init(rawValue:))),
            catalog: catalog
        )
    }

    /// The modules shown in the tab bar, in order. Never empty.
    public var enabled: [ModuleID] { order.filter { !disabled.contains($0) } }

    public func isEnabled(_ module: ModuleID) -> Bool { !disabled.contains(module) }

    /// Whether `module` may be turned off (it isn't the last enabled one).
    public func canDisable(_ module: ModuleID) -> Bool {
        !isEnabled(module) || enabled.count > 1
    }

    /// Turns a module on or off. Refuses (returns `false`) to disable the last enabled module.
    @discardableResult
    public mutating func setEnabled(_ module: ModuleID, _ isEnabled: Bool) -> Bool {
        if isEnabled {
            disabled.remove(module)
            return true
        }
        guard canDisable(module) else { return false }
        disabled.insert(module)
        return true
    }

    /// Moves modules with the same semantics as SwiftUI's `onMove`.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.filter(order.indices.contains).map { order[$0] }
        guard !moving.isEmpty else { return }
        let insertAt = destination - source.filter { $0 < destination }.count
        var remaining = order.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moving, at: min(max(insertAt, 0), remaining.count))
        order = remaining
    }

    /// The selection to show: `module` if it's enabled, otherwise the first enabled module.
    public func resolvedSelection(_ module: ModuleID) -> ModuleID {
        isEnabled(module) ? module : enabled[0]
    }

    /// The enabled module after `module`, wrapping around.
    public func module(after module: ModuleID) -> ModuleID { step(from: module, by: 1) }

    /// The enabled module before `module`, wrapping around.
    public func module(before module: ModuleID) -> ModuleID { step(from: module, by: -1) }

    /// Number keys reach at most this many tabs (1-9), so a kit can show up to
    /// nine tabs that are all one keystroke away.
    public static let maxShortcutTabs = 9

    /// The enabled module that number key `number` (1-based) jumps to, or nil
    /// when that tab doesn't exist or the key is outside 1-9.
    public func module(forShortcut number: Int) -> ModuleID? {
        let list = enabled
        guard (1...Self.maxShortcutTabs).contains(number), number <= list.count else { return nil }
        return list[number - 1]
    }

    /// The number key (1-9) that jumps to `module`, or nil when it's disabled
    /// or sits beyond the ninth tab.
    public func shortcut(for module: ModuleID) -> Int? {
        guard let index = enabled.firstIndex(of: module), index < Self.maxShortcutTabs else { return nil }
        return index + 1
    }

    private func step(from module: ModuleID, by delta: Int) -> ModuleID {
        let list = enabled
        guard let index = list.firstIndex(of: module) else { return list[0] }
        return list[(index + delta + list.count) % list.count]
    }
}
