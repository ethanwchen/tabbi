/// Every panel the notch can show, in tab order.
public enum ModuleID: String, CaseIterable, Codable, Sendable, Identifiable {
    case spotify
    case system
    case claudeUsage
    case planner
    case claudeAsk

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .spotify: "Now Playing"
        case .system: "System"
        case .claudeUsage: "Claude Usage"
        case .planner: "Today"
        case .claudeAsk: "Ask Claude"
        }
    }

    /// SF Symbol shown in the tab bar.
    public var symbol: String {
        switch self {
        case .spotify: "music.note"
        case .system: "cpu"
        case .claudeUsage: "gauge.with.dots.needle.67percent"
        case .planner: "checklist"
        case .claudeAsk: "sparkles"
        }
    }

    /// The module after this one, wrapping around.
    public var next: ModuleID {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// The module before this one, wrapping around.
    public var previous: ModuleID {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + all.count - 1) % all.count]
    }
}
