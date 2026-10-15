/*
 * The Windows client's wire types checked against the backend's own
 * TypeScript types, so contract drift on either side fails a build.
 *
 * This file lives outside the Windows tsconfig's `include` on purpose:
 * importing backend/src pulls the backend's sources into the program, and
 * they are written for the backend's own, looser compiler options. The test
 * `tests/unit/party/backendContract.test.ts` compiles this file with the
 * TypeScript compiler API and fails on any error reported in it (errors
 * inside backend/src are the backend's own typecheck's business). Every
 * check is a type: it compiles or it does not.
 */

import type { APPLE_AUTH_FIELDS, AppleAuthRequest } from "@backend/src/apple";
import type { CRASH_FIELDS, CRASH_THREAD_FIELDS } from "@backend/src/crashes";
import type { LeaderboardEntry } from "@backend/src/leaderboard";
import type { MAX_BODY_BYTES, PROTOCOL_HEADER, PROTOCOL_VERSION } from "@backend/src/lib";
import type { MAX_REPORT_NOTE, REPORT_FIELDS, REPORT_REASONS, ReportRequest } from "@backend/src/moderation";
import type { JOIN_FIELDS, PartySession, SESSION_FIELDS, parseSession } from "@backend/src/party";
import type { PRESENCE_FIELDS, Presence } from "@backend/src/presence";
import type { PROFILE_FIELDS, Profile, ProfilePatch } from "@backend/src/profile";
import type { SUGGESTION_FIELDS } from "@backend/src/suggestions";
import type { SYNC_FIELDS } from "@backend/src/sync";
import type { APP_CALLBACK_URL, WEB_CALLBACK_PATH, WEB_TOKEN_FIELDS, WEB_TOKEN_PATH, parseWebToken } from "@backend/src/webauth";

import type { CRASH_BODY_FIELDS, CRASH_THREAD_BODY_FIELDS } from "../src/core/feedback/crashReport";
import type { SUGGEST_LINK_FIELDS } from "../src/core/feedback/feedbackLink";
import type * as Wire from "../src/core/party/partyWire";
import type { APPLE_AUTH_BODY_FIELDS, AppleAuthBody } from "../src/core/sync/syncClient";

/** True only when A and B are the same type (optional modifiers and readonly included). */
export type Equal<A, B> = (<T>() => T extends A ? 1 : 2) extends <T>() => T extends B ? 1 : 2 ? true : false;
/** Compiles only for `true`. */
export type Assert<T extends true> = T;
/** Every key of every member of a union. */
export type KeysOf<T> = T extends unknown ? keyof T : never;
/** The members of a tuple of names, as a union. */
export type Names<T extends readonly string[]> = T[number];
/** Whether every member of A is in B. */
export type Within<A, B> = [A] extends [B] ? true : false;

export type ProfileChecks = [
  /* `POST /v1/register` and `PATCH /v1/me` send exactly the profile fields, with the backend's types. */
  Assert<Equal<Names<typeof Wire.PROFILE_BODY_FIELDS>, Names<typeof PROFILE_FIELDS>>>,
  Assert<Equal<keyof Wire.ProfileBody, Names<typeof PROFILE_FIELDS>>>,
  Assert<Equal<Wire.ProfileBody, ProfilePatch>>,
  /* A profile reply is the backend's `Profile`, plus the badges friends lists and rosters add. */
  Assert<Equal<Omit<Wire.WireProfile, "badges">, Profile>>,
  Assert<Within<LeaderboardEntry, Wire.WireLeaderboardEntry>>,
  Assert<Equal<Omit<Wire.WireLeaderboardEntry, "profile">, Omit<LeaderboardEntry, "profile">>>,
];

export type PresenceChecks = [
  /* `POST /v1/presence` sends only the documented heartbeat fields. */
  Assert<Equal<Names<typeof Wire.HEARTBEAT_BODY_FIELDS>, Names<typeof PRESENCE_FIELDS>>>,
  Assert<Equal<keyof Wire.HeartbeatBody, Names<typeof PRESENCE_FIELDS>>>,
  /* Presence replies are the backend's `Presence`. */
  Assert<Equal<Wire.WirePresence, Presence>>,
];

export type PartyChecks = [
  Assert<Equal<Names<typeof Wire.JOIN_BODY_FIELDS>, Names<typeof JOIN_FIELDS>>>,
  Assert<Equal<KeysOf<Wire.JoinBody>, Names<typeof JOIN_FIELDS>>>,
  Assert<Equal<Names<typeof Wire.SESSION_BODY_FIELDS>, Names<typeof SESSION_FIELDS>>>,
  Assert<Equal<Wire.SessionBody, ReturnType<typeof parseSession>>>,
  Assert<Equal<Wire.WirePartySession, PartySession>>,
];

export type ModerationChecks = [
  Assert<Equal<Names<typeof Wire.REPORT_BODY_FIELDS>, Names<typeof REPORT_FIELDS>>>,
  Assert<Equal<keyof Wire.ReportBody, keyof ReportRequest>>,
  Assert<Equal<typeof Wire.REPORT_REASONS, typeof REPORT_REASONS>>,
  Assert<Equal<typeof Wire.MAX_REPORT_NOTE, typeof MAX_REPORT_NOTE>>,
];

export type ProtocolChecks = [
  Assert<Equal<typeof Wire.PROTOCOL_VERSION, typeof PROTOCOL_VERSION>>,
  Assert<Equal<typeof Wire.PROTOCOL_HEADER, typeof PROTOCOL_HEADER>>,
  Assert<Equal<typeof Wire.MAX_BODY_BYTES, typeof MAX_BODY_BYTES>>,
];

export type SignInAndSyncChecks = [
  Assert<Equal<Names<typeof Wire.SYNC_BODY_FIELDS>, Names<typeof SYNC_FIELDS>>>,
  Assert<Equal<Names<typeof Wire.WEB_TOKEN_BODY_FIELDS>, Names<typeof WEB_TOKEN_FIELDS>>>,
  Assert<Equal<Wire.WebTokenBody, ReturnType<typeof parseWebToken>>>,
  Assert<Equal<typeof Wire.WEB_TOKEN_PATH, typeof WEB_TOKEN_PATH>>,
  Assert<Equal<typeof Wire.WEB_CALLBACK_PATH, typeof WEB_CALLBACK_PATH>>,
  Assert<Equal<typeof Wire.APP_CALLBACK_URL, typeof APP_CALLBACK_URL>>,
  Assert<Equal<Names<typeof APPLE_AUTH_BODY_FIELDS>, Names<typeof APPLE_AUTH_FIELDS>>>,
  Assert<Equal<keyof AppleAuthBody, keyof AppleAuthRequest>>,
];

export type FeedbackChecks = [
  /* A crash report body names exactly the fields the backend reads, in its order. */
  Assert<Equal<typeof CRASH_BODY_FIELDS, typeof CRASH_FIELDS>>,
  Assert<Equal<typeof CRASH_THREAD_BODY_FIELDS, typeof CRASH_THREAD_FIELDS>>,
  /* The Suggest link only carries fields the suggestions route accepts. */
  Assert<Within<Names<typeof SUGGEST_LINK_FIELDS>, Names<typeof SUGGESTION_FIELDS>>>,
];
