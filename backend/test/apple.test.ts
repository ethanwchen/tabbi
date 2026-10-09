import { runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
  APPLE_AUTH_PER_MIN, APPLE_CLIENT_ID, APPLE_ISSUER, APPLE_KEYS_URL, APPLE_REVOKE_URL, APPLE_TOKEN_URL, appleSecrets,
  exchangeAuthorizationCode, resetAppleKeyCache, revokeRefreshToken, verifyIdentityToken,
} from "../src/apple";
import { call, expectError, freshIp, hub, register } from "./helpers";

// ---------- a fake Apple ----------

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const encode = (v: unknown) => b64url(new TextEncoder().encode(JSON.stringify(v)));

let signingKey: CryptoKeyPair;
let otherKey: CryptoKeyPair;
let publicJwk: JsonWebKey;

async function rsaKey(): Promise<CryptoKeyPair> {
  return (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true, ["sign", "verify"],
  )) as CryptoKeyPair;
}

beforeAll(async () => {
  signingKey = await rsaKey();
  otherKey = await rsaKey();
  publicJwk = (await crypto.subtle.exportKey("jwk", signingKey.publicKey)) as JsonWebKey;
});

const now = () => Math.floor(Date.now() / 1000);

/** An identity token as Apple would sign it; `claims` and `header` override the defaults. */
async function identityToken(sub: string, claims: Record<string, unknown> = {}, opts: { kid?: string; key?: CryptoKey; alg?: string } = {}) {
  const header = encode({ alg: opts.alg ?? "RS256", kid: opts.kid ?? "apple-key-1" });
  const payload = encode({
    iss: APPLE_ISSUER, aud: APPLE_CLIENT_ID, exp: now() + 600, iat: now(), sub, email: "never-read@example.com", ...claims,
  });
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", opts.key ?? signingKey.privateKey, new TextEncoder().encode(`${header}.${payload}`));
  return `${header}.${payload}.${b64url(new Uint8Array(sig))}`;
}

interface AppleCall { url: string; form: URLSearchParams | null }
let appleCalls: AppleCall[];
let tokenReply: { status: number; body: unknown };
let keysUp: boolean;

beforeEach(() => {
  resetAppleKeyCache();
  appleCalls = [];
  keysUp = true;
  tokenReply = { status: 200, body: { access_token: "a", refresh_token: "apple-refresh-1", id_token: "x" } };
  // The Durable Object runs in the test isolate, so its outbound fetch is this spy.
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = input instanceof Request ? input.url : String(input);
    const form = typeof init?.body === "string" ? new URLSearchParams(init.body) : null;
    appleCalls.push({ url, form });
    if (url === APPLE_KEYS_URL) {
      return keysUp ? Response.json({ keys: [{ ...publicJwk, kid: "apple-key-1", alg: "RS256", use: "sig" }] }) : new Response("down", { status: 503 });
    }
    if (url === APPLE_TOKEN_URL) return Response.json(tokenReply.body, { status: tokenReply.status });
    if (url === APPLE_REVOKE_URL) return new Response(null, { status: 200 });
    throw new Error(`unexpected fetch ${url}`);
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});

const signIn = (body: Record<string, unknown>, token?: string, ip = freshIp()) => call("POST", "/v1/auth/apple", body, token, ip);

async function storedAccounts(code: string) {
  return runInDurableObject(hub(), (_, state) =>
    state.storage.sql.exec<{ apple_sub: string; refresh_token: string | null }>(
      "SELECT apple_sub, refresh_token FROM apple_accounts WHERE code = ?", code).toArray());
}

/** Reads the claims of a JWT without verifying it. */
function claimsOf(jwt: string) {
  const part = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(part + "=".repeat((4 - (part.length % 4)) % 4)));
}

// ---------- the route ----------

describe("POST /v1/auth/apple", () => {
  it("creates an account for a new Apple ID without a token", async () => {
    const r = await signIn({ identityToken: await identityToken("sub.new.1") });
    expect(r.status).toBe(200);
    expect(r.body.ok).toBe(true);
    expect(r.body.newAccount).toBe(true);
    expect(r.body.token).toMatch(/^[0-9a-f]{64}$/);
    expect(r.body.code).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
    expect(r.body.profile.code).toBe(r.body.code);
    const me = await call("GET", "/v1/me", undefined, r.body.token);
    expect(me.body.profile.code).toBe(r.body.code);
    expect(await storedAccounts(r.body.code)).toEqual([{ apple_sub: "sub.new.1", refresh_token: null }]);
  });

  it("links the caller's anonymous Party user to a new account, keeping its token and code", async () => {
    const anon = await register({ name: "Ana" });
    const r = await signIn({ identityToken: await identityToken("sub.link.1") }, anon.token);
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ ok: true, token: anon.token, code: anon.code, newAccount: true });
    expect(r.body.profile.name).toBe("Ana");
    expect((await call("GET", "/v1/sync", undefined, anon.token)).status).toBe(200);
  });

  it("gives a second Mac the account's identity with a token of its own, and keeps the first Mac's token working", async () => {
    const mac1 = await register();
    await signIn({ identityToken: await identityToken("sub.two.macs") }, mac1.token);
    const r = await signIn({ identityToken: await identityToken("sub.two.macs") });
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ code: mac1.code, newAccount: false });
    expect(r.body.token).not.toBe(mac1.token);
    expect((await call("GET", "/v1/me", undefined, r.body.token)).body.profile.code).toBe(mac1.code);
    expect((await call("GET", "/v1/me", undefined, mac1.token)).status).toBe(200);
  });

  it("returns the caller's own token when the caller is already the account", async () => {
    const mac = await register();
    await signIn({ identityToken: await identityToken("sub.again") }, mac.token);
    const r = await signIn({ identityToken: await identityToken("sub.again") }, mac.token);
    expect(r.body).toMatchObject({ token: mac.token, code: mac.code, newAccount: false });
  });

  it("folds a second Mac's anonymous user into the account: friends and study days move, the user is deleted", async () => {
    const mac1 = await register();
    await signIn({ identityToken: await identityToken("sub.fold") }, mac1.token);
    const mac2 = await register();
    const friend = await register({ name: "Bea" });
    await call("POST", "/v1/friends", { code: friend.code }, mac2.token);
    await call("POST", "/v1/friends", { code: mac1.code }, mac2.token); // a friendship with itself-to-be is dropped
    await call("POST", "/v1/presence", { status: "studying", todayMinutes: 30 }, mac2.token);

    const r = await signIn({ identityToken: await identityToken("sub.fold") }, mac2.token);
    expect(r.body.code).toBe(mac1.code);
    expectError(await call("GET", "/v1/me", undefined, mac2.token), 401, "unauthorized");
    const friends = (await call("GET", "/v1/friends", undefined, r.body.token)).body.friends.map((f: any) => f.profile.code);
    expect(friends).toEqual([friend.code]);
    const theirs = (await call("GET", "/v1/friends", undefined, friend.token)).body.friends.map((f: any) => f.profile.code);
    expect(theirs).toEqual([mac1.code]);
    const board = (await call("GET", "/v1/leaderboard", undefined, r.body.token)).body.entries;
    expect(board.find((e: any) => e.me).minutes).toBe(30);
  });

  it("does not fold or relink a caller that already belongs to another Apple ID", async () => {
    const mac = await register();
    await signIn({ identityToken: await identityToken("sub.first") }, mac.token);
    const r = await signIn({ identityToken: await identityToken("sub.second") }, mac.token);
    expect(r.body.newAccount).toBe(true);
    expect(r.body.code).not.toBe(mac.code);
    expect(r.body.token).not.toBe(mac.token);
    expect((await storedAccounts(mac.code)).map((a) => a.apple_sub)).toEqual(["sub.first"]);
  });

  it("exchanges the authorization code with a signed client secret and stores only the refresh token", async () => {
    const r = await signIn({ identityToken: await identityToken("sub.exchange"), authorizationCode: "c0de" });
    expect(r.status).toBe(200);
    const exchange = appleCalls.find((c) => c.url === APPLE_TOKEN_URL)!;
    expect(exchange.form!.get("code")).toBe("c0de");
    expect(exchange.form!.get("grant_type")).toBe("authorization_code");
    expect(exchange.form!.get("client_id")).toBe(APPLE_CLIENT_ID);
    const secret = exchange.form!.get("client_secret")!;
    expect(claimsOf(secret)).toMatchObject({ iss: "TESTTEAM01", aud: APPLE_ISSUER, sub: APPLE_CLIENT_ID });
    expect(JSON.parse(atob(secret.split(".")[0]))).toEqual({ alg: "ES256", kid: "TESTKEY001" });
    expect(await storedAccounts(r.body.code)).toEqual([{ apple_sub: "sub.exchange", refresh_token: "apple-refresh-1" }]);
  });

  it("still signs in when Apple refuses the authorization code", async () => {
    tokenReply = { status: 400, body: { error: "invalid_grant" } };
    const r = await signIn({ identityToken: await identityToken("sub.badcode"), authorizationCode: "used" });
    expect(r.status).toBe(200);
    expect(await storedAccounts(r.body.code)).toEqual([{ apple_sub: "sub.badcode", refresh_token: null }]);
  });

  it("rejects tokens that are not Apple's or not for Tabbi", async () => {
    const cases = [
      await identityToken("s", { iss: "https://evil.example" }),
      await identityToken("s", { aud: "com.other.app" }),
      await identityToken("s", { exp: now() - 120 }),
      await identityToken("s", { iat: now() + 3600 }),
      await identityToken("s", { sub: "" }),
      await identityToken("s", {}, { key: otherKey.privateKey }),
      await identityToken("s", {}, { kid: "unknown-key" }),
      await identityToken("s", {}, { alg: "none" }),
      "not.a.jwt",
      "garbage",
    ];
    for (const t of cases) expectError(await signIn({ identityToken: t }), 401, "invalid_identity_token");
  });

  it("accepts an audience list that contains Tabbi", async () => {
    const r = await signIn({ identityToken: await identityToken("sub.audlist", { aud: ["x", APPLE_CLIENT_ID] }) });
    expect(r.status).toBe(200);
  });

  it("validates the body and the caller's token", async () => {
    expectError(await signIn({}), 400, "invalid_field");
    expectError(await signIn({ identityToken: 5 }), 400, "invalid_field");
    expectError(await signIn({ identityToken: "a.b.c", authorizationCode: 7 }), 400, "invalid_field");
    expectError(await signIn({ identityToken: "a.b.c", email: "x@y.z" }), 400, "unknown_field");
  });

  it("signs in as a new caller when the Bearer token no longer resolves", async () => {
    const stale = "f".repeat(64);
    const r = await signIn({ identityToken: await identityToken("sub.badbearer") }, stale);
    expect(r.status).toBe(200);
    expect(r.body.newAccount).toBe(true);
    expect(r.body.token).not.toBe(stale);
    expect((await call("GET", "/v1/me", undefined, r.body.token)).body.profile.code).toBe(r.body.code);
  });

  it("creates a user of its own when the caller is deleted while Apple is asked", async () => {
    const anon = await register();
    const fetchApple = globalThis.fetch;
    vi.mocked(globalThis.fetch).mockImplementationOnce(async (input, init) => {
      // Another request deletes the caller while the sign-in waits for Apple's keys.
      expect((await call("DELETE", "/v1/me", undefined, anon.token)).status).toBe(200);
      return fetchApple(input, init);
    });
    const r = await signIn({ identityToken: await identityToken("sub.deleted.caller") }, anon.token);
    expect(r.status).toBe(200);
    expect(r.body.newAccount).toBe(true);
    expect(r.body.code).not.toBe(anon.code);
    expect((await call("GET", "/v1/me", undefined, r.body.token)).body.profile.code).toBe(r.body.code);
    const again = await signIn({ identityToken: await identityToken("sub.deleted.caller") });
    expect(again.body).toMatchObject({ code: r.body.code, newAccount: false });
  });

  it("is 503 when Apple's keys cannot be fetched", async () => {
    keysUp = false;
    expectError(await signIn({ identityToken: await identityToken("sub.down") }), 503, "apple_unavailable");
  });

  it("caches Apple's keys between sign-ins", async () => {
    await signIn({ identityToken: await identityToken("sub.cache.1") });
    await signIn({ identityToken: await identityToken("sub.cache.2") });
    expect(appleCalls.filter((c) => c.url === APPLE_KEYS_URL)).toHaveLength(1);
  });

  it("is rate limited per IP", async () => {
    const ip = freshIp();
    for (let i = 0; i < APPLE_AUTH_PER_MIN; i++) await signIn({ identityToken: "x.y.z" }, undefined, ip);
    const r = await signIn({ identityToken: "x.y.z" }, undefined, ip);
    expectError(r, 429, "rate_limited");
    expect(r.headers.get("Retry-After")).toMatch(/^\d+$/);
  });
});

describe("DELETE /v1/me with an Apple account", () => {
  it("deletes the account everywhere, revokes the Apple token and stops every Mac's token", async () => {
    const mac1 = await register();
    await signIn({ identityToken: await identityToken("sub.delete"), authorizationCode: "c" }, mac1.token);
    const mac2 = (await signIn({ identityToken: await identityToken("sub.delete") })).body;
    const friend = await register();
    await call("POST", "/v1/friends", { code: friend.code }, mac1.token);
    await call("POST", "/v1/party", {}, mac1.token);

    const r = await call("DELETE", "/v1/me", undefined, mac2.token);
    expect(r.body).toEqual({ ok: true, appleRevoked: true });
    const revoke = appleCalls.find((c) => c.url === APPLE_REVOKE_URL)!;
    expect(revoke.form!.get("token")).toBe("apple-refresh-1");
    expect(revoke.form!.get("token_type_hint")).toBe("refresh_token");
    expectError(await call("GET", "/v1/me", undefined, mac1.token), 401, "unauthorized");
    expectError(await call("GET", "/v1/me", undefined, mac2.token), 401, "unauthorized");
    expect((await call("GET", "/v1/friends", undefined, friend.token)).body.friends).toEqual([]);
    expect(await storedAccounts(mac1.code)).toEqual([]);

    // The Apple ID can sign up again from scratch.
    const again = await signIn({ identityToken: await identityToken("sub.delete") });
    expect(again.body.newAccount).toBe(true);
    expect(again.body.code).not.toBe(mac1.code);
  });

  it("skips the revoke without a stored refresh token", async () => {
    const r = await signIn({ identityToken: await identityToken("sub.delete.norefresh") });
    expect((await call("DELETE", "/v1/me", undefined, r.body.token)).body).toEqual({ ok: true, appleRevoked: false });
    expect(appleCalls.some((c) => c.url === APPLE_REVOKE_URL)).toBe(false);
  });
});

describe("POST /v1/auth/signout", () => {
  it("stops a second Mac's token and leaves the account and the first Mac working", async () => {
    const mac1 = await register();
    await signIn({ identityToken: await identityToken("sub.signout.2") }, mac1.token);
    const mac2 = (await signIn({ identityToken: await identityToken("sub.signout.2") })).body;

    expect((await call("POST", "/v1/auth/signout", undefined, mac2.token)).body).toEqual({ ok: true });
    expectError(await call("GET", "/v1/me", undefined, mac2.token), 401, "unauthorized");
    expect((await call("GET", "/v1/sync", undefined, mac1.token)).status).toBe(200);
    expect(appleCalls.some((c) => c.url === APPLE_REVOKE_URL)).toBe(false);
  });

  it("stops the first Mac's token, and signing in again on that Mac adopts the same account", async () => {
    const mac1 = await register();
    await signIn({ identityToken: await identityToken("sub.signout.1") }, mac1.token);
    const mac2 = (await signIn({ identityToken: await identityToken("sub.signout.1") })).body;

    expect((await call("POST", "/v1/auth/signout", undefined, mac1.token)).status).toBe(200);
    expectError(await call("GET", "/v1/me", undefined, mac1.token), 401, "unauthorized");
    expect((await call("GET", "/v1/me", undefined, mac2.token)).body.profile.code).toBe(mac1.code);

    const again = await signIn({ identityToken: await identityToken("sub.signout.1") });
    expect(again.body).toMatchObject({ code: mac1.code, newAccount: false });
    expect((await call("GET", "/v1/me", undefined, again.body.token)).status).toBe(200);
  });

  it("refuses an anonymous user, whose token is its only one", async () => {
    const anon = await register();
    expectError(await call("POST", "/v1/auth/signout", undefined, anon.token), 403, "no_account");
    expect((await call("GET", "/v1/me", undefined, anon.token)).status).toBe(200);
    expectError(await call("POST", "/v1/auth/signout"), 401, "unauthorized");
  });
});

// ---------- the helpers on their own ----------

describe("apple helpers", () => {
  it("skip the exchange and revoke when any secret is unset", async () => {
    expect(appleSecrets({})).toBeNull();
    expect(appleSecrets({ APPLE_TEAM_ID: "T", APPLE_KEY_ID: "K" })).toBeNull();
    expect(appleSecrets(env)).not.toBeNull();
    expect(await exchangeAuthorizationCode("c", { APPLE_TEAM_ID: "T" }, now())).toBeNull();
    expect(await revokeRefreshToken("r", {}, now())).toBe(false);
    expect(appleCalls).toEqual([]);
  });

  it("ask Apple for keys at most once a minute while Apple is down", async () => {
    keysUp = false;
    const t = now();
    const token = await identityToken("sub.outage");
    for (const at of [t, t + 1, t + 59]) {
      await expect(verifyIdentityToken(token, at)).rejects.toMatchObject({ status: 503, error: "apple_unavailable" });
    }
    expect(appleCalls.filter((c) => c.url === APPLE_KEYS_URL)).toHaveLength(1);
    keysUp = true;
    expect(await verifyIdentityToken(token, t + 60)).toBe("sub.outage");
    expect(appleCalls.filter((c) => c.url === APPLE_KEYS_URL)).toHaveLength(2);
  });

  it("keep trusting expired cached keys while a refetch fails, without asking Apple again", async () => {
    const t = now();
    const token = await identityToken("sub.stale");
    expect(await verifyIdentityToken(token, t)).toBe("sub.stale");
    keysUp = false;
    // An hour later the cache is stale; the failed refetch falls back to the cached key, and so does the next sign-in.
    const later = t + 3600;
    const lateToken = await identityToken("sub.stale", { iat: later, exp: later + 600 });
    expect(await verifyIdentityToken(lateToken, later)).toBe("sub.stale");
    expect(await verifyIdentityToken(lateToken, later + 10)).toBe("sub.stale");
    expect(appleCalls.filter((c) => c.url === APPLE_KEYS_URL)).toHaveLength(2);
  });

  it("verifies a token directly and never needs the email claim", async () => {
    expect(await verifyIdentityToken(await identityToken("sub.direct"), now())).toBe("sub.direct");
  });

  it("accept a private key with escaped newlines", async () => {
    const escaped = { ...appleSecrets(env)!, APPLE_PRIVATE_KEY: env.APPLE_PRIVATE_KEY!.replace(/\n/g, "\\n") };
    expect(await exchangeAuthorizationCode("c", escaped, now())).toBe("apple-refresh-1");
  });
});
