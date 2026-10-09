// Sign in with Apple: identity token verification, and the authorization code exchange and revoke.
//
// The app sends the identity token (a JWT that Apple signs with RS256) and the one-time authorization
// code it got from AuthenticationServices. The token proves who the user is: its signature is checked
// against Apple's published keys (cached), and its issuer, audience and expiry against this app, and
// the Hub accepts each token once (see `VerifiedIdentity.reusableUntil`), so a copied token cannot open
// a second session. The code is exchanged for a refresh token only so the account's Apple tokens can be revoked when the user
// deletes their account, as Apple requires. That needs a client secret, a short JWT signed with the Sign
// in with Apple key (ES256) from the Worker secrets; without them the exchange and revoke are skipped.
import { HttpError, Obj } from "./lib";

export const APPLE_ISSUER = "https://appleid.apple.com";
/** The app's bundle id, which Apple puts in the token's `aud` and expects as `client_id`. */
export const APPLE_CLIENT_ID = "dev.tabbi.Tabbi";
export const APPLE_KEYS_URL = `${APPLE_ISSUER}/auth/keys`;
export const APPLE_TOKEN_URL = `${APPLE_ISSUER}/auth/token`;
export const APPLE_REVOKE_URL = `${APPLE_ISSUER}/auth/revoke`;

/** Sign-in attempts per minute per client IP. A sign-in is rare; this stops token guessing. */
export const APPLE_AUTH_PER_MIN = 10;
export const APPLE_AUTH_FIELDS = ["identityToken", "authorizationCode"] as const;

/** Apple's keys rotate rarely; an unknown key id or a failed fetch refetches them, at most once a minute. */
const KEYS_TTL_S = 3600;
const KEYS_REFETCH_S = 60;
/** Allowed clock difference between Apple and the Worker when checking `exp` and `iat`. */
const CLOCK_SKEW_S = 60;
/** Apple accepts client secrets valid for up to six months; each one here lives five minutes. */
const CLIENT_SECRET_TTL_S = 300;

/** The Worker secrets that sign client secrets. All three are needed; any missing disables exchange and revoke. */
export interface AppleSecrets {
  APPLE_TEAM_ID?: string;
  APPLE_KEY_ID?: string;
  APPLE_PRIVATE_KEY?: string;
}

export interface AppleAuthRequest {
  identityToken: string;
  authorizationCode: string | null;
}

/** Reads a POST /v1/auth/apple body: `{ identityToken, authorizationCode? }`. */
export function parseAppleAuth(body: Obj): AppleAuthRequest {
  const { identityToken, authorizationCode } = body;
  if (typeof identityToken !== "string" || identityToken.length === 0 || identityToken.length > 3000) {
    throw new HttpError(400, "invalid_field", "invalid identityToken");
  }
  if (authorizationCode !== undefined && authorizationCode !== null
    && (typeof authorizationCode !== "string" || authorizationCode.length === 0 || authorizationCode.length > 512)) {
    throw new HttpError(400, "invalid_field", "invalid authorizationCode");
  }
  return { identityToken, authorizationCode: typeof authorizationCode === "string" ? authorizationCode : null };
}

// ---------- base64url ----------

function base64UrlDecode(s: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]*$/.test(s)) throw new Error("not base64url");
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (s.length % 4)) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

function base64UrlEncode(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const encodeJSON = (v: unknown) => base64UrlEncode(new TextEncoder().encode(JSON.stringify(v)));

// ---------- Apple's public keys ----------

interface KeyCache {
  keys: Map<string, CryptoKey>;
  fetchedAt: number;
}

let keyCache: KeyCache | null = null;
let lastFetchAttempt = -Infinity;

/** Forgets the cached keys, so tests can serve different ones. */
export function resetAppleKeyCache(): void {
  keyCache = null;
  lastFetchAttempt = -Infinity;
}

async function fetchAppleKeys(now: number): Promise<KeyCache> {
  lastFetchAttempt = now;
  let res: Response;
  try {
    res = await fetch(APPLE_KEYS_URL);
  } catch (e) {
    console.error("apple: could not fetch keys", e);
    throw new HttpError(503, "apple_unavailable", "could not reach Apple, retry");
  }
  if (!res.ok) {
    console.error(`apple: keys request failed with ${res.status}`);
    throw new HttpError(503, "apple_unavailable", "could not reach Apple, retry");
  }
  const body = (await res.json().catch(() => null)) as { keys?: unknown } | null;
  const keys = new Map<string, CryptoKey>();
  for (const jwk of Array.isArray(body?.keys) ? body.keys : []) {
    const k = jwk as { kid?: unknown; kty?: unknown; n?: unknown; e?: unknown };
    if (typeof k.kid !== "string" || k.kty !== "RSA" || typeof k.n !== "string" || typeof k.e !== "string") continue;
    try {
      keys.set(k.kid, await crypto.subtle.importKey(
        "jwk", { kty: "RSA", n: k.n, e: k.e, alg: "RS256", ext: true },
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"],
      ));
    } catch (e) {
      console.error(`apple: skipping key ${k.kid}`, e);
    }
  }
  return { keys, fetchedAt: now };
}

/** The key with this id, from the cache when it is fresh, or `null` if Apple has no such key. */
async function appleKey(kid: string, now: number): Promise<CryptoKey | null> {
  const fresh = keyCache !== null && now - keyCache.fetchedAt < KEYS_TTL_S;
  const cached = keyCache?.keys.get(kid);
  if (fresh && cached) return cached;
  // An unknown key id refetches (Apple may have rotated), and a failed fetch is retried, but neither more
  // than once a minute, so sign-ins while Apple is down do not turn into a stream of requests to Apple.
  if (now - lastFetchAttempt < KEYS_REFETCH_S) {
    if (fresh) return null;
    if (cached) return cached;
    throw new HttpError(503, "apple_unavailable", "could not reach Apple, retry");
  }
  try {
    keyCache = await fetchAppleKeys(now);
  } catch (e) {
    // Apple being briefly unreachable should not stop sign-in with a key we already trust.
    if (cached) return cached;
    throw e;
  }
  return keyCache.keys.get(kid) ?? null;
}

// ---------- identity token ----------

export const invalidToken = (why: string) => new HttpError(401, "invalid_identity_token", `invalid identity token: ${why}`);

/** What a verified identity token says. */
export interface VerifiedIdentity {
  /** Apple's stable user id. */
  sub: string;
  /**
   * The last second (Unix) at which the token would still verify. Until then the Hub keeps the token's
   * hash, so the same token is refused if it is sent again (a replay); after it, the token is expired.
   */
  reusableUntil: number;
}

/**
 * Verifies an identity token from Sign in with Apple and returns Apple's stable user id (`sub`) and how
 * long the token stays valid. Checks the RS256 signature against Apple's keys, then `iss`, `aud` (this
 * app), `exp` and `iat`. It is stateless; refusing a token that was already used is up to the caller.
 * The token's email claims, if any, are never read.
 */
export async function verifyIdentityToken(token: string, now: number): Promise<VerifiedIdentity> {
  const parts = token.split(".");
  if (parts.length !== 3) throw invalidToken("not a JWT");
  let header: { alg?: unknown; kid?: unknown };
  let claims: { iss?: unknown; aud?: unknown; exp?: unknown; iat?: unknown; sub?: unknown };
  let signature: Uint8Array;
  try {
    header = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[0])));
    claims = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[1])));
    signature = base64UrlDecode(parts[2]);
  } catch {
    throw invalidToken("malformed");
  }
  if (header.alg !== "RS256" || typeof header.kid !== "string") throw invalidToken("unexpected algorithm");
  const key = await appleKey(header.kid, now);
  if (!key) throw invalidToken("unknown signing key");
  const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  if (!(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, signed))) throw invalidToken("bad signature");

  if (claims.iss !== APPLE_ISSUER) throw invalidToken("wrong issuer");
  const aud = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!aud.includes(APPLE_CLIENT_ID)) throw invalidToken("wrong audience");
  if (typeof claims.exp !== "number" || claims.exp + CLOCK_SKEW_S <= now) throw invalidToken("expired");
  if (typeof claims.iat === "number" && claims.iat - CLOCK_SKEW_S > now) throw invalidToken("issued in the future");
  if (typeof claims.sub !== "string" || claims.sub.length === 0 || claims.sub.length > 255) throw invalidToken("no subject");
  return { sub: claims.sub, reusableUntil: claims.exp + CLOCK_SKEW_S };
}

// ---------- client secret, code exchange and revoke ----------

/** The three secrets, or `null` when any is unset (then exchange and revoke are skipped). */
export function appleSecrets(env: AppleSecrets): Required<AppleSecrets> | null {
  const { APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY } = env;
  if (!APPLE_TEAM_ID || !APPLE_KEY_ID || !APPLE_PRIVATE_KEY) return null;
  return { APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY };
}

/** Reads the `.p8` key Apple hands out (PKCS#8 PEM). Escaped `\n` sequences are accepted too. */
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/\\n/g, "\n").replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

/** The `client_secret` Apple's token and revoke endpoints expect: an ES256 JWT from the team's key. */
export async function clientSecret(secrets: Required<AppleSecrets>, now: number): Promise<string> {
  const header = encodeJSON({ alg: "ES256", kid: secrets.APPLE_KEY_ID });
  const claims = encodeJSON({
    iss: secrets.APPLE_TEAM_ID, iat: now, exp: now + CLIENT_SECRET_TTL_S, aud: APPLE_ISSUER, sub: APPLE_CLIENT_ID,
  });
  const key = await importPrivateKey(secrets.APPLE_PRIVATE_KEY);
  // WebCrypto returns the raw r || s signature, which is the form JWS uses.
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key,
    new TextEncoder().encode(`${header}.${claims}`));
  return `${header}.${claims}.${base64UrlEncode(new Uint8Array(sig))}`;
}

async function postForm(url: string, form: Record<string, string>): Promise<Response> {
  return fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form).toString(),
  });
}

/**
 * Exchanges an authorization code for a refresh token, kept only to revoke it on account deletion.
 * Returns `null` (and logs why) when the secrets are unset or Apple refuses; sign-in goes on either way.
 */
export async function exchangeAuthorizationCode(code: string, env: AppleSecrets, now: number): Promise<string | null> {
  const secrets = appleSecrets(env);
  if (!secrets) {
    console.log("apple: secrets unset, skipping the authorization code exchange");
    return null;
  }
  try {
    const res = await postForm(APPLE_TOKEN_URL, {
      client_id: APPLE_CLIENT_ID, client_secret: await clientSecret(secrets, now), code, grant_type: "authorization_code",
    });
    const body = (await res.json().catch(() => null)) as { refresh_token?: unknown; error?: unknown } | null;
    if (!res.ok || typeof body?.refresh_token !== "string") {
      console.error(`apple: code exchange failed with ${res.status} ${String(body?.error ?? "")}`);
      return null;
    }
    return body.refresh_token;
  } catch (e) {
    console.error("apple: code exchange failed", e);
    return null;
  }
}

/** Revokes a refresh token (and with it the user's grant to the app). Returns whether Apple accepted it. */
export async function revokeRefreshToken(token: string, env: AppleSecrets, now: number): Promise<boolean> {
  const secrets = appleSecrets(env);
  if (!secrets) {
    console.log("apple: secrets unset, skipping the token revoke");
    return false;
  }
  try {
    const res = await postForm(APPLE_REVOKE_URL, {
      client_id: APPLE_CLIENT_ID, client_secret: await clientSecret(secrets, now), token, token_type_hint: "refresh_token",
    });
    if (!res.ok) console.error(`apple: revoke failed with ${res.status}`);
    return res.ok;
  } catch (e) {
    console.error("apple: revoke failed", e);
    return false;
  }
}
