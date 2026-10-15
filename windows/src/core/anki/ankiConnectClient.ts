import {
  type AnkiConnectError,
  AnkiConnectFailure,
  AnkiErrors,
  errorFromAnkiMessage,
  failsWholeRefresh,
  isMalformedRequest,
} from "./ankiConnectError";
import {
  type AnkiDayCount,
  AnkiDecodeError,
  type AnkiDeck,
  type AnkiDeckStats,
  type AnkiPermission,
  type AnkiReview,
  type Decoder,
  DEFAULT_DECK_ID,
  decodeArray,
  decodeBool,
  decodeDayCount,
  decodeDeckStats,
  decodeDictionary,
  decodeInt,
  decodePermission,
  decodeReview,
  decodeString,
  isRecord,
} from "./ankiConnectModels";

/** The API version this client speaks. Older add-ons are rejected. */
export const ANKI_CONNECT_API_VERSION = 6;

/** Where AnkiConnect listens; the host posts there. */
export const ANKI_CONNECT_ENDPOINT = "http://127.0.0.1:8765";

/** Default timeouts, in seconds: a polling read, a `multi` batch, and `sync`. */
export const ANKI_TIMEOUTS = { request: 3, batch: 20, sync: 90 } as const;

/**
 * Every request AnkiConnect takes: `{"action", "version": 6, "params", "key"}`.
 * `params` and `key` are left out when there are none.
 */
export interface AnkiEnvelope {
  action: string;
  version: number;
  params?: unknown;
  key?: string;
}

/**
 * One POST for the host to make to `ANKI_CONNECT_ENDPOINT`. `body` is the
 * envelope as JSON, exactly the bytes to send with `Content-Type:
 * application/json`, a `Content-Length` and no `Origin` header (AnkiConnect
 * lets any request without one through, so no CORS setup is needed). The
 * host gives up after `timeoutSeconds` and stops early on `signal`.
 */
export interface AnkiRequest {
  envelope: AnkiEnvelope;
  body: string;
  timeoutSeconds: number;
  signal?: AbortSignal;
}

/**
 * Network-level failures the transport rejects with, already classified so
 * the client maps them to user-facing states. `status` is a reply that
 * wasn't 2xx (AnkiConnect answers 200 even for its own errors, so this is
 * only origin rejection or something else on the port).
 */
export type AnkiTransportError =
  /** Nothing is listening on the port: Anki is closed, still starting, or the add-on is missing. */
  | { kind: "connectionRefused" }
  /** Something is listening but did not answer in time (a dialog blocking Anki). */
  | { kind: "timedOut" }
  | { kind: "status"; status: number }
  | { kind: "failed"; message: string };

const transportKinds = new Set(["connectionRefused", "timedOut", "status", "failed"]);

export function isAnkiTransportError(value: unknown): value is AnkiTransportError {
  return isRecord(value) && typeof value.kind === "string" && transportKinds.has(value.kind);
}

/**
 * Sends one request to AnkiConnect and resolves with the reply body: the
 * raw text, or that text already parsed as JSON. Rejects with an
 * `AnkiTransportError` for anything but a 2xx reply. Injected, so the Rust
 * host makes the call and tests replay recorded replies.
 */
export type AnkiConnectTransport = (request: AnkiRequest) => Promise<unknown>;

export interface AnkiConnectClientOptions {
  transport: AnkiConnectTransport;
  /** Sent as `key` when the user configured one in AnkiConnect. */
  apiKey?: string;
  requestTimeout?: number;
  batchTimeout?: number;
  syncTimeout?: number;
  /** Whether an Anki process is running; only decides how to explain a refused connection. */
  isAnkiRunning?: () => Promise<boolean>;
  /** Told about every failed action with its name, so the app can log which call Anki refused. */
  onError?: (action: string, error: AnkiConnectError) => void;
}

/** True when a running process looks like Anki, by its executable or window name. */
export function isAnkiProcess(name: string | undefined): boolean {
  if (!name) return false;
  const base = name.replace(/^.*[\\/]/, "").toLowerCase();
  return base === "anki" || base === "anki.exe";
}

function abortReason(signal: AbortSignal): unknown {
  return signal.reason ?? new DOMException("The operation was aborted.", "AbortError");
}

function checkCancellation(signal: AbortSignal | undefined): void {
  if (signal?.aborted) throw abortReason(signal);
}

interface MultiReply<T> {
  result: T | undefined;
  error: string | undefined;
}

function decodeMultiReplies<T>(inner: Decoder<T>): Decoder<MultiReply<T>[]> {
  return decodeArray((value, path) => {
    if (!isRecord(value)) throw new AnkiDecodeError(`Expected to decode Dictionary<String, Any> at ${path}.`);
    const result = value.result === undefined || value.result === null ? undefined : inner(value.result, `${path}.result`);
    const error = value.error === undefined || value.error === null ? undefined : decodeString(value.error, `${path}.error`);
    return { result, error };
  });
}

/**
 * Port of AnkiConnectClient: a typed client for the AnkiConnect add-on (API
 * version 6). Every reply is `{"result", "error"}` with HTTP 200, so errors
 * are read from the body. Failures are thrown as `AnkiConnectFailure`; a
 * cancelled call throws its signal's reason (an `AbortError`), never an
 * Anki error, so an abandoned refresh can't flash an error state.
 */
export class AnkiConnectClient {
  readonly transport: AnkiConnectTransport;
  readonly apiKey: string | undefined;
  readonly requestTimeout: number;
  readonly batchTimeout: number;
  readonly syncTimeout: number;
  private readonly isAnkiRunning: () => Promise<boolean>;
  private readonly onError: ((action: string, error: AnkiConnectError) => void) | undefined;

  constructor(options: AnkiConnectClientOptions) {
    this.transport = options.transport;
    this.apiKey = options.apiKey;
    this.requestTimeout = options.requestTimeout ?? ANKI_TIMEOUTS.request;
    this.batchTimeout = options.batchTimeout ?? ANKI_TIMEOUTS.batch;
    this.syncTimeout = options.syncTimeout ?? ANKI_TIMEOUTS.sync;
    this.isAnkiRunning = options.isAnkiRunning ?? (async () => false);
    this.onError = options.onError;
  }

  /* Actions */

  /** The add-on's API version. */
  version(signal?: AbortSignal): Promise<number> {
    return this.invoke("version", undefined, decodeInt, signal);
  }

  /** Asks for access. Native callers are trusted, so no dialog appears. */
  requestPermission(signal?: AbortSignal): Promise<AnkiPermission> {
    return this.invoke("requestPermission", undefined, decodePermission, signal);
  }

  /** The recommended handshake: permission granted and version 6 or later. */
  async connect(signal?: AbortSignal): Promise<AnkiPermission> {
    const permission = await this.requestPermission(signal);
    if (!permission.granted) throw new AnkiConnectFailure(AnkiErrors.permissionDenied);
    if (permission.version !== undefined && permission.version < ANKI_CONNECT_API_VERSION) {
      throw new AnkiConnectFailure(AnkiErrors.addOnOutdated(permission.version));
    }
    return permission;
  }

  /**
   * Whether Tabbi can really read the cards: the handshake, then one call
   * that needs the collection. The handshake alone answers without the API
   * key, and an older add-on doesn't say a key is required, so only a real
   * call shows that a key blocks access. Undefined when it works.
   */
  async checkAccess(signal?: AbortSignal): Promise<AnkiConnectError | undefined> {
    try {
      const permission = await this.connect(signal);
      if (permission.requireAPIKey && !this.apiKey) return AnkiErrors.apiKeyRequired;
      await this.decks(signal);
      return undefined;
    } catch (error) {
      if (error instanceof AnkiConnectFailure) return error.error;
      if (signal?.aborted) throw error;
      return AnkiErrors.transport(error instanceof Error ? error.message : String(error));
    }
  }

  /** All decks, sorted by name so parents precede their children. */
  async decks(signal?: AbortSignal): Promise<AnkiDeck[]> {
    const map = await this.invoke("deckNamesAndIds", undefined, decodeDictionary(decodeInt), signal);
    return [...map].map(([name, id]) => ({ id, name })).sort((a, b) => compareStrings(a.name, b.name));
  }

  /**
   * Due counts for the decks, in the order asked for; decks Anki doesn't
   * return are left out. Older add-ons name each deck by its leaf only
   * ("Cardio" for "Step1::Cardio") and newer ones by its full name, so
   * replies are matched by id and keep the deck's full name.
   *
   * AnkiConnect 2026.10 (the rewrite AnkiWeb serves for Anki 26.08 and
   * later) fails the whole call with "Deck counts unavailable." when any
   * deck is missing from Anki's deck list, as the empty Default deck always
   * is; older versions skip such a deck. So a batch that fails with an Anki
   * error is asked again without Default, and then deck by deck in one
   * `multi`, leaving out only the decks that fail. A connection failure is
   * never retried.
   */
  async deckStats(decks: readonly AnkiDeck[], signal?: AbortSignal): Promise<AnkiDeckStats[]> {
    if (decks.length === 0) return [];
    let replies: AnkiDeckStats[];
    try {
      replies = await this.deckStatsBatch(decks, signal);
    } catch (error) {
      if (!isRetryable(error)) throw error;
      const withoutDefault = decks.filter((deck) => deck.id !== DEFAULT_DECK_ID);
      try {
        if (!(withoutDefault.length < decks.length && withoutDefault.length > 0)) throw error;
        replies = await this.deckStatsBatch(withoutDefault, signal);
      } catch (retry) {
        if (!isRetryable(retry)) throw retry;
        replies = await this.deckStatsOneByOne(decks, signal);
      }
    }
    const byID = new Map<number, AnkiDeckStats>();
    for (const reply of replies) if (!byID.has(reply.deckID)) byID.set(reply.deckID, reply);
    return decks.flatMap((deck) => {
      const stats = byID.get(deck.id);
      return stats ? [{ ...stats, deckID: deck.id, name: deck.name }] : [];
    });
  }

  private async deckStatsBatch(decks: readonly AnkiDeck[], signal: AbortSignal | undefined): Promise<AnkiDeckStats[]> {
    const params = { decks: decks.map((deck) => deck.name) };
    const map = await this.invoke("getDeckStats", params, decodeDictionary(decodeDeckStats), signal);
    return [...map.values()];
  }

  /**
   * `getDeckStats` for each deck on its own, batched through `multi`; a deck
   * whose call fails is left out. Fails only when every deck does.
   */
  private async deckStatsOneByOne(decks: readonly AnkiDeck[], signal: AbortSignal | undefined): Promise<AnkiDeckStats[]> {
    const actions = decks.map((deck) => this.multiAction("getDeckStats", { decks: [deck.name] }));
    const replies = await this.invoke(
      "multi",
      { actions },
      decodeMultiReplies(decodeDictionary(decodeDeckStats)),
      signal,
      this.batchTimeout,
    );
    const stats: AnkiDeckStats[] = [];
    let firstError: string | undefined;
    for (const reply of replies) {
      if (reply.error !== undefined) {
        firstError ??= reply.error;
        continue;
      }
      if (reply.result) stats.push(...reply.result.values());
    }
    if (stats.length === 0 && firstError !== undefined) {
      throw this.reported(errorFromAnkiMessage(firstError, "getDeckStats"), "getDeckStats");
    }
    return stats;
  }

  /** Reviews (button presses) since today's rollover. */
  numCardsReviewedToday(signal?: AbortSignal): Promise<number> {
    return this.invoke("getNumCardsReviewedToday", undefined, decodeInt, signal);
  }

  /** Review counts for every day with reviews, newest first. */
  numCardsReviewedByDay(signal?: AbortSignal): Promise<AnkiDayCount[]> {
    return this.invoke("getNumCardsReviewedByDay", undefined, decodeArray(decodeDayCount), signal);
  }

  /** Card ids matching an Anki search query, e.g. `deck:"Step1" is:due`. */
  findCards(query: string, signal?: AbortSignal): Promise<number[]> {
    return this.invoke("findCards", { query }, decodeArray(decodeInt), signal);
  }

  /**
   * Review-log rows for one deck after `startID` (exclusive, ms epoch).
   * Child decks are not included; query each subdeck separately.
   */
  cardReviews(deck: string, startID: number, signal?: AbortSignal): Promise<AnkiReview[]> {
    return this.invoke("cardReviews", { deck, startID }, decodeArray(decodeReview), signal);
  }

  /**
   * Review-log rows for several decks in one round trip, batched through
   * `multi` because `cardReviews` takes a single deck and skips children.
   * Rows come back in deck order; any deck's error fails the whole call.
   */
  async cardReviewsForDecks(decks: readonly string[], startID: number, signal?: AbortSignal): Promise<AnkiReview[]> {
    if (decks.length === 0) return [];
    const actions = decks.map((deck) => this.multiAction("cardReviews", { deck, startID }));
    const replies = await this.invoke("multi", { actions }, decodeMultiReplies(decodeArray(decodeReview)), signal, this.batchTimeout);
    if (replies.length !== decks.length) {
      throw new AnkiConnectFailure(AnkiErrors.invalidResponse(`multi: expected ${decks.length} replies, got ${replies.length}`));
    }
    const rows: AnkiReview[] = [];
    for (const reply of replies) {
      if (reply.error !== undefined) throw this.reported(errorFromAnkiMessage(reply.error, "cardReviews"), "cardReviews");
      rows.push(...(reply.result ?? []));
    }
    return rows;
  }

  /** Opens the deck and starts reviewing. Anki is not brought to the front; the app must activate it. */
  guiDeckReview(name: string, signal?: AbortSignal): Promise<boolean> {
    return this.invoke("guiDeckReview", { name }, decodeBool, signal);
  }

  /** Opens the deck's overview screen. */
  guiDeckOverview(name: string, signal?: AbortSignal): Promise<boolean> {
    return this.invoke("guiDeckOverview", { name }, decodeBool, signal);
  }

  /** Syncs with AnkiWeb, using the long timeout. */
  async sync(signal?: AbortSignal): Promise<void> {
    try {
      await this.send("sync", undefined, this.syncTimeout, signal);
    } catch (error) {
      if (error instanceof AnkiConnectFailure) throw this.reported(error.error, "sync");
      throw error;
    }
  }

  /* Plumbing */

  /**
   * One inner action of a `multi` batch. Inner actions default to API
   * version 4 (bare results), so each carries its own `version`, and
   * AnkiConnect checks the API key of each one, so each carries the key.
   */
  private multiAction(action: string, params: unknown): AnkiEnvelope {
    return envelope(action, params, this.apiKey);
  }

  private async invoke<T>(
    action: string,
    params: unknown,
    decode: Decoder<T>,
    signal: AbortSignal | undefined,
    timeout = this.requestTimeout,
  ): Promise<T> {
    let body: Record<string, unknown>;
    try {
      try {
        body = await this.send(action, params, timeout, signal);
      } catch (error) {
        /* AnkiConnect read a damaged body; ask once more. */
        if (!(error instanceof AnkiConnectFailure) || !isMalformedRequest(error.error)) throw error;
        body = await this.send(action, params, timeout, signal);
      }
    } catch (error) {
      if (error instanceof AnkiConnectFailure) throw this.reported(error.error, action);
      throw error;
    }
    try {
      if (!("result" in body)) throw new AnkiDecodeError(`No value associated with key "result".`);
      return decode(body.result, "result");
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw this.reported(AnkiErrors.invalidResponse(`${action}: ${detail}`), action);
    }
  }

  /** Hands a failure to `onError` on its way out. */
  private reported(error: AnkiConnectError, action: string): AnkiConnectFailure {
    this.onError?.(action, error);
    return new AnkiConnectFailure(error);
  }

  /**
   * Posts one action and returns the reply once its `error` field is clear.
   * A cancelled caller always gets its abort reason, never an Anki error.
   */
  private async send(
    action: string,
    params: unknown,
    timeoutSeconds: number,
    signal: AbortSignal | undefined,
  ): Promise<Record<string, unknown>> {
    checkCancellation(signal);
    const request = envelope(action, params, this.apiKey);
    let reply: unknown;
    try {
      reply = await this.transport({ envelope: request, body: JSON.stringify(request), timeoutSeconds, signal });
    } catch (error) {
      checkCancellation(signal);
      if (isAnkiTransportError(error)) {
        switch (error.kind) {
          case "connectionRefused":
            throw new AnkiConnectFailure((await this.isAnkiRunning()) ? AnkiErrors.addOnMissing : AnkiErrors.ankiNotRunning);
          case "timedOut":
            throw new AnkiConnectFailure(AnkiErrors.timeout);
          case "status":
            throw new AnkiConnectFailure(
              error.status === 403 ? AnkiErrors.permissionDenied : AnkiErrors.transport(`HTTP ${error.status}`),
            );
          case "failed":
            throw new AnkiConnectFailure(AnkiErrors.transport(error.message));
        }
      }
      throw new AnkiConnectFailure(AnkiErrors.transport(error instanceof Error ? error.message : String(error)));
    }
    checkCancellation(signal);

    let object: unknown = reply;
    if (typeof reply === "string") {
      try {
        object = JSON.parse(reply);
      } catch {
        object = undefined;
      }
    }
    if (!isRecord(object) || (object.error !== undefined && object.error !== null && typeof object.error !== "string")) {
      throw new AnkiConnectFailure(AnkiErrors.invalidResponse(`${action}: not JSON`));
    }
    if (typeof object.error === "string") throw new AnkiConnectFailure(errorFromAnkiMessage(object.error, action));
    return object;
  }
}

/** The envelope in AnkiConnect's field order, without empty `params` or `key`. */
export function envelope(action: string, params: unknown, key: string | undefined): AnkiEnvelope {
  const value: AnkiEnvelope = { action, version: ANKI_CONNECT_API_VERSION };
  if (params !== undefined) value.params = params;
  if (key !== undefined) value.key = key;
  return value;
}

/** Whether a failed `getDeckStats` is worth asking again in smaller pieces. */
function isRetryable(error: unknown): boolean {
  return error instanceof AnkiConnectFailure && !failsWholeRefresh(error.error);
}

/** Orders deck names by UTF-16 code units, as Swift's `<` on ASCII names does. */
function compareStrings(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}
