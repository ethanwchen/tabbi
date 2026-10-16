import { tr } from "../localization/tr";
import type { ModuleID } from "../modules/moduleId";
import type { PetProfile } from "../pets/petProfile";
import { STUDY_METHOD_KINDS, type StudyMethodKind } from "../studyMethods/studyMethodFile";
import { StudyMethodInfo } from "../studyMethods/studyMethodInfo";
import type { Instant, Seconds } from "../time";
import { ProvidedFocus } from "./providedFocus";

/** Port of ProvidedPartyPet: one pet in a `ProvidedParty`. */
export interface ProvidedPartyPet {
  /** Stable for the person, e.g. their friend code. */
  readonly id: string;
  readonly name: string;
  readonly pet: PetProfile;
  /** Offline, so their pet dozes. */
  readonly isAway: boolean;
}

function isStudyMethodKind(value: string): value is StudyMethodKind {
  return (STUDY_METHOD_KINDS as readonly string[]).includes(value);
}

/**
 * Port of ProvidedPartySession: a party's shared focus session as the user
 * takes part in it, one countdown the host started for everyone. The Timer
 * tab shows it and the shared focus clock counts it in the closed island,
 * so neither needs to know about the Party module.
 */
export class ProvidedPartySession {
  /** The label the shared focus clock carries. */
  static readonly label = "Party focus";

  /** The study method id the host picked, e.g. `pomodoro`. */
  readonly method: string;
  readonly startedAt: Instant;
  readonly endsAt: Instant;
  /** The other members in the session: "with 2 friends". */
  readonly friendCount: number;
  /** Who started it, for "Maya's session"; undefined when I did. */
  readonly hostName: string | undefined;

  constructor(init: { method: string; startedAt: Instant; endsAt: Instant; friendCount: number; hostName?: string | undefined }) {
    this.method = init.method;
    this.startedAt = init.startedAt;
    this.endsAt = init.endsAt;
    this.friendCount = Math.max(init.friendCount, 0);
    this.hostName = init.hostName;
  }

  /** Whether I started the session (and so can end it for everyone). */
  get isHost(): boolean {
    return this.hostName === undefined;
  }

  /** The full length of the shared phase. */
  get length(): Seconds {
    return Math.max(this.endsAt - this.startedAt, 0);
  }

  /** Time left at `now`, never negative. */
  remaining(now: Instant): Seconds {
    return Math.max(this.endsAt - now, 0);
  }

  /** The method's display name, e.g. "Pomodoro"; "Focus" for an id this version doesn't know. */
  get methodName(): string {
    return isStudyMethodKind(this.method) ? StudyMethodInfo.info(this.method).displayName : tr("Focus");
  }

  /** "with 2 friends", "with 1 friend", or "on your own" once everyone else has left. */
  get companyLine(): string {
    return this.friendCount === 0 ? tr("on your own") : tr("with %lld friends", this.friendCount);
  }

  /**
   * The session as the shared focus clock: a focus countdown to its end. It
   * never counts completions, since Party awards a finished shared session
   * itself, so the pet's ledger never pays it twice.
   */
  focus(source: ModuleID): ProvidedFocus {
    return new ProvidedFocus({
      source,
      phase: "focus",
      label: ProvidedPartySession.label,
      clock: { kind: "countdown", endsAt: this.endsAt },
      phaseLength: this.length,
    });
  }
}

/**
 * Port of ProvidedParty: the study party the user is in, so the closed
 * island can show the other members' pets beside the user's own. The
 * PartySource role.
 */
export class ProvidedParty {
  /** The user's pet first, then the other members' in roster order. */
  readonly pets: readonly ProvidedPartyPet[];
  /** The host's shared focus session while it runs and the user is in it; undefined otherwise. */
  readonly session: ProvidedPartySession | undefined;

  constructor(pets: readonly ProvidedPartyPet[], session?: ProvidedPartySession) {
    this.pets = pets;
    this.session = session;
  }

  /** Everyone in the party, the user included. */
  get memberCount(): number {
    return this.pets.length;
  }
}
