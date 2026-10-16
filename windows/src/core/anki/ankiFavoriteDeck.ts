import { defaultsString, type Defaults } from "../persistence/defaults";
import type { JSONObject } from "../persistence/json";
import { VersionedJSON } from "../persistence/versionedJson";
import type { AnkiDeckStats } from "./ankiConnectModels";
import { normalizedDeckName } from "./ankiDeckName";

/**
 * Port of AnkiFavoriteDeck: the deck the user pinned for the one-click
 * "Study <deck>" button. Kept by id, which follows a rename in Anki, and by
 * full name, the fallback when the id is gone and what a click opens before
 * any deck list has loaded.
 */
export interface AnkiFavoriteDeck {
  deckID?: number;
  /** The full name, with "::" between parent and child decks. */
  name: string;
}

/** A favorite for `name`, or undefined when the name is blank. */
export function makeFavoriteDeck(name: string, deckID?: number): AnkiFavoriteDeck | undefined {
  const normalized = normalizedDeckName(name);
  if (normalized === undefined) return undefined;
  return deckID === undefined ? { name: normalized } : { deckID, name: normalized };
}

export function favoriteFromDeck(deck: AnkiDeckStats): AnkiFavoriteDeck {
  return { deckID: deck.deckID, name: normalizedDeckName(deck.name) ?? deck.name };
}

/** Whether `deck` is this favorite: the same id, or, when the id is unknown, the same full name. */
export function favoriteMatches(favorite: AnkiFavoriteDeck, deck: AnkiDeckStats): boolean {
  if (favorite.deckID !== undefined) return deck.deckID === favorite.deckID;
  return normalizedDeckName(deck.name) === favorite.name;
}

/** The favorite's current stats in `decks`: by id, else by name, else undefined. */
export function resolveFavorite(favorite: AnkiFavoriteDeck, decks: readonly AnkiDeckStats[]): AnkiDeckStats | undefined {
  if (favorite.deckID !== undefined) {
    const byID = decks.find((deck) => deck.deckID === favorite.deckID);
    if (byID) return byID;
  }
  return decks.find((deck) => normalizedDeckName(deck.name) === favorite.name);
}

/**
 * The favorite as `resolveFavorite` finds it, with its id and name brought up
 * to date. Undefined when nothing matches or nothing changed.
 */
export function updatedFavorite(favorite: AnkiFavoriteDeck, decks: readonly AnkiDeckStats[]): AnkiFavoriteDeck | undefined {
  const deck = resolveFavorite(favorite, decks);
  if (!deck) return undefined;
  const current = favoriteFromDeck(deck);
  return current.deckID === favorite.deckID && current.name === favorite.name ? undefined : current;
}

/*
 * Persistence, after AnkiFavoriteDeck's `encoded()` and `init?(encoded:)`.
 * The Mac keeps the favorite as `Data` in `UserDefaults` under
 * `anki.favoriteDeck`; here that value is the same JSON text in the core's
 * `Defaults`. Written by a default `JSONEncoder`: compact, keys in
 * declaration order (`deckID` left out when unknown), `schemaVersion` last.
 */

/** The preferences key AnkiStore keeps the favorite under. */
export const ANKI_FAVORITE_DECK_KEY = "anki.favoriteDeck";

/** The stored format. Version 1 is the first. */
export const ANKI_FAVORITE_DECK_SCHEMA = new VersionedJSON(1);

/** The favorite as JSON text, the Mac's `encoded()`. */
export function encodedFavoriteDeck(favorite: AnkiFavoriteDeck): string {
  const document: JSONObject = {};
  if (favorite.deckID !== undefined) document.deckID = favorite.deckID;
  document.name = favorite.name;
  return ANKI_FAVORITE_DECK_SCHEMA.encode(document);
}

/**
 * Reads `encodedFavoriteDeck` output; undefined for missing, corrupt or
 * blank data. As with the Mac's synthesized Codable, a `deckID` that isn't
 * an integer makes the whole document unreadable, while null counts as none.
 */
export function decodeFavoriteDeck(text: string | undefined): AnkiFavoriteDeck | undefined {
  if (text === undefined) return undefined;
  try {
    return ANKI_FAVORITE_DECK_SCHEMA.decode(text, readFavoriteDeck);
  } catch {
    return undefined;
  }
}

function readFavoriteDeck(document: JSONObject): AnkiFavoriteDeck | undefined {
  const { deckID, name } = document;
  if (typeof name !== "string") throw new TypeError("Invalid name");
  if (deckID === undefined || deckID === null) return makeFavoriteDeck(name);
  if (typeof deckID !== "number" || !Number.isInteger(deckID)) throw new TypeError("Invalid deckID");
  return makeFavoriteDeck(name, deckID);
}

/** The saved favorite, or undefined when none is saved or it can't be read. */
export function loadFavoriteDeck(defaults: Defaults): AnkiFavoriteDeck | undefined {
  return decodeFavoriteDeck(defaultsString(defaults, ANKI_FAVORITE_DECK_KEY));
}

/** Saves the favorite; undefined clears it, as setting nil in `UserDefaults` does. */
export function saveFavoriteDeck(defaults: Defaults, favorite: AnkiFavoriteDeck | undefined): void {
  if (favorite === undefined) defaults.remove(ANKI_FAVORITE_DECK_KEY);
  else defaults.set(ANKI_FAVORITE_DECK_KEY, encodedFavoriteDeck(favorite));
}
