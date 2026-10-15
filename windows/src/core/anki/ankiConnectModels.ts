import { type AnkiDay, ankiDayText, parseAnkiDay } from "./ankiDay";

/*
 * Port of AnkiConnectModels: the shapes AnkiConnect (API version 6) sends,
 * with strict decoders. A decoder throws `AnkiDecodeError` for a reply that
 * isn't what the Mac's `JSONDecoder` would accept, and the client turns that
 * into `invalidResponse` naming the action.
 */

/** A reply that doesn't have the expected shape. */
export class AnkiDecodeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AnkiDecodeError";
  }
}

/** Reads one JSON value as T, or throws `AnkiDecodeError`. */
export type Decoder<T> = (value: unknown, path: string) => T;

function describeType(value: unknown): string {
  if (value === null) return "null";
  if (Array.isArray(value)) return "an array";
  if (typeof value === "object") return "a dictionary";
  return `a ${typeof value === "boolean" ? "bool" : typeof value}`;
}

function mismatch(expected: string, value: unknown, path: string): AnkiDecodeError {
  const where = path ? ` at ${path}` : "";
  if (value === null || value === undefined) {
    return new AnkiDecodeError(`Expected ${expected} value but found null instead${where}.`);
  }
  return new AnkiDecodeError(`Expected to decode ${expected} but found ${describeType(value)} instead${where}.`);
}

export const decodeInt: Decoder<number> = (value, path) => {
  if (typeof value !== "number" || !Number.isInteger(value)) throw mismatch("Int", value, path);
  return value;
};

export const decodeString: Decoder<string> = (value, path) => {
  if (typeof value !== "string") throw mismatch("String", value, path);
  return value;
};

export const decodeBool: Decoder<boolean> = (value, path) => {
  if (typeof value !== "boolean") throw mismatch("Bool", value, path);
  return value;
};

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function decodeObject(value: unknown, path: string): Record<string, unknown> {
  if (!isRecord(value)) throw mismatch("Dictionary<String, Any>", value, path);
  return value;
}

export function decodeArray<T>(element: Decoder<T>): Decoder<T[]> {
  return (value, path) => {
    if (!Array.isArray(value)) throw mismatch("Array<Any>", value, path);
    return value.map((item, index) => element(item, `${path}[${index}]`));
  };
}

export function decodeDictionary<T>(element: Decoder<T>): Decoder<Map<string, T>> {
  return (value, path) => {
    const object = decodeObject(value, path);
    const map = new Map<string, T>();
    for (const [key, item] of Object.entries(object)) map.set(key, element(item, `${path}.${key}`));
    return map;
  };
}

function required(object: Record<string, unknown>, key: string, path: string): unknown {
  if (!(key in object)) throw new AnkiDecodeError(`No value associated with key "${key}"${path ? ` at ${path}` : ""}.`);
  return object[key];
}

function optional<T>(object: Record<string, unknown>, key: string, decoder: Decoder<T>, path: string): T | undefined {
  const value = object[key];
  return value === undefined || value === null ? undefined : decoder(value, `${path}.${key}`);
}

/**
 * Result of `requestPermission`. A native app (no `Origin` header) is
 * always trusted, so `granted` is the normal answer.
 */
export interface AnkiPermission {
  granted: boolean;
  /** Whether the user configured an API key that every other call must send. */
  requireAPIKey: boolean;
  /** AnkiConnect API version; only present when granted. */
  version: number | undefined;
}

export const decodePermission: Decoder<AnkiPermission> = (value, path) => {
  const object = decodeObject(value, path);
  const granted = decodeString(required(object, "permission", path), `${path}.permission`) === "granted";
  /* The add-on code sends `requireApikey`; its README says `requireApiKey`. */
  const requireAPIKey =
    optional(object, "requireApikey", decodeBool, path) ?? optional(object, "requireApiKey", decodeBool, path) ?? false;
  return { granted, requireAPIKey, version: optional(object, "version", decodeInt, path) };
};

/** A deck from `deckNamesAndIds`. Names nest with `::`; ids are stable. */
export interface AnkiDeck {
  id: number;
  name: string;
}

/** Anki's Default deck, which every collection has. Anki hides it while it is empty. */
export const DEFAULT_DECK_ID = 1;

/** The last path component, e.g. "Cardio" for "Step1::Cardio". */
export function deckLeafName(deck: AnkiDeck): string {
  return deck.name.split("::").at(-1) ?? deck.name;
}

/** Nesting depth: 0 for a top-level deck. */
export function deckDepth(deck: AnkiDeck): number {
  return deck.name.split("::").length - 1;
}

/**
 * Due counts for one deck from `getDeckStats`. The numbers match Anki's deck
 * list: daily limits applied and child decks rolled up.
 */
export interface AnkiDeckStats {
  deckID: number;
  name: string;
  newCount: number;
  learnCount: number;
  reviewCount: number;
  totalInDeck: number;
}

/** Everything Anki would show today. */
export function dueTotal(stats: AnkiDeckStats): number {
  return stats.newCount + stats.learnCount + stats.reviewCount;
}

export const decodeDeckStats: Decoder<AnkiDeckStats> = (value, path) => {
  const object = decodeObject(value, path);
  const int = (key: string) => decodeInt(required(object, key, path), `${path}.${key}`);
  return {
    deckID: int("deck_id"),
    name: decodeString(required(object, "name", path), `${path}.name`),
    newCount: int("new_count"),
    learnCount: int("learn_count"),
    reviewCount: int("review_count"),
    totalInDeck: int("total_in_deck"),
  };
};

/** One row of `getNumCardsReviewedByDay`: `["2026-09-30", 412]`. */
export interface AnkiDayCount {
  day: AnkiDay;
  count: number;
}

export const decodeDayCount: Decoder<AnkiDayCount> = (value, path) => {
  if (!Array.isArray(value)) throw mismatch("Array<Any>", value, path);
  const text = decodeString(value[0], `${path}[0]`);
  const day = parseAnkiDay(text);
  if (!day) throw new AnkiDecodeError(`Bad day ${text}`);
  return { day, count: decodeInt(value[1], `${path}[1]`) };
};

/** The JSON form AnkiConnect uses, for recorded replies. */
export function encodeDayCount(entry: AnkiDayCount): [string, number] {
  return [ankiDayText(entry.day), entry.count];
}

/** Review-log kinds as stored in Anki's `revlog.type` column. */
export const AnkiReviewKind = {
  learn: 0,
  review: 1,
  relearn: 2,
  filtered: 3,
  manual: 4,
  unknown: -1,
} as const;
export type AnkiReviewKind = (typeof AnkiReviewKind)[keyof typeof AnkiReviewKind];

/**
 * One review-log row from `cardReviews`, decoded from AnkiConnect's 9-tuple
 * `(reviewTime ms, cardID, usn, ease, newIvl, lastIvl, factor, durationMs, type)`.
 */
export interface AnkiReview {
  /** The answer time in milliseconds since 1970; also the exclusive `startID` cursor. */
  id: number;
  cardID: number;
  /** Answer button: 1 Again, 2 Hard, 3 Good, 4 Easy (0 for manual entries). */
  ease: number;
  interval: number;
  lastInterval: number;
  factor: number;
  durationMilliseconds: number;
  kind: AnkiReviewKind;
}

/** Seconds since 1970 of the answer. */
export function reviewedAt(review: AnkiReview): number {
  return review.id / 1000;
}

/** True when the user pressed Again (a lapse for review cards). */
export function isFailure(review: AnkiReview): boolean {
  return review.ease === 1;
}

const knownKinds = new Set<number>(Object.values(AnkiReviewKind));

export const decodeReview: Decoder<AnkiReview> = (value, path) => {
  if (!Array.isArray(value)) throw mismatch("Array<Any>", value, path);
  const at = (index: number) => {
    if (index >= value.length) throw new AnkiDecodeError(`Unkeyed container is at end${path ? ` at ${path}` : ""}.`);
    return decodeInt(value[index], `${path}[${index}]`);
  };
  const id = at(0);
  const cardID = at(1);
  at(2); /* usn: sync bookkeeping, unused */
  const ease = at(3);
  const interval = at(4);
  const lastInterval = at(5);
  const factor = at(6);
  const durationMilliseconds = at(7);
  const raw = at(8);
  const kind = (knownKinds.has(raw) ? raw : AnkiReviewKind.unknown) as AnkiReviewKind;
  return { id, cardID, ease, interval, lastInterval, factor, durationMilliseconds, kind };
};
