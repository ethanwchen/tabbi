import Foundation

/// The crest frame, emblem and color ids and the limits. The ids and the
/// colors come from the crest art (`Pets/PetArt/crew.json`, `CrewCrestArt`),
/// and `CrewsTests` keeps them equal to the server's `backend/shared/crews.json`.
/// Ids are only ever added once shipped, and an id the app has no art for
/// draws as the first one, so a newer server never breaks an older app.
public enum CrewCatalog {
    /// The catalog version in `crews.json`.
    public static let version = 1

    /// The frames, in picker order.
    public static var frames: [String] { CrewCrestArt.art.frames.map(\.id) }
    /// The emblems, in picker order.
    public static var emblems: [String] { CrewCrestArt.art.emblems.map(\.id) }

    /// A crew color: its id and the base hex the crest's frame takes.
    public struct Color: Hashable, Sendable, Identifiable {
        public let id: String
        public let hex: String

        public var petColor: PetColor { PetColor(hex: hex)! }

        /// The name the color picker's tooltip shows.
        public var title: String {
            switch id {
            case "coral": String(localized: "Coral", bundle: .tabbi)
            case "amber": String(localized: "Amber", bundle: .tabbi)
            case "mint": String(localized: "Mint", bundle: .tabbi)
            case "teal": String(localized: "Teal", bundle: .tabbi)
            case "sky": String(localized: "Sky", bundle: .tabbi)
            case "indigo": String(localized: "Indigo", bundle: .tabbi)
            case "violet": String(localized: "Violet", bundle: .tabbi)
            case "rose": String(localized: "Rose", bundle: .tabbi)
            case "slate": String(localized: "Slate", bundle: .tabbi)
            case "charcoal": String(localized: "Charcoal", bundle: .tabbi)
            default: id
            }
        }
    }

    public static var colors: [Color] {
        CrewCrestArt.art.colorIDs.map { Color(id: $0, hex: CrewCrestArt.art.tones($0)!.base.hex) }
    }

    /// A frame's name, for the builder's tooltips.
    public static func frameTitle(_ id: String) -> String { localizedName(CrewCrestArt.art.frame(id).name) }

    /// An emblem's name, for the builder's tooltips.
    public static func emblemTitle(_ id: String) -> String { localizedName(CrewCrestArt.art.emblem(id).name) }

    /// A frame's or emblem's English name from crew.json, translated through
    /// the string catalog, where every name is a key
    /// (`scripts/crews-import-art.py` lists the ones still missing), so a new
    /// emblem set is a data change. A name with no entry reads in English.
    static func localizedName(_ name: String) -> String {
        String(localized: String.LocalizationValue(name), bundle: .tabbi)
    }

    public static let nameMaxLength = 20
    public static let descriptionMaxLength = 120
    public static let maxMembers = 20
    public static let searchPageSize = 20
    public static let maxSessionsPerReport = 20
    public static let maxSessionMinutes = 720
    public static let dailyCapMinutes = 960
    public static let weeklyCapMinutes = 4800

    /// `id` if the app has art for it, else the first frame.
    public static func frame(_ id: String) -> String { frames.contains(id) ? id : frames[0] }
    /// `id` if the app has art for it, else the first emblem.
    public static func emblem(_ id: String) -> String { emblems.contains(id) ? id : emblems[0] }
    /// The color for `id`, or the first color.
    public static func color(_ id: String) -> Color { colors.first { $0.id == id } ?? colors[0] }
}

/// A crew invite link: `tabbi://crew/<code>` or
/// `https://tabbinotch.com/crew/<code>`. Parsed as strictly as
/// `PartyInvite`, since links come from outside the app.
public struct CrewInvite: Hashable, Sendable {
    public static let action = "crew"

    /// The normalized 7-character invite code.
    public let code: String

    public init?(code: String) {
        guard let normalized = CrewCode.invite(code) else { return nil }
        self.code = normalized
    }

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else { return nil }
        let host = components.host?.lowercased() ?? ""
        let path = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let raw: String
        switch scheme {
        case PartyInvite.scheme:
            guard host == Self.action, path.count == 1 else { return nil }
            raw = path[0]
        case "https":
            guard host == PartyInvite.webHost || host == "www." + PartyInvite.webHost, components.port == nil,
                  path.count == 2, path[0].lowercased() == Self.action else { return nil }
            raw = path[1]
        default:
            return nil
        }
        guard !raw.contains("%"), let code = CrewCode.invite(raw) else { return nil }
        self.code = code
    }

    /// The link to share; the web page hands off to the app when it is installed.
    public var webURL: URL { URL(string: "https://\(PartyInvite.webHost)/\(Self.action)/\(code)")! }

    /// The link that opens Tabbi directly.
    public var appURL: URL { URL(string: "\(PartyInvite.scheme)://\(Self.action)/\(code)")! }
}
