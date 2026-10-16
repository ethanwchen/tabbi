// Port of ChargingWatchTests.swift: when plugging the PC in makes the pet sip from its mug.
import { describe, expect, it } from "vitest";
import { ChargingWatch } from "../../../src/core/ticker/chargingWatch";

const start = 1_800_000_000;
const at = (seconds: number) => start + seconds;

describe("ChargingWatch", () => {
  it("sips once on plugging in", () => {
    const watch = new ChargingWatch();
    expect(watch.update(false, start)).toBe(false);
    expect(watch.update(true, at(10)), "battery to charger is a plug-in").toBe(true);
    expect(watch.update(true, at(20)), "still on the charger: once per plug-in").toBe(false);
    expect(watch.update(true, at(600))).toBe(false);
  });

  it("plays nothing when launched on a charger or without a battery", () => {
    const watch = new ChargingWatch();
    expect(watch.update(true, start), "the first reading is only the baseline").toBe(false);
    expect(watch.update(true, at(60)), "a desktop never switches").toBe(false);
  });

  it("sips again on each new plug-in", () => {
    const watch = new ChargingWatch();
    watch.update(false, start);
    expect(watch.update(true, at(10))).toBe(true);
    expect(watch.update(false, at(3600))).toBe(false);
    expect(watch.update(true, at(7200))).toBe(true);
  });

  it("sips once per cooldown for a wiggled cable", () => {
    const watch = new ChargingWatch();
    watch.update(false, start);
    expect(watch.update(true, at(1))).toBe(true);
    expect(watch.update(false, at(2))).toBe(false);
    expect(watch.update(true, at(3)), "too soon after the last sip").toBe(false);
    expect(watch.update(false, at(4))).toBe(false);
    expect(watch.update(true, at(1 + ChargingWatch.cooldown))).toBe(true);
  });

  it("keeps the last reading when the source is unreadable", () => {
    const watch = new ChargingWatch();
    watch.update(false, start);
    expect(watch.update(undefined, at(5))).toBe(false);
    expect(watch.update(true, at(10)), "the battery reading still counts").toBe(true);
  });
});
