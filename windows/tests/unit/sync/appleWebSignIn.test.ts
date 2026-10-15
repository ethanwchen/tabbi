import { describe, expect, it } from "vitest";
import { PartyError } from "../../../src/core/party/partyError";
import type { PartyHttpRequest, PartyHttpResponse, PartyTransport } from "../../../src/core/party/partyTransport";
import {
  AppleWebSignIn,
  appleRedirectURI,
  newWebSignInState,
  parseAppleCallback,
  webSignInFailureMessage,
  webSignInNonce,
} from "../../../src/core/sync/appleWebSignIn";
import { SyncClient } from "../../../src/core/sync/syncClient";

// Port of AppleWebSignInTests.swift: Apple's authorize link, the
// tabbi://auth/apple callback and the code exchange, against a server that
// answers like backend/src/webauth.ts.

const code = "ab12".repeat(16);

/** Answers POST /v1/auth/apple/web/token like the backend: each code works once, and a wrong state spends it. */
class WebTokenServer {
  private readonly pending = new Map<string, string>();
  readonly requests: PartyHttpRequest[] = [];
  failure: [number, string] | undefined;

  issue(issued: string, state: string): void {
    this.pending.set(issued, state);
  }

  readonly transport: PartyTransport = async (request) => {
    this.requests.push(request);
    if (this.failure !== undefined) return reply(this.failure[1], this.failure[0]);
    let body: Record<string, unknown>;
    try {
      body = JSON.parse(request.body ?? "") as Record<string, unknown>;
    } catch {
      body = {};
    }
    if (request.method !== "POST" || request.path !== "/v1/auth/apple/web/token" || typeof body.code !== "string" || typeof body.state !== "string") {
      return reply(`{"ok":false,"error":"invalid_field"}`, 400);
    }
    const expected = this.pending.get(body.code);
    this.pending.delete(body.code);
    if (expected !== body.state) return reply(`{"ok":false,"error":"invalid_code"}`, 401);
    return reply(
      `{"ok":true,"token":"t-new","code":"K7QW2MZD","newAccount":false,"profile":{"code":"K7QW2MZD","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":10,"level":1}}`,
    );
  };
}

function reply(body: string, status = 200): PartyHttpResponse {
  return { status, body };
}

async function failure(promise: Promise<unknown>): Promise<PartyError> {
  try {
    await promise;
  } catch (error) {
    if (error instanceof PartyError) return error;
    throw error;
  }
  throw new Error("expected a failure");
}

describe("AppleWebSignIn authorize link", () => {
  it("makes a state of 32 random bytes in base64url", () => {
    const first = newWebSignInState();
    const second = newWebSignInState();
    expect(first).toHaveLength(43);
    expect(first).not.toBe(second);
    expect(first).toMatch(/^[A-Za-z0-9_-]+$/);
  });

  it("derives the nonce from the state the way the server does", async () => {
    expect(await webSignInNonce("abc")).toBe("ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0");
    expect((await AppleWebSignIn.start()).nonce).not.toContain("=");
  });

  it("asks Apple per the web flow", async () => {
    const attempt = await AppleWebSignIn.start();
    const text = attempt.authorizeURL();
    const url = new URL(text);
    expect(url.protocol).toBe("https:");
    expect(url.host).toBe("appleid.apple.com");
    expect(url.pathname).toBe("/auth/authorize");
    expect(Object.fromEntries(url.searchParams)).toEqual({
      response_type: "code id_token",
      response_mode: "form_post",
      client_id: "dev.tabbi.Tabbi.signin",
      redirect_uri: "https://tabbi-friends.drosophil-anki-friends-backend.workers.dev/v1/auth/apple/web/callback",
      scope: "name",
      state: attempt.state,
      nonce: attempt.nonce,
    });
    expect(text, "a space, not a plus").toContain("response_type=code%20id_token");
  });

  it("follows the server for the redirect", () => {
    expect(appleRedirectURI("http://localhost:8787")).toBe("http://localhost:8787/v1/auth/apple/web/callback");
    expect(appleRedirectURI("http://localhost:8787/")).toBe("http://localhost:8787/v1/auth/apple/web/callback");
  });
});

describe("AppleWebSignIn callback link", () => {
  it("reads the one-time code", () => {
    expect(parseAppleCallback(`tabbi://auth/apple?code=${code}`)).toEqual({ kind: "code", code });
    expect(parseAppleCallback(`TABBI://Auth/apple/?code=${code}`)).toEqual({ kind: "code", code });
  });

  it("reads the server's errors", () => {
    expect(parseAppleCallback("tabbi://auth/apple?error=cancelled")).toEqual({ kind: "failure", failure: "cancelled" });
    expect(parseAppleCallback("tabbi://auth/apple?error=not_configured")).toEqual({ kind: "failure", failure: "notConfigured" });
    for (const reason of ["invalid_state", "invalid_identity_token", "apple_error"]) {
      expect(parseAppleCallback(`tabbi://auth/apple?error=${reason}`), reason).toEqual({ kind: "failure", failure: "rejected" });
    }
    for (const reason of ["apple_unavailable", "rate_limited", "internal", "body_too_large", "something_new"]) {
      expect(parseAppleCallback(`tabbi://auth/apple?error=${reason}`), reason).toEqual({ kind: "failure", failure: "unavailable" });
    }
    expect(webSignInFailureMessage("cancelled"), "cancelling says nothing").toBeUndefined();
    expect(webSignInFailureMessage("unavailable")).toBeDefined();
  });

  it("ignores anything else", () => {
    for (const text of [
      "tabbi://auth/apple",
      "tabbi://auth/apple?code=short",
      `tabbi://auth/apple?code=${code.toUpperCase()}`,
      `tabbi://auth/apple?code=${code}&code=${code}`,
      `tabbi://auth/google?code=${code}`,
      `tabbi://auth/apple/more?code=${code}`,
      `tabbi://open?code=${code}`,
      `https://tabbinotch.com/auth/apple?code=${code}`,
    ]) {
      expect(parseAppleCallback(text), text).toBeUndefined();
    }
  });
});

describe("AppleWebSignIn code exchange", () => {
  it("exchanges the code with its state and the anonymous token", async () => {
    const server = new WebTokenServer();
    const state = newWebSignInState();
    server.issue(code, state);
    const result = await new SyncClient(server.transport, "anonymous-token").exchangeWebSignIn(code, state);
    expect(result.credentials).toEqual({ token: "t-new", code: "K7QW2MZD" });
    expect(result.profile.name).toBe("Ana");
    expect(result.newAccount).toBe(false);
    const request = server.requests[0];
    expect(request?.method).toBe("POST");
    expect(request?.path).toBe("/v1/auth/apple/web/token");
    expect(request?.token, "links the device's anonymous Party user").toBe("anonymous-token");
    expect(JSON.parse(request?.body ?? "")).toEqual({ code, state });
  });

  it("lets a code work once and only with its state", async () => {
    const server = new WebTokenServer();
    const state = newWebSignInState();
    server.issue(code, state);
    const client = new SyncClient(server.transport);
    expect((await failure(client.exchangeWebSignIn(code, newWebSignInState()))).isExpiredWebSignIn).toBe(true);
    expect((await failure(client.exchangeWebSignIn(code, state))).isExpiredWebSignIn, "the wrong state spent the code").toBe(true);
    server.issue(code, state);
    await client.exchangeWebSignIn(code, state);
    expect((await failure(client.exchangeWebSignIn(code, state))).isExpiredWebSignIn).toBe(true);
  });

  it("tells other failures from an expired code", async () => {
    const server = new WebTokenServer();
    server.failure = [503, `{"ok":false,"error":"apple_unavailable"}`];
    const error = await failure(new SyncClient(server.transport).exchangeWebSignIn(code, newWebSignInState()));
    expect(error.isExpiredWebSignIn).toBe(false);
    expect(error.kind).toBe("serverUnavailable");
  });
});
