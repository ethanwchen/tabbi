import { SELF, runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it, vi } from "vitest";
import { APPLE_AUTH_PER_MIN, APPLE_CLIENT_ID, APPLE_ISSUER, APPLE_REVOKE_URL, APPLE_TOKEN_URL } from "../src/apple";
import { migrate } from "../src/hub";
import { APP_CALLBACK_URL, WEB_CALLBACK_PATH, WEB_CODE_TTL_S, WEB_TOKEN_PATH, servicesId, webNonce } from "../src/webauth";
import { apple, claimsOf, identityToken, installFakeApple } from "./fake-apple";
import { BASE, call, expectError, freshIp, hub, pinClockToMinuteStart, register } from "./helpers";

installFakeApple();

const SERVICES_ID = env.APPLE_SERVICES_ID as string;

/** A state as the app makes it: 32 random bytes, base64url. */
function newState(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** An identity token Apple would sign for the web flow: the Services ID as audience and the state's nonce. */
async function webIdentityToken(sub: string, state: string, claims: Record<string, unknown> = {}) {
  return identityToken(sub, { aud: SERVICES_ID, nonce: await webNonce(state), ...claims });
}

/** Apple's form_post to the callback; returns where the Worker sends the browser. */
async function callback(form: Record<string, string>, ip = freshIp()): Promise<{ status: number; location: URL }> {
  const res = await SELF.fetch(BASE + WEB_CALLBACK_PATH, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", "CF-Connecting-IP": ip, Origin: APPLE_ISSUER },
    body: new URLSearchParams(form).toString(),
    redirect: "manual",
  });
  await res.arrayBuffer();
  return { status: res.status, location: new URL(res.headers.get("Location")!) };
}

/** The callback for a fresh sign-in by `sub`; returns the state and the one-time code the app gets. */
async function signedInAtApple(sub: string) {
  const state = newState();
  const r = await callback({ state, code: "apple-auth-code", id_token: await webIdentityToken(sub, state) });
  expect(r.status).toBe(303);
  const code = r.location.searchParams.get("code")!;
  expect(code).toMatch(/^[0-9a-f]{64}$/);
  return { state, code };
}

const exchange = (body: Record<string, unknown>, token?: string) => call("POST", WEB_TOKEN_PATH, body, token, freshIp());

async function storedAccount(code: string) {
  return runInDurableObject(hub(), (_, state) =>
    state.storage.sql.exec<{ apple_sub: string; refresh_token: string | null; client_id: string | null }>(
      "SELECT apple_sub, refresh_token, client_id FROM apple_accounts WHERE code = ?", code).toArray());
}

describe("POST /v1/auth/apple/web/callback", () => {
  it("verifies Apple's post, exchanges the code as the Services ID and sends the browser to the app with a one-time code", async () => {
    const state = newState();
    const r = await callback({ state, code: "apple-auth-code", id_token: await webIdentityToken("sub.web.1", state), user: '{"name":{}}' });
    expect(r.status).toBe(303);
    expect(`${r.location.protocol}//${r.location.host}${r.location.pathname}`).toBe(APP_CALLBACK_URL);
    expect([...r.location.searchParams.keys()]).toEqual(["code"]);
    // The state never travels in the tabbi:// link, so a leaked link alone cannot finish the sign-in.
    expect(r.location.toString()).not.toContain(state);

    const exchanged = apple.calls.find((c) => c.url === APPLE_TOKEN_URL)!;
    expect(exchanged.form!.get("client_id")).toBe(SERVICES_ID);
    expect(exchanged.form!.get("code")).toBe("apple-auth-code");
    expect(exchanged.form!.get("redirect_uri")).toBe(BASE + WEB_CALLBACK_PATH);
    expect(claimsOf(exchanged.form!.get("client_secret")!)).toMatchObject({ iss: "TESTTEAM01", aud: APPLE_ISSUER, sub: SERVICES_ID });
  });

  it("refuses a state that does not match the token's nonce", async () => {
    const r = await callback({ state: newState(), code: "c", id_token: await webIdentityToken("sub.web.bad", newState()) });
    expect(r.location.searchParams.get("error")).toBe("invalid_state");
    expect(r.location.searchParams.has("code")).toBe(false);
    expect(apple.calls.some((c) => c.url === APPLE_TOKEN_URL)).toBe(false);
  });

  it("refuses a missing or malformed state", async () => {
    const token = await webIdentityToken("sub.web.nostate", "x".repeat(43));
    expect((await callback({ code: "c", id_token: token })).location.searchParams.get("error")).toBe("invalid_state");
    expect((await callback({ state: "short", code: "c", id_token: token })).location.searchParams.get("error")).toBe("invalid_state");
  });

  it("refuses a token made for the app instead of the Services ID", async () => {
    const state = newState();
    const r = await callback({ state, code: "c", id_token: await webIdentityToken("sub.web.aud", state, { aud: APPLE_CLIENT_ID }) });
    expect(r.location.searchParams.get("error")).toBe("invalid_identity_token");
  });

  it("refuses a replayed post: each identity token signs in once", async () => {
    const state = newState();
    const form = { state, code: "c", id_token: await webIdentityToken("sub.web.replay", state) };
    expect((await callback(form)).location.searchParams.has("code")).toBe(true);
    expect((await callback(form)).location.searchParams.get("error")).toBe("invalid_identity_token");
  });

  it("refuses a missing, empty or oversized code or identity token, and a repeated field", async () => {
    const state = newState();
    const token = await webIdentityToken("sub.web.malformed", state);
    const error = async (form: Record<string, string> | string) => {
      const raw = typeof form === "string" ? form : new URLSearchParams(form).toString();
      const res = await SELF.fetch(BASE + WEB_CALLBACK_PATH, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded", "CF-Connecting-IP": freshIp(), Origin: APPLE_ISSUER },
        body: raw,
        redirect: "manual",
      });
      await res.arrayBuffer();
      expect(res.status).toBe(303);
      const location = new URL(res.headers.get("Location")!);
      expect(location.searchParams.has("code")).toBe(false);
      return location.searchParams.get("error");
    };
    expect(await error({ state, id_token: token })).toBe("invalid_field");
    expect(await error({ state, code: "", id_token: token })).toBe("invalid_field");
    expect(await error({ state, code: "c".repeat(513), id_token: token })).toBe("invalid_field");
    expect(await error({ state, code: "c" })).toBe("invalid_field");
    expect(await error({ state, code: "c", id_token: "" })).toBe("invalid_field");
    expect(await error({ state, code: "c", id_token: "t".repeat(3001) })).toBe("invalid_field");
    // A repeated field is ambiguous, so the post is refused rather than read either way.
    const params = new URLSearchParams({ state, code: "c", id_token: token });
    params.append("code", "c2");
    expect(await error(params.toString())).toBe("invalid_field");
    // None of these reached Apple, and the identity token was not used up.
    expect(apple.calls.some((c) => c.url === APPLE_TOKEN_URL)).toBe(false);
    expect((await callback({ state, code: "c", id_token: token })).location.searchParams.has("code")).toBe(true);
  });

  it("still sends the app a code when Apple's token endpoint cannot be reached", async () => {
    apple.unreachable.add(APPLE_TOKEN_URL);
    const { state, code } = await signedInAtApple("sub.web.tokendown");
    const r = await exchange({ code, state });
    expect(r.body).toMatchObject({ ok: true, newAccount: true });
    expect(await storedAccount(r.body.code)).toEqual([{ apple_sub: "sub.web.tokendown", refresh_token: null, client_id: SERVICES_ID }]);
  });

  it("tells the app about an Apple error other than cancelling, without echoing it", async () => {
    const r = await callback({ state: newState(), error: "invalid_request<script>" });
    expect(r.status).toBe(303);
    expect([...r.location.searchParams.entries()]).toEqual([["error", "apple_error"]]);
  });

  it("tells the app when the user cancelled at Apple", async () => {
    const r = await callback({ state: newState(), error: "user_cancelled_authorize" });
    expect(r.status).toBe(303);
    expect(r.location.searchParams.get("error")).toBe("cancelled");
  });

  it("answers rate limited through the app link too", async () => {
    pinClockToMinuteStart();
    const ip = freshIp();
    for (let i = 0; i < APPLE_AUTH_PER_MIN; i++) await callback({ state: newState(), code: "c", id_token: "x.y.z" }, ip);
    expect((await callback({ state: newState(), code: "c", id_token: "x.y.z" }, ip)).location.searchParams.get("error")).toBe("rate_limited");
  });
});

describe("POST /v1/auth/apple/web/token", () => {
  it("exchanges a code with its state for a session, like POST /v1/auth/apple", async () => {
    const { state, code } = await signedInAtApple("sub.web.new");
    const r = await exchange({ code, state });
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ ok: true, newAccount: true });
    expect(r.body.token).toMatch(/^[0-9a-f]{64}$/);
    expect(r.body.profile.code).toBe(r.body.code);
    expect((await call("GET", "/v1/sync", undefined, r.body.token)).status).toBe(200);
    expect(await storedAccount(r.body.code)).toEqual([{ apple_sub: "sub.web.new", refresh_token: "apple-refresh-1", client_id: SERVICES_ID }]);
  });

  it("links the caller's anonymous Party user, keeping its token and code", async () => {
    const anon = await register({ name: "Wes" });
    const { state, code } = await signedInAtApple("sub.web.link");
    const r = await exchange({ code, state }, anon.token);
    expect(r.body).toMatchObject({ ok: true, token: anon.token, code: anon.code, newAccount: true });
    expect(r.body.profile.name).toBe("Wes");
  });

  it("signs in as a new caller when the Bearer token no longer resolves", async () => {
    const stale = "f".repeat(64);
    const { state, code } = await signedInAtApple("sub.web.stale");
    const r = await exchange({ code, state }, stale);
    expect(r.status).toBe(200);
    expect(r.body.newAccount).toBe(true);
    expect(r.body.token).not.toBe(stale);
    expect((await call("GET", "/v1/me", undefined, r.body.token)).body.profile.code).toBe(r.body.code);
  });

  it("reaches the same account as native sign-in for the same Apple ID", async () => {
    const native = await call("POST", "/v1/auth/apple", { identityToken: await identityToken("sub.web.both") }, undefined, freshIp());
    const { state, code } = await signedInAtApple("sub.web.both");
    const r = await exchange({ code, state });
    expect(r.body).toMatchObject({ code: native.body.code, newAccount: false });
    expect(r.body.token).not.toBe(native.body.token);
  });

  it("refuses a replayed code", async () => {
    const { state, code } = await signedInAtApple("sub.web.twice");
    expect((await exchange({ code, state })).status).toBe(200);
    expectError(await exchange({ code, state }), 401, "invalid_code");
  });

  it("refuses the wrong state and spends the code, so it cannot be guessed against", async () => {
    const { state, code } = await signedInAtApple("sub.web.wrongstate");
    expectError(await exchange({ code, state: newState() }), 401, "invalid_code");
    expectError(await exchange({ code, state }), 401, "invalid_code");
  });

  it("refuses an expired code", async () => {
    const start = pinClockToMinuteStart();
    const { state, code } = await signedInAtApple("sub.web.expired");
    vi.setSystemTime((start + WEB_CODE_TTL_S + 1) * 1000);
    expectError(await exchange({ code, state }), 401, "invalid_code");
  });

  it("accepts a code just inside its two minutes", async () => {
    const start = pinClockToMinuteStart();
    const { state, code } = await signedInAtApple("sub.web.intime");
    vi.setSystemTime((start + WEB_CODE_TTL_S) * 1000);
    expect((await exchange({ code, state })).status).toBe(200);
  });

  it("refuses an unknown code and malformed bodies", async () => {
    expectError(await exchange({ code: "a".repeat(64), state: newState() }), 401, "invalid_code");
    expectError(await exchange({ code: "nope", state: newState() }), 400, "invalid_field");
    expectError(await exchange({ code: "a".repeat(64), state: "short" }), 400, "invalid_field");
    expectError(await exchange({ code: "a".repeat(64), state: newState(), extra: 1 }), 400, "unknown_field");
  });

  it("revokes a web sign-in's Apple token as the Services ID when the account is deleted", async () => {
    const { state, code } = await signedInAtApple("sub.web.delete");
    const r = await exchange({ code, state });
    expect((await call("DELETE", "/v1/me", undefined, r.body.token)).body).toEqual({ ok: true, appleRevoked: true });
    const revoke = apple.calls.find((c) => c.url === APPLE_REVOKE_URL)!;
    expect(revoke.form!.get("client_id")).toBe(SERVICES_ID);
    expect(claimsOf(revoke.form!.get("client_secret")!).sub).toBe(SERVICES_ID);
  });

  it("stores native sign-in's client as the app's bundle id", async () => {
    const native = await call("POST", "/v1/auth/apple",
      { identityToken: await identityToken("sub.native.client"), authorizationCode: "c" }, undefined, freshIp());
    expect(await storedAccount(native.body.code)).toEqual([{ apple_sub: "sub.native.client", refresh_token: "apple-refresh-1", client_id: null }]);
  });
});

describe("web sign-in configuration", () => {
  it("needs a Services ID other than the app's bundle id", () => {
    expect(servicesId({ APPLE_SERVICES_ID: "dev.tabbi.Tabbi.signin" })).toBe("dev.tabbi.Tabbi.signin");
    expect(() => servicesId({})).toThrow("not configured");
    expect(() => servicesId({ APPLE_SERVICES_ID: " " })).toThrow("not configured");
    expect(() => servicesId({ APPLE_SERVICES_ID: APPLE_CLIENT_ID })).toThrow("Services ID");
  });

  it("derives the nonce from the state as base64url SHA-256", async () => {
    // SHA-256 of "abc", a published test vector.
    expect(await webNonce("abc")).toBe("ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0");
  });
});

describe("schema step 11", () => {
  it("adds the web sign-in table and the client column to a database at version 10 and keeps its accounts", async () => {
    const stub = env.HUB.get(env.HUB.idFromName("version-10"));
    await runInDurableObject(stub, (_, state) => {
      const sql = state.storage.sql;
      sql.exec("DROP TABLE web_sign_ins");
      sql.exec("ALTER TABLE apple_accounts DROP COLUMN client_id");
      sql.exec("UPDATE schema_version SET version = 10");
      sql.exec("INSERT INTO apple_accounts (apple_sub, code, refresh_token, created_at) VALUES ('s', 'CCCCCCCC', 'r', 0)");
      migrate(state.storage);
      expect(sql.exec("SELECT version FROM schema_version").toArray()).toEqual([{ version: 11 }]);
      expect(sql.exec("SELECT apple_sub, refresh_token, client_id FROM apple_accounts").toArray())
        .toEqual([{ apple_sub: "s", refresh_token: "r", client_id: null }]);
      expect(sql.exec("SELECT * FROM web_sign_ins").toArray()).toEqual([]);
    });
  });
});
