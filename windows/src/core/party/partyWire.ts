/*
 * The friends API's JSON as it goes over the wire (docs/study/backend-api.md),
 * mirrored from the backend's own types: `Profile`, `PROFILE_FIELDS`,
 * `Presence`, `PRESENCE_FIELDS`, `PartySession`, `JOIN_FIELDS`,
 * `SESSION_FIELDS`, `REPORT_FIELDS`, `REPORT_REASONS`, `LeaderboardEntry`,
 * `SYNC_FIELDS`, `WEB_TOKEN_FIELDS` and the size limits.
 *
 * The Windows typecheck cannot import backend/src directly: the backend is
 * written for its own, looser compiler options (no `noUncheckedIndexedAccess`)
 * and every type import would pull its sources into this program. So
 * `windows/contracts/backend.contract.ts` imports both sides and asserts they
 * match, and `tests/unit/party/backendContract.test.ts` compiles it (and
 * compares the field lists at run time), so a contract change on either side
 * fails `npm test`.
 *
 * Request bodies list exactly the documented fields: the server rejects
 * unknown ones with `unknown_field`.
 */

/** The Party protocol this app speaks, sent in `PROTOCOL_HEADER` on every request. Backend `PROTOCOL_VERSION`. */
export const PROTOCOL_VERSION = 2;
/** Backend `PROTOCOL_HEADER`. */
export const PROTOCOL_HEADER = "Tabbi-Protocol";

/** Largest request body in bytes (backend `MAX_BODY_BYTES`). */
export const MAX_BODY_BYTES = 4096;
/** Largest `PUT /v1/sync` body in bytes (backend `MAX_SYNC_BYTES`). */
export const MAX_SYNC_BYTES = 64 * 1024;

/* MARK: Request bodies */

/** Body fields of `POST /v1/register` and `PATCH /v1/me` (backend `PROFILE_FIELDS`). */
export const PROFILE_BODY_FIELDS = ["name", "petName", "species", "breed", "colors", "costume", "accessories", "points", "level"] as const;

/** A profile write: every field optional; an absent one keeps the server's value (backend `ProfilePatch`). */
export interface ProfileBody {
  name?: string;
  petName?: string;
  species?: string;
  breed?: string;
  colors?: string[];
  costume?: string;
  accessories?: string[];
  points?: number;
  level?: number;
}

/** Body fields of `POST /v1/presence` (backend `PRESENCE_FIELDS`). */
export const HEARTBEAT_BODY_FIELDS = ["status", "method", "phaseEndsAt", "sessionMinutes", "todayMinutes", "streakDays", "day"] as const;

/** The status values a heartbeat sends (`catalog.statuses`). */
export type WireStatus = "studying" | "break" | "idle" | "offline";

export interface HeartbeatBody {
  status: WireStatus;
  method?: string;
  phaseEndsAt?: number;
  sessionMinutes?: number;
  todayMinutes?: number;
  streakDays?: number;
  day?: string;
}

/** Body fields of `POST /v1/friends` and `POST /v1/blocks`. */
export const CODE_BODY_FIELDS = ["code"] as const;
export interface CodeBody {
  code: string;
}

/** Body fields of `POST /v1/party/join` (backend `JOIN_FIELDS`): exactly one of the two. */
export const JOIN_BODY_FIELDS = ["code", "friend"] as const;
export type JoinBody = { code: string } | { friend: string };

/** Body fields of `POST /v1/party/session` (backend `SESSION_FIELDS`). */
export const SESSION_BODY_FIELDS = ["method", "phaseEndsAt"] as const;
export interface SessionBody {
  method: string;
  phaseEndsAt: number;
}

/** Body fields of `POST /v1/reports` (backend `REPORT_FIELDS`). */
export const REPORT_BODY_FIELDS = ["code", "reason", "note"] as const;
/** Backend `REPORT_REASONS`. */
export const REPORT_REASONS = ["inappropriate_name", "harassment", "spam", "other"] as const;
export type WireReportReason = (typeof REPORT_REASONS)[number];
/** Backend `MAX_REPORT_NOTE`. */
export const MAX_REPORT_NOTE = 280;
export interface ReportBody {
  code: string;
  reason: WireReportReason;
  note?: string;
}

/** Body fields of `PUT /v1/sync` (backend `SYNC_FIELDS`). */
export const SYNC_BODY_FIELDS = ["document"] as const;

/** Body fields of `POST /v1/auth/apple/web/token` (backend `WEB_TOKEN_FIELDS`). */
export const WEB_TOKEN_BODY_FIELDS = ["code", "state"] as const;
export interface WebTokenBody {
  code: string;
  state: string;
}

/** Backend `WEB_TOKEN_PATH` and `WEB_CALLBACK_PATH`. */
export const WEB_TOKEN_PATH = "/v1/auth/apple/web/token";
export const WEB_CALLBACK_PATH = "/v1/auth/apple/web/callback";
/** Backend `APP_CALLBACK_URL`: where the callback sends the browser. */
export const APP_CALLBACK_URL = "tabbi://auth/apple";

/* MARK: Replies */

/** A profile as replies carry it (backend `Profile`), plus `badges` in friends lists and party rosters. */
export interface WireProfile {
  code: string;
  name: string;
  petName: string;
  species: string;
  breed: string;
  colors: string[];
  costume: string;
  accessories: string[];
  points: number;
  level: number;
  badges?: string[];
}

/** Backend `Presence`. */
export interface WirePresence {
  status: string;
  method: string | null;
  phaseEndsAt: number | null;
  sessionMinutes: number;
  todayMinutes: number;
  streakDays: number;
  day: string;
  lastSeen: number;
}

/** Backend `PartySession`. */
export interface WirePartySession {
  method: string;
  phaseEndsAt: number;
  startedAt: number;
}

/** Backend `LeaderboardEntry`. */
export interface WireLeaderboardEntry {
  rank: number;
  minutes: number;
  me: boolean;
  profile: WireProfile;
}
