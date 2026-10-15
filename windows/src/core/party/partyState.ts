import type { PetProfile } from "../pets/petProfile";
import type { Instant, Seconds } from "../time";
import type { PartyError } from "./partyError";
import type { Party, PartyFriend, PartyFriendAddition, PartyFriendList, PartyFriendRequest, PartyMember, PartyProfile } from "./partyModels";
import { partyPet } from "./partyPetAppearance";
import { rosterStatus, rosterTimeLeft, sortedFriends, sortedMembers } from "./partyRoster";
import type { PartySharedSession } from "./partySessionTracker";
import { partyAgeStatus, partyServerIssue, type PartySettings } from "./partySettings";

/*
 * Port of PartyState: everything the Party tab shows, and how each server
 * reply or failure changes it. The app's store does the networking and
 * feeds results in here, so which screen appears (bad server, connecting,
 * unreachable, empty friends, in a party) is decided by tested, pure code.
 *
 * A refresh that fails after data has loaded keeps that data on screen and
 * only records `staleError`, so a flaky network shows a quiet "offline"
 * hint instead of wiping the friends list.
 */

export type PartyConnection =
  /** The server field in Settings can't be used; the message says why. */
  | { readonly kind: "invalidServer"; readonly message: string }
  /** The age check wasn't answered, or said under 13 until `tooYoungUntil`. Nothing is sent. */
  | { readonly kind: "ageCheck"; readonly tooYoungUntil: Instant | undefined }
  /** Registering or syncing the profile for the first time this run. */
  | { readonly kind: "connecting" }
  /** The first connection failed; nothing has loaded yet. */
  | { readonly kind: "unreachable"; readonly error: PartyError }
  /** The profile is synced and the friend code known. */
  | { readonly kind: "connected" };

/**
 * One pet for other modules and the closed island. The module wiring maps
 * it onto the providers' `ProvidedPartyPet`; only names and pets leave.
 */
export interface PartyPetView {
  readonly id: string;
  readonly name: string;
  readonly pet: PetProfile;
  readonly isAway: boolean;
}

/** A result as the Mac's `Result<Value, PartyError>`. */
export type PartyResult<Value> = { readonly ok: true; readonly value: Value } | { readonly ok: false; readonly error: PartyError };

function connectionFor(settings: PartySettings, now: Instant): PartyConnection {
  const issue = partyServerIssue(settings);
  if (issue !== undefined) return { kind: "invalidServer", message: issue };
  const age = partyAgeStatus(settings, now);
  switch (age.kind) {
    case "unanswered":
      return { kind: "ageCheck", tooYoungUntil: undefined };
    case "tooYoung":
      return { kind: "ageCheck", tooYoungUntil: age.until };
    case "passed":
      return { kind: "connecting" };
  }
}

function ordered(party: Party): Party {
  return { ...party, members: sortedMembers(party.members) };
}

/** The first moment after `now` when the time left until `end`, rounded up to `unit`s, drops by one. */
function nextStep(end: Instant, now: Instant, unit: Seconds): Instant | undefined {
  const left = end - now;
  if (!(left > 0)) return undefined;
  const stepsAfterNext = Math.ceil(left / unit) - 1;
  return end - stepsAfterNext * unit;
}

export class PartyState {
  private connectionValue: PartyConnection;
  private profileValue: PartyProfile | undefined;
  private friendsValue: readonly PartyFriend[] = [];
  private incoming: readonly PartyFriendRequest[] = [];
  private outgoing: readonly PartyFriendRequest[] = [];
  private waiting = 0;
  private loaded = false;
  private partyValue: Party | undefined;
  private stale: PartyError | undefined;
  private leftStart: Instant | undefined;

  constructor(settings: PartySettings, now: Instant) {
    this.connectionValue = connectionFor(settings, now);
  }

  /** A state with data already loaded, for demo mode and previews. */
  static loaded(
    profile: PartyProfile,
    friends: readonly PartyFriend[],
    party: Party | undefined,
    incoming: readonly PartyFriendRequest[] = [],
    outgoing: readonly PartyFriendRequest[] = [],
  ): PartyState {
    const state = new PartyState({ serverText: "", name: "", invisible: false, ageEligibleFrom: Number.NEGATIVE_INFINITY }, 0);
    state.connectionValue = { kind: "connected" };
    state.profileValue = profile;
    state.friendsValue = sortedFriends(friends);
    state.incoming = incoming;
    state.outgoing = outgoing;
    state.waiting = incoming.length;
    state.loaded = true;
    state.partyValue = party === undefined ? undefined : ordered(party);
    return state;
  }

  /** A copy to change without touching this one (the Swift struct's value semantics). */
  clone(): PartyState {
    const copy = Object.create(PartyState.prototype) as PartyState;
    Object.assign(copy, this);
    return copy;
  }

  get connection(): PartyConnection {
    return this.connectionValue;
  }
  /** My profile as the server last returned it. */
  get profile(): PartyProfile | undefined {
    return this.profileValue;
  }
  /** Friends in display order. */
  get friends(): readonly PartyFriend[] {
    return this.friendsValue;
  }
  /** Friend requests waiting for me to accept or decline, newest first. */
  get incomingRequests(): readonly PartyFriendRequest[] {
    return this.incoming;
  }
  /** Friend requests I sent that wait for an answer, newest first. */
  get outgoingRequests(): readonly PartyFriendRequest[] {
    return this.outgoing;
  }
  /** How many friend requests wait for me by the server's latest word: the Party tab's badge. */
  get waitingRequestCount(): number {
    return this.waiting;
  }
  /** Whether the friends list has loaded at least once, so "no friends yet" never shows while loading. */
  get friendsLoaded(): boolean {
    return this.loaded;
  }
  /** The party I'm in, members in display order. */
  get party(): Party | undefined {
    return this.partyValue;
  }
  /** The last refresh failed; what's on screen may be out of date. */
  get staleError(): PartyError | undefined {
    return this.stale;
  }
  /** The start of the shared session I stepped out of. */
  get leftSessionStart(): Instant | undefined {
    return this.leftStart;
  }

  /* MARK: Derived */

  get friendCode(): string | undefined {
    return this.profileValue?.code;
  }

  /** Whether the friends column has anyone to list: friends or requests. */
  get hasPeople(): boolean {
    return this.friendsValue.length > 0 || this.incoming.length > 0 || this.outgoing.length > 0;
  }

  get inParty(): boolean {
    return this.partyValue !== undefined;
  }

  /** Whether I host the current party and so control its session. */
  get isHost(): boolean {
    const code = this.profileValue?.code;
    return this.partyValue !== undefined && code !== undefined && this.partyValue.host === code;
  }

  /** The other members of my party, for the pets beside mine; empty when not in a party. */
  get companions(): PartyMember[] {
    return this.partyValue?.members.filter((member) => member.profile.code !== this.profileValue?.code) ?? [];
  }

  /** The party's pets for other modules: mine first, then the others in roster order; undefined outside a party. */
  get partyPets(): PartyPetView[] | undefined {
    const me = this.profileValue;
    if (!this.inParty || me === undefined) return undefined;
    const mine: PartyPetView = { id: me.code, name: me.name, pet: partyPet(me), isAway: false };
    const others = this.companions.map((member) => ({
      id: member.profile.code,
      name: member.profile.name,
      pet: partyPet(member.profile),
      isAway: rosterStatus(member.presence, member.online) === "offline",
    }));
    return [mine, ...others];
  }

  /**
   * The shared session I'm in at `now`: the party's session while it runs,
   * unless I stepped out of it. Offline members don't count as company.
   */
  session(now: Instant): PartySharedSession | undefined {
    const party = this.partyValue;
    const session = party?.session;
    if (party === undefined || session === undefined || !(session.phaseEndsAt > now) || this.leftStart === session.startedAt) return undefined;
    const friends = this.companions.filter((member) => rosterStatus(member.presence, member.online) !== "offline");
    const host = this.isHost ? undefined : (party.members.find((member) => member.host)?.profile.name ?? "The host");
    return { method: session.method, startedAt: session.startedAt, endsAt: session.phaseEndsAt, friendCount: friends.length, hostName: host };
  }

  /**
   * When what the panel shows next changes by itself after `now`: the next
   * second while the shared session's clock runs, otherwise the next whole
   * minute of a member's or friend's countdown. Undefined when nothing counts down.
   */
  nextClockChange(now: Instant): Instant | undefined {
    const changes: Instant[] = [];
    const end = this.partyValue?.session?.phaseEndsAt;
    if (end !== undefined) {
      const next = nextStep(end, now, 1);
      if (next !== undefined) changes.push(next);
    }
    const presences = [
      ...(this.partyValue?.members ?? []).map((member) => ({ presence: member.presence, online: member.online })),
      ...this.friendsValue.map((friend) => ({ presence: friend.presence, online: friend.online })),
    ];
    for (const { presence, online } of presences) {
      if (rosterTimeLeft(presence, online, now) === undefined) continue;
      const phaseEnd = presence?.phaseEndsAt;
      if (phaseEnd === undefined) continue;
      const next = nextStep(phaseEnd, now, 60);
      if (next !== undefined) changes.push(next);
    }
    return changes.length === 0 ? undefined : Math.min(...changes);
  }

  /** Whether I stepped out of the session that is running now. */
  hasLeftSession(now: Instant): boolean {
    const session = this.partyValue?.session;
    if (session === undefined || !(session.phaseEndsAt > now)) return false;
    return this.leftStart === session.startedAt;
  }

  /** Whether the age check still stands between the user and Party. */
  get awaitsAgeCheck(): boolean {
    return this.connectionValue.kind === "ageCheck";
  }

  /* MARK: Transitions */

  /** Steps out of the running shared session without ending it for the others. */
  leaveSession(): void {
    const started = this.partyValue?.session?.startedAt;
    if (started !== undefined) this.leftStart = started;
  }

  /** Back into a shared session I stepped out of. */
  rejoinSession(): void {
    this.leftStart = undefined;
  }

  /** Starts over after the server setting changed: drops everything that belonged to the old server. */
  reset(settings: PartySettings, now: Instant): void {
    Object.assign(this, new PartyState(settings, now));
  }

  /** The profile synced (or registered). */
  didConnect(profile: PartyProfile): void {
    this.profileValue = profile;
    this.connectionValue = { kind: "connected" };
    this.stale = undefined;
  }

  /** Registering or syncing failed. Once connected, the old data stays and the failure only marks it stale. */
  didFailToConnect(error: PartyError): void {
    const kind = this.connectionValue.kind;
    if (kind === "connected") this.stale = error;
    else if (kind === "invalidServer" || kind === "ageCheck") return;
    else this.connectionValue = { kind: "unreachable", error };
  }

  /** Retrying after `unreachable`. */
  willReconnect(): void {
    if (this.connectionValue.kind === "unreachable") this.connectionValue = { kind: "connecting" };
  }

  /** A friends fetch from a server that sends friends only. */
  didFetchFriends(result: PartyResult<readonly PartyFriend[]>): void {
    this.didFetchFriendList(result.ok ? { ok: true, value: { friends: result.value, incoming: [], outgoing: [] } } : result);
  }

  /** A friends fetch: friends and the friend requests on either side. */
  didFetchFriendList(result: PartyResult<PartyFriendList>): void {
    if (!result.ok) {
      this.stale = result.error;
      return;
    }
    this.friendsValue = sortedFriends(result.value.friends);
    this.incoming = result.value.incoming;
    this.outgoing = result.value.outgoing;
    this.waiting = result.value.incoming.length;
    this.loaded = true;
    this.stale = undefined;
  }

  /** A heartbeat said how many friend requests wait for me. */
  didCountWaitingRequests(count: number): void {
    this.waiting = Math.max(0, count);
  }

  /** A party fetch, or the reply to create, join, leave or a session change. `notInParty` and `partyNotFound` mean it is gone. */
  didFetchParty(result: PartyResult<Party | undefined>): void {
    if (result.ok) {
      this.partyValue = result.value === undefined ? undefined : ordered(result.value);
      this.stale = undefined;
    } else if (result.error.kind === "notInParty" || result.error.kind === "partyNotFound") {
      this.partyValue = undefined;
    } else {
      this.stale = result.error;
    }
  }

  /** A friend was added: shown right away, before the next refresh brings their presence. */
  didAddFriend(profile: PartyProfile, now: Instant): void {
    this.dropRequests(profile.code);
    if (this.friendsValue.some((friend) => friend.profile.code === profile.code)) return;
    this.friendsValue = sortedFriends([...this.friendsValue, { profile, since: now, presence: undefined, online: false, party: undefined }]);
    this.loaded = true;
  }

  /** What asking someone by code led to, shown right away. */
  didAsk(addition: PartyFriendAddition, now: Instant): void {
    if (addition.kind !== "requested") {
      this.didAddFriend(addition.profile, now);
      return;
    }
    if (this.outgoing.some((request) => request.profile.code === addition.profile.code)) return;
    this.outgoing = [{ profile: addition.profile, since: now }, ...this.outgoing];
    this.loaded = true;
  }

  /** Ends whatever linked us: a friendship, my request, or theirs (declined). */
  didRemoveFriend(code: string): void {
    this.friendsValue = this.friendsValue.filter((friend) => friend.profile.code !== code);
    this.dropRequests(code);
  }

  /** I blocked someone: they leave my friends and my party's members right away. */
  didBlock(code: string): void {
    this.didRemoveFriend(code);
    const party = this.partyValue;
    if (party !== undefined) this.partyValue = { ...party, members: party.members.filter((member) => member.profile.code !== code) };
  }

  private dropRequests(code: string): void {
    const waited = this.incoming.some((request) => request.profile.code === code);
    this.incoming = this.incoming.filter((request) => request.profile.code !== code);
    this.outgoing = this.outgoing.filter((request) => request.profile.code !== code);
    if (waited) this.waiting = Math.max(0, this.waiting - 1);
  }
}
