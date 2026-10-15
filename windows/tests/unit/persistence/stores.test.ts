import { describe, expect, it } from "vitest";
import {
  InMemoryDefaults,
  defaultsBool,
  defaultsInteger,
  defaultsObject,
  defaultsString,
  defaultsStringArray,
  loadDefaults,
  saveDefaults,
} from "../../../src/core/persistence/defaults";
import { InMemoryDocumentStore, documentName } from "../../../src/core/persistence/documentStore";

describe("InMemoryDefaults", () => {
  it("round-trips typed values", () => {
    const defaults = new InMemoryDefaults();
    defaults.set("bool", true);
    defaults.set("int", 3);
    defaults.set("double", 2.5);
    defaults.set("string", "kit");
    defaults.set("strings", ["a", "b"]);
    defaults.set("dictionary", { a: ["b"] });
    defaults.set("data", '{"keyCode":49}');

    expect(defaultsBool(defaults, "bool")).toBe(true);
    expect(defaultsInteger(defaults, "int")).toBe(3);
    expect(defaultsInteger(defaults, "double")).toBeUndefined();
    expect(defaults.get("double")).toBe(2.5);
    expect(defaultsString(defaults, "string")).toBe("kit");
    expect(defaultsStringArray(defaults, "strings")).toEqual(["a", "b"]);
    expect(defaultsObject(defaults, "dictionary")).toEqual({ a: ["b"] });
    expect(defaultsString(defaults, "data")).toBe('{"keyCode":49}');

    defaults.remove("string");
    expect(defaultsString(defaults, "string")).toBeUndefined();
    expect(defaultsBool(defaults, "missing")).toBeUndefined();
    expect(defaultsBool(defaults, "int")).toBeUndefined();
  });

  /* Two instances never see each other's values. */
  it("keeps instances independent", () => {
    const first = new InMemoryDefaults();
    first.set("settings.kit", "medicine");
    expect(new InMemoryDefaults().get("settings.kit")).toBeUndefined();
  });

  it("copies values in and out", () => {
    const defaults = new InMemoryDefaults();
    const list = ["a"];
    defaults.set("list", list);
    list.push("b");
    const read = defaultsStringArray(defaults, "list");
    read?.push("c");
    expect(defaults.get("list")).toEqual(["a"]);
  });

  it("loads and saves through a document store", async () => {
    const store = new InMemoryDocumentStore();
    const defaults = await loadDefaults(store, "settings.json");
    expect(defaults.entries()).toEqual({});
    defaults.set("settings.displayName", "Sam");
    await saveDefaults(store, "settings.json", defaults);
    expect((await loadDefaults(store, "settings.json")).get("settings.displayName")).toBe("Sam");

    await store.write("broken.json", "not json");
    expect((await loadDefaults(store, "broken.json")).entries()).toEqual({});
  });
});

describe("InMemoryDocumentStore", () => {
  it("lists only the documents directly in a folder", async () => {
    const store = new InMemoryDocumentStore();
    await store.write(documentName("Activity", "2026-10-02.json"), "{}");
    await store.write("Activity/Nested/x.json", "{}");
    await store.write("Planner/2026-10-02.json", "{}");
    expect(await store.list("Activity")).toEqual(["2026-10-02.json"]);
    expect(await store.list("Activity/")).toEqual(["2026-10-02.json"]);
    expect(await store.read("Activity/2026-10-02.json")).toBe("{}");
    await store.remove("Activity/2026-10-02.json");
    expect(await store.read("Activity/2026-10-02.json")).toBeUndefined();
    expect(await store.list("Missing")).toEqual([]);
  });
});
