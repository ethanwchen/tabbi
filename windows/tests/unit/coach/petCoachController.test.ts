// The pet coach on the runtime: it samples the host only during a focus
// phase with nudges on, glances then nudges after time in a distracting
// app, puts its scene in the closed overlay slot, closes it once the pet is
// home, and keeps its save beside the pet's.
import { beforeAll, describe, expect, it } from "vitest";
import { closedOverlaySlot } from "../../../src/app/takeover";
import { Observable } from "../../../src/app/store";
import { PetCoach } from "../../../src/core/coach/petCoach";
import { moduleProvision, type ModuleProvision } from "../../../src/core/providers/moduleProvision";
import { ProvidedFocus } from "../../../src/core/providers/providedFocus";
import { MODULE_LIST } from "../../../src/modules/moduleList";
import { ClosetModule } from "../../../src/modules/closet/closetModule";
import type { PetCoachController } from "../../../src/modules/closet/coach/petCoachController";
import { switchLanguage } from "../../support/catalogs";
import { recordingModule, testApp } from "../../support/runtime";

const NOW = 1_790_000_000;

beforeAll(() => switchLanguage("en"));

const settle = async () => {
  for (let i = 0; i < 4; i++) await new Promise((resolve) => setTimeout(resolve, 0));
};

/* The coach's private sampler and answer, driven by hand so the test needs no fake timers. */
type Testable = { sample(): Promise<void>; answer(reply: "backToIt"): void; sampler: unknown; isRunning: boolean };
const inside = (coach: PetCoachController) => coach as unknown as Testable;

describe("PetCoachController", () => {
  it("nudges after time in a distracting app during a focus phase, and sends the pet home on an answer", async () => {
    const log: string[] = [];
    const provision = new Observable<ModuleProvision>(moduleProvision());
    const timer = recordingModule("timer", log, provision);
    const entries = { "settings.modules.order": ["timer", "closet"], "settings.modules.disabled": [] };
    const { app, host, clock } = await testApp({ moduleTypes: [timer, ...MODULE_LIST], settingsEntries: entries }, NOW);
    const closet = app.modules.instance(ClosetModule);
    if (!closet) throw new Error("no closet");
    const coach = closet.coach;
    host.coachSample = () => Promise.resolve({ idleSeconds: 0, frontmost: "Discord.exe" });
    coach.toggleDistracting("Discord.exe");
    const slot = closedOverlaySlot(app.shared);
    await settle();

    /* No focus phase: no sampler at all. */
    expect(inside(coach).sampler).toBeUndefined();
    provision.set(moduleProvision({ focus: new ProvidedFocus({ source: "timer", phase: "focus", clock: { kind: "countdown", endsAt: NOW + 25 * 60 }, phaseLength: 25 * 60, focusLength: 25 * 60 }) }));
    expect(inside(coach).sampler).toBeDefined();
    const step = async (seconds: number) => {
      for (let passed = 0; passed < seconds; passed += PetCoach.sampleInterval) {
        clock.now += PetCoach.sampleInterval;
        await inside(coach).sample();
      }
    };
    /* 30 s in a distracting app: a silent glance. */
    await step(35);
    expect(coach.state.scene?.line.kind).toBe("glance");
    expect(slot.get()).toBeDefined();
    /* Two minutes in: a bubble with its answers. */
    await step(100);
    const scene = coach.state.scene;
    expect(scene?.line.kind).toBe("nudge");
    expect(scene?.line.kind === "nudge" ? scene.line.nudge.kind : undefined).toBe("distraction");
    await settle();
    expect(host.documents.get("durable:Pet/coach")).toContain('"distracting"');

    /* Answering turns the pet around where it stands. */
    clock.now += 3;
    const stroll = scene?.stroll;
    if (!stroll) throw new Error("no stroll");
    inside(coach).answer("backToIt");
    expect(stroll.dismissedAt).toBe(clock.now);
    expect(stroll.endsAt).toBeLessThan(clock.now + 2);

    /* Nudges off: the sampler stops and the lists stay. */
    coach.setNudgesOn(false);
    expect(inside(coach).sampler).toBeUndefined();
    expect(coach.state.scene).toBeUndefined();
    expect(slot.get()).toBeUndefined();
    expect(coach.state.apps.isDistracting("discord.exe")).toBe(true);
  });

  it("never runs in a demo and keeps the demo's app lists", async () => {
    const { app } = await testApp({ moduleTypes: MODULE_LIST, settingsEntries: { "settings.modules.order": ["closet"], "settings.modules.disabled": [] }, runMode: { isDemo: true, isSnapshot: false } }, NOW);
    const closet = app.modules.instance(ClosetModule);
    if (!closet) throw new Error("no closet");
    expect(inside(closet.coach).isRunning).toBe(false);
    expect(inside(closet.coach).sampler).toBeUndefined();
    expect(closet.coach.state.apps.isDistracting("Discord.exe")).toBe(true);
    expect(closet.coach.state.apps.addedDistracting).toEqual(["spotify.exe"]);
  });
});
