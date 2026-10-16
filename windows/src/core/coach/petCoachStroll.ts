import type { Instant, Seconds } from "../time";

/*
 * Port of PetCoachStroll: the coach overlay's little play. The pet trots
 * out from under the island along the top of the screen, stops to say its
 * line, then trots back.
 *
 * A value of timestamps, so the overlay only asks "where is the pet at
 * `date`?" and every frame (and every snapshot) is deterministic. Offsets
 * are in logical pixels from the island's edge, growing away from it.
 */

export type PetCoachStrollPhase =
  | "walkingOut"
  /** Standing still with the speech bubble up. */
  | "talking"
  | "walkingBack"
  /** Back under the island; the overlay can close. */
  | "finished";

/** Which way the pet faces. The walk clip faces left, so `awayFromNotch` draws it mirrored right of the island. */
export type PetCoachStrollHeading = "awayFromNotch" | "towardNotch";

export class PetCoachStroll {
  /** After a hold ends the bubble stays at least this long, so moving the pointer away never snaps it shut mid-sentence. */
  static readonly lingerAfterHold: Seconds = 1.5;

  readonly startedAt: Instant;
  /** How far from the edge the pet stops to talk. */
  readonly distance: number;
  /** Walking speed per second. */
  readonly speed: number;
  /** How long the bubble stays up when nobody answers it. */
  readonly talkDuration: Seconds;
  private dismissedAtValue: Instant | undefined;
  private heldSinceValue: Instant | undefined;
  private heldForValue: Seconds = 0;

  /** A calm trot: 96 at 64 per second takes 1.5 s each way, quick enough to not be in the way and slow enough to read as a walk. */
  constructor(startedAt: Instant, options: { distance?: number; speed?: number; talkDuration?: Seconds } = {}) {
    this.startedAt = startedAt;
    this.distance = Math.max(options.distance ?? 96, 0);
    this.speed = Math.max(options.speed ?? 64, 1);
    this.talkDuration = Math.max(options.talkDuration ?? 12, 0);
  }

  /** When the user answered (or dismissed) the bubble, if they did. */
  get dismissedAt(): Instant | undefined {
    return this.dismissedAtValue;
  }

  /** When the pointer came to rest on the bubble, while it is still there. Holding stops the talking clock. */
  get heldSince(): Instant | undefined {
    return this.heldSinceValue;
  }

  /** Talk time added by earlier holds. */
  get heldFor(): Seconds {
    return this.heldForValue;
  }

  /** Seconds for the full walk one way. */
  get walkDuration(): Seconds {
    return this.distance / this.speed;
  }

  /** The pet arrives at its spot and the bubble appears. */
  get arrivesAt(): Instant {
    return this.startedAt + this.walkDuration;
  }

  /** When the pet turns to walk home: on time, or early once dismissed. Dismissing mid-walk turns it around where it stands. */
  get turnsBackAt(): Instant {
    const unanswered = this.heldSinceValue === undefined ? this.arrivesAt + this.talkDuration + this.heldForValue : Infinity;
    if (this.dismissedAtValue === undefined) return unanswered;
    return Math.min(Math.max(this.dismissedAtValue, this.startedAt), unanswered);
  }

  /** Back under the island. */
  get endsAt(): Instant {
    const turn = this.turnsBackAt;
    return turn + this.offsetWalkingOut(turn) / this.speed;
  }

  /** Ends the bubble early: the pet turns around now. Only the first dismissal counts, so a double click can't restart the walk. */
  dismiss(date: Instant): void {
    if (this.dismissedAtValue === undefined) this.dismissedAtValue = date;
  }

  /** Keeps the bubble up while the pointer rests on it: only while talking and not dismissed. */
  hold(date: Instant): void {
    if (this.heldSinceValue !== undefined || this.dismissedAtValue !== undefined || this.phase(date) !== "talking") return;
    this.heldSinceValue = date;
  }

  /** The pointer left the bubble: the talking clock runs again, with at least `lingerAfterHold` left. */
  release(date: Instant): void {
    const heldSince = this.heldSinceValue;
    if (heldSince === undefined) return;
    this.heldSinceValue = undefined;
    this.heldForValue += Math.max(date - heldSince, 0);
    const left = this.arrivesAt + this.talkDuration + this.heldForValue - date;
    if (left < PetCoachStroll.lingerAfterHold) this.heldForValue += PetCoachStroll.lingerAfterHold - left;
  }

  /** Seconds the bubble has been talking at `date`, not counting holds: what moves a two-part line on to its second part. */
  talkElapsed(date: Instant): Seconds {
    const clock = Math.min(date, this.heldSinceValue ?? date);
    return Math.max(clock - this.arrivesAt - this.heldForValue, 0);
  }

  /** When the bubble will have talked for `seconds`, or undefined while held (the clock is stopped). */
  dateAfterTalking(seconds: Seconds): Instant | undefined {
    if (this.heldSinceValue !== undefined) return undefined;
    return this.arrivesAt + seconds + this.heldForValue;
  }

  phase(date: Instant): PetCoachStrollPhase {
    if (date >= this.endsAt) return "finished";
    if (date >= this.turnsBackAt) return "walkingBack";
    if (date >= this.arrivesAt) return "talking";
    return "walkingOut";
  }

  /** Distance from the edge at `date`: 0 before the start and after the end. */
  offset(date: Instant): number {
    switch (this.phase(date)) {
      case "walkingOut":
      case "talking":
        return this.offsetWalkingOut(date);
      case "walkingBack": {
        const turn = this.turnsBackAt;
        return Math.max(this.offsetWalkingOut(turn) - (date - turn) * this.speed, 0);
      }
      case "finished":
        return 0;
    }
  }

  heading(date: Instant): PetCoachStrollHeading {
    const phase = this.phase(date);
    return phase === "walkingOut" || phase === "talking" ? "awayFromNotch" : "towardNotch";
  }

  /** Whether the speech bubble shows at `date`. */
  showsBubble(date: Instant): boolean {
    return this.phase(date) === "talking";
  }

  private offsetWalkingOut(date: Instant): number {
    const walked = Math.max(date - this.startedAt, 0) * this.speed;
    return Math.min(walked, this.distance);
  }
}
