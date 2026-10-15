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
