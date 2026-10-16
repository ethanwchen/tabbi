import { describe, expect, it } from "vitest";
import { PetCloset } from "../../../src/core/closet/petCloset";
import { PetMilestoneProgress } from "../../../src/core/closet/petLimited";
import { ACTIVITY_KINDS, ACTIVITY_UNITS, type ActivityRecord } from "../../../src/core/activity/activityRecord";
import { activity } from "../../support/activity";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { PetSave } from "../../../src/core/pets/petSave";
import { PetPointsLedger, StreakFreezePurchaseError } from "../../../src/core/pets/petUnlocks";
import { instantOf } from "../../../src/core/calendar/zonedCalendar";
import { dayKey, type DayCalendar } from "../../../src/core/streaks/dayCalendar";
import { StreakFreezeRules, StudyStreak } from "../../../src/core/streaks/studyStreak";

// Port of StreakFreezePurchaseTests: buying extra streak freezes with
// points and keeping them in the pet save.
const calendar: DayCalendar = { timeZone: "America/New_York", firstWeekday: 2 };

/** Noon on a day of October 2026 (Monday the 12th starts a week). */
function date(day: number): number {
  return instantOf({ year: 2026, month: 10, day: day, hour: 12, minute: 0 }, calendar.timeZone);
}

function streak(ledger: PetPointsLedger, days: number[], today: number): StudyStreak {
  return new StudyStreak(
    days.map((day) => dayKey(date(day), calendar)),
    ledger.streakFreezes,
    date(today),
    calendar,
  );
}

function freezeError(run: () => void): StreakFreezePurchaseError {
  try {
    run();
  } catch (error) {
    if (error instanceof StreakFreezePurchaseError) return error;
    throw error;
  }
  throw new Error("expected a StreakFreezePurchaseError");
}

describe("streak freezes: buying", () => {
  it("buying a freeze spends its price and holds it", () => {
    const ledger = new PetPointsLedger({ earned: 300 });
    ledger.buyStreakFreeze(streak(ledger, [12, 13], 14), date(14));
    expect(ledger.balance).toBe(300 - StreakFreezeRules.price());
    expect(ledger.streakFreezes).toEqual([date(14)]);
    expect(streak(ledger, [12, 13], 14).extraFreezes).toBe(1);
  });

  it("buying without enough points says how many are missing", () => {
    const ledger = new PetPointsLedger({ earned: 100 });
    const error = freezeError(() => ledger.buyStreakFreeze(streak(ledger, [13], 14), date(14)));
    expect(error.reason).toBe("notEnoughPoints");
    expect(error.missing).toBe(StreakFreezeRules.price() - 100);
    expect(ledger.balance, "a failed purchase spends nothing").toBe(100);
    expect(ledger.streakFreezes).toEqual([]);
  });

  it("buying stops at the holding limit", () => {
    const ledger = new PetPointsLedger({ earned: 1000 });
    for (let i = 0; i < StreakFreezeRules.maxHeld; i++) ledger.buyStreakFreeze(streak(ledger, [13], 14), date(14));
    const balance = ledger.balance;
    expect(freezeError(() => ledger.buyStreakFreeze(streak(ledger, [13], 14), date(14))).reason).toBe("holdingLimit");
    expect(ledger.balance).toBe(balance);
  });

  it("a used freeze makes room for another", () => {
    const ledger = new PetPointsLedger({ earned: 1000 });
    // Two extras bought on Monday the 12th, then Tuesday and Wednesday
    // missed: the week's free freeze covers one, an extra the other.
    ledger.buyStreakFreeze(streak(ledger, [12], 12), date(12));
    ledger.buyStreakFreeze(streak(ledger, [12], 12), date(12));
    const later = streak(ledger, [12, 15], 15);
    expect(later.length).toBe(2);
    expect(later.extraFreezes).toBe(1);
    expect(later.canBuyFreeze).toBe(true);
    ledger.buyStreakFreeze(later, date(15));
    expect(streak(ledger, [12, 15], 15).extraFreezes).toBe(2);
  });
});

describe("streak freezes: closet", () => {
  it("the closet buys against its own study days", () => {
    const records: ActivityRecord[] = [12, 13].map((day) => activity({
      id: `focus-${day}`,
      source: "focus",
      kind: ACTIVITY_KINDS.focusCompleted,
      end: date(day),
      quantity: 25,
      unit: ACTIVITY_UNITS.minutes,
    }));
    const progress = new PetMilestoneProgress(records, calendar);
    const closet = new PetCloset(
      new PetSave(new PetProfile("Mochi", "britishShorthair"), new PetPointsLedger({ earned: 200 })),
    );
    expect(closet.streak(progress, date(14), calendar).length).toBe(2);
    closet.buyStreakFreeze(progress, date(14), calendar);
    expect(closet.balance).toBe(200 - StreakFreezeRules.price());
    expect(closet.streak(progress, date(14), calendar).freezesReady).toBe(2);
  });
});

describe("streak freezes: saving", () => {
  it("freezes survive the save file", () => {
    const ledger = new PetPointsLedger({ earned: 300 });
    ledger.buyStreakFreeze(streak(ledger, [13], 14), date(14));
    const save = new PetSave(new PetProfile("Mochi", "britishShorthair"), ledger);
    const decoded = PetSave.decode(JSON.parse(save.encoded()));
    expect(decoded.ledger.streakFreezes).toEqual([date(14)]);
    expect(decoded.ledger.balance).toBe(ledger.balance);
  });

  it("older saves without freezes still load", () => {
    const ledger = PetPointsLedger.fromJSON({ earned: 50, spent: 10, purchased: [] });
    expect(ledger.streakFreezes).toEqual([]);
    expect(ledger.balance).toBe(40);
  });

  it("a save without freezes writes no freeze key", () => {
    expect(JSON.stringify(new PetPointsLedger({ earned: 50 }).toJSON())).not.toContain("streakFreezes");
  });

  it("an unreadable freeze list is dropped, not the ledger", () => {
    const ledger = PetPointsLedger.fromJSON({ earned: 50, spent: 0, streakFreezes: "soon" });
    expect(ledger.streakFreezes).toEqual([]);
    expect(ledger.balance).toBe(50);
  });

  it("freezes are written as seconds since 2001, the Mac's Date encoding", () => {
    const ledger = new PetPointsLedger({ earned: 300, streakFreezes: [date(14)] });
    expect(ledger.toJSON().streakFreezes).toEqual([date(14) - 978307200]);
  });

  // testAdoptingASyncedLedgerKeepsTheFreezesBoughtHere is not ported: SyncDocument belongs to the sync port.
  it("keeping another copy's freezes unions them once", () => {
    const local = new PetPointsLedger({ earned: 300, streakFreezes: [date(14)] });
    const synced = new PetPointsLedger({ earned: 300, streakFreezes: [date(12), date(14)] });
    local.keepStreakFreezes(synced);
    expect(local.streakFreezes).toEqual([date(12), date(14)]);
  });
});
