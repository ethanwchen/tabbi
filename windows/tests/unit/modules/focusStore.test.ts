import { afterEach, describe, expect, it } from "vitest";
import { FocusMix } from "../../../src/core/focus/focusMix";
import { FocusSettings } from "../../../src/core/focus/focusSettings";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { FocusController, playlistLink } from "../../../src/modules/focus/focusController";
import { FocusModule } from "../../../src/modules/focus/focusModule";
import { FocusStore } from "../../../src/modules/focus/focusStore";
import { ModulePreferences } from "../../../src/modules/focus/modulePreferences";
import { MODULE_LIST } from "../../../src/modules/moduleList";
import { StudyModule } from "../../../src/modules/study/studyModule";
import { testApp, type TestApp } from "../../support/runtime";

/* The Pomodoro store over the mock host at a pinned clock: saving, the shared clock, phase ends with a toast, and the settings side. */

const NOW = 1_790_000_000;
let apps: TestApp[] = [];

afterEach(() => {
  for (const { app } of apps) app.dispose();
  apps = [];
});

async function focusApp(options: { demo?: boolean } = {}): Promise<TestApp & { store: FocusStore; controller: FocusController }> {
  const made = await testApp({ moduleTypes: MODULE_LIST, ...(options.demo ? { runMode: { isDemo: true, isSnapshot: false } } : {}) }, NOW);
  apps.push(made);
  const module = made.app.modules.instance(FocusModule);
  if (module === undefined) throw new Error("no Focus module");
  await module.store.ready;
  return { ...made, store: module.store, controller: module.controller };
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("FocusStore", () => {
  it("saves the timer in the Focus folder and keeps time from the wall clock", async () => {
    const { host, clock, store } = await focusApp();
    expect(store.state.timer.runState.kind).toBe("idle");
    store.start();
    expect(store.state.timer.endsAt).toBe(NOW + 25 * 60);
    await settle();
    const saved = host.documents.get("durable:Focus/preferences");
    expect(saved).toContain('"focus.timer"');
    expect(saved).toContain('"focus.lastAlive"');
    clock.now += 60;
    store.pause();
    expect(store.state.timer.runState).toEqual({ kind: "paused", remaining: 24 * 60 });
    store.dispose();
  });

  it("rolls into the break when the focus phase ends, toasts once, logs the stretch and celebrates", async () => {
    const { app, host, clock, store } = await focusApp();
    const bursts: string[] = [];
    store.celebrations.on((celebration) => bursts.push(celebration.style));
    store.start();
    clock.now += 25 * 60 + 5;
    store.setVisible(true, "focus");
    expect(store.state.timer.phase).toBe("rest");
    expect(store.state.timer.completedFocusCount).toBe(1);
    expect(host.calls.filter((call) => call.name === "notify").map((call) => call.args)).toEqual([["Focus session done", "Time for a 5-minute break."]]);
    expect(bursts).toEqual(["confetti"]);
    const records = await app.activityLog.records("2026-09-21");
    expect(records.map((record) => [record.source, record.kind, record.quantity])).toEqual([["focus", "focus.completed", 25]]);
    await settle();
    expect(store.state.sessionsToday).toBe(1);
    store.setVisible(false, "focus");
    store.dispose();
  });

  it("keeps a stale end quiet and banks a stopped stretch", async () => {
    const { app, host, clock, store } = await focusApp();
    store.start();
    clock.now += 60 * 60;
    store.skip();
    expect(host.calls.some((call) => call.name === "notify")).toBe(false);
    /* The hour ran through the focus and its break; the skip moved the idle timer to a break, and one more back to focus. */
    expect(store.state.timer.phase).toBe("rest");
    store.skip();
    store.start();
    clock.now += 10 * 60;
    store.stop();
    const records = await app.activityLog.records("2026-09-21");
    expect(records.map((record) => [record.kind, record.metadata.outcome])).toEqual([
      ["focus.completed", "completed"],
      ["break.taken", "completed"],
      ["focus.completed", "abandoned"],
    ]);
    store.dispose();
  });

  it("shows a running sample session in demo mode and saves nothing", async () => {
    const { host, store } = await focusApp({ demo: true });
    expect(store.state.timer.isRunning).toBe(true);
    expect(store.state.sessionsToday).toBe(2);
    store.pause();
    expect(host.calls.filter((call) => call.name.startsWith("storage"))).toEqual([]);
  });

  it("is the one timer the Timer module drives focus mode beside", async () => {
    const { app, store, controller } = await focusApp();
    const study = app.modules.instance(StudyModule);
    expect(study).toBeDefined();
    const timers = app.modules.modules.map((module) => (module as { store?: unknown }).store).filter((candidate) => candidate instanceof FocusStore);
    expect(timers).toEqual([store]);
    expect(app.modules.instance(FocusModule)?.controller).toBe(controller);
  });
});

describe("FocusController", () => {
  it("follows the timer into focus mode, saves settings and takes a kit's sound", async () => {
    const { app, host, store, controller } = await focusApp();
    expect(controller.offersDoNotDisturb).toBe(false);
    controller.toggleSound("rain");
    expect(controller.settings.mix.summary).toBe("Rain");
    await settle();
    expect(host.documents.get("durable:Focus/preferences")).toContain('"focus.settings"');
    store.start();
    expect(controller.isFocusing).toBe(true);
    store.pause();
    expect(controller.isFocusing).toBe(false);
    app.settings.switchKit("medicine");
    const kit = app.settings.activeKit;
    expect(kit?.id).toBe("medicine");
    if (kit !== undefined) expect(controller.settings.usesKitDefaults(kit.defaults)).toBe(true);
    app.settings.undoKitSwitch();
    expect(controller.settings.mix.summary).toBe("Rain");
    store.dispose();
  });

  it("remembers a playlist and opens its web link, and shows sample settings when not live", () => {
    const opened: string[] = [];
    const preferences = new ModulePreferences(new InMemoryDocumentStore());
    const controller = new FocusController({ isLive: true, preferences, soundEngine: () => undefined, openLink: (url) => opened.push(url) });
    controller.choosePlaylist("spotify:playlist:37i9dQZF1DWZeKCadgRdKQ");
    expect(opened).toEqual(["https://open.spotify.com/playlist/37i9dQZF1DWZeKCadgRdKQ"]);
    expect(controller.playlistSourceName).toBe("Spotify");
    /* A library name only the Mac can play opens nothing. */
    controller.choosePlaylist("Deep Work");
    expect(opened).toHaveLength(1);
    expect(playlistLink({ kind: "appleMusicLink", url: "https://music.apple.com/us/playlist/x" })).toBe("https://music.apple.com/us/playlist/x");
    controller.openNotificationSettings();
    expect(opened.at(-1)).toBe("ms-settings:notifications");
    const sample = new FocusController({ isLive: false, preferences, soundEngine: () => undefined, openLink: () => {} });
    expect(sample.settings.equals(FocusController.sampleSettings)).toBe(true);
    expect(FocusSettings.default.mix.equals(FocusMix.off)).toBe(true);
  });
});
