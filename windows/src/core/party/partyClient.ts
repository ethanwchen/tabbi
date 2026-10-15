import type { Seconds } from "../time";
import { PartyError } from "./partyError";
import {
  PartyCode,
  read,
  readFriendList,
  readLeaderboardEntry,
  readParty,
  readPresence,
  readProfile,
  statusToWire,
  type Party,
  type PartyFriend,
  type PartyFriendAddition,
  type PartyFriendList,
  type PartyHeartbeat,
  type PartyHeartbeatReply,
  type PartyLeaderboard,
  type PartyProfile,
  type PartyProfileUpdate,
  type PartyRegistration,
  type PartyStanding,
} from "./partyModels";
import { reportSentNote, type PartyBlockedUser, type PartyReport } from "./partyModeration";
import type { PartyHttpRequest, PartyHttpResponse, PartyMethod, PartyTransport } from "./partyTransport";
import {
  MAX_BODY_BYTES,
  PROFILE_BODY_FIELDS,
  PROTOCOL_HEADER,
  PROTOCOL_VERSION,
  type CodeBody,
  type HeartbeatBody,
  type JoinBody,
  type ProfileBody,
  type ReportBody,
  type SessionBody,
} from "./partyWire";

/*
 * Port of PartyClient: a typed client for the Tabbi friends API
 * (docs/study/backend-api.md).
 *
 * It only sends what the contract lists: profile and pet appearance,
 * presence (status, timer, minute counters) and codes. It has no call that
 * could carry card, deck or note content. It does no scheduling; callers
 * follow the polling guidance (`PartyHeartbeatSchedule`, `PartyRefreshPlan`).
 */

/** Service names a friends server answers `GET /` with, including the deployment from before the rename. */
export const PARTY_SERVICE_NAMES: ReadonlySet<string> = new Set(["tabbi-friends", "studynotch-friends"]);

type JSONRecord = Readonly<Record<string, unknown>>;

/**
 * JSON with keys sorted, as the Mac's encoder writes it, so both apps send
 * byte-identical bodies. Undefined fields are left out.
 */
export function encodeSorted(value: unknown): string {
  return JSON.stringify(sortKeys(value));
}

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (typeof value !== "object" || value === null) return value;
  const object = value as Record<string, unknown>;
  return Object.fromEntries(
    Object.keys(object)
      .filter((key) => object[key] !== undefined)
      .sort()
      .map((key) => [key, sortKeys(object[key])]),
  );
}

/** UTF-8 length of a body, which is what the server's size limit counts. */
export function byteLength(text: string): number {
  return new TextEncoder().encode(text).length;
}

/** Whole unix seconds, which is what the server accepts for times. */
export function wireSeconds(instant: number): number {
  return Math.round(instant);
}

/** The body of `POST /v1/register` and `PATCH /v1/me`: exactly the profile fields present. */
export function profileBody(update: PartyProfileUpdate): ProfileBody {
  const body: ProfileBody = {};
  for (const field of PROFILE_BODY_FIELDS) {
    const value = update[field];
    if (value === undefined) continue;
    if (field === "colors" || field === "accessories") body[field] = [...(value as readonly string[])];
    else (body as Record<string, unknown>)[field] = value;
  }
  return body;
}

/** The body of `POST /v1/presence`: status, timer and counters, absent ones left out. */
export function heartbeatBody(heartbeat: PartyHeartbeat): HeartbeatBody {
  const body: HeartbeatBody = { status: statusToWire(heartbeat.status) };
  if (heartbeat.method !== undefined) body.method = heartbeat.method;
  if (heartbeat.phaseEndsAt !== undefined) body.phaseEndsAt = wireSeconds(heartbeat.phaseEndsAt);
  if (heartbeat.sessionMinutes !== undefined) body.sessionMinutes = heartbeat.sessionMinutes;
  if (heartbeat.todayMinutes !== undefined) body.todayMinutes = heartbeat.todayMinutes;
  if (heartbeat.streakDays !== undefined) body.streakDays = heartbeat.streakDays;
  if (heartbeat.day !== undefined) body.day = heartbeat.day;
  return body;
}

/**
 * Reads the `{ok, error}` envelope and returns a successful reply's object.
 * Failures branch on the stable `error` code, never on `message`.
 */
export function decodeReply(response: PartyHttpResponse): JSONRecord {
  let parsed: unknown;
  try {
    parsed = JSON.parse(response.body);
  } catch {
    parsed = undefined;
  }
  const object = typeof parsed === "object" && parsed !== null && !Array.isArray(parsed) ? (parsed as JSONRecord) : undefined;
  const ok = typeof object?.ok === "boolean" ? object.ok : undefined;
  const code = ok !== undefined && typeof object?.error === "string" ? object.error : undefined;
  if (response.status >= 400 || ok === false) {
    if (code !== undefined) throw PartyError.fromServer(code, response.status, response.retryAfter);
    if (response.status === 429) throw PartyError.rateLimited(Math.max(1, response.retryAfter ?? 60));
    if (response.status >= 500) throw PartyError.of("serverUnavailable");
    throw PartyError.invalidResponse(`HTTP ${response.status}`);
  }
  if (ok !== true || object === undefined) throw PartyError.invalidResponse("not a friends-server reply");
  return object;
}

function validCode(code: string | undefined): string {
  if (code === undefined) throw PartyError.invalidRequest("invalid_field");
  return code;
}

/** Runs the transport, wrapping anything that is not a `PartyError` (or a cancellation) as `transport`. */
export async function sendThrough(transport: PartyTransport, request: PartyHttpRequest, timeout: Seconds): Promise<PartyHttpResponse> {
  try {
    return await transport(request, timeout);
  } catch (error) {
    if (error instanceof PartyError) throw error;
    if (error instanceof Error && error.name === "AbortError") throw error;
    if (typeof error === "object" && error !== null && "code" in error && (error as { code: unknown }).code === "cancelled") throw error;
    throw PartyError.transport(error instanceof Error ? error.name : "failed");
  }
}

export class PartyClient {
  readonly transport: PartyTransport;
  /** The secret bearer token from `register`; undefined before registration. */
  readonly token: string | undefined;
  readonly timeout: Seconds;

  constructor(transport: PartyTransport, token?: string, timeout: Seconds = 10) {
    this.transport = transport;
    this.token = token;
    this.timeout = timeout;
  }

  /** The same client with another token. */
  withToken(token: string | undefined): PartyClient {
    return new PartyClient(this.transport, token, this.timeout);
  }

  /* MARK: Health */

  /** `GET /`: true when the server answers as a friends server. */
  async health(): Promise<boolean> {
    const reply = await this.send("GET", "/", { authorized: false });
    return PARTY_SERVICE_NAMES.has(read.string(reply, "service"));
  }

  /* MARK: Profile */

  /** `POST /v1/register` without a token: creates a user. Safe to retry. */
  async register(profile: PartyProfileUpdate = {}): Promise<PartyRegistration> {
    const reply = await this.send("POST", "/v1/register", { body: profileBody(profile), authorized: false });
    const token = read.optional(reply, "token", read.string);
    if (token === undefined) throw PartyError.invalidResponse("register returned no token");
    return { token, code: read.string(reply, "code"), profile: readProfile(reply.profile) };
  }

  /** `GET /v1/me`. */
  async me(): Promise<PartyProfile> {
    return (await this.standing()).profile;
  }

  /** `GET /v1/me` with whether the maintainer banned this user. */
  async standing(): Promise<PartyStanding> {
    return readStanding(await this.send("GET", "/v1/me"));
  }

  /** `PATCH /v1/me`: unchanged fields cost nothing, so sending the whole profile is fine. */
  async updateProfile(update: PartyProfileUpdate): Promise<PartyProfile> {
    return (await this.updateStanding(update)).profile;
  }

  /** `PATCH /v1/me` with whether the maintainer banned this user. */
  async updateStanding(update: PartyProfileUpdate): Promise<PartyStanding> {
    return readStanding(await this.send("PATCH", "/v1/me", { body: profileBody(update) }));
  }

  /** `DELETE /v1/me`: deletes the user and everything about them. */
  async deleteMe(): Promise<void> {
    await this.send("DELETE", "/v1/me");
  }

  /* MARK: Friends */

  /** `GET /v1/friends`: friends sorted by name, and the friend requests waiting on either side. */
  async friendList(): Promise<PartyFriendList> {
    return readFriendList(await this.send("GET", "/v1/friends"));
  }

  /** `GET /v1/friends`, friends only. */
  async friends(): Promise<readonly PartyFriend[]> {
    return (await this.friendList()).friends;
  }

  /**
   * `POST /v1/friends`: asks someone to be friends by their code. A server
   * from before friend requests makes every add a friendship right away.
   */
  async addFriend(code: string): Promise<PartyFriendAddition> {
    const body: CodeBody = { code: validCode(PartyCode.friendCode(code)) };
    return readAddition(await this.send("POST", "/v1/friends", { body }), true);
  }

  /** `POST /v1/friends/{code}/accept`: accepts the request they sent me. */
  async acceptFriend(code: string): Promise<PartyFriendAddition> {
    const valid = validCode(PartyCode.friendCode(code));
    return readAddition(await this.send("POST", `/v1/friends/${valid}/accept`), false);
  }

  /** `DELETE /v1/friends/{code}`: ends a friendship, cancels my request, or declines theirs. False if nothing to end. */
  async removeFriend(code: string): Promise<boolean> {
    const valid = validCode(PartyCode.friendCode(code));
    return read.boolean(await this.send("DELETE", `/v1/friends/${valid}`), "removed");
  }

  /* MARK: Moderation */

  /** `GET /v1/blocks`: the users I blocked, newest first. */
  async blocks(): Promise<readonly PartyBlockedUser[]> {
    return read.array(await this.send("GET", "/v1/blocks"), "blocks").map(readBlockedUser);
  }

  /** `POST /v1/blocks`. `blocked` is false when I had already blocked them. */
  async block(code: string): Promise<{ blocked: boolean; user: PartyBlockedUser }> {
    const body: CodeBody = { code: validCode(PartyCode.friendCode(code)) };
    const reply = await this.send("POST", "/v1/blocks", { body });
    return { blocked: read.boolean(reply, "blocked"), user: readBlockedUser(reply.block) };
  }

  /** `DELETE /v1/blocks/{code}`. The friendship is not restored. False if I had not blocked them. */
  async unblock(code: string): Promise<boolean> {
    const valid = validCode(PartyCode.friendCode(code));
    return read.boolean(await this.send("DELETE", `/v1/blocks/${valid}`), "unblocked");
  }

  /** `POST /v1/reports`. False when it updated my earlier report about the same user. */
  async report(report: PartyReport): Promise<boolean> {
    const note = reportSentNote(report);
    const body: ReportBody = { code: validCode(PartyCode.friendCode(report.code)), reason: report.reason, ...(note === undefined ? {} : { note }) };
    return read.boolean(await this.send("POST", "/v1/reports", { body }), "created");
  }

  /* MARK: Presence */

  /** `POST /v1/presence`: the heartbeat. */
  async heartbeat(heartbeat: PartyHeartbeat): Promise<PartyHeartbeatReply> {
    const reply = await this.send("POST", "/v1/presence", { body: heartbeatBody(heartbeat) });
    return {
      presence: readPresence(reply.presence),
      nextHeartbeat: read.optional(reply, "heartbeatSeconds", read.number),
      incomingRequests: read.optional(reply, "incomingRequests", read.integer),
    };
  }

  /** `GET /v1/leaderboard`: this ISO week's minutes for me and my friends. */
  async leaderboard(): Promise<PartyLeaderboard> {
    const reply = await this.send("GET", "/v1/leaderboard");
    return {
      week: read.string(reply, "week"),
      from: read.string(reply, "from"),
      to: read.string(reply, "to"),
      entries: read.array(reply, "entries").map(readLeaderboardEntry),
    };
  }

  /** `GET /v1/grants`: ids of the limited edition items granted to this user. */
  async grants(): Promise<readonly string[]> {
    return read.strings(await this.send("GET", "/v1/grants"), "items");
  }

  /* MARK: Parties */

  /** `GET /v1/party`: my party, or undefined. */
  async party(): Promise<Party | undefined> {
    return read.optionalObject(await this.send("GET", "/v1/party"), "party", readParty);
  }

  /** `POST /v1/party`: a new party hosted by me, leaving any other. */
  async createParty(): Promise<Party> {
    return readParty((await this.send("POST", "/v1/party")).party);
  }

  /** `POST /v1/party/join` by party code. */
  async joinParty(code: string): Promise<Party> {
    const body: JoinBody = { code: validCode(PartyCode.partyCode(code)) };
    return readParty((await this.send("POST", "/v1/party/join", { body })).party);
  }

  /** `POST /v1/party/join` through an online friend who is in a party. */
  async joinPartyOf(friend: string): Promise<Party> {
    const body: JoinBody = { friend: validCode(PartyCode.friendCode(friend)) };
    return readParty((await this.send("POST", "/v1/party/join", { body })).party);
  }

  /** `POST /v1/party/leave`. False if I was not in a party. */
  async leaveParty(): Promise<boolean> {
    return read.boolean(await this.send("POST", "/v1/party/leave"), "left");
  }

  /** `POST /v1/party/session` (host only): starts or replaces the shared session. */
  async startSession(method: string, phaseEndsAt: number): Promise<Party> {
    const body: SessionBody = { method, phaseEndsAt: wireSeconds(phaseEndsAt) };
    return readParty((await this.send("POST", "/v1/party/session", { body })).party);
  }

  /** `DELETE /v1/party/session` (host only). */
  async endSession(): Promise<Party> {
    return readParty((await this.send("DELETE", "/v1/party/session")).party);
  }

  /* MARK: Plumbing */

  private async send(
    method: PartyMethod,
    path: string,
    options: { body?: object; authorized?: boolean } = {},
  ): Promise<JSONRecord> {
    const authorized = options.authorized ?? true;
    const body = options.body === undefined ? undefined : encodeSorted(options.body);
    if (body !== undefined && byteLength(body) > MAX_BODY_BYTES) throw PartyError.invalidRequest("body_too_large");
    if (authorized && this.token === undefined) throw PartyError.of("unauthorized");
    const request: PartyHttpRequest = {
      method,
      path,
      ...(body === undefined ? {} : { body }),
      ...(authorized && this.token !== undefined ? { token: this.token } : {}),
      headers: { [PROTOCOL_HEADER]: String(PROTOCOL_VERSION) },
    };
    return decodeReply(await sendThrough(this.transport, request, this.timeout));
  }
}

function readStanding(reply: JSONRecord): PartyStanding {
  return { profile: readProfile(reply.profile), banned: read.optional(reply, "banned", read.boolean) ?? false };
}

/* `status` is `friends` or `requested`; missing from a protocol 1 server, where `added` decides. */
function readAddition(reply: JSONRecord, honorsRequested: boolean): PartyFriendAddition {
  const added = read.boolean(reply, "added");
  const status = read.optional(reply, "status", read.string);
  const profile = readProfile(reply.friend);
  if (honorsRequested && status === "requested") return { kind: "requested", profile };
  return added ? { kind: "friends", profile } : { kind: "alreadyFriends", profile };
}

function readBlockedUser(value: unknown): PartyBlockedUser {
  const object = read.record(value, "block");
  return {
    code: read.string(object, "code"),
    name: read.string(object, "name"),
    petName: read.string(object, "petName"),
    since: read.optional(object, "since", read.number),
  };
}
