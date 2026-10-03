/// An ordered set of module descriptors: the modules this build knows about.
///
/// The order is the canonical tab order used when no saved layout or kit
/// says otherwise. Ids are unique; a later duplicate is ignored.
public struct ModuleCatalog: Equatable, Sendable {
    public let descriptors: [ModuleDescriptor]
    private let index: [ModuleID: Int]

    public init(_ descriptors: [ModuleDescriptor]) {
        var index: [ModuleID: Int] = [:]
        var unique: [ModuleDescriptor] = []
        for descriptor in descriptors where index[descriptor.id] == nil {
            index[descriptor.id] = unique.count
            unique.append(descriptor)
        }
        self.descriptors = unique
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
}

public extension ModuleAccent {
    /// Claude's terracotta, shared by both Claude modules.
    static let claude = ModuleAccent(red: 0.85, green: 0.47, blue: 0.34)
}
