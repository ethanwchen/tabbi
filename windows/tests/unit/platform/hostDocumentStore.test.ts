import { describe, expect, it } from "vitest";
import { ActivityLogRepository } from "../../../src/core/activity/activityLogRepository";
import { makeActivityRecord } from "../../../src/core/activity/activityRecord";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";
import { mockHost } from "../../../src/host/mock";
import { HostDocumentStore, UnsupportedDocumentName } from "../../../src/platform/hostDocumentStore";

describe("HostDocumentStore", () => {
  it("reads and writes JSON documents under the host's names", async () => {
    const host = mockHost();
    const store = new HostDocumentStore(host);
    expect(await store.read("Planner/2026-10-15.json")).toBeUndefined();
    await store.write("Planner/2026-10-15.json", '{"schemaVersion":2,"items":[]}');
    expect(host.documents.get("durable:Planner/2026-10-15")).toBe('{"schemaVersion":2,"items":[]}');
    await store.write("settings.json", "[1, 2]");
    expect(await store.read("settings.json")).toBe("[1, 2]");
  });

  it("keeps the characters exactly, the Mac's format and large integers included", async () => {
    const store = new HostDocumentStore(mockHost());
    const pet = '{\n  "name" : "Mo\\/Mi",\n  "points" : 1.5\n}';
    await store.write("pet.json", pet);
    expect(await store.read("pet.json")).toBe(pet);
    const journal = '{"seed" : 18446744073709551615}';
    await store.write("journal.json", journal);
    expect(await store.read("journal.json")).toBe(journal);
  });

  it("stores documents two folders deep, with spaces in folder names", async () => {
    const host = mockHost();
    const store = new HostDocumentStore(host);
    await store.write("tabbi/Claude Chats/0B5F2E9A.json", "{}");
    expect(host.documents.has("durable:tabbi/Claude Chats/0B5F2E9A")).toBe(true);
    expect(await store.list("tabbi/Claude Chats")).toEqual(["0B5F2E9A.json"]);
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
    await expect(store.read("Tabbi/Planner/Days/day.json")).rejects.toBeInstanceOf(UnsupportedDocumentName);
    await expect(store.read(".json")).rejects.toBeInstanceOf(UnsupportedDocumentName);
    await expect(store.list("Tabbi/Planner/Days")).rejects.toBeInstanceOf(UnsupportedDocumentName);
    expect(host.calls).toEqual([]);
  });

  it("passes the host's errors on: a bad segment or text that is not JSON rejects", async () => {
    const store = new HostDocumentStore(mockHost());
    await expect(store.read("con.json")).rejects.toMatchObject({ code: "invalidName" });
    await expect(store.write("pet.json", "{not json")).rejects.toMatchObject({ code: "invalid" });
  });

  it("carries a core repository end to end", async () => {
    const host = mockHost();
    const repository = new ActivityLogRepository(new HostDocumentStore(host), "UTC");
    const record = makeActivityRecord({ source: "focus", kind: "focus.completed", start: 1_790_000_000, quantity: 25, unit: "min" });
    await repository.append([record]);
    const day = new Date(record.end * 1000).toISOString().slice(0, 10);
    expect(VersionedJSON.versionOf(JSON.parse(host.documents.get(`durable:Activity/${day}`) ?? "null"))).toBe(1);
    expect(await repository.records(day)).toEqual([record]);
  });
});
