// The Windows additions to SettingsStore: imported kits with undo, Start with
// Windows through the host, the hotkey through the host, and the keys the
// Windows Settings keep beside the Mac's.
import { describe, expect, it } from "vitest";
import { ImportedKitStore } from "../../../src/core/kits/importedKitStore";
import { KitLibrary } from "../../../src/core/kits/kitLibrary";
import { BUNDLED_KITS } from "../../../src/core/kits/bundledKits";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { HOTKEY_MODIFIERS } from "../../../src/core/settings/hotkey";
import { hostChannel } from "../../../src/app/windowChannel";
import { SettingsStore, type SystemIntegration } from "../../../src/app/settingsStore";
import { mockHost, MockWindowBus } from "../../../src/host/mock";
import { BUILT_IN_CATALOG } from "../../support/builtInCatalog";

const catalog = BUILT_IN_CATALOG;
const kitText = `{"formatVersion":1,"id":"deep-work","name":"Deep Work","modules":["planner","spotify"],"starterTasks":["Plan the week"]}`;

function system(taken: string[] = []): SystemIntegration & { autostart: boolean; registered: string[] } {
  const state = {
    autostart: false,
    registered: [] as string[],
    autostartEnable: async () => {
      state.autostart = true;
    },
    autostartDisable: async () => {
      state.autostart = false;
    },
    autostartIsEnabled: async () => state.autostart,
    setHotkey: async (shortcut: string | null) => {
      state.registered.push(shortcut ?? "none");
      return { shortcut: shortcut ?? "", registered: shortcut !== null && !taken.includes(shortcut) };
    },
  };
  return state;
}

async function storeWithKits() {
  const documents = new InMemoryDocumentStore();
  const kits = new KitLibrary(BUNDLED_KITS.kits);
  const store = await SettingsStore.load({ catalog, kits, store: documents, kitStore: new ImportedKitStore(documents) });
  return { store, documents, kits };
}

describe("SettingsStore on Windows", () => {
  it("imports a kit, switches to it, and undo takes the file and the tabs back", async () => {
    const { store, documents, kits } = await storeWithKits();
    const before = store.current.kitID;
    const inspection = await store.inspectKit(kitText, "deep-work.json");
    if (!inspection.ok) throw new Error(inspection.error.kind);
    await store.installKit(inspection.candidate, {});
    expect(store.current.kitID).toBe("imported.deep-work");
    expect(store.current.modules.enabled).toEqual(["planner", "spotify"]);
    expect(kits.get("imported.deep-work")?.name).toBe("Deep Work");
    expect(store.canRemoveActiveKit).toBe(true);
    expect(store.lastKitSwitch.get()?.switchedKit).toBe(true);

    await store.undoKitSwitch();
    expect(store.current.kitID).toBe(before);
    expect(kits.get("imported.deep-work")).toBeUndefined();
    expect(Object.keys(documents.snapshot()).filter((name) => name.startsWith("Kits/"))).toEqual([]);
  });

  it("adds a kit without switching, and removing the active import falls back to the default kit", async () => {
    const { store, kits } = await storeWithKits();
    const inspection = await store.inspectKit(kitText, "deep-work.json");
    if (!inspection.ok) throw new Error(inspection.error.kind);
    await store.installKit(inspection.candidate, undefined);
    expect(store.current.kitID).toBe("essentials");
    expect(store.lastKitSwitch.get()?.switchedKit).toBe(false);
    store.switchKit("imported.deep-work");
    expect(store.canRemoveActiveKit).toBe(true);
    await store.removeActiveKit();
    expect(store.current.kitID).toBe("essentials");
    expect(kits.get("imported.deep-work")).toBeUndefined();
    expect(store.lastKitSwitch.get()?.kitName).toBe("Deep Work");
    await store.undoKitSwitch();
    expect(store.current.kitID).toBe("imported.deep-work");
  });

  it("refuses a kit that shadows a bundled one", async () => {
    const { store } = await storeWithKits();
    const inspection = await store.inspectKit(`{"formatVersion":1,"id":"medicine","name":"Mine","modules":["planner"]}`, "m.json");
    expect(inspection.ok ? undefined : inspection.error.kind).toBe("reservedID");
  });

  it("tells the other window when the kit files change", async () => {
    const bus = new MockWindowBus();
    const documents = new InMemoryDocumentStore();
    const island = await SettingsStore.load({ catalog, kits: new KitLibrary(BUNDLED_KITS.kits), store: documents, kitStore: new ImportedKitStore(documents), channel: hostChannel(mockHost(undefined, { bus }), "settings") });
    const window = await SettingsStore.load({ catalog, kits: new KitLibrary(BUNDLED_KITS.kits), store: documents, kitStore: new ImportedKitStore(documents), channel: hostChannel(mockHost(undefined, { bus }), "settings") });
    const inspection = await window.inspectKit(kitText, "deep-work.json");
    if (!inspection.ok) throw new Error(inspection.error.kind);
    await window.installKit(inspection.candidate, undefined);
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(island.kits.get("imported.deep-work")?.name).toBe("Deep Work");
    expect(island.kitsChanged.get()).toBe(1);
    const heard: number[] = [];
    island.setupRequested(() => heard.push(1));
    window.requestSetup();
    expect(heard).toEqual([1]);
  });

  it("drives Start with Windows through the host and records only what Windows accepted", async () => {
    const integration = system();
    const store = SettingsStore.inMemory({ catalog, kits: BUNDLED_KITS, system: integration });
    expect(store.current.launchAtLogin).toBe(false);
    await store.setLaunchAtLogin(true);
    expect(integration.autostart).toBe(true);
    expect(store.current.launchAtLogin).toBe(true);
    integration.autostart = false;
    await store.refreshLaunchAtLogin();
    expect(store.current.launchAtLogin).toBe(false);
  });

  it("registers the hotkey through the host, reports a taken one, and suspends it while recording", async () => {
    const integration = system(["ctrl+shift+KeyT"]);
    const store = SettingsStore.inMemory({ catalog, kits: BUNDLED_KITS, system: integration, hotkeyStatus: { shortcut: "ctrl+alt+space", registered: true } });
    await store.registerSavedHotkey();
    expect(integration.registered).toEqual([]);
    const status = await store.setHotkey({ keyCode: 17, modifiers: HOTKEY_MODIFIERS.control | HOTKEY_MODIFIERS.shift });
    expect(status).toEqual({ shortcut: "ctrl+shift+KeyT", registered: false });
    expect(store.hotkeyStatus.get()?.registered).toBe(false);
    await store.suspendHotkey(true);
    await store.suspendHotkey(false);
    expect(integration.registered).toEqual(["ctrl+shift+KeyT", "none", "ctrl+shift+KeyT"]);
    store.resetGeneral();
    expect(integration.registered.at(-1)).toBe("ctrl+alt+Space");
  });

  it("keeps Reduce Motion, the crash report choice and the tray hint beside the Mac's keys", async () => {
    const documents = new InMemoryDocumentStore();
    const store = await SettingsStore.load({ catalog, kits: BUNDLED_KITS, store: documents });
    expect(store.reduceMotion.get()).toBe(false);
    expect(store.crashReportConsent.get()).toBe("ask");
    expect(store.trayHintShown).toBe(false);
    store.setReduceMotion(true);
    store.setCrashReportConsent("alwaysSend");
    store.markTrayHintShown();
    await store.flush();
    const again = await SettingsStore.load({ catalog, kits: BUNDLED_KITS, store: documents });
    expect(again.reduceMotion.get()).toBe(true);
    expect(again.crashReportConsent.get()).toBe("alwaysSend");
    expect(again.trayHintShown).toBe(true);
    const saved = JSON.parse(documents.snapshot()["settings.json"] ?? "{}") as Record<string, unknown>;
    expect(saved["settings.crashReports"]).toBe("alwaysSend");
    expect(saved["windows.reduceMotion"]).toBe(true);
  });
});
