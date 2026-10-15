import { StudyMethod } from "./studyMethod";
import { studyMethodDefinitions as file } from "./studyMethodDefinitions";
import { intDivide, swiftInt } from "./swiftMath";

/** Allowed Timer lengths, in minutes. */
export const TIMER_MIN_MINUTES: number = file.timer.minMinutes;
export const TIMER_MAX_MINUTES: number = file.timer.maxMinutes;

/**
 * Port of StudyTimerLength: how long the plain Timer method counts down, in
 * whole minutes. One click picks a common length from `presets`, and the
 * stepper reaches any other in a few clicks (single minutes up to 10, then
 * steps of 5). Clamped on construction, so a saved value can never make a
 * zero-length countdown.
 */
export class StudyTimerLength {
  readonly minutes: number;

  constructor(minutes: number) {
    this.minutes = Math.min(Math.max(minutes, TIMER_MIN_MINUTES), TIMER_MAX_MINUTES);
  }

  /** The one-click lengths the Timer offers. */
  static readonly presets: readonly number[] = file.timer.presetMinutes;

  /** Where a fresh Timer starts: the Timer preset's length. */
  static get standard(): StudyTimerLength {
    return new StudyTimerLength(swiftInt((StudyMethod.preset("timer").duration("focus") ?? 600) / 60));
  }

  /** Whether this is one of the one-click presets. */
  get isPreset(): boolean {
    return StudyTimerLength.presets.includes(this.minutes);
  }

  /** The length one stepper click up or down makes, snapping an odd value like 23 to 20 or 25. */
  stepped(up: boolean): StudyTimerLength {
    const minutes = this.minutes;
    let value: number;
    if (up) {
      value = minutes < 10 ? minutes + 1 : (intDivide(minutes, 5) + 1) * 5;
    } else {
      value = minutes <= 10 ? minutes - 1 : intDivide(minutes - 1, 5) * 5;
    }
    return new StudyTimerLength(value);
  }

  /** Whether one click in that direction would change the length. */
  canStep(up: boolean): boolean {
    return this.stepped(up).minutes !== this.minutes;
  }

  /** The Timer method this length makes. */
  get method(): StudyMethod {
    return StudyMethod.timer(this.minutes * 60);
  }

  /** Decodes a saved length (a bare integer), clamping it. */
  static fromJSON(value: unknown): StudyTimerLength | undefined {
    return typeof value === "number" && Number.isInteger(value) ? new StudyTimerLength(value) : undefined;
  }

  toJSON(): number {
    return this.minutes;
  }
}
