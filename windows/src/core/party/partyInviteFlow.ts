import { tr } from "../localization/tr";
import type { Instant } from "../time";
import { PartyError, partyErrorMessage } from "./partyError";
import type { PartyInvite } from "./partyInvite";
import { MINIMUM_AGE } from "./partyAgeCheck";
import type { Party, PartyFriendAddition, PartyProfile } from "./partyModels";
import type { PartyBlockedUser } from "./partyModeration";
import type { PartyState } from "./partyState";

/*
 * Port of PartyInviteFlow: the confirmation an invite link opens in the
 * Party tab, from "Turn on Party?" through "Add a friend?" to "Request sent
 * to Maya". The app feeds it the Party state and the server's answers;
 * which step shows, and what it says, is decided here.
 *
 * Nothing happens without a click: a link only asks. Checks that need no
 * server (my own code, someone already a friend, someone I blocked, the
 * party I'm already in) answer before anything is sent, and the server's
 * refusals end in a friendly sentence rather than a raw error.
 */

export type InviteOutcome =
  | { readonly kind: "added"; readonly profile: PartyProfile }
  | { readonly kind: "alreadyFriends"; readonly profile: PartyProfile }
  /** My friend request waits for them to accept. */
  | { readonly kind: "requested"; readonly profile: PartyProfile }
  | { readonly kind: "joined"; readonly party: Party }
  | { readonly kind: "alreadyInParty" };

export type InviteRefusal =
  /** The link carries my own friend code. */
  | { readonly kind: "ownCode" }
  /** I blocked the person behind the link. */
  | { readonly kind: "blocked"; readonly name: string }
  /** The server said no. */
  | { readonly kind: "failed"; readonly error: PartyError };

export type InviteStage =
  /** The Party tab is off; the link asks to turn it on first. */
  | { readonly kind: "needsParty" }
  /** Waiting for Party to connect and load the friends list. */
  | { readonly kind: "connecting" }
  /** Party can't connect; "Try Again" shows when the problem may pass. */
  | { readonly kind: "unavailable"; readonly error: PartyError }
  /** Party waits for its age check; `tooYoungUntil` is set when it said under 13. */
  | { readonly kind: "ageCheck"; readonly tooYoungUntil: Instant | undefined }
  /** Asking "Add a friend?" or "Join this party?". */
  | { readonly kind: "confirming" }
  /** The request is on its way. */
  | { readonly kind: "working" }
  | { readonly kind: "finished"; readonly outcome: InviteOutcome }
  | { readonly kind: "refused"; readonly refusal: InviteRefusal };

/** "K7QW-2MZD": friend codes read more easily in two groups of four. */
function display(code: string): string {
  if (code.length <= 6) return code;
  const split = Math.trunc(code.length / 2);
  return `${code.slice(0, split)}-${code.slice(split)}`;
}

export class PartyInviteFlow {
  readonly invite: PartyInvite;
  private stageValue: InviteStage;
  /* The party I was in when asked, so the question can say joining leaves it. */
  private current: string | undefined;
  /* The person behind a friend link when they already asked me, so confirming accepts their request. */
  private askerValue: PartyProfile | undefined;

  constructor(invite: PartyInvite, partyIsOn: boolean) {
    this.invite = invite;
    this.stageValue = partyIsOn ? { kind: "connecting" } : { kind: "needsParty" };
  }

  get stage(): InviteStage {
    return this.stageValue;
  }

  get currentParty(): string | undefined {
    return this.current;
  }

  get asker(): PartyProfile | undefined {
    return this.askerValue;
  }

  /* MARK: Steps */

  /** The user turned Party on from the first question. */
  partyTurnedOn(): void {
    if (this.stageValue.kind === "needsParty") this.stageValue = { kind: "connecting" };
  }

  /** The user asked to try connecting again after `unavailable`. */
  retryConnecting(): void {
    if (this.stageValue.kind === "unavailable") this.stageValue = { kind: "connecting" };
  }

  /**
   * Follows the Party state while connecting: moves on once it is connected
   * (and, for a friend link, the friends list has loaded), or stops on a
   * connection failure. `blocked` is the Blocked list when it has loaded.
   */
  update(state: PartyState, blocked: readonly PartyBlockedUser[] | undefined): void {
    if (this.stageValue.kind !== "connecting") return;
    const connection = state.connection;
    switch (connection.kind) {
      case "invalidServer":
        this.stageValue = { kind: "unavailable", error: PartyError.invalidRequest("server") };
        return;
      case "unreachable":
        this.stageValue = { kind: "unavailable", error: connection.error };
        return;
      case "ageCheck":
        this.stageValue = { kind: "ageCheck", tooYoungUntil: connection.tooYoungUntil };
        return;
      case "connecting":
        return;
      case "connected":
        break;
    }
    const code = this.invite.code;
    if (this.invite.kind === "addFriend") {
      if (!state.friendsLoaded) return;
      const friend = state.friends.find((candidate) => candidate.profile.code === code);
      const sent = state.outgoingRequests.find((request) => request.profile.code === code);
      const user = blocked?.find((candidate) => candidate.code === code);
      if (code === state.friendCode) {
        this.stageValue = { kind: "refused", refusal: { kind: "ownCode" } };
      } else if (friend !== undefined) {
        this.stageValue = { kind: "finished", outcome: { kind: "alreadyFriends", profile: friend.profile } };
      } else if (sent !== undefined) {
        this.stageValue = { kind: "finished", outcome: { kind: "requested", profile: sent.profile } };
      } else if (user !== undefined) {
        this.stageValue = { kind: "refused", refusal: { kind: "blocked", name: user.name } };
      } else {
        this.askerValue = state.incomingRequests.find((request) => request.profile.code === code)?.profile;
        this.stageValue = { kind: "confirming" };
      }
    } else if (state.party?.code === code) {
      this.stageValue = { kind: "finished", outcome: { kind: "alreadyInParty" } };
    } else {
      this.current = state.party?.code;
      this.stageValue = { kind: "confirming" };
    }
  }

  /** The user confirmed, or asked to try a failed request again. Returns whether to send the request now. */
  begin(): boolean {
    const stage = this.stageValue;
    const retryable = stage.kind === "refused" && stage.refusal.kind === "failed" && stage.refusal.error.isTransient;
    if (stage.kind !== "confirming" && !retryable) return false;
    this.stageValue = { kind: "working" };
    return true;
  }

  /** The server's answer to asking the person behind the link. */
  didAsk(addition: PartyFriendAddition): void {
    if (this.stageValue.kind !== "working" || this.invite.kind !== "addFriend") return;
    const outcome: InviteOutcome =
      addition.kind === "friends" ? { kind: "added", profile: addition.profile } : { kind: addition.kind, profile: addition.profile };
    this.stageValue = { kind: "finished", outcome };
  }

  didJoin(party: Party): void {
    if (this.stageValue.kind !== "working" || this.invite.kind !== "joinParty") return;
    this.stageValue = { kind: "finished", outcome: { kind: "joined", party } };
  }

  didFail(error: PartyError): void {
    if (this.stageValue.kind !== "working") return;
    this.stageValue = { kind: "refused", refusal: { kind: "failed", error } };
  }

  /* MARK: Copy */

  /** Whether the flow is over and only needs closing. */
  get isDone(): boolean {
    const stage = this.stageValue;
    switch (stage.kind) {
      case "finished":
        return true;
      case "refused":
        return stage.refusal.kind !== "failed" || !stage.refusal.error.isTransient;
      case "ageCheck":
        return stage.tooYoungUntil !== undefined;
      default:
        return false;
    }
  }

  /** The person behind the link, once known. */
  get person(): PartyProfile | undefined {
    const stage = this.stageValue;
    if (stage.kind !== "finished") return undefined;
    const outcome = stage.outcome;
    return outcome.kind === "added" || outcome.kind === "alreadyFriends" || outcome.kind === "requested" ? outcome.profile : undefined;
  }

  get title(): string {
    const stage = this.stageValue;
    switch (stage.kind) {
      case "needsParty":
        return tr("Turn on Party?");
      case "connecting":
        return tr("Connecting to Party");
      case "unavailable":
        return tr("Party isn't available");
      case "ageCheck":
        return stage.tooYoungUntil === undefined ? tr("One question first") : tr("Party isn't available");
      case "confirming":
      case "working":
        if (this.invite.kind === "joinParty") return tr("Join this party?");
        return this.askerValue === undefined ? tr("Add a friend?") : tr("%@ wants to be friends", this.askerValue.name);
      case "finished":
        switch (stage.outcome.kind) {
          case "requested":
            return tr("Request sent to %@", stage.outcome.profile.name);
          case "added":
            return tr("%@ is now your friend", stage.outcome.profile.name);
          case "alreadyFriends":
            return tr("%@ is already your friend", stage.outcome.profile.name);
          case "joined":
            return tr("You joined the party");
          case "alreadyInParty":
            return tr("You're already in this party");
        }
        break;
      case "refused":
        switch (stage.refusal.kind) {
          case "ownCode":
            return tr("That's your own link");
          case "blocked":
            return tr("You blocked %@", stage.refusal.name);
          case "failed":
            return this.invite.kind === "addFriend" ? tr("Couldn't add this friend") : tr("Couldn't join this party");
        }
    }
    return "";
  }

  get message(): string {
    const stage = this.stageValue;
    switch (stage.kind) {
      case "needsParty":
        return this.invite.kind === "addFriend"
          ? tr("Party lets you study beside friends. Turn it on to add this friend.")
          : tr("Party lets you study beside friends. Turn it on to join this party.");
      case "connecting":
        return tr("One moment.");
      case "ageCheck":
        return stage.tooYoungUntil === undefined
          ? tr("The Party tab asks when you were born before you join. Then open the link again.")
          : tr("Party is for people %lld and older.", MINIMUM_AGE);
      case "unavailable":
        if (stage.error.kind === "invalidRequest") return tr("Check the server in Party options.");
        return partyErrorMessage(stage.error);
      case "confirming":
      case "working":
        if (this.invite.kind === "addFriend") {
          return this.askerValue === undefined
            ? tr("Friend code %@. Once they accept, you'll see each other's pets and study time.", display(this.invite.code))
            : tr("Friend code %@. Accept to see each other's pets and study time.", display(this.invite.code));
        }
        return this.current === undefined
          ? tr("Party code %@. Study together with everyone in it.", this.invite.code)
          : tr("Party code %@. Study together with everyone in it. You'll leave your current party.", this.invite.code);
      case "finished": {
        const outcome = stage.outcome;
        switch (outcome.kind) {
          case "added":
          case "alreadyFriends":
            return tr("You'll see %@ in your Party tab.", outcome.profile.petName);
          case "requested":
            return tr("You'll be friends once they accept.");
          case "joined": {
            const others = outcome.party.members.length - 1;
            return others < 1 ? tr("You're the only one here for now.") : tr("%lld friends are here with you.", others);
          }
          case "alreadyInParty":
            return tr("Nothing to do.");
        }
        break;
      }
      case "refused":
        switch (stage.refusal.kind) {
          case "ownCode":
            return tr("Share it with a friend so they can add you.");
          case "blocked":
            return tr("Unblock them in Party options to add them again.");
          case "failed":
            return failedMessage(stage.refusal.error);
        }
    }
    return "";
  }

  /** The main button, or undefined when there is nothing to do but close. */
  get primaryTitle(): string | undefined {
    const stage = this.stageValue;
    switch (stage.kind) {
      case "needsParty":
        return tr("Turn On Party");
      case "unavailable":
        return stage.error.isTransient ? tr("Try Again") : undefined;
      case "ageCheck":
        return stage.tooYoungUntil === undefined ? tr("Open Party") : undefined;
      case "confirming":
      case "working":
        if (this.invite.kind === "joinParty") return tr("Join Party");
        return this.askerValue === undefined ? tr("Add Friend") : tr("Accept");
      case "refused":
        return stage.refusal.kind === "failed" && stage.refusal.error.isTransient ? tr("Try Again") : undefined;
      default:
        return undefined;
    }
  }

  /** The other button: "Not Now" while asking, "Done" once over. */
  get dismissTitle(): string {
    return this.isDone ? tr("Done") : tr("Not Now");
  }
}

/** Server refusals in the words of an invite: a code from a link most likely expired or was changed. */
function failedMessage(error: PartyError): string {
  switch (error.kind) {
    case "unknownCode":
      return tr("This link doesn't match anyone now. Ask your friend for a new one.");
    case "partyNotFound":
      return tr("That party has ended. Ask for a new link.");
    case "rateLimited":
      return tr("Too many tries for now. Wait a minute, then try again.");
    case "selfFriend":
      return tr("That's your own link.");
    default:
      return partyErrorMessage(error);
  }
}
