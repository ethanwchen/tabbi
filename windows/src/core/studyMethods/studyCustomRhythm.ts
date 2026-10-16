import { StudyMethod, studyLongBreak } from "./studyMethod";
import { studyMethodDefinitions as file } from "./studyMethodDefinitions";
import { CUSTOM_RHYTHM_FIELDS, type CustomRhythmField, type StudyMethodKind } from "./studyMethodFile";
import { StudyTimerLength } from "./studyTimerLength";
import { intDivide, swiftInt } from "./swiftMath";

export { CUSTOM_RHYTHM_FIELDS, type CustomRhythmField } from "./studyMethodFile";

/** A Custom field's limits and step (minutes, or rounds for `longBreakEvery`). */
export function customFieldStepper(field: CustomRhythmField): { min: number; max: number; step: number } {
  const stepper = file.custom.fields[field];
  return { min: stepper.min, max: stepper.max, step: stepper.step };
}

function clampField(value: number, field: CustomRhythmField): number {
  const { min, max } = file.custom.fields[field];
  return Math.min(Math.max(value, min), max);
}

/** The long break a fresh rhythm keeps ready (15 min after every 4th round). */
export const DEFAULT_LONG_BREAK_MINUTES: number = swiftInt(file.custom.longBreak.minutes);
export const DEFAULT_LONG_BREAK_EVERY: number = file.custom.longBreak.every;

export interface StudyCustomRhythmInit {
  focusMinutes: number;
  breakMinutes: number;
  longBreakMinutes?: number;
  longBreakEvery?: number;
  hasLongBreak?: boolean;
}

/**
 * Port of StudyCustomRhythm: the lengths a user picks for the Custom study
 * method, in whole minutes on coarse steps. Every value is clamped on
 * construction, so a saved or hand-edited value can never make a zero-length
 * phase. The long break keeps its length and spacing while switched off.
 */
export class StudyCustomRhythm {
  readonly focusMinutes: number;
  readonly breakMinutes: number;
  readonly longBreakMinutes: number;
  /** A long break replaces every this-many-th regular break. */
  readonly longBreakEvery: number;
  readonly hasLongBreak: boolean;

  constructor(init: StudyCustomRhythmInit) {
    this.focusMinutes = clampField(init.focusMinutes, "focus");
    this.breakMinutes = clampField(init.breakMinutes, "shortBreak");
    this.longBreakMinutes = clampField(init.longBreakMinutes ?? DEFAULT_LONG_BREAK_MINUTES, "longBreak");
    this.longBreakEvery = clampField(init.longBreakEvery ?? DEFAULT_LONG_BREAK_EVERY, "longBreakEvery");
    this.hasLongBreak = init.hasLongBreak ?? false;
  }

  /** The Custom preset's lengths (30 min focus, 5 min break), with no long break. */
  static get standard(): StudyCustomRhythm {
    const preset = StudyMethod.preset("custom");
    const minutes = (phase: "focus" | "shortBreak"): number => swiftInt((preset.duration(phase) ?? 0) / 60);
    return new StudyCustomRhythm({ focusMinutes: minutes("focus"), breakMinutes: minutes("shortBreak") });
  }

  /** Decodes a saved rhythm, falling back to `standard` per missing field and clamping the rest. */
  static fromJSON(value: unknown): StudyCustomRhythm {
    const fallback = StudyCustomRhythm.standard;
    const entry = typeof value === "object" && value !== null ? (value as Record<string, unknown>) : {};
    const int = (key: string, otherwise: number): number => {
      const raw = entry[key];
      return typeof raw === "number" && Number.isInteger(raw) ? raw : otherwise;
    };
    return new StudyCustomRhythm({
      focusMinutes: int("focusMinutes", fallback.focusMinutes),
      breakMinutes: int("breakMinutes", fallback.breakMinutes),
      longBreakMinutes: int("longBreakMinutes", fallback.longBreakMinutes),
      longBreakEvery: int("longBreakEvery", fallback.longBreakEvery),
      hasLongBreak: typeof entry.hasLongBreak === "boolean" ? entry.hasLongBreak : fallback.hasLongBreak,
    });
  }

  toJSON(): Record<string, number | boolean> {
    return {
      focusMinutes: this.focusMinutes,
      breakMinutes: this.breakMinutes,
      longBreakMinutes: this.longBreakMinutes,
      longBreakEvery: this.longBreakEvery,
      hasLongBreak: this.hasLongBreak,
    };
  }

  /** The value of `field`. */
  value(field: CustomRhythmField): number {
    switch (field) {
      case "focus":
        return this.focusMinutes;
      case "shortBreak":
        return this.breakMinutes;
      case "longBreak":
        return this.longBreakMinutes;
      case "longBreakEvery":
        return this.longBreakEvery;
    }
  }

  equals(other: StudyCustomRhythm): boolean {
    return (
      CUSTOM_RHYTHM_FIELDS.every((field) => this.value(field) === other.value(field)) && this.hasLongBreak === other.hasLongBreak
    );
  }

  /** Whether moving `field` by `steps` clicks would change it. */
  canStep(field: CustomRhythmField, steps: number): boolean {
    return !this.stepped(field, steps).equals(this);
  }

  /** The rhythm with `field` moved by `steps` clicks, snapped to the field's step and kept in its range. */
  stepped(field: CustomRhythmField, steps: number): StudyCustomRhythm {
    const current = this.value(field);
    const { step } = file.custom.fields[field];
    /* Snap first, so a decoded 23 min focus steps to 25 or 20, not 28 or 18. */
    const snapped = intDivide(current, step) * step;
    let target: number;
    if (steps > 0) {
      target = snapped + steps * step;
    } else if (steps < 0 && snapped < current) {
      target = snapped + (steps + 1) * step;
    } else {
      target = snapped + steps * step;
    }
    return this.setting(field, target);
  }

  /** The rhythm with `field` set to `value`, clamped to its range. */
  setting(field: CustomRhythmField, value: number): StudyCustomRhythm {
    return new StudyCustomRhythm({
      focusMinutes: field === "focus" ? value : this.focusMinutes,
      breakMinutes: field === "shortBreak" ? value : this.breakMinutes,
      longBreakMinutes: field === "longBreak" ? value : this.longBreakMinutes,
      longBreakEvery: field === "longBreakEvery" ? value : this.longBreakEvery,
      hasLongBreak: this.hasLongBreak,
    });
  }

  /** The rhythm with the long break switched on or off. */
  withLongBreak(on: boolean): StudyCustomRhythm {
    return new StudyCustomRhythm({ ...this.toInit(), hasLongBreak: on });
  }

  private toInit(): StudyCustomRhythmInit {
    return {
      focusMinutes: this.focusMinutes,
      breakMinutes: this.breakMinutes,
      longBreakMinutes: this.longBreakMinutes,
      longBreakEvery: this.longBreakEvery,
      hasLongBreak: this.hasLongBreak,
    };
  }

  /** The Custom study method these lengths make. */
  get method(): StudyMethod {
    return StudyMethod.custom(
      this.focusMinutes * 60,
      this.breakMinutes * 60,
      this.hasLongBreak ? studyLongBreak(this.longBreakMinutes * 60, this.longBreakEvery) : undefined,
    );
  }
}

/** Port of StudyMethod.preset(_:custom:timer:): the preset, or the user's own lengths for Custom and the Timer. */
export function presetMethod(
  kind: StudyMethodKind,
  custom: StudyCustomRhythm,
  timer: StudyTimerLength = StudyTimerLength.standard,
): StudyMethod {
  switch (kind) {
    case "custom":
      return custom.method;
    case "timer":
      return timer.method;
    default:
      return StudyMethod.preset(kind);
  }
}
