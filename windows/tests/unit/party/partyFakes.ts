import { expect } from "vitest";
import { PartyError } from "../../../src/core/party/partyError";
import type { PartyHttpRequest, PartyHttpResponse, PartyTransport } from "../../../src/core/party/partyTransport";

/* Replays recorded friends-server replies by `METHOD path` and records what the client sent. */

export type FakeReply =
  | { readonly json: string; readonly status?: number; readonly retryAfter?: number }
  | { readonly failure: unknown };

export class FakePartyTransport {
  readonly requests: PartyHttpRequest[] = [];
  private readonly replies: Map<string, FakeReply | (() => FakeReply)>;

  constructor(replies: Record<string, FakeReply | (() => FakeReply)> = {}) {
    this.replies = new Map(Object.entries(replies));
  }

  set(route: string, reply: FakeReply | (() => FakeReply)): void {
    this.replies.set(route, reply);
  }

  /** The JSON body of the last request. */
  get lastBody(): Record<string, unknown> {
    const body = this.requests[this.requests.length - 1]?.body;
    return body === undefined ? {} : (JSON.parse(body) as Record<string, unknown>);
  }

  get last(): PartyHttpRequest | undefined {
    return this.requests[this.requests.length - 1];
  }

  readonly send: PartyTransport = async (request) => {
    this.requests.push(request);
    const entry = this.replies.get(`${request.method} ${request.path}`);
    const reply = typeof entry === "function" ? entry() : entry;
    if (reply === undefined) return { status: 404, body: '{"ok":false,"error":"not_found","message":"no route"}' };
    if ("failure" in reply) throw reply.failure;
    const response: PartyHttpResponse = {
      status: reply.status ?? 200,
      body: reply.json,
      ...(reply.retryAfter === undefined ? {} : { retryAfter: reply.retryAfter }),
    };
    return response;
  };
}

export const json = (text: string, status?: number, retryAfter?: number): FakeReply => ({
  json: text,
  ...(status === undefined ? {} : { status }),
  ...(retryAfter === undefined ? {} : { retryAfter }),
});

export const errorBody = (code: string) => `{"ok":false,"error":"${code}","message":"whatever"}`;

export const TOKEN = "ab".repeat(32);

/** Recorded replies, shaped exactly like docs/study/backend-api.md. */
export const Fixture = {
  ana: '{"code":"K7QW2MZD","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":["#F2A65A","#FFFFFF"],"costume":"scrubs","accessories":["glasses","coffee-mug"],"points":1240,"level":7}',
  ben: '{"code":"B3NX9QRT","name":"Ben","petName":"Biscuit","species":"dog","breed":"corgi","colors":[],"costume":"none","accessories":[],"points":80,"level":2}',
  studying: '{"status":"studying","method":"pomodoro","phaseEndsAt":1790000000,"sessionMinutes":50,"todayMinutes":125,"streakDays":12,"day":"2026-10-01","lastSeen":1789999100}',
  offline: '{"status":"offline","method":null,"phaseEndsAt":null,"sessionMinutes":0,"todayMinutes":30,"streakDays":3,"day":"2026-09-30","lastSeen":1789900000}',
  get party(): string {
    return `{"ok":true,"party":{"code":"Q4RT8M","host":"K7QW2MZD","createdAt":1789990000,"lastActive":1789999000,"expiresAt":1790042200,"maxMembers":8,"session":{"method":"pomodoro","phaseEndsAt":1790000000,"startedAt":1789998500},"members":[{"profile":${this.ana},"joinedAt":1789990000,"host":true,"presence":${this.studying},"online":true},{"profile":${this.ben},"joinedAt":1789991000,"host":false,"presence":null,"online":false}]}}`;
  },
};

/** Expects `body` to reject with a PartyError equal to `expected`. */
export async function expectPartyError(body: () => Promise<unknown>, expected: PartyError): Promise<void> {
  let caught: unknown;
  try {
    await body();
  } catch (error) {
    caught = error;
  }
  expect(caught, `expected ${expected.message}`).toBeInstanceOf(PartyError);
  const error = caught as PartyError;
  expect({ kind: error.kind, code: error.code, status: error.status, retryAfter: error.retryAfter, detail: error.detail }).toEqual({
    kind: expected.kind,
    code: expected.code,
    status: expected.status,
    retryAfter: expected.retryAfter,
    detail: expected.detail,
  });
}
