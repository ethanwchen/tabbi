// A fake Apple for tests: its signing keys, identity tokens it would sign, and its keys, token and revoke
// endpoints, served through a `fetch` spy (the Durable Object runs in the test isolate, so its outbound
// fetch is the spy). Call `installFakeApple()` at the top of a test file.
import { afterEach, beforeAll, beforeEach, vi } from "vitest";
import { APPLE_CLIENT_ID, APPLE_ISSUER, APPLE_KEYS_URL, APPLE_REVOKE_URL, APPLE_TOKEN_URL, resetAppleKeyCache } from "../src/apple";

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const encode = (v: unknown) => b64url(new TextEncoder().encode(JSON.stringify(v)));

export interface AppleCall { url: string; form: URLSearchParams | null }

/** The fake's state, reset before each test: the calls it got, its token reply and whether its keys are up. */
export const apple = {
  calls: [] as AppleCall[],
  tokenReply: { status: 200, body: {} as unknown },
  keysUp: true,
  signingKey: undefined as unknown as CryptoKeyPair,
  /** A key Apple does not publish. */
  otherKey: undefined as unknown as CryptoKeyPair,
  publicJwk: undefined as unknown as JsonWebKey,
};

async function rsaKey(): Promise<CryptoKeyPair> {
  return (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true, ["sign", "verify"],
  )) as CryptoKeyPair;
}

export const now = () => Math.floor(Date.now() / 1000);

/**
 * An identity token as Apple would sign it; `claims` and `header` override the defaults. Each one is
 * unique, as Apple's are (they carry per-sign-in claims such as `c_hash` and `auth_time`).
 */
export async function identityToken(sub: string, claims: Record<string, unknown> = {}, opts: { kid?: string; key?: CryptoKey; alg?: string } = {}) {
  const header = encode({ alg: opts.alg ?? "RS256", kid: opts.kid ?? "apple-key-1" });
  const payload = encode({
    iss: APPLE_ISSUER, aud: APPLE_CLIENT_ID, exp: now() + 600, iat: now(), sub, email: "never-read@example.com",
    c_hash: crypto.randomUUID(), ...claims,
  });
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", opts.key ?? apple.signingKey.privateKey, new TextEncoder().encode(`${header}.${payload}`));
  return `${header}.${payload}.${b64url(new Uint8Array(sig))}`;
}

/** Reads the claims of a JWT without verifying it. */
export function claimsOf(jwt: string) {
  const part = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(part + "=".repeat((4 - (part.length % 4)) % 4)));
}

export function installFakeApple(): void {
  beforeAll(async () => {
    apple.signingKey = await rsaKey();
    apple.otherKey = await rsaKey();
    apple.publicJwk = (await crypto.subtle.exportKey("jwk", apple.signingKey.publicKey)) as JsonWebKey;
  });

  beforeEach(() => {
    resetAppleKeyCache();
    apple.calls = [];
    apple.keysUp = true;
    apple.tokenReply = { status: 200, body: { access_token: "a", refresh_token: "apple-refresh-1", id_token: "x" } };
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      const url = input instanceof Request ? input.url : String(input);
      const form = typeof init?.body === "string" ? new URLSearchParams(init.body) : null;
      apple.calls.push({ url, form });
      if (url === APPLE_KEYS_URL) {
        return apple.keysUp
          ? Response.json({ keys: [{ ...apple.publicJwk, kid: "apple-key-1", alg: "RS256", use: "sig" }] })
          : new Response("down", { status: 503 });
      }
      if (url === APPLE_TOKEN_URL) return Response.json(apple.tokenReply.body, { status: apple.tokenReply.status });
      if (url === APPLE_REVOKE_URL) return new Response(null, { status: 200 });
      throw new Error(`unexpected fetch ${url}`);
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });
}
