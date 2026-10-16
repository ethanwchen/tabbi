import { REFERENCE_DATE_OFFSET } from "../pets/petUnlocks";
import type { JSONObject } from "../persistence/json";
import type { Instant, Seconds } from "../time";
import type { RandomSource } from "../motivation/randomSource";
import type { CoachAppCategory } from "./coachAppList";
import { pickCoachMessage, STANDARD_COACH_LINES, type PetCoachMessage, type PetCoachNudgeKind } from "./petCoachMessages";
import { PET_COACH_SNOOZE_DURATION, type PetCoachReply } from "./petCoachReply";

/*
 * Port of PetCoach.swift: when the study pet nudges, and with what.
 */

/** Where the study timer is, as far as the coach cares. */
export type PetCoachStudyState =
  /** A focus or review phase is running. The only state the coach nudges in. */
  | "focusing"
  /** A break is running. Distracting apps are exactly what breaks are for. */
  | "onBreak"
  | "paused"
  | "notStudying";

/**
 * One reading of the world, taken by the app every few seconds while a
 * session runs: idle seconds and the frontmost app's executable from the
 * host, neither of which needs a permission prompt.
 */
export interface PetCoachInput {
  readonly now: Instant;
  /** Seconds since the last keyboard, mouse or touch input. */
  readonly idleSeconds: Seconds;
  readonly frontmost: CoachAppCategory;
  readonly study: PetCoachStudyState;
  /** Deep focus: long reading stretches are expected, so idle checks wait much longer. */
  readonly deepFocus: boolean;
}

/**
 * Timing for the coach. The standard rules follow the research notes: the
 * pet looks over after 30 s in a distracting app, says something at 2 min,
 * offers to pause at 5 min; asks "still studying?" after 2 idle minutes and
 * pauses the timer after 5; at most one new nudge every 10 minutes.
 */
export interface PetCoachRules {
  readonly lookOverAfter: Seconds;
  readonly distractionNudgeAfter: Seconds;
  readonly offerPauseAfter: Seconds;
  readonly idleCheckAfter: Seconds;
  readonly idleAutoPauseAfter: Seconds;
  readonly deepFocusIdleCheckAfter: Seconds;
  readonly deepFocusIdleAutoPauseAfter: Seconds;
  /** Minimum gap before the first bubble of a new episode. */
  readonly minimumNudgeInterval: Seconds;
  /** Minimum gap before the next, kinder step within the same episode. */
  readonly escalationGap: Seconds;
  /** Speech bubbles allowed in any rolling hour; past this the pet goes quiet rather than nag. */
  readonly maxNudgesPerHour: number;
}

export const STANDARD_COACH_RULES: PetCoachRules = {
  lookOverAfter: 30,
  distractionNudgeAfter: 2 * 60,
  offerPauseAfter: 5 * 60,
  idleCheckAfter: 2 * 60,
  idleAutoPauseAfter: 5 * 60,
  deepFocusIdleCheckAfter: 10 * 60,
  deepFocusIdleAutoPauseAfter: 20 * 60,
  minimumNudgeInterval: 10 * 60,
  escalationGap: 2 * 60,
  maxNudgesPerHour: 3,
};

const RULE_KEYS = Object.keys(STANDARD_COACH_RULES) as (keyof PetCoachRules)[];

/** A speech bubble the pet should show. */
export interface PetCoachNudge {
  readonly kind: PetCoachNudgeKind;
  readonly message: PetCoachMessage;
}

/** Whether the app should pause the study timer along with this bubble. */
export function nudgePausesTimer(nudge: PetCoachNudge): boolean {
  return nudge.kind === "autoPause";
}

/** What the pet does after an evaluation: nothing, a silent glance, or a bubble. */
export type PetCoachDecision =
  | { readonly type: "none" }
  | { readonly type: "lookOver" }
  | { readonly type: "nudge"; readonly nudge: PetCoachNudge };

const NONE: PetCoachDecision = { type: "none" };
const LOOK_OVER: PetCoachDecision = { type: "lookOver" };

/** The decision's bubble, if it has one. */
export function decisionNudge(decision: PetCoachDecision): PetCoachNudge | undefined {
  return decision.type === "nudge" ? decision.nudge : undefined;
}

/** How far a distracting-app episode has gone, in order. */
export const DISTRACTION_STEPS = ["none", "lookedOver", "nudged", "offeredPause"] as const;
export type DistractionStep = (typeof DISTRACTION_STEPS)[number];

/** How far an idle episode has gone, in order. */
export const IDLE_STEPS = ["none", "asked", "paused"] as const;
export type IdleStep = (typeof IDLE_STEPS)[number];

const distractionRank = (step: DistractionStep) => DISTRACTION_STEPS.indexOf(step);
const idleRank = (step: IdleStep) => IDLE_STEPS.indexOf(step);

/** How many line ids to remember for variety. */
const MESSAGE_MEMORY = 8;

/**
 * Decides when the study pet nudges, and with what.
 *
 * Feed it a `PetCoachInput` every few seconds while a session runs. It
 * tracks two kinds of episodes: time in a distracting app (look over, then
 * a bubble, then an offer to pause) and time without input (ask, then pause
 * the timer). Each step fires once per episode and steps up one at a time,
 * so the tone only ever gets kinder: the last step is always an offer to
 * rest, never a scolding. Rate limits keep it rare, and snooze or the
 * per-session "do not nudge" switch silence it completely.
 *
 * Idle never means distracted; it only triggers a question. Cooldowns and
 * snooze survive a relaunch through `toJSON`; open episodes are not saved,
 * since carrying them into the next phase would skip its grace period.
 */
export class PetCoach {
  /** How often the app samples idle time and the frontmost app while a focus phase runs; the shortest threshold is 30 s. */
  static readonly sampleInterval: Seconds = 5;
  /** How long a celebration bubble stays up, so it never stands between the user and their work. */
  static readonly celebrationDuration: Seconds = 4;
  /** How long a Cat wisdom line stays up after the celebration. */
  static readonly wisdomDuration: Seconds = 6;

  rules: PetCoachRules;
  /** The per-session "Do not nudge" switch. */
  nudgesEnabled: boolean;
  private snoozedUntilValue: Instant | undefined;
  private lastNudgeAtValue: Instant | undefined;
  private recentNudgesValue: Instant[] = [];
  private recentMessageIDsValue: string[] = [];
  private distractionStartedAtValue: Instant | undefined;
  private distractionStepValue: DistractionStep = "none";
  private idleStepValue: IdleStep = "none";

  constructor(rules: PetCoachRules = STANDARD_COACH_RULES, nudgesEnabled = true) {
    this.rules = rules;
    this.nudgesEnabled = nudgesEnabled;
  }

  get snoozedUntil(): Instant | undefined {
    return this.snoozedUntilValue;
  }

  get lastNudgeAt(): Instant | undefined {
    return this.lastNudgeAtValue;
  }

  /** When each bubble in the last hour was shown, oldest first. */
  get recentNudges(): readonly Instant[] {
    return this.recentNudgesValue;
  }

  /** Ids of recently used lines, oldest first, so lines don't repeat. */
  get recentMessageIDs(): readonly string[] {
    return this.recentMessageIDsValue;
  }

  /** When the current distracting-app episode began, if one is going. */
  get distractionStartedAt(): Instant | undefined {
    return this.distractionStartedAtValue;
  }

  get distractionStep(): DistractionStep {
    return this.distractionStepValue;
  }

  get idleStep(): IdleStep {
    return this.idleStepValue;
  }

  snooze(duration: Seconds, now: Instant): void {
    this.snoozeUntil(now + Math.max(0, duration));
  }

  snoozeUntil(date: Instant): void {
    this.snoozedUntilValue = date;
  }

  endSnooze(): void {
    this.snoozedUntilValue = undefined;
  }

  isSnoozed(now: Instant): boolean {
    return this.snoozedUntilValue !== undefined && now < this.snoozedUntilValue;
  }

  /**
   * Updates episodes from `input` and returns what the pet should do now.
   * Bubbles pick from `lines`, e.g. `coachLines(kitSettings)` for the
   * active kit's flavor.
   */
  evaluate(input: PetCoachInput, random: RandomSource, lines: readonly PetCoachMessage[] = STANDARD_COACH_LINES): PetCoachDecision {
    const now = input.now;
    this.recentNudgesValue = this.recentNudgesValue.filter((date) => now - date < 3600);
    if (this.snoozedUntilValue !== undefined && now >= this.snoozedUntilValue) this.snoozedUntilValue = undefined;

    if (input.study !== "focusing") {
      this.endEpisodes();
      return NONE;
    }

    if (input.frontmost === "distracting") {
      if (this.distractionStartedAtValue === undefined) this.distractionStartedAtValue = now;
    } else {
      this.distractionStartedAtValue = undefined;
      this.distractionStepValue = "none";
    }
    const idle = this.idleThresholds(input.deepFocus);
    if (input.idleSeconds < idle.check) this.idleStepValue = "none";

    if (!this.nudgesEnabled || this.isSnoozed(now)) return NONE;

    return this.distractionDecision(now, lines, random) ?? this.idleDecision(input.idleSeconds, idle, now, lines, random);
  }

  /** Applies the coach's part of a bubble answer: snooze silences every nudge for 15 minutes. Timer changes are the app's job. */
  handle(reply: PetCoachReply, now: Instant): void {
    if (reply === "snooze") this.snooze(PET_COACH_SNOOZE_DURATION, now);
  }

  /**
   * Forgets any open distraction or idle episode, e.g. when the app stops
   * watching mid-phase, so the next focus phase starts with its full grace
   * period. Cooldowns and snooze are kept.
   */
  endEpisodes(): void {
    this.distractionStartedAtValue = undefined;
    this.distractionStepValue = "none";
    this.idleStepValue = "none";
  }

  private distractionDecision(now: Instant, lines: readonly PetCoachMessage[], random: RandomSource): PetCoachDecision | undefined {
    const start = this.distractionStartedAtValue;
    if (start === undefined) return undefined;
    const elapsed = now - start;
    const rules = this.rules;
    const target: DistractionStep =
      elapsed >= rules.offerPauseAfter
        ? "offeredPause"
        : elapsed >= rules.distractionNudgeAfter
          ? "nudged"
          : elapsed >= rules.lookOverAfter
            ? "lookedOver"
            : "none";
    const current = distractionRank(this.distractionStepValue);
    if (distractionRank(target) <= current) return undefined;
    const next = DISTRACTION_STEPS[current + 1];
    switch (next) {
      case "lookedOver":
        this.distractionStepValue = "lookedOver";
        return LOOK_OVER;
      case "nudged":
        if (!this.canNudge(now, rules.minimumNudgeInterval)) return undefined;
        this.distractionStepValue = "nudged";
        return { type: "nudge", nudge: this.makeNudge("distraction", now, lines, random) };
      case "offeredPause":
        if (!this.canNudge(now, rules.escalationGap)) return undefined;
        this.distractionStepValue = "offeredPause";
        return { type: "nudge", nudge: this.makeNudge("offerPause", now, lines, random) };
      default:
        return undefined;
    }
  }

  private idleDecision(
    idleSeconds: Seconds,
    thresholds: { check: Seconds; pause: Seconds },
    now: Instant,
    lines: readonly PetCoachMessage[],
    random: RandomSource,
  ): PetCoachDecision {
    if (idleSeconds >= thresholds.pause && idleRank(this.idleStepValue) < idleRank("paused")) {
      /* Not rate limited: pausing keeps the user's stats honest, and any input (including answering) ends the idle episode anyway. */
      this.idleStepValue = "paused";
      return { type: "nudge", nudge: this.makeNudge("autoPause", now, lines, random) };
    }
    if (
      idleSeconds >= thresholds.check &&
      idleRank(this.idleStepValue) < idleRank("asked") &&
      this.canNudge(now, this.rules.minimumNudgeInterval)
    ) {
      this.idleStepValue = "asked";
      return { type: "nudge", nudge: this.makeNudge("idleCheck", now, lines, random) };
    }
    return NONE;
  }

  private idleThresholds(deepFocus: boolean): { check: Seconds; pause: Seconds } {
    return deepFocus
      ? { check: this.rules.deepFocusIdleCheckAfter, pause: this.rules.deepFocusIdleAutoPauseAfter }
      : { check: this.rules.idleCheckAfter, pause: this.rules.idleAutoPauseAfter };
  }

  private canNudge(now: Instant, gap: Seconds): boolean {
    if (this.recentNudgesValue.length >= this.rules.maxNudgesPerHour) return false;
    return this.lastNudgeAtValue === undefined || now - this.lastNudgeAtValue >= gap;
  }

  private makeNudge(kind: PetCoachNudgeKind, now: Instant, lines: readonly PetCoachMessage[], random: RandomSource): PetCoachNudge {
    const message = pickCoachMessage(kind, random, lines, this.recentMessageIDsValue);
    this.recentMessageIDsValue.push(message.id);
    if (this.recentMessageIDsValue.length > MESSAGE_MEMORY) {
      this.recentMessageIDsValue.splice(0, this.recentMessageIDsValue.length - MESSAGE_MEMORY);
    }
    this.lastNudgeAtValue = now;
    this.recentNudgesValue.push(now);
    return { kind, message };
  }

  /** A copy with the same state, open episodes included. */
  clone(): PetCoach {
    const copy = PetCoach.fromJSON(this.toJSON());
    copy.distractionStartedAtValue = this.distractionStartedAtValue;
    copy.distractionStepValue = this.distractionStepValue;
    copy.idleStepValue = this.idleStepValue;
    return copy;
  }

  /**
   * The Mac's Codable shape: the rules, the switch, the snooze, cooldowns
   * and recent lines, with dates as seconds since 2001. Open episodes are
   * left out on purpose.
   */
  toJSON(): JSONObject {
    const json: JSONObject = {
      rules: { ...this.rules },
      nudgesEnabled: this.nudgesEnabled,
      recentNudges: this.recentNudgesValue.map(toMacDate),
      recentMessageIDs: [...this.recentMessageIDsValue],
    };
    if (this.snoozedUntilValue !== undefined) json.snoozedUntil = toMacDate(this.snoozedUntilValue);
    if (this.lastNudgeAtValue !== undefined) json.lastNudgeAt = toMacDate(this.lastNudgeAtValue);
    return json;
  }

  /** Reads `toJSON`'s shape; throws on a malformed one. */
  static fromJSON(json: unknown): PetCoach {
    const object = asObject(json, "coach");
    const rulesJSON = asObject(object.rules, "rules");
    const rules = Object.fromEntries(RULE_KEYS.map((key) => [key, finite(rulesJSON[key], key)])) as unknown as PetCoachRules;
    if (typeof object.nudgesEnabled !== "boolean") throw new TypeError("Invalid nudgesEnabled");
    const coach = new PetCoach(rules, object.nudgesEnabled);
    coach.snoozedUntilValue = optionalMacDate(object.snoozedUntil, "snoozedUntil");
    coach.lastNudgeAtValue = optionalMacDate(object.lastNudgeAt, "lastNudgeAt");
    coach.recentNudgesValue = numbers(object.recentNudges, "recentNudges").map(fromMacDate);
    const ids = object.recentMessageIDs;
    if (!Array.isArray(ids) || !ids.every((id): id is string => typeof id === "string")) throw new TypeError("Invalid recentMessageIDs");
    coach.recentMessageIDsValue = [...ids];
    return coach;
  }
}

/* Dates in the Mac's saves are seconds since 2001 (Foundation's default). */
export function toMacDate(instant: Instant): number {
  return instant - REFERENCE_DATE_OFFSET;
}

export function fromMacDate(value: number): Instant {
  return value + REFERENCE_DATE_OFFSET;
}

export function optionalMacDate(value: unknown, key: string): Instant | undefined {
  return value === undefined || value === null ? undefined : fromMacDate(finite(value, key));
}

export function asObject(value: unknown, key: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new TypeError(`Invalid ${key}`);
  return value as Record<string, unknown>;
}

export function finite(value: unknown, key: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new TypeError(`Invalid ${key}`);
  return value;
}

function numbers(value: unknown, key: string): number[] {
  if (!Array.isArray(value)) throw new TypeError(`Invalid ${key}`);
  return value.map((item) => finite(item, key));
}
