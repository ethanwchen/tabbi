import { afterEach, describe, expect, it } from "vitest";
import { StudyCustomRhythm } from "../../../src/core/studyMethods/studyCustomRhythm";
import { StudyTimerLength } from "../../../src/core/studyMethods/studyTimerLength";
import { FocusModule } from "../../../src/modules/focus/focusModule";
import { MODULE_LIST } from "../../../src/modules/moduleList";
import { StudyModule } from "../../../src/modules/study/studyModule";
import type { StudyStore } from "../../../src/modules/study/studyStore";
import { testApp, type TestApp } from "../../support/runtime";

/* The Study store over the mock host at a pinned clock: the session, its saving, the log, deep focus, kits and the demo. */

const NOW = 1_790_000_000;
let apps: TestApp[] = [];

afterEach(() => {
  for (const { app } of apps) app.dispose();
  apps = [];
});

async function studyApp(options: { demo?: boolean } = {}): Promise<TestApp & { store: StudyStore }> {
  const made = await testApp({ moduleTypes: MODULE_LIST, ...(options.demo ? { runMode: { isDemo: true, isSnapshot: false } } : {}) }, NOW);
  apps.push(made);
  const module = made.app.modules.instance(StudyModule);
  if (module === undefined) throw new Error("no Study module");
  await module.store.ready;
  return { ...made, store: module.store };
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("StudyStore", () => {
  it("starts on the kit's method, saves the session in the Study folder and shares the block as the focus clock", async () => {
    const { app, host, clock, store } = await studyApp();
    expect(store.session.method.kind).toBe("timer");
    store.choose("pomodoro");
    store.primaryAction();
    expect(store.session.isRunning).toBe(true);
    await settle();
    expect(host.documents.get("durable:Study/preferences")).toContain('"study.session"');
    const provision = app.modules.provision("study")?.get();
    expect(provision?.focus?.source).toBe("study");
    expect(provision?.focus?.endsAt).toBe(NOW + 25 * 60);
    expect(provision?.progress[0]?.title).toBe("Focus time");
    clock.now += 60;
    store.pause();
    expect(store.session.runState).toBe("paused");
    store.dispose();
  });

  it("rolls a finished block into the break, the study log and the activity log, and the pet celebrates", async () => {
    const { app, host, clock, store } = await studyApp();
    let bursts = 0;
    store.celebrations.on(() => bursts++);
    store.choose("pomodoro");
    store.setVisible(true);
    store.primaryAction();
    clock.now += 25 * 60 + 2;
    store.setVisible(false);
    store.setVisible(true);
    expect(store.session.phase).toBe("shortBreak");
    expect(store.session.isRunning).toBe(true);
    expect(store.session.completedFocusCount).toBe(1);
    expect(store.today).toEqual({ minutes: 25, sessions: 1, points: expect.any(Number) });
    expect(bursts).toBe(1);
    await settle();
    expect(host.documents.get("durable:Study/log")).toContain('"schemaVersion"');
    const records = await app.activityLog.records("2026-09-21");
    expect(records.map((record) => [record.source, record.kind, record.quantity])).toEqual([["study", "focus.completed", 25]]);
    store.setVisible(false);
    store.dispose();
  });

  it("drives focus mode only with deep focus on", async () => {
    const { app, store } = await studyApp();
    const controller = app.modules.instance(FocusModule)?.controller;
    store.setEnabled(true);
    store.choose("pomodoro");
    store.primaryAction();
    expect(controller?.isFocusing).toBe(false);
    store.setDeepFocus(true);
    expect(controller?.isFocusing).toBe(true);
    store.stop();
    expect(controller?.isFocusing).toBe(false);
    store.dispose();
  });

  it("takes on Custom lengths and Timer chips at once", async () => {
    const { store } = await studyApp();
    store.startTimer(new StudyTimerLength(25));
    expect(store.session.isRunning).toBe(true);
    expect(store.session.phaseDuration).toBe(25 * 60);
    store.stop();
    store.choose("custom");
    store.setCustom(new StudyCustomRhythm({ focusMinutes: 45, breakMinutes: 10, hasLongBreak: true }));
    expect(store.session.method.rhythmLabel).toBe("45/10");
    expect(store.methods.find((method) => method.kind === "custom")?.longBreak?.every).toBe(4);
    store.dispose();
  });

  it("follows a kit switch to its starting method while idle, and keeps a running block", async () => {
    const { app, store } = await studyApp();
    app.settings.switchKit("medicine");
    expect(store.state.menu.kinds).toContain("ankiSprint");
    expect(store.session.method.kind).toBe(store.state.menu.startingKind);
    store.primaryAction();
    const running = store.session.method.kind;
    app.settings.undoKitSwitch();
    expect(store.session.method.kind).toBe(running);
    store.dispose();
  });

  it("shows a Pomodoro on its second round and a morning's log in demo mode, and every method on request", async () => {
    const { host, store } = await studyApp({ demo: true });
    expect(store.session.method.kind).toBe("pomodoro");
    expect(store.session.completedFocusCount).toBe(1);
    expect(store.session.remaining(NOW)).toBe(18 * 60 + 42);
    expect(store.today).toEqual({ minutes: 64, sessions: 3, points: expect.any(Number) });
    expect(store.state.deepFocus).toBe(true);
    store.showDemoMethod("flowtime");
    expect(store.session.method.focus.kind).toBe("openEnded");
    expect(store.session.elapsed(NOW)).toBe(23 * 60 + 12);
    store.showDemoMethod("ankiSprint");
    expect(store.session.cardsDone).toBe(37);
    store.showDemoMethod("pomodoro", true);
    expect(store.session.runState).toBe("paused");
    expect(host.calls.filter((call) => call.name.startsWith("storage"))).toEqual([]);
  });
});
