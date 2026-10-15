import { describe, expect, it } from "vitest";
import {
  ACTIVITY_KINDS,
  ACTIVITY_UNITS,
  activityDay,
  decodeActivityRecord,
  encodeActivityRecord,
  makeActivityRecord,
  wholeSeconds,
  type ActivityRecord,
} from "../../../src/core/activity/activityRecord";
import { ActivityLogRepository } from "../../../src/core/activity/activityLogRepository";
import { plannerDayKeyOf as dayKeyOf, isPlannerDayKey as isDayKey } from "../../../src/core/planner/plannerDayKey";
import { formatISODate, parseISODate } from "../../../src/core/activity/isoDate";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";
import { MODULE_IDS } from "../../../src/core/modules/moduleId";

/* 2026-10-<day> at hour:minute UTC. */
function date(hour: number, minute = 0, day = 2): number {
  return Date.UTC(2026, 9, day, hour, minute) / 1000;
}

function focus(end: number, minutes = 25, source: string = MODULE_IDS.focus): ActivityRecord {
  return makeActivityRecord({
    source,
    kind: ACTIVITY_KINDS.focusCompleted,
    start: end - minutes * 60,
    end,
    quantity: minutes,
    unit: ACTIVITY_UNITS.minutes,
  });
}

function setup() {
  const store = new InMemoryDocumentStore();
  return { store, repo: new ActivityLogRepository(store, "UTC") };
}

describe("ActivityRecord", () => {
  it("never ends before it starts and counts toward its end day", () => {
    const moment = makeActivityRecord({ source: MODULE_IDS.planner, kind: ACTIVITY_KINDS.taskCompleted, start: date(9) });
    expect(moment.end).toBe(moment.start);
    const backwards = makeActivityRecord({
      source: MODULE_IDS.focus,
      kind: ACTIVITY_KINDS.breakTaken,
      start: date(9),
      end: date(8),
    });
    expect(backwards.end).toBe(date(9));
    const overnight = focus(date(0, 10, 3), 30);
    expect(activityDay(overnight, "UTC")).toBe("2026-10-03");
  });

  it("counts toward the end day on the wall clock of the given zone", () => {
    const evening = focus(date(23, 30));
    expect(activityDay(evening, "UTC")).toBe("2026-10-02");
    expect(activityDay(evening, "Europe/Berlin")).toBe("2026-10-03");
    expect(activityDay(evening, "America/Los_Angeles")).toBe("2026-10-02");
  });

  it("rounds start and end to whole seconds like the Mac", () => {
    const record = makeActivityRecord({ source: "focus", kind: "focus.completed", start: date(9) + 0.4, end: date(9) + 10.5 });
    expect(record.start).toBe(date(9));
    expect(record.end).toBe(date(9) + 11);
    /* Swift rounds half away from zero relative to 2001, so a time before 2001 rounds down at .5. */
    expect(wholeSeconds(978_307_200 - 0.5)).toBe(978_307_200 - 1);
    expect(wholeSeconds(978_307_200 + 0.5)).toBe(978_307_200 + 1);
  });

  it("keeps kinds as open strings", () => {
    const solved = makeActivityRecord({ source: "leetcode", kind: "problem.solved", start: date(10), subject: "two-sum" });
    const json = encodeActivityRecord(solved);
    expect(json.kind).toBe("problem.solved");
    expect(json.source).toBe("leetcode");
    expect(decodeActivityRecord(JSON.parse(JSON.stringify(json)))).toEqual(solved);
  });

  it("encodes the Mac's shape: ISO 8601 dates, nil fields left out, metadata always there", () => {
    const record = makeActivityRecord({
      id: "6f1d3a2e-0c59-4d0b-9a64-1b5b8f1d2c3e",
      source: "anki",
      kind: ACTIVITY_KINDS.cardsReviewed,
      start: date(9),
      quantity: 12,
      unit: ACTIVITY_UNITS.cards,
    });
    expect(encodeActivityRecord(record)).toEqual({
      id: "6F1D3A2E-0C59-4D0B-9A64-1B5B8F1D2C3E",
      source: "anki",
      kind: "cards.reviewed",
      start: "2026-10-02T09:00:00Z",
      end: "2026-10-02T09:00:00Z",
      quantity: 12,
      unit: "cards",
      metadata: {},
    });
  });

  it("refuses records the Mac's decoder would refuse", () => {
    const valid = encodeActivityRecord(focus(date(9)));
    expect(() => decodeActivityRecord({ ...valid, id: "nope" })).toThrow();
    expect(() => decodeActivityRecord({ ...valid, start: "2026-10-02 09:00" })).toThrow();
    expect(() => decodeActivityRecord({ ...valid, start: "2026-10-02T09:00:00.5Z" })).toThrow();
    expect(() => decodeActivityRecord({ ...valid, end: 5 })).toThrow();
    expect(() => decodeActivityRecord({ ...valid, quantity: "5" })).toThrow();
    expect(() => decodeActivityRecord({ ...valid, metadata: { cards: 4 } })).toThrow();
    expect(() => decodeActivityRecord(42)).toThrow();
  });
});

describe("ISO 8601 dates", () => {
  it("writes UTC with Z and reads Z or an offset", () => {
    expect(formatISODate(date(9, 5))).toBe("2026-10-02T09:05:00Z");
    expect(parseISODate("2026-10-02T09:05:00Z")).toBe(date(9, 5));
    expect(parseISODate("2026-10-02T11:05:00+02:00")).toBe(date(9, 5));
    expect(parseISODate("2026-10-02T04:05:00-0500")).toBe(date(9, 5));
    expect(parseISODate("2026-10-02")).toBeUndefined();
  });
});

describe("day keys", () => {
  it("accepts only real yyyy-MM-dd dates", () => {
    expect(isDayKey("2026-10-02")).toBe(true);
    expect(isDayKey("2028-02-29")).toBe(true);
    expect(isDayKey("2026-02-29")).toBe(false);
    expect(isDayKey("2026-13-01")).toBe(false);
    expect(isDayKey("2026-1-01")).toBe(false);
    expect(isDayKey("readme")).toBe(false);
  });

  it("names the day on a zone's wall clock", () => {
    expect(dayKeyOf(date(11), "Pacific/Chatham")).toBe("2026-10-03");
    expect(dayKeyOf(date(11), "UTC")).toBe("2026-10-02");
  });
});

describe("ActivityLogRepository", () => {
  it("reads appended records back by day from a versioned file", async () => {
    const { store, repo } = setup();
    const morning = focus(date(9));
    const evening = focus(date(21), 25, MODULE_IDS.study);
    const tomorrow = focus(date(8, 0, 3));
    await repo.append([evening, tomorrow, morning]);

    expect(await repo.records("2026-10-02")).toEqual([morning, evening]);
    expect(await repo.records("2026-10-03")).toEqual([tomorrow]);
    expect(await repo.records("2026-10-04")).toEqual([]);
    expect(await repo.savedDays()).toEqual(["2026-10-02", "2026-10-03"]);
    const text = (await store.read("Activity/2026-10-02.json")) ?? "";
    expect(VersionedJSON.version(text)).toBe(ActivityLogRepository.schema.current);
    expect(Object.keys(JSON.parse(text) as object)).toEqual(["records", "schemaVersion"]);
  });

  it("keeps one copy of a record appended twice", async () => {
    const { repo } = setup();
    const record = focus(date(9));
    await repo.append([record]);
    await repo.append([record, record]);
    expect(await repo.records("2026-10-02")).toEqual([record]);
  });

  it("skips unrelated and unreadable files when reading a range", async () => {
    const { store, repo } = setup();
    const first = focus(date(9, 0, 1));
    const third = focus(date(9, 0, 3));
    await repo.append([first, third]);
    await store.write("Activity/2026-10-02.json", "not json");
    await store.write("Activity/readme.txt", "notes");

    expect(await repo.recordsBetween("2026-10-01", "2026-10-03")).toEqual([first, third]);
    expect(await repo.recordsBetween("2026-10-02", "2026-10-02")).toEqual([]);
  });

  it("never overwrites an unreadable day", async () => {
    const { store, repo } = setup();
    await repo.append([focus(date(8))]);
    const garbage = '{"records": 42}';
    await store.write("Activity/2026-10-02.json", garbage);

    await expect(repo.append([focus(date(10))])).rejects.toThrow();
    expect(await store.read("Activity/2026-10-02.json")).toBe(garbage);
  });

  it("still loads day files without a version", async () => {
    const { store, repo } = setup();
    await store.write(
      "Activity/2026-10-02.json",
      `{"records": [{"id": "6F1D3A2E-0C59-4D0B-9A64-1B5B8F1D2C3E", "source": "anki", "kind": "cards.reviewed",
                     "start": "2026-10-02T09:00:00Z", "quantity": 12, "unit": "cards"}]}`,
    );
    const records = await repo.records("2026-10-02");
    expect(records.map((record) => record.kind)).toEqual([ACTIVITY_KINDS.cardsReviewed]);
    expect(records[0]?.end).toBe(date(9));
    expect(records[0]?.metadata).toEqual({});
  });

  it("files a record under its local day in the repository's zone", async () => {
    const store = new InMemoryDocumentStore();
    const repo = new ActivityLogRepository(store, "Europe/Berlin");
    await repo.append([focus(date(23, 30))]);
    expect(await repo.savedDays()).toEqual(["2026-10-03"]);
  });

  it("writes a file the Mac reads: pretty, sorted keys, ISO dates", async () => {
    const { store, repo } = setup();
    await repo.append([
      makeActivityRecord({
        id: "6F1D3A2E-0C59-4D0B-9A64-1B5B8F1D2C3E",
        source: "planner",
        kind: "task.completed",
        start: date(9),
        subject: "a/b",
      }),
    ]);
    expect(await store.read("Activity/2026-10-02.json")).toBe(
      [
        "{",
        '  "records" : [',
        "    {",
        '      "end" : "2026-10-02T09:00:00Z",',
        '      "id" : "6F1D3A2E-0C59-4D0B-9A64-1B5B8F1D2C3E",',
        '      "kind" : "task.completed",',
        '      "metadata" : {},',
        '      "source" : "planner",',
        '      "start" : "2026-10-02T09:00:00Z",',
        '      "subject" : "a\\/b"',
        "    }",
        "  ],",
        '  "schemaVersion" : 1',
        "}",
      ].join("\n"),
    );
  });
});
