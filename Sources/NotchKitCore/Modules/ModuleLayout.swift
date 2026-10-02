import Foundation

/// The user's tab bar: which modules are shown and in what order.
///
/// Every module in the catalog always has a slot in `order`, so a module that
/// ships in a future version (and is missing from saved data) is appended at
/// the end and starts enabled. At least one module always stays enabled so the notch never
/// opens onto an empty panel.
public struct ModuleLayout: Equatable, Sendable {
    /// Every known module, in the user's order.
    public private(set) var order: [ModuleID]
    /// Modules the user turned off.
    public private(set) var disabled: Set<ModuleID>

    public static let `default` = ModuleLayout(order: ModuleCatalog.builtIn.ids, disabled: [])

    /// Builds a layout from possibly stale or partial data: ids not in
    /// `catalog` and duplicates are dropped, missing modules are appended
    /// (enabled), and if that would leave nothing enabled the first module is
    /// re-enabled.
    public init(order: [ModuleID], disabled: Set<ModuleID>, catalog: ModuleCatalog = .builtIn) {
        var seen = Set<ModuleID>()
        var normalized = order.filter { catalog.contains($0) && seen.insert($0).inserted }
        normalized += catalog.ids.filter { !seen.contains($0) }
        var disabled = disabled.intersection(normalized)
        if normalized.allSatisfy(disabled.contains), let first = normalized.first {
            disabled.remove(first)
        }
        self.order = normalized
        self.disabled = disabled
    }

    /// Restores a layout from raw identifiers, ignoring ones `catalog` doesn't know.
    public init(orderRawValues: [String], disabledRawValues: [String], catalog: ModuleCatalog = .builtIn) {
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

    private func step(from module: ModuleID, by delta: Int) -> ModuleID {
        let list = enabled
        guard let index = list.firstIndex(of: module) else { return list[0] }
        return list[(index + delta + list.count) % list.count]
    }
}
