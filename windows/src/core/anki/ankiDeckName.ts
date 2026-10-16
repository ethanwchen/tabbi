/** Port of AnkiDeckName: deck paths as Anki writes them, with `::` between parent and child. */
export const DECK_SEPARATOR = "::";

/** The path's parts, trimmed, with empty parts dropped, the way Anki cleans a typed deck name. */
export function deckNameComponents(name: string): string[] {
  return name
    .split(DECK_SEPARATOR)
    .map((part) => part.trim())
    .filter((part) => part.length > 0);
}

/** The full name AnkiConnect expects, or undefined for a blank name. */
export function normalizedDeckName(name: string): string | undefined {
  const parts = deckNameComponents(name);
  return parts.length === 0 ? undefined : parts.join(DECK_SEPARATOR);
}

/** The deck's own name: "Arrhythmias" for "Step1::Cardio::Arrhythmias". */
export function deckLeaf(name: string): string {
  return deckNameComponents(name).at(-1) ?? name;
}
