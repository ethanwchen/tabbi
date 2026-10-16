import { describe, expect, it } from "vitest";
import { ActivityLog } from "../../../src/app/activityLog";
import { EditionFolders, FolderDocumentStore } from "../../../src/app/editionStorage";
import { ProviderHub } from "../../../src/app/providerHub";
import { ModuleRegistry } from "../../../src/app/registry";
import { SettingsStore, SETTINGS_DOCUMENT, type KitApplication } from "../../../src/app/settingsStore";
import { serviceKey, SharedServices } from "../../../src/app/sharedServices";
import { Observable } from "../../../src/app/store";
import { hostChannel } from "../../../src/app/windowChannel";
import { ActivityLogRepository } from "../../../src/core/activity/activityLogRepository";
import { makeActivityRecord } from "../../../src/core/activity/activityRecord";
import { BUNDLED_KITS } from "../../../src/core/kits/bundledKits";
import { ModuleCatalog } from "../../../src/core/modules/moduleCatalog";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { moduleProvision, type ModuleProvision } from "../../../src/core/providers/moduleProvision";
import { ProvidedFocus } from "../../../src/core/providers/providedFocus";
import { providedTask } from "../../../src/core/providers/providedTask";
import { mockHost, MockWindowBus } from "../../../src/host/mock";
import { MODULE_LIST } from "../../../src/modules/moduleList";
import { recordingModule } from "../../support/runtime";

const NOW = 1_790_000_000;

function running(source: string, endsAt: number): ProvidedFocus {
  return new ProvidedFocus({ source, phase: "focus", clock: { kind: "countdown", endsAt }, phaseLength: 1500 });
}

describe("ProviderHub", () => {
  it("merges the enabled modules' provisions in tab order and drops a module that is turned off", () => {
    const a = new Observable<ModuleProvision>(moduleProvision({ tasks: [providedTask({ id: "1", source: "a", title: "A" })] }));
    const b = new Observable<ModuleProvision>(moduleProvision({ tasks: [providedTask({ id: "1", source: "b", title: "B" })] }));
    const hub = new ProviderHub(() => NOW);
    hub.attach((id) => ({ a, b })[id]);
    hub.update(["b", "a"]);
    expect(hub.snapshot.get().tasks.map((task) => task.title)).toEqual(["B", "A"]);
    hub.update(["a"]);
    expect(hub.snapshot.get().tasks.map((task) => task.title)).toEqual(["A"]);
    b.set(moduleProvision({ isPlaying: true }));
    expect(hub.snapshot.get().isPlaying).toBe(false);
    a.set(moduleProvision({ isPlaying: true }));
    expect(hub.snapshot.get().isPlaying).toBe(true);
  });

  it("keeps the snapshot when nothing it merges changed", () => {
    const a = new Observable<ModuleProvision>(moduleProvision());
    const hub = new ProviderHub(() => NOW);
    hub.attach(() => a);
    hub.update(["a"]);
    const first = hub.snapshot.get();
    hub.update(["a"]);
    expect(hub.snapshot.get()).toBe(first);
  });

  it("shows the focus clock the user started last", () => {
    let now = NOW;
    const a = new Observable<ModuleProvision>(moduleProvision());
    const b = new Observable<ModuleProvision>(moduleProvision());
    const hub = new ProviderHub(() => now);
    hub.attach((id) => ({ a, b })[id]);
    hub.update(["a", "b"]);
    b.set(moduleProvision({ focus: running("b", NOW + 900) }));
    now += 60;
    a.set(moduleProvision({ focus: running("a", NOW + 1500) }));
    expect(hub.snapshot.get().focus?.source).toBe("a");
    now += 60;
    b.set(moduleProvision());
    b.set(moduleProvision({ focus: running("b", NOW + 2000) }));
    expect(hub.snapshot.get().focus?.source).toBe("b");
  });
});

describe("ModuleRegistry", () => {
  it("starts and stops modules as their switches change, and skips a duplicate id", () => {
    const log: string[] = [];
    const types = [recordingModule("a", log), recordingModule("b", log), recordingModule("a", log)];
    const errors: string[] = [];
    const registry = new ModuleRegistry(
      types.map((type) => type.create({} as never)),
      { debug: () => {}, info: () => {}, warning: () => {}, error: (message) => errors.push(message) },
    );
    expect(registry.catalog.ids).toEqual(["a", "b"]);
    expect(errors).toEqual(["Two modules share an id: a"]);
    registry.update(["b", "a", "unknown"]);
    registry.update(["a"]);
    registry.stopAll();
    expect(log.filter((line) => !line.startsWith("create"))).toEqual(["start b", "start a", "stop b", "stop a"]);
  });

  it("hands an action only to a running module", () => {
    const performed: string[] = [];
    const module = { descriptor: recordingModule("a", []).descriptor, Panel: () => null, perform: (action: { id: string }) => performed.push(action.id) };
    const registry = new ModuleRegistry([module]);
    registry.perform({ id: "study", title: "Study" }, "a");
    registry.update(["a"]);
    registry.perform({ id: "study", title: "Study" }, "a");
    expect(performed).toEqual(["study"]);
  });
});

describe("SharedServices", () => {
  it("makes each service once", () => {
    const shared = new SharedServices();
    const key = serviceKey<{ n: number }>("test");
    let made = 0;
    const first = shared.resolve(key, () => ({ n: ++made }));
    expect(shared.resolve(key, () => ({ n: ++made }))).toBe(first);
    expect(made).toBe(1);
    expect(shared.existing(serviceKey<number>("test"))).toBeUndefined();
  });
});

describe("EditionFolders", () => {
  it("names a module's documents inside its folder", async () => {
    const host = mockHost();
    const storage = EditionFolders.live(host);
    await storage.folder("Planner").write("tasks.json", "[]");
    expect(host.documents.get("durable:Planner/tasks")).toBe("[]");
    expect(await storage.folder("Planner").list("")).toEqual(["tasks.json"]);
    await storage.folder("Calendars", "cache").write("feed.json", "{}");
    expect(host.documents.has("cache:Calendars/feed")).toBe(true);
    expect(new FolderDocumentStore(new InMemoryDocumentStore(), "A").folder).toBe("A");
  });
});

describe("ActivityLog", () => {
  it("keeps records in memory in demo runs and tells followers", async () => {
    const log = new ActivityLog(undefined, () => "UTC");
    const heard: string[] = [];
    log.recorded((record) => heard.push(record.kind));
    const record = makeActivityRecord({ source: "leetcode", kind: "problem.solved", start: NOW });
    expect(await log.record(record)).toBe(false);
    expect(heard).toEqual(["problem.solved"]);
    expect((await log.records("2026-09-21")).map((r) => r.id)).toEqual([record.id]);
  });

  it("saves records to day files", async () => {
    const store = new InMemoryDocumentStore();
    const log = new ActivityLog(new ActivityLogRepository(store, "UTC"), () => "UTC");
    expect(await log.record([makeActivityRecord({ source: "focus", kind: "focus.completed", start: NOW - 1500, end: NOW })])).toBe(true);
    expect(Object.keys(store.snapshot())).toEqual(["Activity/2026-09-21.json"]);
    expect(await log.records("2026-09-21")).toHaveLength(1);
  });
});

describe("SettingsStore", () => {
  const catalog = new ModuleCatalog(MODULE_LIST.map((type) => type.descriptor));

  it("saves every change to the preferences document and loads it back", async () => {
    const store = new InMemoryDocumentStore();
    const settings = await SettingsStore.load({ catalog, kits: BUNDLED_KITS, store });
    settings.update((s) => ({ ...s, themeID: "cozy", panelSize: "large" }));
    settings.setIslandMode("alwaysVisible");
    await settings.flush();
    expect(store.snapshot()[SETTINGS_DOCUMENT]).toContain('"settings.theme": "cozy"');
    const again = await SettingsStore.load({ catalog, kits: BUNDLED_KITS, store });
    expect(again.current.themeID).toBe("cozy");
    expect(again.current.panelSize).toBe("large");
    expect(again.islandMode.get()).toBe("alwaysVisible");
  });

  it("tells modules about kit switches, resets and undos", () => {
    const settings = SettingsStore.inMemory({ catalog, kits: BUNDLED_KITS });
    const heard: string[] = [];
    settings.kitApplied((application: KitApplication) => heard.push(`${application.kind} ${application.kit.id}`));
    const before = settings.current.kitID;
    settings.switchKit("medicine");
    expect(settings.current.kitID).toBe("medicine");
    expect(settings.lastKitSwitch.get()?.kitName).toBeTruthy();
    settings.resetToKitDefaults();
    settings.undoKitSwitch();
    expect(settings.current.kitID).toBe(before);
    expect(heard).toEqual(["switched medicine", "reset medicine", `undo ${before}`]);
    expect(settings.lastKitSwitch.get()).toBeUndefined();
  });

  it("hands changes and kit switches to the other windows", () => {
    const bus = new MockWindowBus();
    const island = SettingsStore.inMemory({ catalog, kits: BUNDLED_KITS, channel: hostChannel(mockHost(undefined, { bus }), "settings") });
    const window = SettingsStore.inMemory({ catalog, kits: BUNDLED_KITS, channel: hostChannel(mockHost(undefined, { bus }), "settings") });
    const heard: string[] = [];
    island.kitApplied((application) => heard.push(application.kind));
    window.update((s) => ({ ...s, themeID: "forest" }));
    window.setIslandMode("showOnHover");
    expect(island.current.themeID).toBe("forest");
    expect(island.islandMode.get()).toBe("showOnHover");
    window.switchKit("medicine");
    expect(island.current.kitID).toBe("medicine");
    expect(island.current.themeID).toBe(window.current.themeID);
    expect(heard).toEqual(["switched"]);
  });
});

