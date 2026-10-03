/// An ordered set of module descriptors: the modules this build knows about.
///
/// The order is the canonical tab order used when no saved layout or kit
/// says otherwise. Ids are unique: a later duplicate is left out of
/// `descriptors` and recorded in `duplicateIDs`, so the app can fail loudly
/// on a module list mistake instead of hiding a module.
public struct ModuleCatalog: Equatable, Sendable {
    public let descriptors: [ModuleDescriptor]
    /// Ids that appeared more than once in the input, once each, in the
    /// order their first repeat appeared. Empty for a well-formed list.
    public let duplicateIDs: [ModuleID]
    private let index: [ModuleID: Int]

    public init(_ descriptors: [ModuleDescriptor]) {
        var index: [ModuleID: Int] = [:]
        var unique: [ModuleDescriptor] = []
        var duplicates: [ModuleID] = []
        for descriptor in descriptors {
            if index[descriptor.id] == nil {
                index[descriptor.id] = unique.count
                unique.append(descriptor)
            } else if !duplicates.contains(descriptor.id) {
                duplicates.append(descriptor.id)
            }
        }
        self.descriptors = unique
        self.duplicateIDs = duplicates
        self.index = index
    }

    public static func == (lhs: ModuleCatalog, rhs: ModuleCatalog) -> Bool {
        lhs.descriptors == rhs.descriptors
    }

    /// Every id, in canonical order.
    public var ids: [ModuleID] { descriptors.map(\.id) }

    public func contains(_ id: ModuleID) -> Bool { index[id] != nil }

    public subscript(id: ModuleID) -> ModuleDescriptor? {
        index[id].map { descriptors[$0] }
    }

    /// The descriptor for `id`, or a neutral placeholder if it is unknown.
    public func descriptor(for id: ModuleID) -> ModuleDescriptor {
        self[id] ?? .unknown(id)
    }

    /// The first enabled module in `layout` that runs its own focus clock
    /// (`ModuleDescriptor.ownsFocusClock`), or nil when the shared Pomodoro
    /// is the layout's only timer. Keeps a kit to one timer: with Study on,
    /// Today follows Study's clock rather than offering a second one.
    public func focusClockOwner(in layout: ModuleLayout) -> ModuleID? {
        layout.enabled.first { self[$0]?.ownsFocusClock == true }
    }
}

public extension ModuleAccent {
    /// Claude's terracotta, shared by both Claude modules.
    static let claude = ModuleAccent(red: 0.85, green: 0.47, blue: 0.34)
}
