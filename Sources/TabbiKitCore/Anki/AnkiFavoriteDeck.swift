import Foundation

/// The deck the user pinned as their default, which the Anki tab offers as
/// its one-click "Study <deck>" button.
///
/// Stored by Anki's deck id and by full name. The id follows a deck through
/// a rename in Anki; the name is the fallback when the id is gone (the deck
/// was deleted and re-imported, or another profile is open) and is what a
/// click opens before any deck list has loaded.
public struct AnkiFavoriteDeck: Hashable, Sendable, Codable {
    public var deckID: Int64?
    /// The full name, with "::" between parent and child decks.
    public var name: String

    /// A favorite for `name`, or nil when the name is blank.
    public init?(deckID: Int64? = nil, name: String) {
        guard let name = AnkiDeckName.normalized(name) else { return nil }
        self.deckID = deckID
        self.name = name
    }

    public init(_ deck: AnkiDeckStats) {
        deckID = deck.deckID
        name = AnkiDeckName.normalized(deck.name) ?? deck.name
    }

    /// Whether `deck` is this favorite: the same id, or, when the id is
    /// unknown, the same full name.
    public func matches(_ deck: AnkiDeckStats) -> Bool {
        if let deckID { return deck.deckID == deckID }
        return AnkiDeckName.normalized(deck.name) == name
    }

    /// The favorite's current stats in `decks`: the deck with its id, else
    /// the deck with its name, else nil.
    public func resolve(in decks: [AnkiDeckStats]) -> AnkiDeckStats? {
        if let deckID, let byID = decks.first(where: { $0.deckID == deckID }) { return byID }
        return decks.first { AnkiDeckName.normalized($0.name) == name }
    }

    /// The favorite as `resolve(in:)` finds it, with its stored id and name
    /// brought up to date (after a rename, or a name-only match). Nil when
    /// nothing in `decks` matches or nothing changed.
    public func updated(from decks: [AnkiDeckStats]) -> AnkiFavoriteDeck? {
        guard let deck = resolve(in: decks) else { return nil }
        let current = AnkiFavoriteDeck(deck)
        return current == self ? nil : current
    }

    // MARK: Persistence

    /// The stored format. Version 1 is the first.
    public static let schema = VersionedJSON(current: 1)

    /// JSON for UserDefaults.
    public func encoded() -> Data? {
        try? Self.schema.encode(self)
    }

    /// Decodes `encoded()` output; nil for missing, corrupt or blank data.
    public init?(encoded data: Data?) {
        guard let data, let stored = try? Self.schema.decode(AnkiFavoriteDeck.self, from: data),
              let favorite = AnkiFavoriteDeck(deckID: stored.deckID, name: stored.name) else { return nil }
        self = favorite
    }
}
