import { describe, expect, it } from "vitest";
import { ACTIVITY_KINDS, ACTIVITY_METADATA, ACTIVITY_UNITS } from "../../../src/core/activity/activityRecord";
import { PARTY_FRIENDS_METADATA_KEY, PartySessionCompletion, PartySessionTracker, type PartySharedSession } from "../../../src/core/party/partySessionTracker";
import { PetPointsRules } from "../../../src/core/pets/petPointsRules";

/*
 * A Party shared session pays every member (host or not) for the time they
 * studied in it, once. The Closet's crediting of a completion is not ported
 * yet (PetCloset.credit), so those Swift cases are left to the Closet port.
 */

const start = 1_790_000_000;
const at = (minutes: number) => start + minutes * 60;

function session(options: { minutes?: number; friends?: number; startedAt?: number; hostName?: string | undefined } = {}): PartySharedSession {
  const startedAt = options.startedAt ?? start;
  return {
    method: "pomodoro",
    startedAt,
    endsAt: startedAt + (options.minutes ?? 25) * 60,
    friendCount: options.friends ?? 2,
    hostName: "hostName" in options ? options.hostName : "Maya",
  };
}

function ended(value: PartySessionCompletion | undefined): PartySessionCompletion {
  if (value === undefined) throw new Error("expected a completion");
  return value;
}

describe("Party shared session points", () => {
  it("pays a fair bonus over a solo session", () => {
    const solo = PetPointsRules.points(25, true);
    expect(PetPointsRules.sharedPoints(25, 0), "alone, it pays like solo").toBe(solo);
    expect(PetPointsRules.sharedPoints(25, 1)).toBe(solo + 5);
    expect(PetPointsRules.sharedPoints(25, 2)).toBe(solo + 10);
    expect(PetPointsRules.sharedPoints(25, 7), "the team bonus is capped").toBe(solo + PetPointsRules.maxSharedBonus);
    expect(PetPointsRules.sharedPoints(3, 3), "too short a stay earns nothing").toBe(0);
  });

  it("pays a stay cut short its minutes without bonuses", () => {
    expect(PetPointsRules.sharedPoints(12, 2, false)).toBe(12);
    expect(PetPointsRules.sharedPoints(30, 3, false)).toBe(PetPointsRules.points(30, false));
    expect(PetPointsRules.sharedPoints(4, 3, false)).toBe(0);
  });

  it("never makes stepping out and back in worth more than staying", () => {
    const stayed = PetPointsRules.sharedPoints(25, 3);
    for (let leftAt = 5; leftAt <= 20; leftAt += 5) {
      expect(PetPointsRules.sharedPoints(leftAt, 3, false) + PetPointsRules.sharedPoints(25 - leftAt, 3)).toBeLessThanOrEqual(stayed);
    }
  });
});

describe("PartySessionTracker", () => {
  it("completes a session that runs to its end once", () => {
    const tracker = new PartySessionTracker();
    expect(tracker.observe(session(), at(0))).toBeUndefined();
    expect(tracker.observe(session({ friends: 3 }), at(10))).toBeUndefined();
    expect(tracker.observe(session({ friends: 1 }), at(20))).toBeUndefined();
    const done = ended(tracker.observe(undefined, at(25)));
    expect(done.minutes).toBe(25);
    expect(done.friendCount, "the most friends who studied along at once").toBe(3);
    expect(done.hostName).toBe("Maya");
    expect(tracker.observe(undefined, at(26)), "paid once").toBeUndefined();
  });

  it("reports the time studied when stepping out or ending early", () => {
    const tracker = new PartySessionTracker();
    tracker.observe(session(), at(0));
    const left = ended(tracker.observe(undefined, at(12)));
    expect(left.finished).toBe(false);
    expect(left.minutes).toBe(12);
    expect(left.friendCount).toBe(2);
    expect(tracker.observe(undefined, at(25)), "reported once").toBeUndefined();
  });

  it("pays the host and every member alike", () => {
    for (const host of [undefined, "Maya"]) {
      const tracker = new PartySessionTracker();
      tracker.observe(session({ hostName: host }), at(0));
      const done = ended(tracker.observe(undefined, at(25)));
      expect(done.finished).toBe(true);
      expect(done.hostName).toBe(host);
      expect(PetPointsRules.sharedPoints(done.minutes, done.friendCount, done.finished)).toBe(PetPointsRules.sharedPoints(25, 2));
    }
  });

  it("credits a late joiner from when they joined", () => {
    const tracker = new PartySessionTracker();
    tracker.observe(session(), at(10));
    const done = ended(tracker.observe(undefined, at(25)));
    expect(done.minutes).toBe(15);
    expect(done.finished, "a late joiner who stays to the end finished it").toBe(true);
  });

  it("counts only the time in after rejoining", () => {
    const tracker = new PartySessionTracker();
    tracker.observe(session(), at(0));
    const left = ended(tracker.observe(undefined, at(5)));
    expect(left.minutes).toBe(5);
    expect(left.finished).toBe(false);
    expect(tracker.observe(session(), at(15))).toBeUndefined();
    const done = ended(tracker.observe(undefined, at(25)));
    expect(done.minutes).toBe(10);
    expect(done.finished).toBe(true);
  });

  it("still pays the last session when a new one starts right after", () => {
    const tracker = new PartySessionTracker();
    tracker.observe(session(), at(0));
    const done = ended(tracker.observe(session({ startedAt: at(25) }), at(25)));
    expect(done.minutes).toBe(25);
    expect(done.finished).toBe(true);
    const cut = ended(tracker.observe(undefined, at(30)));
    expect(cut.finished).toBe(false);
    expect(cut.minutes).toBe(5);
  });

  it("counts a session that drops off a moment early as finished", () => {
    const tracker = new PartySessionTracker();
    tracker.observe(session(), at(0));
    expect(ended(tracker.observe(undefined, at(25) - PartySessionTracker.endTolerance)).finished).toBe(true);
  });

  it("logs the completion as a focus stretch", () => {
    const record = new PartySessionCompletion({ method: "pomodoro", joinedAt: at(0), endedAt: at(25), friendCount: 2 }).activityRecord("party");
    expect(record?.kind).toBe(ACTIVITY_KINDS.focusCompleted);
    expect(record?.source).toBe("party");
    expect(record?.quantity).toBe(25);
    expect(record?.unit).toBe(ACTIVITY_UNITS.minutes);
    expect(record?.metadata[ACTIVITY_METADATA.method]).toBe("pomodoro");
    expect(record?.metadata[ACTIVITY_METADATA.outcome]).toBe("completed");
    expect(record?.metadata[PARTY_FRIENDS_METADATA_KEY]).toBe("2");
    expect(new PartySessionCompletion({ method: "pomodoro", joinedAt: at(0), endedAt: at(0.5), friendCount: 2 }).activityRecord("party")).toBeUndefined();
    const left = new PartySessionCompletion({ method: "pomodoro", joinedAt: at(0), endedAt: at(12), friendCount: 2, finished: false }).activityRecord("party");
    expect(left?.quantity, "the minutes studied still count").toBe(12);
    expect(left?.metadata[ACTIVITY_METADATA.outcome], "but not as a finished session").toBe("skipped");
  });
});
