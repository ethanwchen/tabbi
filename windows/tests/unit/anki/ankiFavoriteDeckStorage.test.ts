import { describe, expect, it } from "vitest";
import {
  ANKI_FAVORITE_DECK_KEY,
  ANKI_FAVORITE_DECK_SCHEMA,
  decodeFavoriteDeck,
  encodedFavoriteDeck,
  favoriteFromDeck,
  loadFavoriteDeck,
  makeFavoriteDeck,
  saveFavoriteDeck,
} from "../../../src/core/anki/ankiFavoriteDeck";
import { InMemoryDefaults } from "../../../src/core/persistence/defaults";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";

/* Port of AnkiFavoriteDeckTests (persistence) and AnkiStore's save and load of the favorite. */

const cardio = favoriteFromDeck({ deckID: 2, name: "Step 1:: Cardio", newCount: 0, learnCount: 0, reviewCount: 0, totalInDeck: 100 });

describe("AnkiFavoriteDeck persistence", () => {
  it("round trips through its schema", () => {
    const text = encodedFavoriteDeck(cardio);
    expect(VersionedJSON.version(text)).toBe(1);
    expect(decodeFavoriteDeck(text)).toEqual(cardio);
  });

  it("writes what the Mac's default encoder writes", () => {
    expect(encodedFavoriteDeck(cardio)).toBe('{"deckID":2,"name":"Step 1::Cardio","schemaVersion":1}');
    expect(encodedFavoriteDeck({ name: "Path/oma" })).toBe('{"name":"Path\\/oma","schemaVersion":1}');
    expect(ANKI_FAVORITE_DECK_SCHEMA.current).toBe(1);
  });

  it("rejects missing, corrupt or blank data", () => {
    for (const text of [undefined, "not json", "[1]", '{"schemaVersion":1,"name":"  "}', '{"schemaVersion":1}', '{"name":4}', '{"deckID":"2","name":"A"}', '{"deckID":2.5,"name":"A"}']) {
      expect(decodeFavoriteDeck(text), String(text)).toBeUndefined();
    }
  });

  it("reads a name-only document, a null id and a version 0 document", () => {
    expect(decodeFavoriteDeck('{"schemaVersion":1,"name":"Pathoma"}')).toEqual(makeFavoriteDeck("Pathoma"));
    expect(decodeFavoriteDeck('{"deckID":null,"name":"Pathoma"}')).toEqual(makeFavoriteDeck("Pathoma"));
    expect(decodeFavoriteDeck('{"deckID":5,"name":" Step 1 :: Cardio "}')).toEqual(makeFavoriteDeck("Step 1::Cardio", 5));
  });

  it("saves under the Mac's key and clears it when unpinned", () => {
    const defaults = new InMemoryDefaults();
    expect(loadFavoriteDeck(defaults)).toBeUndefined();
    saveFavoriteDeck(defaults, cardio);
    expect(ANKI_FAVORITE_DECK_KEY).toBe("anki.favoriteDeck");
    expect(defaults.get(ANKI_FAVORITE_DECK_KEY)).toBe(encodedFavoriteDeck(cardio));
    expect(loadFavoriteDeck(defaults)).toEqual(cardio);
    saveFavoriteDeck(defaults, undefined);
    expect(defaults.entries()).toEqual({});
  });

  it("loads nothing from a damaged value", () => {
    expect(loadFavoriteDeck(new InMemoryDefaults({ [ANKI_FAVORITE_DECK_KEY]: "{" }))).toBeUndefined();
    expect(loadFavoriteDeck(new InMemoryDefaults({ [ANKI_FAVORITE_DECK_KEY]: { name: "A" } }))).toBeUndefined();
  });
});
