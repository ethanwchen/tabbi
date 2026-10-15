import { StudyCustomRhythm, presetMethod } from "./studyCustomRhythm";
import { StudyMethod } from "./studyMethod";
import { STUDY_METHOD_KINDS, type StudyMethodKind } from "./studyMethodFile";
import type { StudySession } from "./studySession";
import { StudyTimerLength } from "./studyTimerLength";

function isKind(value: unknown): value is StudyMethodKind {
  return typeof value === "string" && (STUDY_METHOD_KINDS as readonly string[]).includes(value);
}

/* Known methods from a kit's `methods` list, or undefined when the kit has no list. */
function kitKinds(section: unknown): StudyMethodKind[] | undefined {
  if (typeof section !== "object" || section === null) return undefined;
  const methods = (section as Record<string, unknown>).methods;
  return Array.isArray(methods) ? methods.filter(isKind) : undefined;
}

/**
 * Port of StudyMethodMenu.kitStartingKind(of:): the method a kit starts on, its
 * `method` if known, otherwise the first known one in `methods`. Takes the
 * kit's Study section (`moduleSettings.study`) as plain JSON.
 */
export function kitStartingKind(studySection: unknown): StudyMethodKind | undefined {
  if (typeof studySection === "object" && studySection !== null) {
    const method = (studySection as Record<string, unknown>).method;
    if (isKind(method)) return method;
  }
  return kitKinds(studySection)?.[0];
}

/**
 * Port of StudyMethodMenu: the study methods the Study timer offers and the one
 * it starts on. A kit picks these in its Study section; the menu is never
 * empty, since a kit that names no known method offers every preset.
 */
export class StudyMethodMenu {
  /** Offered methods in order, without duplicates; never empty. */
  readonly kinds: readonly StudyMethodKind[];
  /** Where a fresh timer starts; always one of `kinds`. */
  readonly startingKind: StudyMethodKind;

  constructor(kinds?: readonly StudyMethodKind[], starting?: StudyMethodKind) {
    const offered = [...new Set(kinds ?? [])];
    const list = offered.length === 0 ? StudyMethod.presets.map((method) => method.kind) : offered;
    const first = list[0];
    if (first === undefined) throw new Error("study-methods.json has no methods");
    this.kinds = list;
    this.startingKind = starting !== undefined && list.includes(starting) ? starting : first;
  }

  /** The menu a kit's Study section sets up; every preset when it says nothing. */
  static fromKit(studySection: unknown): StudyMethodMenu {
    return new StudyMethodMenu(kitKinds(studySection), kitStartingKind(studySection));
  }

  /** Every preset, starting on Pomodoro. */
  static get all(): StudyMethodMenu {
    return new StudyMethodMenu();
  }

  /** The offered methods for the picker, with Custom and the Timer on the user's lengths. */
  methods(custom: StudyCustomRhythm = StudyCustomRhythm.standard, timer: StudyTimerLength = StudyTimerLength.standard): StudyMethod[] {
    return this.kinds.map((kind) => presetMethod(kind, custom, timer));
  }

  offers(kind: StudyMethodKind): boolean {
    return this.kinds.includes(kind);
  }

  /**
   * The method a session should move to when this menu takes effect, or
   * undefined to leave it alone. A session whose clock has started is never
   * interrupted; a stopped one moves to `startingKind` when the kit was just
   * applied, and otherwise only when its method is no longer offered.
   */
  replacement(session: StudySession, kitApplied: boolean): StudyMethodKind | undefined {
    if (session.runState !== "idle" || session.phase !== "focus") return undefined;
    const current = session.method.kind;
    if (kitApplied) return current === this.startingKind ? undefined : this.startingKind;
    return this.offers(current) ? undefined : this.startingKind;
  }
}
