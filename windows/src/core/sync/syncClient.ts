import { byteLength, decodeReply, encodeSorted, sendThrough } from "../party/partyClient";
import type { PartyCredentials } from "../party/partyCredentialStore";
import { PartyError } from "../party/partyError";
import { read, readProfile, type PartyProfile } from "../party/partyModels";
import type { PartyHttpRequest, PartyHttpResponse, PartyTransport } from "../party/partyTransport";
import { MAX_SYNC_BYTES, WEB_TOKEN_PATH, type WebTokenBody } from "../party/partyWire";
import type { Instant, Seconds } from "../time";
import { SyncDocument } from "./syncDocument";

/*
 * Port of SyncClient, AppleSignInReply and SyncPull: the calls Sign in with
 * Apple adds to the friends API (docs/study/backend-api.md). Errors are
 * `PartyError`s like every other friends-server call; the sync ones are
 * named by `isRevisionConflict`, `isNoSyncAccount`, `isExpiredWebSignIn`
 * and `isRejectedAppleSignIn`.
 */

/** Body fields of `POST /v1/auth/apple` (backend `APPLE_AUTH_FIELDS`). */
export const APPLE_AUTH_BODY_FIELDS = ["identityToken", "authorizationCode"] as const;
export interface AppleAuthBody {
  identityToken: string;
  authorizationCode?: string;
}

/** What sign-in hands back: the identity this device uses from now on, and whether the Apple ID was new. */
export interface AppleSignInReply {
  readonly credentials: PartyCredentials;
  readonly profile: PartyProfile;
  /** False when the Apple ID already had an account, so this device adopted its friend code. */
  readonly newAccount: boolean;
}

/** The account's sync document as the server holds it. */
export interface SyncPull {
  /** 0 before any device pushed. */
  readonly revision: number;
  readonly updatedAt: Instant | undefined;
  /** Undefined before any device pushed. */
  readonly document: SyncDocument | undefined;
}

/** The `PUT /v1/sync` body: `{"document": ...}` with the document exactly as `SyncDocument.encoded` writes it. */
export function syncPushBody(document: SyncDocument): string {
  return `{"document":${document.encoded()}}`;
}

export class SyncClient {
  readonly transport: PartyTransport;
  /** The friends token: optional for sign-in (it links this device's Party user), required for the sync routes. */
  readonly token: string | undefined;
  readonly timeout: Seconds;

  constructor(transport: PartyTransport, token?: string, timeout: Seconds = 10) {
    this.transport = transport;
    this.token = token;
    this.timeout = timeout;
  }

  /** `POST /v1/auth/apple` with the native sign-in's tokens. Store the reply's credentials in place of the old ones. */
  async signInWithApple(identityToken: string, authorizationCode?: string): Promise<AppleSignInReply> {
    const body: AppleAuthBody = { identityToken, ...(authorizationCode === undefined ? {} : { authorizationCode }) };
    return this.signIn({ method: "POST", path: "/v1/auth/apple", body: encodeSorted(body), ...this.optionalToken() });
  }

  /**
   * `POST /v1/auth/apple/web/token`: trades the one-time code from the web
   * flow's `tabbi://auth/apple` link, with the state of the attempt that
   * made it, for the same reply as the native sign-in. `isExpiredWebSignIn`
   * is true when the code was used, expired or made for another state.
   */
  async exchangeWebSignIn(code: string, state: string): Promise<AppleSignInReply> {
    const body: WebTokenBody = { code, state };
    return this.signIn({ method: "POST", path: WEB_TOKEN_PATH, body: encodeSorted(body), ...this.optionalToken() });
  }

  /** `GET /v1/sync`. */
  async pull(): Promise<SyncPull> {
    const reply = decodeReply(await this.send(this.authorized({ method: "GET", path: "/v1/sync" })));
    const raw = reply.document;
    let document: SyncDocument | undefined;
    if (typeof raw === "object" && raw !== null && !Array.isArray(raw)) {
      try {
        document = SyncDocument.decode(JSON.stringify(raw));
      } catch {
        throw PartyError.invalidResponse("unreadable sync document");
      }
    }
    return { revision: read.integer(reply, "revision"), updatedAt: read.optional(reply, "updatedAt", read.number), document };
  }

  /**
   * `PUT /v1/sync` with `If-Match: "<revision>"`, the revision `document`
   * was merged into. Returns the new revision. `isRevisionConflict` is true
   * when another device pushed first: pull, merge and push again.
   */
  async push(document: SyncDocument, ifMatch: number): Promise<number> {
    const body = syncPushBody(document);
    if (byteLength(body) > MAX_SYNC_BYTES) throw PartyError.invalidRequest("body_too_large");
    const request = this.authorized({ method: "PUT", path: "/v1/sync", body, headers: { "If-Match": `"${ifMatch}"` } });
    return read.integer(decodeReply(await this.send(request)), "revision");
  }

  /** `POST /v1/auth/signout`: this device's token stops working; the account and other devices stay signed in. */
  async signOut(): Promise<void> {
    decodeReply(await this.send(this.authorized({ method: "POST", path: "/v1/auth/signout" })));
  }

  private async signIn(request: PartyHttpRequest): Promise<AppleSignInReply> {
    const reply = decodeReply(await this.send(request));
    return {
      credentials: { token: read.string(reply, "token"), code: read.string(reply, "code") },
      profile: readProfile(reply.profile),
      newAccount: read.boolean(reply, "newAccount"),
    };
  }

  private optionalToken(): { token?: string } {
    return this.token === undefined ? {} : { token: this.token };
  }

  private authorized(request: PartyHttpRequest): PartyHttpRequest {
    if (this.token === undefined) throw PartyError.of("unauthorized");
    return { ...request, token: this.token };
  }

  private send(request: PartyHttpRequest): Promise<PartyHttpResponse> {
    return sendThrough(this.transport, request, this.timeout);
  }
}
