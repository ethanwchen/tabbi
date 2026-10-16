import { describe, expect, it } from "vitest";
import { instantOf } from "../../../src/core/calendar/zonedCalendar";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";
import { RecapArchive } from "../../../src/core/recap/recapArchive";
import { demoRecapArchive } from "../../../src/core/recap/recapDemo";
import { addingWeeks } from "../../../src/core/recap/recapWeek";
import { WeeklyRecap } from "../../../src/core/recap/weeklyRecap";

/* Port of RecapArchiveTests. */

const zone = "America/New_York";

/** October `day`, 2026 at `hour` o'clock in New York. October 5 is a Monday. */
function date(day: number, hour: number): number {
  return instantOf({ year: 2026, month: 10, day, hour }, zone);
}

function recap(week: string, minutes: number): WeeklyRecap {
  return new WeeklyRecap({
    week,
    minutesByDay: [minutes],
    sessions: minutes > 0 ? 1 : 0,
    cardsReviewed: 0,
    tasksDone: 0,
    points: minutes,
    longestStreak: minutes > 0 ? 1 : 0,
  });
}

describe("which weeks to build", () => {
  it("catches up on recent weeks, oldest first", () => {
    expect(new RecapArchive().weeksToBuild(date(11, 19), zone)).toEqual(["2026-09-14", "2026-09-21", "2026-09-28", "2026-10-05"]);
  });

  it("builds last week as the newest before Sunday evening", () => {
    expect(new RecapArchive().weeksToBuild(date(11, 17), zone).at(-1)).toBe("2026-09-28");
  });

  it("builds a week again until it is over", () => {
    const archive = new RecapArchive();
    archive.record(recap("2026-10-05", 30), date(11, 19), zone);
    expect(archive.weeksToBuild(date(11, 22), zone).at(-1)).toBe("2026-10-05");
    archive.record(recap("2026-10-05", 90), date(12, 9), zone);
    expect(archive.settledWeek).toBe("2026-10-05");
    expect(archive.weeksToBuild(date(12, 10), zone)).toEqual([]);
    expect(archive.recaps.map((r) => r.focusMinutes)).toEqual([90]);
    expect(archive.weeksToBuild(date(18, 18), zone)).toEqual(["2026-10-12"]);
  });
});

describe("recording", () => {
  it("never keeps empty weeks but still settles them", () => {
    const archive = new RecapArchive();
    expect(archive.record(recap("2026-09-28", 0), date(6, 9), zone)).toBe(true);
    expect(archive.recaps).toEqual([]);
    expect(archive.unseen).toBeUndefined();
    expect(archive.settledWeek).toBe("2026-09-28");
    expect(archive.record(recap("2026-09-28", 0), date(6, 10), zone)).toBe(false);
  });

  it("keeps recaps newest first and catching up does not unsettle newer weeks", () => {
    const archive = new RecapArchive();
    archive.record(recap("2026-10-05", 50), date(12, 9), zone);
    archive.record(recap("2026-09-21", 70), date(12, 9), zone);
    expect(archive.recaps.map((r) => r.week)).toEqual(["2026-10-05", "2026-09-21"]);
    expect(archive.settledWeek).toBe("2026-10-05");
    expect(archive.recap("2026-09-21")?.focusMinutes).toBe(70);
  });

  it("keeps at most two years of weeks, dropping the oldest", () => {
    const archive = new RecapArchive();
    let current = "2026-10-05";
    for (let i = 0; i < RecapArchive.capacity + 3; i++) {
      archive.record(recap(current, 30), date(12, 9), zone);
      current = addingWeeks(current, -1);
    }
    expect(archive.recaps).toHaveLength(RecapArchive.capacity);
    expect(archive.recaps[0]?.week).toBe("2026-10-05");
  });
});

describe("showing and notifying once", () => {
  it("shows only the newest recap, and only once", () => {
    const archive = new RecapArchive();
    archive.record(recap("2026-09-21", 40), date(12, 9), zone);
    archive.record(recap("2026-09-28", 40), date(12, 9), zone);
    expect(archive.unseen?.week).toBe("2026-09-28");
    expect(archive.markSeen("2026-09-28")).toBe(true);
    expect(archive.unseen).toBeUndefined();
    expect(archive.markSeen("2026-09-21")).toBe(false);
    archive.record(recap("2026-09-28", 80), date(12, 9), zone);
    expect(archive.unseen).toBeUndefined();
    archive.record(recap("2026-10-05", 10), date(12, 9), zone);
    expect(archive.unseen?.week).toBe("2026-10-05");
  });

  it("shows only the week that just ended after weeks away", () => {
    const archive = new RecapArchive({ seenWeek: "2026-09-07" });
    for (const start of ["2026-09-14", "2026-09-21", "2026-09-28", "2026-10-05"]) archive.record(recap(start, 30), date(13, 9), zone);
    expect(archive.skipStaleWeeks(date(13, 9), zone)).toBe(true);
    expect(archive.unseen?.week).toBe("2026-10-05");
    expect(archive.seenWeek).toBe("2026-09-28");
    expect(archive.recaps).toHaveLength(4);
    expect(archive.skipStaleWeeks(date(14, 9), zone)).toBe(false);
    archive.markSeen("2026-10-05");
    expect(archive.unseen).toBeUndefined();
  });

  it("never shows an old unseen week when the latest week was empty", () => {
    const archive = new RecapArchive();
    archive.record(recap("2026-09-14", 30), date(21, 9), zone);
    archive.record(recap("2026-10-05", 0), date(13, 9), zone);
    archive.skipStaleWeeks(date(13, 9), zone);
    expect(archive.unseen).toBeUndefined();
    expect(archive.unnotified).toBeUndefined();
    expect(archive.recaps.map((r) => r.week)).toEqual(["2026-09-14"]);
  });

  it("treats last week as stale on Sunday evening so this week can show", () => {
    const archive = new RecapArchive();
    archive.record(recap("2026-09-28", 30), date(11, 19), zone);
    archive.record(recap("2026-10-05", 30), date(11, 19), zone);
    archive.skipStaleWeeks(date(11, 19), zone);
    expect(archive.unseen?.week).toBe("2026-10-05");
    expect(archive.seenWeek).toBe("2026-09-28");
  });

  it("keeps the newer markers on a merge, so a seen week never shows again", () => {
    const here = new RecapArchive({ recaps: [recap("2026-10-05", 30)], settledWeek: "2026-10-05", seenWeek: "2026-09-28" });
    const there = new RecapArchive({
      recaps: [recap("2026-10-05", 90), recap("2026-09-28", 20)],
      settledWeek: "2026-09-28",
      seenWeek: "2026-10-05",
      notifiedWeek: "2026-10-05",
    });
    expect(here.merge(there)).toBe(true);
    expect(here.seenWeek).toBe("2026-10-05");
    expect(here.notifiedWeek).toBe("2026-10-05");
    expect(here.settledWeek).toBe("2026-10-05");
    expect(here.unseen).toBeUndefined();
    expect(here.recaps.map((r) => r.week)).toEqual(["2026-10-05", "2026-09-28"]);
    expect(here.recap("2026-10-05")?.focusMinutes).toBe(30);
    expect(here.merge(new RecapArchive({ seenWeek: "2026-09-21" }))).toBe(false);
    expect(here.seenWeek).toBe("2026-10-05");
  });

  it("notifies once per week and not after the recap was seen", () => {
    const archive = new RecapArchive();
    archive.record(recap("2026-10-05", 40), date(11, 19), zone);
    expect(archive.unnotified?.week).toBe("2026-10-05");
    archive.markNotified("2026-10-05");
    expect(archive.unnotified).toBeUndefined();
    expect(archive.unseen?.week).toBe("2026-10-05");
    archive.record(recap("2026-10-12", 40), date(18, 19), zone);
    archive.markSeen("2026-10-12");
    expect(archive.unnotified).toBeUndefined();
  });

  it("cheers against the saved weeks", () => {
    const archive = new RecapArchive();
    archive.record(recap("2026-09-21", 200), date(12, 9), zone);
    archive.record(recap("2026-09-28", 120), date(12, 9), zone);
    const newest = recap("2026-10-05", 300);
    archive.record(newest, date(12, 9), zone);
    expect(archive.cheer(newest)).toBe("bestYet");
    const middle = archive.recap("2026-09-28");
    expect(middle && archive.cheer(middle)).toBe("steady");
  });
});

describe("persistence", () => {
  it("round-trips through a versioned document", async () => {
    const store = new InMemoryDocumentStore();
    expect(await RecapArchive.load(store)).toBeUndefined();
    const archive = new RecapArchive();
    archive.record(recap("2026-10-05", 45), date(12, 9), zone);
    archive.markSeen("2026-10-05");
    archive.markNotified("2026-10-05");
    await archive.write(store);
    const text = store.snapshot()["Recaps/recaps.json"] ?? "";
    expect(VersionedJSON.version(text)).toBe(RecapArchive.schema.current);
    const loaded = await RecapArchive.load(store);
    expect(loaded?.equals(archive)).toBe(true);
  });

  it("drops empty and duplicate weeks and tolerates bad markers", () => {
    const json = `{"recaps": [
      {"week": "2026-09-28", "minutesByDay": [30], "sessions": 1, "cardsReviewed": 0, "tasksDone": 0, "points": 30, "longestStreak": 1},
      {"week": "2026-10-05", "minutesByDay": [0], "sessions": 0, "cardsReviewed": 0, "tasksDone": 0, "points": 0, "longestStreak": 0},
      {"week": "2026-09-28", "minutesByDay": [99], "sessions": 1, "cardsReviewed": 0, "tasksDone": 0, "points": 99, "longestStreak": 1}
    ], "seenWeek": 12}`;
    const archive = RecapArchive.decode(json);
    expect(archive.recaps.map((r) => r.week)).toEqual(["2026-09-28"]);
    expect(archive.recaps[0]?.focusMinutes).toBe(30);
    expect(archive.seenWeek).toBeUndefined();
    expect(archive.unseen?.week).toBe("2026-09-28");
  });

  it("rejects a corrupt file instead of reading it as empty", async () => {
    const store = new InMemoryDocumentStore({ [RecapArchive.documentName]: "not json" });
    await expect(RecapArchive.load(store)).rejects.toThrow();
  });
});

describe("demo", () => {
  it("ends on an unseen best week with a light week among them", () => {
    const archive = demoRecapArchive(date(11, 19), zone);
    const newest = archive.unseen;
    expect(newest?.week).toBe("2026-10-05");
    expect(newest && archive.cheer(newest)).toBe("bestYet");
    expect(archive.recaps.some((r) => archive.cheer(r) === "light")).toBe(true);
  });
});
