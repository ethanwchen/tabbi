import { tr } from "../localization/tr";
import type { Instant, Seconds } from "../time";
import type { PartySessionCompletion } from "./partySessionTracker";

/*
 * Port of PartyTeamCelebration: the short "Great job, team!" moment after a
 * shared session runs to its end: what it says and how long it stays.
 */
export class PartyTeamCelebration {
  /** How long the message stays before the panel goes back to normal. */
  static readonly displayDuration: Seconds = 8;

  readonly completion: PartySessionCompletion;
  /** Pet points earned for the session; 0 when the stay was too short to pay. */
  readonly points: number;
  /** The user's pet name, for "+20 points for Miso". */
  readonly petName: string | undefined;
  /** When the celebration started. */
  readonly date: Instant;

  constructor(completion: PartySessionCompletion, points: number, date: Instant, petName?: string) {
    this.completion = completion;
    this.points = Math.max(points, 0);
    const name = petName?.trim() ?? "";
    this.petName = name === "" ? undefined : name;
    this.date = date;
  }

  /** "Great job, team!", or "Great job!" when nobody else studied along. */
  get title(): string {
    return this.completion.friendCount > 0 ? tr("Great job, team!") : tr("Great job!");
  }

  /** What was earned and how: "+20 points for Miso · 25 min with 2 friends". */
  get detail(): string {
    const parts: string[] = [];
    if (this.points > 0) {
      parts.push(this.petName === undefined ? tr("+%lld points", this.points) : tr("+%lld points for %@", this.points, this.petName));
    }
    const minutes = this.completion.minutes;
    if (this.completion.friendCount === 0) {
      parts.push(tr("%lld min on your own", minutes));
    } else {
      const company = tr("with %lld friends", this.completion.friendCount);
      parts.push(tr("%lld min %@", minutes, company));
    }
    return parts.join(" · ");
  }

  /** Whether the message is still up at `now`. */
  isShowing(now: Instant): boolean {
    return now >= this.date && now - this.date < PartyTeamCelebration.displayDuration;
  }

  /** When the message goes away. */
  get endsAt(): Instant {
    return this.date + PartyTeamCelebration.displayDuration;
  }
}
