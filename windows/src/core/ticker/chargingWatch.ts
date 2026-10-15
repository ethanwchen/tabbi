import type { Instant, Seconds } from "../time";

/**
 * Port of ChargingWatch: decides when the pet sips from its mug because the
 * PC started charging, once per plug-in, when the power source switches
 * from the battery to a charger.
 *
 * The first reading only sets the baseline, so launching on a charger plays
 * nothing, and a desktop without a battery never switches. A cable that is
 * wiggled in and out cheers once per `cooldown`, not once per contact.
 */
export class ChargingWatch {
  /** The shortest time between two sips. */
  static readonly cooldown: Seconds = 60;

  /** The last reading, undefined before the first one. */
  private onCharger: boolean | undefined;
  private lastSip: Instant | undefined;

  /**
   * Records whether the PC draws power from a charger at `now`, and returns
   * true when that is a plug-in worth a sip. Undefined (the power source
   * can't be read) keeps the last reading.
   */
  update(reading: boolean | undefined, now: Instant): boolean {
    if (reading === undefined) return false;
    const previous = this.onCharger;
    this.onCharger = reading;
    if (!reading || previous !== false) return false;
    const lastSip = this.lastSip;
    if (lastSip !== undefined && now - lastSip < ChargingWatch.cooldown && now >= lastSip) return false;
    this.lastSip = now;
    return true;
  }
}
