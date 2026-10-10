// Sign in with Apple on the web, for builds that cannot use AuthenticationServices' native sign-in (the
// Developer ID build, whose provisioning profile lacks the entitlement, and later Windows).
//
// 1. The app makes a random `state`, keeps it, and opens Apple's authorize page with that state, the
//    nonce `webNonce(state)`, the Services ID as client_id and WEB_CALLBACK_PATH on this Worker as
//    redirect_uri (response_mode form_post).
// 2. Apple posts `state`, `code` and `id_token` to the callback. The Worker verifies the identity token
//    (audience: the Services ID; nonce: the state's), exchanges the code for a refresh token (kept only to
//    revoke on deletion) and stores a pending sign-in under a fresh one-time code, bound to the state's
//    hash. It then sends the browser to `tabbi://auth/apple?code=...` (APP_CALLBACK_URL).
// 3. The app posts `{ code, state }` to WEB_TOKEN_PATH, with its anonymous friends token as Bearer if it
//    has one, and gets the same reply as POST /v1/auth/apple. A code works once, for WEB_CODE_TTL_S, and
//    only with the state it was made for, so a code that leaks from the tabbi:// link is useless alone.
import { APPLE_CLIENT_ID, base64UrlEncode } from "./apple";
import { HttpError, Obj, TOKEN_RE } from "./lib";

export const WEB_CALLBACK_PATH = "/v1/auth/apple/web/callback";
export const WEB_TOKEN_PATH = "/v1/auth/apple/web/token";
/** Where the callback sends the browser; the app (or ASWebAuthenticationSession) catches this scheme. */
export const APP_CALLBACK_URL = "tabbi://auth/apple";
/** How long a one-time code from the callback can be exchanged. */
export const WEB_CODE_TTL_S = 120;
/** Apple's form_post is a few kilobytes (the identity token, and the user's name on the first sign-in). */
export const MAX_CALLBACK_BYTES = 16_384;
export const WEB_TOKEN_FIELDS = ["code", "state"] as const;

/** A state is at least 32 characters of base64url (the app sends 32 random bytes, 43 characters). */
const STATE_RE = /^[A-Za-z0-9_-]{32,128}$/;

/** The Worker variables of the web flow. */
export interface WebAuthVars {
  /** The Services ID registered for web sign-in (dev.tabbi.Tabbi.signin); unset turns the web flow off. */
  APPLE_SERVICES_ID?: string;
}

/** The Services ID, or a 503 when the variable is unset. */
export function servicesId(env: WebAuthVars): string {
  const id = env.APPLE_SERVICES_ID?.trim();
  if (!id) throw new HttpError(503, "not_configured", "web sign-in is not configured");
  if (id === APPLE_CLIENT_ID) throw new HttpError(503, "not_configured", "APPLE_SERVICES_ID must be a Services ID, not the app id");
  return id;
}

/**
 * The nonce the app sends to Apple for a state: base64url(SHA-256(state)). Deriving it from the state lets
 * the Worker check the identity token's nonce with nothing stored before the callback, and the hash keeps
 * the state (which the token exchange needs) out of the token.
 */
export async function webNonce(state: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(state));
  return base64UrlEncode(new Uint8Array(digest));
}

/** What Apple posts to the callback: a sign-in, or an error such as the user cancelling. */
export type WebCallback =
  | { kind: "signIn"; state: string; code: string; idToken: string }
  | { kind: "error"; error: string };

/**
 * Reads Apple's form_post. Unknown fields (such as `user`, the name Apple sends on the first sign-in, which
 * is never stored) are ignored: the form is Apple's, and refusing a field Apple adds would break sign-in.
 */
export function parseWebCallback(raw: string): WebCallback {
  const form = new URLSearchParams(raw);
  const one = (name: string): string | null => {
    const values = form.getAll(name);
    if (values.length > 1) throw new HttpError(400, "invalid_field", `repeated field: ${name}`);
    return values[0] ?? null;
  };
  const error = one("error");
  if (error !== null) return { kind: "error", error: error === "user_cancelled_authorize" ? "cancelled" : "apple_error" };
  const state = one("state");
  const code = one("code");
  const idToken = one("id_token");
  if (state === null || !STATE_RE.test(state)) throw new HttpError(400, "invalid_state", "invalid state");
  if (code === null || code.length === 0 || code.length > 512) throw new HttpError(400, "invalid_field", "invalid code");
  if (idToken === null || idToken.length === 0 || idToken.length > 3000) throw new HttpError(400, "invalid_field", "invalid id_token");
  return { kind: "signIn", state, code, idToken };
}

/** Reads a POST /v1/auth/apple/web/token body: `{ code, state }`. */
export function parseWebToken(body: Obj): { code: string; state: string } {
  const { code, state } = body;
  if (typeof code !== "string" || !TOKEN_RE.test(code)) throw new HttpError(400, "invalid_field", "invalid code");
  if (typeof state !== "string" || !STATE_RE.test(state)) throw new HttpError(400, "invalid_field", "invalid state");
  return { code, state };
}

/** The tabbi:// link the callback answers with: `code` on success, `error` (a short reason) otherwise. */
export function appRedirect(params: { code: string } | { error: string }): Response {
  const url = `${APP_CALLBACK_URL}?${new URLSearchParams(params).toString()}`;
  return new Response(null, { status: 303, headers: { Location: url, "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" } });
}
