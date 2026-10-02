// Study parties: small groups whose pets sit side by side in the notch, with an optional shared session.
import { HttpError, Obj, PARTY_IDLE_EXPIRY_S, STUDY_METHODS, int, oneOf, parseFriendCode, parsePartyCode } from "./lib";

/** Body fields accepted by `POST /v1/party/join`: exactly one of a party code or a friend's code. */
export const JOIN_FIELDS = ["code", "friend"] as const;
/** Body fields accepted by `POST /v1/party/session`. */
export const SESSION_FIELDS = ["method", "phaseEndsAt"] as const;

/**
 * Party activity (polls by members) is persisted at most this often. A party only needs `lastActive`
 * to the nearest few minutes to decide its 12 h expiry, and every bump is a billed row write.
 */
export const PARTY_TOUCH_S = 600;

/** How far ahead a shared phase may end; the same window as presence `phaseEndsAt`. */
const SESSION_WINDOW_S = 86_400;

/** The shared session the host started; every member's client counts down to `phaseEndsAt`. */
export interface PartySession {
  method: string;
  phaseEndsAt: number;
  startedAt: number;
}

/** Where to join: a party code, or the party an online friend is in. */
export type JoinTarget = { party: string } | { friend: string };

export function parseJoin(body: Obj): JoinTarget {
  const hasCode = body.code !== undefined;
  const hasFriend = body.friend !== undefined;
  if (hasCode === hasFriend) throw new HttpError(400, "invalid_field", "send exactly one of code or friend");
  return hasCode ? { party: parsePartyCode(body.code) } : { friend: parseFriendCode(body.friend) };
}

/** Validates a shared session. Both fields are required and the phase must end in the future. */
export function parseSession(body: Obj, now: number): Omit<PartySession, "startedAt"> {
  if (body.method === undefined) throw new HttpError(400, "invalid_field", "method is required");
  if (body.phaseEndsAt === undefined) throw new HttpError(400, "invalid_field", "phaseEndsAt is required");
  return {
    method: oneOf(body.method, STUDY_METHODS, "method"),
    phaseEndsAt: int(body.phaseEndsAt, "phaseEndsAt", now + 1, now + SESSION_WINDOW_S),
  };
}

/** A party expires once it has seen no activity for `partyIdleExpirySeconds` (12 h). */
export function partyExpired(lastActive: number, now: number): boolean {
  return now - lastActive >= PARTY_IDLE_EXPIRY_S;
}
