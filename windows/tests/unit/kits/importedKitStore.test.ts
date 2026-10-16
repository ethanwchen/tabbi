import { describe, expect, it } from "vitest";
import { BUNDLED_KITS } from "../../../src/core/kits/bundledKits";
import { ImportedKitStore, importedCopy, kitVersionChange } from "../../../src/core/kits/importedKitStore";
import { importedKitID } from "../../../src/core/kits/kitLibrary";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { BUILT_IN_CATALOG } from "../../support/builtInCatalog";

const catalog = BUILT_IN_CATALOG;
const reserved = new Set(BUNDLED_KITS.ids);

const kitText = (version: string, extra = "") =>
  `{"formatVersion":1,"version":"${version}","id":"deep-work","name":"Deep Work","modules":["planner","spotify"]${extra}}`;

describe("ImportedKitStore", () => {
  it("inspects a kit file without saving it and gives it the imported id", async () => {
    const documents = new InMemoryDocumentStore();
    const store = new ImportedKitStore(documents);
    const inspection = await store.inspect(kitText("1.2"), "deep-work.json", catalog, reserved);
    if (!inspection.ok) throw new Error(inspection.error.kind);
    expect(inspection.candidate.kit.id).toBe("imported.deep-work");
    expect(inspection.candidate.overwritesFile).toBe(false);
    expect(inspection.candidate.replaces).toBeUndefined();
    expect(await store.load()).toEqual([]);
    expect(documents.snapshot()).toEqual({});
  });

  it("refuses a bundled id, a kit needing a missing module, and a broken file", async () => {
    const store = new ImportedKitStore(new InMemoryDocumentStore());
    const bundled = await store.inspect(`{"formatVersion":1,"id":"essentials","name":"Mine","modules":["planner"]}`, "e.json", catalog, reserved);
    expect(bundled.ok ? undefined : bundled.error.kind).toBe("reservedID");
    const needs = await store.inspect(`{"formatVersion":1,"id":"x","name":"X","modules":["planner"],"requires":{"modules":["leetcode"]}}`, "x.json", catalog, reserved);
    expect(needs.ok ? undefined : needs.error.kind).toBe("missingRequiredModules");
    const broken = await store.inspect("{not json", "b.json", catalog, reserved);
    expect(broken.ok ? undefined : broken.error.kind).toBe("malformed");
  });

  it("installs the file byte for byte, loads it with the imported id, and says what a re-import replaces", async () => {
    const documents = new InMemoryDocumentStore();
    const store = new ImportedKitStore(documents);
    const first = await store.inspect(kitText("1.2"), "deep-work.json", catalog, reserved);
    if (!first.ok) throw new Error(first.error.kind);
    await store.install(first.candidate);
    expect(documents.snapshot()).toEqual({ "Kits/deep-work.json": kitText("1.2") });
    const loaded = await store.load();
    expect(loaded.map((kit) => [kit.id, kit.version])).toEqual([["imported.deep-work", "1.2"]]);

    const again = await store.inspect(kitText("1.3"), "deep-work.json", catalog, reserved);
    if (!again.ok) throw new Error(again.error.kind);
    expect(again.candidate.overwritesFile).toBe(true);
    expect(again.candidate.replaces?.id).toBe("imported.deep-work");
    expect(kitVersionChange(again.candidate)).toBe("Deep Work 1.2 to 1.3");
    expect(kitVersionChange(first.candidate)).toBeUndefined();
  });

  it("restores and removes files for undo, skipping a file that no longer loads", async () => {
    const documents = new InMemoryDocumentStore({ "Kits/broken.json": "{oops", "Kits/notes.txt": "{}" });
    const store = new ImportedKitStore(documents);
    expect(await store.load()).toEqual([]);
    const id = importedKitID("deep-work");
    expect(await store.savedText(id)).toBeUndefined();
    await store.restore(kitText("1.0"), id);
    expect(await store.savedText(id)).toBe(kitText("1.0"));
    await store.restore(undefined, id);
    expect(await store.savedText(id)).toBeUndefined();
    await store.remove(id);
    expect(importedCopy(BUNDLED_KITS.kits[0] as never).id.startsWith("imported.")).toBe(true);
  });
});
