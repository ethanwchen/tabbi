import { describe, expect, it } from "vitest";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";
import {
  decodeStudyLog,
  encodeStudyLog,
  loadStudyLog,
  STUDY_LOG_DOCUMENT_NAME,
  STUDY_LOG_SCHEMA,
  StudyLog,
  studyLogEntry,
  writeStudyLog,
  type StudyLogEntry,
} from "../../../src/core/studyMethods/studyLog";

/* Port of the persistence cases in StudyLogTests and VersionedJSONTests, over an in-memory store. */

const t0 = 1_800_000_000;
const ID = "6B1A3A4E-6C55-4D0A-9E1B-6A7E0F2C1D3B";

function entry(minutes = 25, cards?: number): StudyLogEntry {
  const made = studyLogEntry(
    {
      method: cards === undefined ? "pomodoro" : "ankiSprint",
      phase: "focus",
      startedAt: t0,
      endedAt: t0 + minutes * 60,
      activeDuration: minutes * 60,
      outcome: "completed",
      ...(cards === undefined ? {} : { cards }),
    },
    ID,
  );
  if (!made) throw new Error("no entry");
  return made;
}

describe("StudyLog persistence", () => {
  it("is schema version 1 in the Mac's Study/log.json", () => {
    expect(STUDY_LOG_SCHEMA.current).toBe(1);
    expect(STUDY_LOG_DOCUMENT_NAME).toBe("Study/log.json");
  });

  it("writes the Mac's sorted keys with dates since 2001", () => {
    expect(encodeStudyLog(new StudyLog([entry(), entry(12, 100)]))).toBe(
      `{"entries":[` +
        `{"completed":true,"endedAt":821694300,"id":"${ID}","method":"pomodoro","minutes":25,"points":35,"startedAt":821692800},` +
        `{"cards":100,"completed":true,"endedAt":821693520,"id":"${ID}","method":"ankiSprint","minutes":12,"points":12,"startedAt":821692800}` +
        `],"schemaVersion":1}`,
    );
  });

  it("round-trips through a store, and is undefined before the first write", async () => {
    const store = new InMemoryDocumentStore();
    const log = new StudyLog([entry(), entry(12, 100)]);
    expect(await loadStudyLog(store)).toBeUndefined();
    await writeStudyLog(store, log);
    expect(Object.keys(store.snapshot())).toEqual(["Study/log.json"]);
    expect(await loadStudyLog(store)).toEqual(log);
  });

  it("loads a log written before versions, and stamps it on the next write", async () => {
    const store = new InMemoryDocumentStore({ "Study/log.json": `{"entries":[]}` });
    expect(await loadStudyLog(store)).toEqual(new StudyLog());
    await writeStudyLog(store, new StudyLog());
    expect(VersionedJSON.version(store.snapshot()["Study/log.json"] ?? "")).toBe(1);
  });

  it("reads a log from a newer build leniently", async () => {
    const store = new InMemoryDocumentStore({ "Study/log.json": `{"schemaVersion":4,"goal":3}` });
    expect(await loadStudyLog(store)).toEqual(new StudyLog());
  });

  it("rejects a damaged log so the caller can keep it", async () => {
    const damaged = [
      "{",
      "[]",
      `{"entries":{}}`,
      `{"entries":[{"id":"nope","method":"pomodoro","startedAt":0,"endedAt":60,"minutes":1,"completed":true,"points":1}]}`,
      `{"entries":[{"id":"${ID}","method":"cram","startedAt":0,"endedAt":60,"minutes":1,"completed":true,"points":1}]}`,
      `{"entries":[{"id":"${ID}","method":"pomodoro","endedAt":60,"minutes":1,"completed":true,"points":1}]}`,
      `{"entries":[{"id":"${ID}","method":"pomodoro","startedAt":0,"endedAt":60,"minutes":1.5,"completed":true,"points":1}]}`,
      `{"entries":[{"id":"${ID}","method":"pomodoro","startedAt":0,"endedAt":60,"minutes":1,"completed":"yes","points":1}]}`,
      `{"entries":[{"id":"${ID}","method":"pomodoro","startedAt":0,"endedAt":60,"minutes":1,"completed":true,"points":1,"cards":"many"}]}`,
    ];
    for (const text of damaged) {
      await expect(loadStudyLog(new InMemoryDocumentStore({ "Study/log.json": text }))).rejects.toThrow();
    }
  });

  it("clamps corrupt values through the entry's init", () => {
    const json = `{"entries":[{"id":"${ID.toLowerCase()}","method":"pomodoro","startedAt":0,"endedAt":60,"minutes":-4,"completed":true,"cards":-2,"points":-10}]}`;
    const log = STUDY_LOG_SCHEMA.decode(json, decodeStudyLog);
    expect(log.entries[0]).toEqual({
      id: ID,
      method: "pomodoro",
      startedAt: 978_307_200,
      endedAt: 978_307_260,
      minutes: 0,
      completed: true,
      cards: 0,
      points: 0,
    });
    expect(log.totalPoints).toBe(0);
  });

  it("ignores the retired uncredited list", () => {
    const one = entry();
    const old = encodeStudyLog(new StudyLog([one])).replace(`"schemaVersion":1`, `"uncredited":[{"id":"${ID}"}]`);
    expect(STUDY_LOG_SCHEMA.decode(old, decodeStudyLog)).toEqual(new StudyLog([one]));
  });

  it("keeps only the newest entries of an oversized file", () => {
    const entries = Array.from({ length: StudyLog.capacity + 2 }, (_, index) => ({ ...entry(1), endedAt: t0 + index }));
    const log = STUDY_LOG_SCHEMA.decode(encodeStudyLog(new StudyLog()).replace(`"entries":[]`, `"entries":${JSON.stringify(entries.map((e) => ({ ...e, startedAt: e.startedAt - 978_307_200, endedAt: e.endedAt - 978_307_200 })))}`), decodeStudyLog);
    expect(log.entries.length).toBe(StudyLog.capacity);
    expect(log.entries[log.entries.length - 1]?.endedAt).toBe(t0 + StudyLog.capacity + 1);
  });
});
