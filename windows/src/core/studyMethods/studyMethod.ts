import type { Seconds } from "../time";
import { studyMethodDefinitions as file } from "./studyMethodDefinitions";
import type { FlowtimeBreakScheme, StudyMethodFileMethod, StudyMethodKind } from "./studyMethodFile";
import { roundHalfAwayFromZero, swiftInt } from "./swiftMath";

export {
  FLOWTIME_BREAK_SCHEMES,
  STUDY_METHOD_KINDS,
  type FlowtimeBreakScheme,
  type StudyMethodKind,
} from "./studyMethodFile";

/** Port of StudyPhaseKind: what happens in one stretch of a study session, in `allCases` order. */
export const STUDY_PHASE_KINDS = ["focus", "review", "shortBreak", "longBreak"] as const;
export type StudyPhaseKind = (typeof STUDY_PHASE_KINDS)[number];

export function isBreakPhase(phase: StudyPhaseKind): boolean {
  return phase === "shortBreak" || phase === "longBreak";
}

/** Port of StudyFocusTarget: when a focus phase ends. */
export type StudyFocusTarget =
  /** After a fixed wall-clock length. */
  | { readonly kind: "duration"; readonly seconds: Seconds }
  /** When the user stops it (Flowtime). */
  | { readonly kind: "openEnded" }
  /** After this many Anki cards are answered (Anki sprint). */
  | { readonly kind: "cards"; readonly cards: number };

/** Port of StudyBreakRule: how long a regular break lasts. */
export type StudyBreakRule =
  | { readonly kind: "fixed"; readonly seconds: Seconds }
  /** Scales with how long the focus phase actually ran (Flowtime). */
  | { readonly kind: "proportional"; readonly scheme: FlowtimeBreakScheme }
  /** No break: the timer stops once focus ends (the plain Timer). */
  | { readonly kind: "none" };

/**
 * Port of FlowtimeBreakScheme.breakDuration(afterWorking:): the break after
 * `worked` seconds of focus, never shorter than a minute. `tiered` gives 5 min
 * after up to 25 min of work, 8 after up to 50, otherwise 10 (Smits, Wenzel and
 * de Bruin, 2025); `fifth` gives a fifth of the time worked in whole minutes.
 */
export function flowtimeBreakDuration(scheme: FlowtimeBreakScheme, worked: Seconds): Seconds {
  const minutes = Number.isFinite(worked) ? Math.max(worked, 0) / 60 : 0;
  switch (scheme) {
    case "tiered":
      if (minutes <= 25) return 5 * 60;
      if (minutes <= 50) return 8 * 60;
      return 10 * 60;
    case "fifth":
      return Math.max(roundHalfAwayFromZero(minutes / 5), 1) * 60;
  }
}

/** Shortest phase the engine accepts, so a bad custom value never makes a zero-length phase. */
export const MINIMUM_PHASE: Seconds = file.phaseMinutes.min * 60;
/** Longest timed phase accepted for a custom method (4 hours). */
export const MAXIMUM_PHASE: Seconds = file.phaseMinutes.max * 60;

/**
 * Clamps a phase length to 1 min...4 h. NaN, which min/max would pass
 * through, becomes the minimum so labels and timers never see a non-finite
 * length.
 */
export function clampedPhase(length: Seconds): Seconds {
  if (Number.isNaN(length)) return MINIMUM_PHASE;
  return Math.min(Math.max(length, MINIMUM_PHASE), MAXIMUM_PHASE);
}

/** Port of StudyLongBreak: a longer break that replaces every `every`-th regular break. */
export interface StudyLongBreak {
  readonly duration: Seconds;
  readonly every: number;
}

/** Builds a long break the way the Swift init does: 1 min...4 h, `every` at least 2. */
export function studyLongBreak(duration: Seconds, every: number): StudyLongBreak {
  return { duration: clampedPhase(duration), every: Math.max(every, 2) };
}

export interface StudyMethodInit {
  readonly kind: StudyMethodKind;
  readonly focus: StudyFocusTarget;
  readonly breakRule: StudyBreakRule;
  readonly longBreak?: StudyLongBreak;
  readonly review?: Seconds;
  readonly questionCount?: number;
}

function clampedFocus(focus: StudyFocusTarget): StudyFocusTarget {
  switch (focus.kind) {
    case "duration":
      return { kind: "duration", seconds: clampedPhase(focus.seconds) };
    case "openEnded":
      return focus;
    case "cards":
      return { kind: "cards", cards: Math.max(focus.cards, 1) };
  }
}

function clampedBreak(rule: StudyBreakRule): StudyBreakRule {
  return rule.kind === "fixed" ? { kind: "fixed", seconds: clampedPhase(rule.seconds) } : rule;
}

/**
 * Port of StudyMethod: the phase lengths and break rules the session engine
 * follows.
 *
 * A session cycles focus, (review), break, focus. `nextPhase` and
 * `duration` are the only rules the engine needs, so presets and custom
 * methods run through identical code. Fields are read-only and every
 * construction clamps, like the Swift init, so the limits hold however the
 * value was made. The long break is taken as given (build it with
 * `studyLongBreak`, which clamps), as in Swift.
 */
export class StudyMethod {
  readonly kind: StudyMethodKind;
  readonly focus: StudyFocusTarget;
  readonly breakRule: StudyBreakRule;
  readonly longBreak: StudyLongBreak | undefined;
  /** Length of the review phase that follows each focus phase, if any. */
  readonly review: Seconds | undefined;
  /** Questions per block, shown as a target ("40 questions"); not enforced. */
  readonly questionCount: number | undefined;

  constructor(init: StudyMethodInit) {
    this.kind = init.kind;
    this.focus = clampedFocus(init.focus);
    this.breakRule = clampedBreak(init.breakRule);
    this.longBreak = init.longBreak;
    this.review = init.review === undefined ? undefined : clampedPhase(init.review);
    this.questionCount = init.questionCount === undefined ? undefined : Math.max(init.questionCount, 1);
  }

  /**
   * The phase after `phase` ends. `completedFocusCount` is the focus phases
   * finished so far, including the one that just ended; it picks long breaks.
   */
  nextPhase(phase: StudyPhaseKind, completedFocusCount: number): StudyPhaseKind {
    if (!this.hasBreaks) return "focus";
    switch (phase) {
      case "focus":
      case "review": {
        if (phase === "focus" && this.review !== undefined) return "review";
        const longBreak = this.longBreak;
        if (longBreak !== undefined && completedFocusCount > 0 && completedFocusCount % longBreak.every === 0) {
          return "longBreak";
        }
        return "shortBreak";
      }
      case "shortBreak":
      case "longBreak":
        return "focus";
    }
  }

  /**
   * Wall-clock length of `phase`, or undefined when it has none (open-ended or
   * card-goal focus). `workedBeforeBreak` is how long the preceding focus
   * phase actually ran; only proportional breaks use it.
   */
  duration(phase: StudyPhaseKind, workedBeforeBreak: Seconds = 0): Seconds | undefined {
    switch (phase) {
      case "focus":
        return this.focus.kind === "duration" ? this.focus.seconds : undefined;
      case "review":
        return this.review;
      case "shortBreak":
        return this.shortBreakDuration(workedBeforeBreak);
      case "longBreak":
        return this.longBreak?.duration ?? this.shortBreakDuration(workedBeforeBreak);
    }
  }

  private shortBreakDuration(workedBeforeBreak: Seconds): Seconds | undefined {
    switch (this.breakRule.kind) {
      case "fixed":
        return this.breakRule.seconds;
      case "proportional":
        return flowtimeBreakDuration(this.breakRule.scheme, workedBeforeBreak);
      case "none":
        return undefined;
    }
  }

  /** Whether focus is followed by breaks; false for the plain Timer, which stops when its countdown ends. */
  get hasBreaks(): boolean {
    return this.breakRule.kind !== "none";
  }

  /** The card goal of an Anki sprint, or undefined for time-based methods. */
  get cardGoal(): number | undefined {
    return this.focus.kind === "cards" ? this.focus.cards : undefined;
  }

  /** Short label for the picker and the timer header, e.g. "25/5", "100 cards" or "10 min". */
  get rhythmLabel(): string {
    const minutes = (seconds: Seconds): string => `${swiftInt(roundHalfAwayFromZero(seconds / 60))}`;
    switch (this.focus.kind) {
      case "cards":
        return `${this.focus.cards} cards`;
      case "openEnded":
        return "Open";
      case "duration": {
        const length = this.focus.seconds;
        const pause = this.duration("shortBreak");
        if (pause === undefined) return `${minutes(length)} min`;
        if (this.review !== undefined) return `${minutes(length)}+${minutes(this.review)}/${minutes(pause)}`;
        return `${minutes(length)}/${minutes(pause)}`;
      }
    }
  }

  // MARK: Presets

  /** Every method in picker order, with default parameters, as `study-methods.json` lists them. */
  static get presets(): readonly StudyMethod[] {
    return PRESETS;
  }

  /** The default-parameter method for `kind`. The file defines every kind, so the fallback is never used. */
  static preset(kind: StudyMethodKind): StudyMethod {
    const found = StudyMethod.presets.find((method) => method.kind === kind) ?? StudyMethod.presets[0];
    if (found === undefined) throw new Error("study-methods.json has no methods");
    return found;
  }

  /** 25 min focus, 5 min break, 15 min long break after every 4th focus. */
  static get pomodoro(): StudyMethod {
    return StudyMethod.preset("pomodoro");
  }

  /** 52 min focus, 17 min break. */
  static get fiftyTwoSeventeen(): StudyMethod {
    return StudyMethod.preset("fiftyTwoSeventeen");
  }

  /** 90 min deep block, 20 min rest. */
  static get ultradian(): StudyMethod {
    return StudyMethod.preset("ultradian");
  }

  /** Open-ended focus; the break scales with the time worked. */
  static flowtime(scheme?: FlowtimeBreakScheme): StudyMethod {
    if (scheme === undefined) return StudyMethod.preset("flowtime");
    return new StudyMethod({ kind: "flowtime", focus: { kind: "openEnded" }, breakRule: { kind: "proportional", scheme } });
  }

  /** Answer `cards` Anki cards, then take the preset's break. */
  static ankiSprint(cards: number = DEFAULT_SPRINT_CARDS): StudyMethod {
    const preset = StudyMethod.preset("ankiSprint");
    return new StudyMethod({
      kind: "ankiSprint",
      focus: { kind: "cards", cards },
      breakRule: preset.breakRule,
      ...(preset.longBreak === undefined ? {} : { longBreak: preset.longBreak }),
    });
  }

  /** Up to 40 questions in 60 min, then an equally long review, then a 10 min break. */
  static get questionBlock(): StudyMethod {
    return StudyMethod.preset("questionBlock");
  }

  /** A user-defined rhythm. Lengths are clamped to 1 min...4 h. */
  static custom(focus: Seconds, breakLength: Seconds, longBreak?: StudyLongBreak): StudyMethod {
    return new StudyMethod({
      kind: "custom",
      focus: { kind: "duration", seconds: focus },
      breakRule: { kind: "fixed", seconds: breakLength },
      ...(longBreak === undefined ? {} : { longBreak }),
    });
  }

  /** One countdown of `length`, then the timer stops and waits; clamped to 1 min...4 h. */
  static timer(length: Seconds): StudyMethod {
    return new StudyMethod({ kind: "timer", focus: { kind: "duration", seconds: length }, breakRule: { kind: "none" } });
  }

  /**
   * Card goal that clears today's reviews and learning cards, the work that
   * should come before new cards. Falls back to the default goal when nothing
   * is due.
   */
  static sprintGoal(reviewDue: number, learnDue: number): number {
    const due = Math.max(reviewDue, 0) + Math.max(learnDue, 0);
    return due > 0 ? due : DEFAULT_SPRINT_CARDS;
  }
}

/** Port of StudyMethodFile.Method.method: the file's minutes made into a method. */
function methodFromFile(entry: StudyMethodFileMethod): StudyMethod {
  const focus: StudyFocusTarget =
    entry.focus.kind === "minutes"
      ? { kind: "duration", seconds: entry.focus.minutes * 60 }
      : entry.focus.kind === "cards"
        ? { kind: "cards", cards: entry.focus.cards }
        : { kind: "openEnded" };
  const breakRule: StudyBreakRule =
    entry.break.kind === "minutes"
      ? { kind: "fixed", seconds: entry.break.minutes * 60 }
      : entry.break.kind === "flowtime"
        ? { kind: "proportional", scheme: entry.break.scheme }
        : { kind: "none" };
  return new StudyMethod({
    kind: entry.kind,
    focus,
    breakRule,
    ...(entry.longBreak === undefined ? {} : { longBreak: studyLongBreak(entry.longBreak.minutes * 60, entry.longBreak.every) }),
    ...(entry.review === undefined ? {} : { review: entry.review * 60 }),
    ...(entry.questionCount === undefined ? {} : { questionCount: entry.questionCount }),
  });
}

/* Built after the class, since building a method needs the class itself. */
const PRESETS: readonly StudyMethod[] = file.methods.map(methodFromFile);

/** Default card goal when no due counts are known. */
export const DEFAULT_SPRINT_CARDS: number = StudyMethod.preset("ankiSprint").cardGoal ?? 1;
/** A sprint suggests a break after this many cards... */
export const SPRINT_BREAK_CARDS: number = file.ankiSprint.breakAfterCards;
/** ...or after this long, whichever comes first. */
export const SPRINT_BREAK_INTERVAL: Seconds = file.ankiSprint.breakAfterMinutes * 60;
