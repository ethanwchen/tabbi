import { PARTY_PRODUCTION_URL } from "../party/partyServer";
import { joinServerPath } from "../party/partyTransport";
import { WEB_CALLBACK_PATH } from "../party/partyWire";
import { tr } from "../localization/tr";

/*
 * Port of AppleWebSignIn: one Sign in with Apple attempt on the web, the
 * flow Windows uses (HANDOFF section 6), with no backend change:
 *
 * 1. `AppleWebSignIn.start()` makes a random `state` (32 bytes, base64url)
 *    kept in memory, and its `nonce`, base64url(SHA-256(state)) through Web
 *    Crypto (`crypto.subtle`, in WebView2 and Node alike).
 * 2. The app opens `authorizeURL` in the system browser. Apple posts to the
 *    Worker's callback, which sends the browser to
 *    `tabbi://auth/apple?code=<64 hex>` (or `?error=<reason>`).
 * 3. `parseAppleCallback` reads that link, and
 *    `SyncClient.exchangeWebSignIn(code, state)` trades the code. The server
 *    takes a code once, for two minutes, and only with its state.
 *
 * The server side is `backend/src/webauth.ts`.
 */

/** Apple's authorize endpoint. */
export const APPLE_AUTHORIZE_ENDPOINT = "https://appleid.apple.com/auth/authorize";
/** The Services ID registered for web sign-in (the Worker's `APPLE_SERVICES_ID`). */
export const APPLE_SERVICES_ID = "dev.tabbi.Tabbi.signin";

/** base64url without padding, as the backend's `base64UrlEncode`. */
export function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

/** base64url(SHA-256(state)): the server derives the same value to check the identity token's nonce. */
export async function webSignInNonce(state: string): Promise<string> {
  const digest = await globalThis.crypto.subtle.digest("SHA-256", new TextEncoder().encode(state));
  return base64URL(new Uint8Array(digest));
}

/** A fresh random state: 32 bytes, base64url (43 characters). */
export function newWebSignInState(): string {
  return base64URL(globalThis.crypto.getRandomValues(new Uint8Array(32)));
}

/** The callback on `server`, registered as the Services ID's return URL. */
export function appleRedirectURI(server: string = PARTY_PRODUCTION_URL): string {
  return joinServerPath(server, WEB_CALLBACK_PATH);
}

/*
 * Query encoding as Foundation's URLComponents does it: a space is %20 (not
 * a plus), and `:` `/` `?` `@` stay as they are.
 */
function encodeQueryValue(value: string): string {
  return encodeURIComponent(value).replace(/%(3A|2F|3F|40)/g, (escape) => decodeURIComponent(escape));
}

export class AppleWebSignIn {
  /** A random value only this device knows; it never leaves the app except to Apple and back. */
  readonly state: string;
  readonly nonce: string;

  private constructor(state: string, nonce: string) {
    this.state = state;
    this.nonce = nonce;
  }

  /** A fresh attempt with a new random state. */
  static start(): Promise<AppleWebSignIn> {
    return AppleWebSignIn.withState(newWebSignInState());
  }

  /** An attempt with a known state (tests, or a state kept elsewhere). */
  static async withState(state: string): Promise<AppleWebSignIn> {
    return new AppleWebSignIn(state, await webSignInNonce(state));
  }

  /** Apple's authorize page for this attempt; `server` is the friends server that receives Apple's form post. */
  authorizeURL(server: string = PARTY_PRODUCTION_URL): string {
    const query: [string, string][] = [
      ["response_type", "code id_token"],
      ["response_mode", "form_post"],
      ["client_id", APPLE_SERVICES_ID],
      ["redirect_uri", appleRedirectURI(server)],
      ["scope", "name"],
      ["state", this.state],
      ["nonce", this.nonce],
    ];
    return `${APPLE_AUTHORIZE_ENDPOINT}?${query.map(([name, value]) => `${name}=${encodeQueryValue(value)}`).join("&")}`;
  }
}

/** Why the callback did not sign in, from its `error` value. */
export type AppleWebSignInFailure =
  /** The user closed Apple's page or chose Cancel. */
  | "cancelled"
  /** Apple or the server was unavailable, or too many attempts came at once: trying again may fix it. */
  | "unavailable"
  /** The server is not set up for web sign-in yet. */
  | "notConfigured"
  /** Apple's answer did not check out (a stale page, a mismatched state, a refused token). */
  | "rejected";

export function webSignInFailure(reason: string): AppleWebSignInFailure {
  switch (reason) {
    case "cancelled":
      return "cancelled";
    case "not_configured":
      return "notConfigured";
    case "invalid_state":
    case "invalid_identity_token":
    case "apple_error":
      return "rejected";
    default:
      return "unavailable";
  }
}

/** A short message for the Account row; undefined when nothing needs saying (the user cancelled). */
export function webSignInFailureMessage(failure: AppleWebSignInFailure): string | undefined {
  switch (failure) {
    case "cancelled":
      return undefined;
    case "unavailable":
      return tr("Sign in with Apple is not available right now. Try again in a moment.");
    case "notConfigured":
      return tr("Sign in with Apple is not set up on the server yet.");
    case "rejected":
      return tr("Apple could not confirm the sign-in. Try again.");
  }
}

/** What the server's callback sent back through `tabbi://auth/apple`. */
export type AppleWebSignInCallback = { readonly kind: "code"; readonly code: string } | { readonly kind: "failure"; readonly failure: AppleWebSignInFailure };

const CODE_PATTERN = /^[0-9a-f]{64}$/;

/**
 * The callback in `url`, or undefined unless it is `tabbi://auth/apple` with
 * a well-formed `code` (64 lowercase hex characters, since the link can come
 * from anywhere) or an `error`.
 */
export function parseAppleCallback(url: string): AppleWebSignInCallback | undefined {
  const match = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/([^/?#]*)([^?#]*)(?:\?([^#]*))?/.exec(url.trim());
  if (match === null) return undefined;
  if ((match[1] ?? "").toLowerCase() !== "tabbi" || (match[2] ?? "").toLowerCase() !== "auth") return undefined;
  const path = (match[3] ?? "").split("/").filter((segment) => segment.length > 0);
  if (path.length !== 1 || path[0] !== "apple") return undefined;
  const params = new URLSearchParams(match[4] ?? "");
  const value = (name: string): string | undefined => {
    const values = params.getAll(name);
    return values.length === 1 ? values[0] : undefined;
  };
  const code = value("code");
  if (code !== undefined) return CODE_PATTERN.test(code) ? { kind: "code", code } : undefined;
  const error = value("error");
  return error === undefined ? undefined : { kind: "failure", failure: webSignInFailure(error) };
}
