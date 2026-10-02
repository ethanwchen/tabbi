/// Which screen the notch lives on.
public enum DisplayPreference: Codable, Equatable, Hashable, Sendable {
    /// The MacBook's built-in display (the one with the notch).
    case builtIn
    /// Whatever display macOS currently treats as main.
    case main
    /// A specific display by its `CGDirectDisplayID`.
    case specific(UInt32)

    /// A screen as seen by `resolve`, decoupled from `NSScreen` for testing.
    public struct Screen: Equatable, Sendable {
        public var id: UInt32
        public var isBuiltIn: Bool
        public var isMain: Bool

        public init(id: UInt32, isBuiltIn: Bool, isMain: Bool) {
            self.id = id
            self.isBuiltIn = isBuiltIn
            self.isMain = isMain
        }
    }

    /// Picks the screen to use. Falls back built-in → main → first, so the notch
    /// stays visible when the preferred display is unplugged or the lid is closed.
    public func resolve(in screens: [Screen]) -> Screen? {
        let builtIn = screens.first(where: \.isBuiltIn)
        let main = screens.first(where: \.isMain)
        switch self {
        case .builtIn:
            return builtIn ?? main ?? screens.first
        case .main:
            return main ?? builtIn ?? screens.first
        case .specific(let id):
            return screens.first { $0.id == id } ?? builtIn ?? main ?? screens.first
        }
    }

    /// Stable string form for persistence: "builtIn", "main", or "screen:<id>".
    public var storageValue: String {
        switch self {
        case .builtIn: "builtIn"
        case .main: "main"
        case .specific(let id): "screen:\(id)"
        }
    }

    public init?(storageValue: String) {
        switch storageValue {
        case "builtIn": self = .builtIn
        case "main": self = .main
        default:
            guard storageValue.hasPrefix("screen:"),
                  let id = UInt32(storageValue.dropFirst("screen:".count)) else { return nil }
            self = .specific(id)
        }
    }
}
