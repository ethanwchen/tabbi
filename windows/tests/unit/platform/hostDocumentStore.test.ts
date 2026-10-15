import { describe, expect, it } from "vitest";
import { ActivityLogRepository } from "../../../src/core/activity/activityLogRepository";
import { makeActivityRecord } from "../../../src/core/activity/activityRecord";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";
import { mockHost } from "../../../src/host/mock";
import { HostDocumentStore, InexactNumberError, UnsupportedDocumentName } from "../../../src/platform/hostDocumentStore";

describe("HostDocumentStore", () => {
  it("reads and writes JSON documents under the host's names", async () => {
    const host = mockHost();
    const store = new HostDocumentStore(host);
    expect(await store.read("Planner/2026-10-15.json")).toBeUndefined();
    await store.write("Planner/2026-10-15.json", '{"schemaVersion":2,"items":[]}');
    expect(host.documents.get("durable:Planner/2026-10-15")).toEqual({ schemaVersion: 2, items: [] });
    expect(JSON.parse((await store.read("Planner/2026-10-15.json")) ?? "")).toEqual({ schemaVersion: 2, items: [] });
    await store.write("settings.json", "[1, 2]");
    expect(host.documents.get("durable:settings")).toEqual([1, 2]);
  });

  it("keeps the value, not the characters", async () => {
    const store = new HostDocumentStore(mockHost());
    await store.write("pet.json", '{\n  "name" : "Mo\\/Mi",\n  "points" : 1.5\n}');
    expect(await store.read("pet.json")).toBe('{"name":"Mo/Mi","points":1.5}');
  });

  it("lists file names with their extension, in one folder or the root", async () => {
    const host = mockHost();
    const store = new HostDocumentStore(host);
    await store.write("Activity/2026-10-15.json", "{}");
    await store.write("Activity/2026-10-14.json", "{}");
    await store.write("pet.json", "{}");
    expect((await store.list("Activity")).sort()).toEqual(["2026-10-14.json", "2026-10-15.json"]);
    expect(await store.list("Activity/")).toHaveLength(2);
    expect(await store.list("")).toEqual(["pet.json"]);
    expect(await store.list("Nothing")).toEqual([]);
  });

  it("removes documents, and removing a missing one is fine", async () => {
    const host = mockHost();
    const store = new HostDocumentStore(host);
    await store.write("Activity/2026-10-15.json", "{}");
    await store.remove("Activity/2026-10-15.json");
    await store.remove("Activity/2026-10-15.json");
    expect(await store.read("Activity/2026-10-15.json")).toBeUndefined();
    expect(host.documents.size).toBe(0);
  });

  it("keeps the cache area apart", async () => {
    const host = mockHost();
    await new HostDocumentStore(host, "cache").write("calendar.json", '{"events":[]}');
    expect(host.documents.has("cache:calendar")).toBe(true);
    expect(await new HostDocumentStore(host).read("calendar.json")).toBeUndefined();
  });

  it("refuses names the host can't store, before calling it", async () => {
    const host = mockHost();
    const store = new HostDocumentStore(host);
    await expect(store.write("notes.txt", "{}")).rejects.toBeInstanceOf(UnsupportedDocumentName);
    await expect(store.read("Tabbi/Planner/day.json")).rejects.toBeInstanceOf(UnsupportedDocumentName);
    await expect(store.read(".json")).rejects.toBeInstanceOf(UnsupportedDocumentName);
    await expect(store.list("Tabbi/Planner")).rejects.toBeInstanceOf(UnsupportedDocumentName);
    expect(host.calls).toEqual([]);
  });

  it("passes the host's errors on: a bad segment or a damaged document rejects", async () => {
    const store = new HostDocumentStore(mockHost());
    await expect(store.read("con.json")).rejects.toMatchObject({ code: "invalidName" });
    await expect(store.write("pet.json", "{not json")).rejects.toBeInstanceOf(SyntaxError);
  });

  it("refuses an integer it would round, rather than saving another number", async () => {
    const store = new HostDocumentStore(mockHost());
    const write = store.write("journal.json", '{"seed" : 18446744073709551615}');
    /* Engines without JSON.parse source text access can't tell, and keep the old behavior. */
    const supportsSource = (() => {
      let seen = false;
      JSON.parse("1", (_key, value: unknown, context?: { source?: string }) => {
        seen = context?.source === "1";
        return value;
      });
      return seen;
    })();
    if (supportsSource) await expect(write).rejects.toBeInstanceOf(InexactNumberError);
    else await write;
    await store.write("journal.json", '{"seed" : 9007199254740991, "big" : 1e300}');
    expect(JSON.parse((await store.read("journal.json")) ?? "")).toEqual({ seed: 9007199254740991, big: 1e300 });
  });

  it("carries a core repository end to end", async () => {
    const host = mockHost();
    const repository = new ActivityLogRepository(new HostDocumentStore(host), "UTC");
    const record = makeActivityRecord({ source: "focus", kind: "focus.completed", start: 1_790_000_000, quantity: 25, unit: "min" });
    await repository.append([record]);
    const day = new Date(record.end * 1000).toISOString().slice(0, 10);
    expect(VersionedJSON.versionOf(host.documents.get(`durable:Activity/${day}`))).toBe(1);
    expect(await repository.records(day)).toEqual([record]);
  });
});
