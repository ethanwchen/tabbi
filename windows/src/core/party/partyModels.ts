import type { Instant, Seconds } from "../time";
import { PartyError } from "./partyError";

/*
 * Port of PartyModels: what the friends API carries, as the app reads it.
 * Pet fields stay strings so a newer server catalog never breaks decoding;
 * `partyPetAppearance` maps them to the app's pets. Times are unix seconds.
 *
 * The readers check every field the way the Mac's `Decodable` does: a
 * missing or mistyped required field makes the reply an `invalidResponse`,
 * and fields this app does not know are ignored.
 */

/** What friends and party members see of a user. Port of PartyProfile. */
export interface PartyProfile {
  readonly code: string;
  readonly name: string;
  readonly petName: string;
  readonly species: string;
  readonly breed: string;
  readonly colors: readonly string[];
  readonly costume: string;
  readonly accessories: readonly string[];
  readonly points: number;
  readonly level: number;
  /** Badge ids shown next to the name (`PARTY_BADGE_FOUNDING`); absent reads as none. */
  readonly badges: readonly string[];
}

/** Port of PartyBadge: the badge ids the server can send. An id the app does not know is ignored. */
export const PARTY_BADGE_FOUNDING = "founding";

/** Whether the user is a Founding Member: signed in during Tabbi's first 100 days. */
export function isFoundingMember(profile: PartyProfile): boolean {
  return profile.badges.includes(PARTY_BADGE_FOUNDING);
}

/** A profile as the server would return it, with the Mac's defaults for what is left out. */
export function partyProfile(
  fields: Pick<PartyProfile, "code" | "name" | "petName" | "species" | "breed"> & Partial<PartyProfile>,
): PartyProfile {
  return {
    colors: [],
    costume: "none",
    accessories: [],
    points: 0,
    level: 1,
    badges: [],
    ...fields,
  };
}

/**
 * Port of PartyProfileUpdate: the profile fields the app may write. Every
 * field is optional: an absent one keeps the server's value, so a partial
 * edit never blanks the rest. It has no room for anything about cards or decks.
 */
export interface PartyProfileUpdate {
  readonly name?: string;
  readonly petName?: string;
  readonly species?: string;
  readonly breed?: string;
  readonly colors?: readonly string[];
  readonly costume?: string;
  readonly accessories?: readonly string[];
  readonly points?: number;
  readonly level?: number;
}

/** Whether two updates send the same body. */
export function sameProfileUpdate(a: PartyProfileUpdate, b: PartyProfileUpdate): boolean {
  const keys = ["name", "petName", "species", "breed", "costume", "points", "level"] as const;
  if (keys.some((key) => a[key] !== b[key])) return false;
  const sameList = (x: readonly string[] | undefined, y: readonly string[] | undefined) =>
    x === undefined || y === undefined ? x === y : x.length === y.length && x.every((value, index) => value === y[index]);
  return sameList(a.colors, b.colors) && sameList(a.accessories, b.accessories);
}

/** Port of PartyStatus: what a user is doing, as heartbeats report it. `onBreak` is `break` on the wire. */
export type PartyStatus = "studying" | "onBreak" | "idle" | "offline";

export const PARTY_STATUSES: readonly PartyStatus[] = ["studying", "onBreak", "idle", "offline"];

export function statusToWire(status: PartyStatus): "studying" | "break" | "idle" | "offline" {
  return status === "onBreak" ? "break" : status;
}

export function statusFromWire(raw: string): PartyStatus | undefined {
  switch (raw) {
    case "studying":
    case "idle":
    case "offline":
      return raw;
    case "break":
      return "onBreak";
    default:
      return undefined;
  }
}

/** Port of PartyPresence: a user's presence from their last heartbeat. */
export interface PartyPresence {
  readonly status: PartyStatus;
  /** A catalog study method id, only while studying or on a break. */
  readonly method: string | undefined;
  /** When the current phase ends; count down locally from this. */
  readonly phaseEndsAt: Instant | undefined;
  readonly sessionMinutes: number;
  readonly todayMinutes: number;
  readonly streakDays: number;
  /** The local day `todayMinutes` belongs to, `YYYY-MM-DD`. */
  readonly day: string;
  readonly lastSeen: Instant;
}

/**
 * Port of PartyHeartbeat: only status, timer and minute counters. Nothing
 * about cards, decks or what is being studied ever leaves the device.
 */
export interface PartyHeartbeat {
  readonly status: PartyStatus;
  readonly method?: string;
  readonly phaseEndsAt?: Instant;
  readonly sessionMinutes?: number;
  readonly todayMinutes?: number;
  readonly streakDays?: number;
  readonly day?: string;
}

/** The `offline` heartbeat sent when quitting, sleeping or going invisible. */
export const OFFLINE_HEARTBEAT: PartyHeartbeat = { status: "offline" };

/** Port of PartyHeartbeatReply. */
export interface PartyHeartbeatReply {
  readonly presence: PartyPresence;
  /** When to send the next heartbeat; undefined after `offline` (stop sending). */
  readonly nextHeartbeat: Seconds | undefined;
  /** Friend requests waiting for me; undefined from a server without friend requests. */
  readonly incomingRequests: number | undefined;
}

/** Port of PartyRef: the party a friend is in, as the friends list shows it. */
export interface PartyRef {
  readonly code: string;
  readonly size: number;
}

/** Port of PartyFriend: one friend in `GET /v1/friends`. */
export interface PartyFriend {
  readonly profile: PartyProfile;
  readonly since: Instant;
  readonly presence: PartyPresence | undefined;
  readonly online: boolean;
  readonly party: PartyRef | undefined;
}

/** The contract offers "Join" only for an online friend in a party. */
export function canJoin(friend: PartyFriend): boolean {
  return friend.online && friend.party !== undefined;
}

/** Port of PartyFriendRequest: someone who asked me, or whom I asked, and when. */
export interface PartyFriendRequest {
  readonly profile: PartyProfile;
  readonly since: Instant;
}

/** Port of PartyFriendList. A server from before friend requests sends only `friends`. */
export interface PartyFriendList {
  readonly friends: readonly PartyFriend[];
  /** Requests waiting for me to accept or decline, newest first. */
  readonly incoming: readonly PartyFriendRequest[];
  /** Requests I sent that wait for the other person, newest first. */
  readonly outgoing: readonly PartyFriendRequest[];
}

/** Port of PartyFriendAddition: what asking someone by code led to. */
export type PartyFriendAddition =
  /** We are friends: they had asked me first, or I just accepted. */
  | { readonly kind: "friends"; readonly profile: PartyProfile }
  /** We were friends already; nothing changed. */
  | { readonly kind: "alreadyFriends"; readonly profile: PartyProfile }
  /** My request waits for them to accept. */
  | { readonly kind: "requested"; readonly profile: PartyProfile };

/** Port of PartySession: the host's shared study session. */
export interface PartySession {
  readonly method: string;
  readonly phaseEndsAt: Instant;
  readonly startedAt: Instant;
}

/** Port of PartyMember: one party member, in join order. */
export interface PartyMember {
  readonly profile: PartyProfile;
  readonly joinedAt: Instant;
  readonly host: boolean;
  readonly presence: PartyPresence | undefined;
  readonly online: boolean;
}

/** Port of Party: up to eight people sharing a code and, optionally, the host's session timer. */
export interface Party {
  readonly code: string;
  /** The host's friend code. */
  readonly host: string;
  readonly createdAt: Instant;
  readonly lastActive: Instant;
  readonly expiresAt: Instant;
  readonly maxMembers: number;
  readonly session: PartySession | undefined;
  readonly members: readonly PartyMember[];
}

export function isPartyHost(party: Party, code: string): boolean {
  return party.host === code;
}

export function isPartyFull(party: Party): boolean {
  return party.members.length >= party.maxMembers;
}

/** Port of PartyLeaderboardEntry. Ties share a rank. */
export interface PartyLeaderboardEntry {
  readonly rank: number;
  readonly minutes: number;
  readonly me: boolean;
  readonly profile: PartyProfile;
}

/** Port of PartyLeaderboard: this ISO week's study minutes for me and my friends. */
export interface PartyLeaderboard {
  /** e.g. `2026-W40`. */
  readonly week: string;
  readonly from: string;
  readonly to: string;
  readonly entries: readonly PartyLeaderboardEntry[];
}

/** Port of PartyRegistration: the secret token (Credential Manager only) and the public friend code. */
export interface PartyRegistration {
  readonly token: string;
  readonly code: string;
  readonly profile: PartyProfile;
}

/** Port of PartyStanding: what `GET /v1/me` says about my own account. */
export interface PartyStanding {
  readonly profile: PartyProfile;
  /** The maintainer banned this user: Party stays read-only for them. */
  readonly banned: boolean;
}

/**
 * Port of PartyCode: friend and party codes use `A-Z` and `2-9` without
 * the look-alikes `I`, `O`, `0` and `1`. Friend codes have 8 characters,
 * party codes 6.
 */
export const PartyCode = {
  alphabet: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789",
  friendCodeLength: 8,
  partyCodeLength: 6,

  /**
   * Upper-cases and strips spaces and dashes so pasted codes like
   * `k7qw-2mzd` work; undefined unless the result is a valid code of
   * `length` characters.
   */
  normalize(text: string, length: number): string | undefined {
    const cleaned = [...text.toUpperCase()].filter((ch) => !/\s/u.test(ch) && ch !== "-");
    if (cleaned.length !== length || !cleaned.every((ch) => PartyCode.alphabet.includes(ch))) return undefined;
    return cleaned.join("");
  },

  friendCode(text: string): string | undefined {
    return PartyCode.normalize(text, PartyCode.friendCodeLength);
  },

  partyCode(text: string): string | undefined {
    return PartyCode.normalize(text, PartyCode.partyCodeLength);
  },

  /**
   * The code in pasted text such as "Add me on Tabbi: k7qw-2mzd." Tries the
   * text, then each word, then each pair of neighboring words. Undefined
   * unless exactly one distinct code is found, so a paste never guesses.
   */
  find(text: string, length: number): string | undefined {
    const whole = PartyCode.normalize(text, length);
    if (whole !== undefined) return whole;
    const words = text.split(/[^\p{L}\p{N}-]+/u).filter((word) => word.length > 0);
    const pairs = words.slice(1).map((word, index) => `${words[index] ?? ""}${word}`);
    const found = new Set([...words, ...pairs].flatMap((candidate) => PartyCode.normalize(candidate, length) ?? []));
    return found.size === 1 ? [...found][0] : undefined;
  },
} as const;

/* MARK: Reading replies */

type JSONRecord = Readonly<Record<string, unknown>>;

function fail(what: string): never {
  throw PartyError.invalidResponse(what);
}

function record(value: unknown, what: string): JSONRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value)) fail(`${what} is not an object`);
  return value as JSONRecord;
}

function string(object: JSONRecord, key: string): string {
  const value = object[key];
  return typeof value === "string" ? value : fail(`${key} is not a string`);
}

/* An integer, as Swift's Int decoding requires. */
function integer(object: JSONRecord, key: string): number {
  const value = object[key];
  return typeof value === "number" && Number.isInteger(value) ? value : fail(`${key} is not an integer`);
}

/* A number (a Swift Date or TimeInterval). */
function number(object: JSONRecord, key: string): number {
  const value = object[key];
  return typeof value === "number" && Number.isFinite(value) ? value : fail(`${key} is not a number`);
}

function boolean(object: JSONRecord, key: string): boolean {
  const value = object[key];
  return typeof value === "boolean" ? value : fail(`${key} is not a boolean`);
}

function strings(object: JSONRecord, key: string): string[] {
  const value = object[key];
  if (!Array.isArray(value) || !value.every((item) => typeof item === "string")) fail(`${key} is not a list of strings`);
  return value as string[];
}

function array(object: JSONRecord, key: string): readonly unknown[] {
  const value = object[key];
  return Array.isArray(value) ? value : fail(`${key} is not a list`);
}

/* `decodeIfPresent`: missing or null is undefined, anything else must read. */
function optional<T>(object: JSONRecord, key: string, read: (object: JSONRecord, key: string) => T): T | undefined {
  const value = object[key];
  return value === undefined || value === null ? undefined : read(object, key);
}

export function readProfile(value: unknown): PartyProfile {
  const object = record(value, "profile");
  return {
    code: string(object, "code"),
    name: string(object, "name"),
    petName: string(object, "petName"),
    species: string(object, "species"),
    breed: string(object, "breed"),
    colors: strings(object, "colors"),
    costume: string(object, "costume"),
    accessories: strings(object, "accessories"),
    points: integer(object, "points"),
    level: integer(object, "level"),
    badges: optional(object, "badges", strings) ?? [],
  };
}

export function readPresence(value: unknown): PartyPresence {
  const object = record(value, "presence");
  const status = statusFromWire(string(object, "status")) ?? fail("unknown status");
  return {
    status,
    method: optional(object, "method", string),
    phaseEndsAt: optional(object, "phaseEndsAt", number),
    sessionMinutes: integer(object, "sessionMinutes"),
    todayMinutes: integer(object, "todayMinutes"),
    streakDays: integer(object, "streakDays"),
    day: string(object, "day"),
    lastSeen: number(object, "lastSeen"),
  };
}

function optionalObject<T>(object: JSONRecord, key: string, read: (value: unknown) => T): T | undefined {
  const value = object[key];
  return value === undefined || value === null ? undefined : read(value);
}

export function readFriend(value: unknown): PartyFriend {
  const object = record(value, "friend");
  return {
    profile: readProfile(object.profile),
    since: number(object, "since"),
    presence: optionalObject(object, "presence", readPresence),
    online: boolean(object, "online"),
    party: optionalObject(object, "party", (raw) => {
      const ref = record(raw, "party");
      return { code: string(ref, "code"), size: integer(ref, "size") };
    }),
  };
}

export function readFriendRequest(value: unknown): PartyFriendRequest {
  const object = record(value, "request");
  return { profile: readProfile(object.profile), since: number(object, "since") };
}

export function readFriendList(value: unknown): PartyFriendList {
  const object = record(value, "reply");
  return {
    friends: array(object, "friends").map(readFriend),
    incoming: optional(object, "incoming", array)?.map(readFriendRequest) ?? [],
    outgoing: optional(object, "outgoing", array)?.map(readFriendRequest) ?? [],
  };
}

export function readSession(value: unknown): PartySession {
  const object = record(value, "session");
  return { method: string(object, "method"), phaseEndsAt: number(object, "phaseEndsAt"), startedAt: number(object, "startedAt") };
}

export function readMember(value: unknown): PartyMember {
  const object = record(value, "member");
  return {
    profile: readProfile(object.profile),
    joinedAt: number(object, "joinedAt"),
    host: boolean(object, "host"),
    presence: optionalObject(object, "presence", readPresence),
    online: boolean(object, "online"),
  };
}

export function readParty(value: unknown): Party {
  const object = record(value, "party");
  return {
    code: string(object, "code"),
    host: string(object, "host"),
    createdAt: number(object, "createdAt"),
    lastActive: number(object, "lastActive"),
    expiresAt: number(object, "expiresAt"),
    maxMembers: integer(object, "maxMembers"),
    session: optionalObject(object, "session", readSession),
    members: array(object, "members").map(readMember),
  };
}

export function readLeaderboardEntry(value: unknown): PartyLeaderboardEntry {
  const object = record(value, "entry");
  return {
    rank: integer(object, "rank"),
    minutes: integer(object, "minutes"),
    me: boolean(object, "me"),
    profile: readProfile(object.profile),
  };
}

/** The field readers, for the other reply shapes the client reads. */
export const read = { record, string, integer, number, boolean, strings, array, optional, optionalObject } as const;
