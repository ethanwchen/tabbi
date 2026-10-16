import { tr } from "../localization/tr";
import type { Seconds } from "../time";

/*
 * Port of PartyError: every way a friends-server call can fail, classified
 * by the server's stable `error` code (never its English `message`), so the
 * UI explains it in one line and the scheduler knows whether and when to
 * retry.
 */

/** The failure kinds that carry nothing but their name. */
export type PartyErrorKind =
  | "unreachable"
  | "timedOut"
  | "unauthorized"
  | "rateLimited"
  | "serverUnavailable"
  | "invalidRequest"
  | "selfFriend"
  | "unknownCode"
  | "friendLimit"
  | "theirFriendLimit"
  | "noRequest"
  | "pendingLimit"
  | "requestLimit"
  | "partyNotFound"
  | "notFriend"
  | "friendOffline"
  | "friendNotInParty"
  | "partyFull"
  | "notInParty"
  | "notHost"
  | "nameNotAllowed"
  | "petNameNotAllowed"
  | "selfBlock"
  | "blockLimit"
  | "blocked"
  | "selfReport"
  | "reportLimit"
  | "banned"
  | "server"
  | "invalidResponse"
  | "transport";

/* Server codes that map one to one onto a kind. */
const SERVER_CODES: Readonly<Record<string, PartyErrorKind>> = {
  unauthorized: "unauthorized",
  self_friend: "selfFriend",
  unknown_code: "unknownCode",
  friend_limit: "friendLimit",
  their_friend_limit: "theirFriendLimit",
  no_request: "noRequest",
  pending_limit: "pendingLimit",
  request_limit: "requestLimit",
  party_not_found: "partyNotFound",
  not_friend: "notFriend",
  friend_offline: "friendOffline",
  friend_not_in_party: "friendNotInParty",
  party_full: "partyFull",
  not_in_party: "notInParty",
  not_host: "notHost",
  name_not_allowed: "nameNotAllowed",
  pet_name_not_allowed: "petNameNotAllowed",
  self_block: "selfBlock",
  block_limit: "blockLimit",
  blocked: "blocked",
  self_report: "selfReport",
  report_limit: "reportLimit",
  banned: "banned",
};

const INVALID_REQUEST_CODES = new Set(["invalid_json", "unknown_field", "invalid_field", "body_too_large"]);

/** The failure kinds the scheduler retries, since the same call may succeed later. */
const TRANSIENT: ReadonlySet<PartyErrorKind> = new Set(["unreachable", "timedOut", "rateLimited", "serverUnavailable", "transport"]);

/**
 * One failure. `retryAfter` is set for `rateLimited`, `code` for
 * `invalidRequest` (the server's code) and `server` (any code this app does
 * not know), `status` for `server`, and `detail` for `invalidResponse` and
 * `transport` (for logs only; never shown, never a token).
 */
export class PartyError extends Error {
  readonly kind: PartyErrorKind;
  readonly retryAfter: Seconds | undefined;
  readonly code: string | undefined;
  readonly status: number | undefined;
  readonly detail: string | undefined;

  private constructor(kind: PartyErrorKind, fields: { retryAfter?: Seconds; code?: string; status?: number; detail?: string } = {}) {
    super(fields.code === undefined ? kind : `${kind} (${fields.code})`);
    this.name = "PartyError";
    this.kind = kind;
    this.retryAfter = fields.retryAfter;
    this.code = fields.code;
    this.status = fields.status;
    this.detail = fields.detail;
  }

  /** A failure with no payload. */
  static of(kind: Exclude<PartyErrorKind, "rateLimited" | "invalidRequest" | "server" | "invalidResponse" | "transport">): PartyError {
    return new PartyError(kind);
  }

  static rateLimited(retryAfter: Seconds): PartyError {
    return new PartyError("rateLimited", { retryAfter });
  }

  static invalidRequest(code: string): PartyError {
    return new PartyError("invalidRequest", { code });
  }

  static server(code: string, status: number): PartyError {
    return new PartyError("server", { code, status });
  }

  static invalidResponse(detail: string): PartyError {
    return new PartyError("invalidResponse", { detail });
  }

  static transport(detail: string): PartyError {
    return new PartyError("transport", { detail });
  }

  /** Maps a server `error` code and HTTP status to a typed failure. */
  static fromServer(code: string, status: number, retryAfter: Seconds | undefined): PartyError {
    if (code === "rate_limited") return PartyError.rateLimited(Math.max(1, retryAfter ?? 60));
    if (code === "unavailable" || code === "internal") return PartyError.of("serverUnavailable");
    if (INVALID_REQUEST_CODES.has(code)) return PartyError.invalidRequest(code);
    const kind = Object.hasOwn(SERVER_CODES, code) ? SERVER_CODES[code] : undefined;
    if (kind !== undefined) return new PartyError(kind);
    return status >= 500 ? PartyError.of("serverUnavailable") : PartyError.server(code, status);
  }

  /** True for failures that say nothing about the request itself, so the same call may succeed later. */
  get isTransient(): boolean {
    return TRANSIENT.has(this.kind);
  }

  /** Whether two failures are the same case with the same payload (the Swift enum's `==`). */
  equals(other: PartyError): boolean {
    return (
      this.kind === other.kind &&
      this.retryAfter === other.retryAfter &&
      this.code === other.code &&
      this.status === other.status &&
      this.detail === other.detail
    );
  }

  /** `409 revision_conflict`: another device pushed since the last pull. Port of isRevisionConflict. */
  get isRevisionConflict(): boolean {
    return this.kind === "server" && this.code === "revision_conflict";
  }

  /** `403 no_account`: the token is not linked to a Sign in with Apple account. */
  get isNoSyncAccount(): boolean {
    return this.kind === "server" && this.code === "no_account";
  }

  /** `401 invalid_code`: the web sign-in's one-time code was used, expired or belongs to another attempt. */
  get isExpiredWebSignIn(): boolean {
    return this.kind === "server" && this.code === "invalid_code";
  }

  /** `401 invalid_identity_token`: Apple's token was refused; ask the user to sign in again. */
  get isRejectedAppleSignIn(): boolean {
    return this.kind === "server" && this.code === "invalid_identity_token";
  }

  /** One short sentence for the UI. */
  get userMessage(): string {
    return partyErrorMessage(this);
  }
}

export function isPartyError(value: unknown): value is PartyError {
  return value instanceof PartyError;
}

/** Whether two optional failures are equal, for state comparisons. */
export function samePartyError(a: PartyError | undefined, b: PartyError | undefined): boolean {
  if (a === undefined || b === undefined) return a === b;
  return a.equals(b);
}

/** The UI sentence for a failure, keyed like the Mac catalog. */
export function partyErrorMessage(error: PartyError): string {
  switch (error.kind) {
    case "unreachable":
      return tr("Can't reach the party server.");
    case "timedOut":
      return tr("The party server didn't answer in time.");
    case "unauthorized":
      return tr("Your party profile was reset. Reconnecting…");
    case "rateLimited":
      return tr("Too many requests. Trying again shortly.");
    case "serverUnavailable":
      return tr("The party server is busy. Trying again shortly.");
    case "invalidRequest":
      return tr("The server didn't accept that.");
    case "selfFriend":
      return tr("That's your own code.");
    case "unknownCode":
      return tr("No one has that friend code.");
    case "friendLimit":
      return tr("You already have 50 friends.");
    case "theirFriendLimit":
      return tr("They already have 50 friends.");
    case "noRequest":
      return tr("That friend request is no longer there.");
    case "pendingLimit":
      return tr("You have 50 friend requests waiting. Cancel some first.");
    case "requestLimit":
      return tr("You've sent a lot of friend requests today. Try again tomorrow.");
    case "partyNotFound":
      return tr("That party has ended or the code is wrong.");
    case "notFriend":
      return tr("You can only join a friend's party.");
    case "friendOffline":
      return tr("Your friend just went offline.");
    case "friendNotInParty":
      return tr("Your friend left their party.");
    case "partyFull":
      return tr("That party is full.");
    case "notInParty":
      return tr("You're not in a party anymore.");
    case "notHost":
      return tr("Only the host can change the session.");
    case "nameNotAllowed":
      return tr("That name isn't allowed. Please pick another.");
    case "petNameNotAllowed":
      return tr("That pet name isn't allowed. Please pick another.");
    case "selfBlock":
      return tr("That's your own code.");
    case "blockLimit":
      return tr("You've blocked too many people. Unblock someone first.");
    case "blocked":
      return tr("You blocked them. Unblock them in Party options first.");
    case "selfReport":
      return tr("That's your own code.");
    case "reportLimit":
      return tr("You've sent a lot of reports today. Try again tomorrow.");
    case "banned":
      return tr("Party is no longer available for this account.");
    case "server":
      return tr("The party server reported a problem.");
    case "invalidResponse":
      return tr("Unexpected reply from the party server.");
    case "transport":
      return tr("Couldn't reach the party server.");
  }
}
