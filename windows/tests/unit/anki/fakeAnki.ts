import type { AnkiRequest, AnkiTransportError } from "../../../src/core/anki/ankiConnectClient";

/*
 * Recorded AnkiConnect replies and fakes that replay them, for the wire-level
 * Anki tests. Each reply is the exact body AnkiConnect wrote, as text, the
 * way the Rust host hands it over.
 */

export const recorded = {
  /** `deckNamesAndIds` with the hidden Default deck and a nested deck. */
  deckList: `{"result":{"Step1::Cardio":3,"Default":1,"Step1":2},"error":null}`,
  /** `getDeckStats` from an older add-on, which names each deck by its leaf only ("JLPT N5"). */
  leafNameStats:
    `{"result":{"1651445861967":{"deck_id":1651445861967,"name":"JLPT N5","new_count":20,"learn_count":0,"review_count":0,"total_in_deck":1506},` +
    `"1651445861960":{"deck_id":1651445861960,"name":"Easy Spanish","new_count":26,"learn_count":10,"review_count":5,"total_in_deck":852}},"error":null}`,
  /** AnkiConnect 2026.10 failing a whole `getDeckStats` because a deck in it is hidden. */
  deckCountsUnavailable: `{"result":null,"error":"Deck counts unavailable."}`,
  /** The 2026.10 rewrite with no profile open. */
  collectionNotAvailable: `{"result":null,"error":"Collection is not available."}`,
  unsupportedAction: `{"result":null,"error":"unsupported action"}`,
};

/** One deck's `getDeckStats` entry as AnkiConnect writes it. */
export function statsJSON(id: number, name: string, due: number): string {
  return `"${id}":{"deck_id":${id},"name":"${name}","new_count":${due},"learn_count":0,"review_count":0,"total_in_deck":10}`;
}

export type Reply = { json: string } | { failure: AnkiTransportError };

export const json = (text: string): Reply => ({ json: text });
export const failure = (error: AnkiTransportError): Reply => ({ failure: error });

export interface Sent {
  body: Record<string, unknown>;
  timeout: number;
}

/** Replays canned replies by action and records every request sent. */
export class FakeAnkiTransport {
  readonly sent: Sent[] = [];

  constructor(private readonly replies: Record<string, Reply>) {}

  get requests(): Record<string, unknown>[] {
    return this.sent.map((entry) => entry.body);
  }

  get timeouts(): number[] {
    return this.sent.map((entry) => entry.timeout);
  }

  readonly transport = async (request: AnkiRequest): Promise<unknown> => {
    const body = JSON.parse(request.body) as Record<string, unknown>;
    this.sent.push({ body, timeout: request.timeoutSeconds });
    const reply = this.replies[String(body.action)];
    if (!reply) return recorded.unsupportedAction;
    if ("failure" in reply) throw reply.failure;
    return reply.json;
  };
}

/** Answers each request with whatever `reply` returns for its JSON body, and records every body. */
export class ScriptedAnkiTransport {
  readonly requests: Record<string, unknown>[] = [];

  constructor(private readonly reply: (request: Record<string, unknown>) => string) {}

  readonly transport = async (request: AnkiRequest): Promise<unknown> => {
    const body = JSON.parse(request.body) as Record<string, unknown>;
    this.requests.push(body);
    return this.reply(body);
  };
}

export function params(request: Record<string, unknown> | undefined): Record<string, unknown> {
  const value = request?.params;
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : {};
}

export function decksIn(request: Record<string, unknown> | undefined): unknown {
  return params(request).decks ?? [];
}

export function actionOf(request: Record<string, unknown> | undefined): string {
  return String(request?.action ?? "");
}

export function innerActions(request: Record<string, unknown> | undefined): Record<string, unknown>[] {
  const actions = params(request).actions;
  return Array.isArray(actions) ? (actions as Record<string, unknown>[]) : [];
}
