// The Windows OnboardingStore: it runs the core flow, applies the kit and
// tabs as soon as the flow leaves the tab step, then asks Windows' own two
// steps, and the tray hint comes back never.
import { describe, expect, it } from "vitest";
import { MODULE_LIST } from "../../../src/modules/moduleList";
import { OnboardingStore, WINDOWS_ONBOARDING_EXTRAS } from "../../../src/ui/onboarding/onboardingStore";
import { testApp } from "../../support/runtime";

async function fresh(entries: Record<string, unknown> = {}) {
  const { app } = await testApp({ moduleTypes: MODULE_LIST, settingsEntries: { "settings.kit.chosen": false, ...entries } });
  return { app, store: new OnboardingStore(app) };
}

describe("OnboardingStore", () => {
  it("passes only the extras that apply on Windows", () => {
    expect(WINDOWS_ONBOARDING_EXTRAS.map((extra) => extra.id)).toEqual(["reminder", "invites"]);
  });

  it("asks the name first on a fresh install, then the flow, then Start with Windows and the tray hint", async () => {
    const { app, store } = await fresh();
    store.start();
    expect(store.step.kind).toBe("name");
    const kinds = store.steps.map((step) => step.kind);
    expect(kinds.slice(0, 2)).toEqual(["name", "kit"]);
    expect(kinds.slice(-2)).toEqual(["startWithWindows", "trayIcon"]);
    expect(app.takeover.get()).toBeUndefined();

    /* Walk to the end. */
    for (let guard = 0; guard < 40 && store.isActive; guard++) store.next();
    expect(store.isActive).toBe(false);
    expect(app.settings.current.hasChosenKit).toBe(true);
    expect(app.settings.trayHintShown).toBe(true);
  });

  it("applies the kit and tabs when leaving the tab step, before Windows' steps", async () => {
    const { app, store } = await fresh();
    store.start();
    store.next();
    const medicine = app.settings.kits.get("medicine");
    if (!medicine) throw new Error("no medicine kit");
    store.update((flow) => flow.choose(medicine));
    expect(store.step.kind).toBe("question");
    while (store.step.kind !== "modules") store.next();
    expect(app.settings.current.hasChosenKit).toBe(false);
    store.update((flow) => void flow.setEnabled("system", true));
    store.next();
    expect(app.settings.current.hasChosenKit).toBe(true);
    expect(app.settings.current.kitID).toBe("medicine");
    expect(app.settings.current.modules.isEnabled("system")).toBe(true);
  });

  it("goes back from Windows' first step into the flow's last and skips the tray hint once shown", async () => {
    const { app, store } = await fresh({ "settings.kit.chosen": true, "settings.displayName": "Ana" });
    app.settings.markTrayHintShown();
    store.start();
    expect(store.step.kind).toBe("kit");
    expect(store.steps.at(-1)?.kind).toBe("startWithWindows");
    while (store.step.kind !== "startWithWindows") store.next();
    expect(store.isLastStep).toBe(true);
    store.back();
    expect(store.step.kind).not.toBe("startWithWindows");
    store.next();
    expect(store.step.kind).toBe("startWithWindows");
    store.finish();
    expect(store.isActive).toBe(false);
  });

  it("re-running switches kits only when the pick changed", async () => {
    const { app, store } = await fresh({ "settings.kit.chosen": true, "settings.displayName": "Ana" });
    const heard: string[] = [];
    app.settings.kitApplied((application) => heard.push(application.kind));
    store.start();
    for (let guard = 0; guard < 40 && store.isActive; guard++) store.next();
    expect(heard).toEqual([]);
  });
});
