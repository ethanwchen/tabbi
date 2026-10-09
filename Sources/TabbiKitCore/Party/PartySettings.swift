import Foundation

/// The user's Party preferences: which friends server to use, the name
/// friends see, and whether to go invisible.
///
/// Nothing here is kit-specific; a kit only decides whether the Party tab
/// is on. The secret token lives in `PartyCredentialStore`, never here.
public struct PartySettings: Codable, Equatable, Sendable {
    /// The server name and pet name limit from the API contract.
    public static let maxNameLength = DisplayName.maxLength

    public static let `default` = PartySettings()

    /// The server field's raw text, kept as typed so the field round-trips.
    /// Blank means the default server (`PartyServer.productionURL`).
    public var serverText: String
    /// The name friends see. Blank keeps the server's current name.
    public var name: String
    /// When on, heartbeats report `offline` and friends see you as away,
    /// while your own minutes keep counting locally.
    public var invisible: Bool

    public init(serverText: String = "", name: String = "", invisible: Bool = false) {
        self.serverText = serverText
        self.name = name
        self.invisible = invisible
    }

    /// The server to talk to, or nil when the field holds something that
    /// isn't a usable server URL (see `PartyServer.parse`).
    public var serverURL: URL? {
        usesDefaultServer ? PartyServer.productionURL : PartyServer.parse(serverText)
    }

    /// True when the server field is blank, so the default server is used.
    public var usesDefaultServer: Bool {
        serverText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A one-line problem with the server field for Settings, or nil when
    /// it is blank or valid.
    public var serverIssue: String? {
        guard !usesDefaultServer, serverURL == nil else { return nil }
        let text = serverText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("http://") {
            return "Use https:// (plain http:// only works for localhost)."
        }
        return "Not a server address. Try https://your-server.example."
    }

    /// The name as the server will store it: trimmed, control and
    /// invisible characters removed, at most `maxNameLength` characters.
    /// Nil when nothing is left, so the server keeps the current name.
    public var cleanedName: String? {
        DisplayName.cleaned(name)
    }

    /// The profile to sync: the cleaned name plus the pet's appearance.
    /// It carries nothing about cards, decks or study content. A name or
    /// pet name that `PartyNameFilter` rejects is left out, since the
    /// server would refuse it; `refusedNames(for:)` says which.
    public func profileUpdate(for pet: PetProfile) -> PartyProfileUpdate {
        var update = PartyPetAppearance.update(for: pet)
        update.name = cleanedName
        return update.removing(refusedNames(for: pet))
    }

    /// The names the server would refuse, known before any request.
    public func refusedNames(for pet: PetProfile) -> PartyNameRefusal {
        var refused: PartyNameRefusal = []
        if let name = cleanedName, !PartyNameFilter.isAllowed(name) { refused.insert(.name) }
        if !PartyNameFilter.isAllowed(pet.name) { refused.insert(.petName) }
        return refused
    }

    private enum CodingKeys: String, CodingKey {
        case serverText, name, invisible
    }

    /// Missing keys fall back to defaults, so adding a setting later never
    /// throws away the saved ones.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverText = try container.decodeIfPresent(String.self, forKey: .serverText) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        invisible = try container.decodeIfPresent(Bool.self, forKey: .invisible) ?? false
    }
}

/// Loads and saves `PartySettings` as one JSON value in `UserDefaults`,
/// under a key of its own so Party never touches `AppSettings`.
public struct PartySettingsRepository {
    static let key = "party.settings"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> PartySettings {
        defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(PartySettings.self, from: $0) } ?? .default
    }

    public func save(_ settings: PartySettings) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: Self.key)
    }
}
