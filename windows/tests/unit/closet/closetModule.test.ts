// The Closet module on the app runtime: the pet's save round-trips through
// the host's storage, points arrive from the activity log, the pet is
// shared as a provider, demo runs never write, and every snapshot state
// the harness lists is handled.
import { beforeAll, describe, expect, it } from "vitest";
import { ModuleContext } from "../../../src/app/context";
import { closedOverlaySlot, takeoverSlot } from "../../../src/app/takeover";
import { ACTIVITY_KINDS, ACTIVITY_UNITS, makeActivityRecord } from "../../../src/core/activity/activityRecord";
import { MODULE_IDS } from "../../../src/core/modules/moduleId";
import { DEMO_RUN_MODE } from "../../../src/core/modules/runMode";
import { MODULE_LIST } from "../../../src/modules/moduleList";
import { ClosetModule } from "../../../src/modules/closet/closetModule";
import { studyPet } from "../../../src/modules/closet/closetServices";
import { switchLanguage } from "../../support/catalogs";
import { testApp } from "../../support/runtime";

const NOW = 1_790_000_000;
const WITH_CLOSET = { "settings.modules.order": ["closet", "focus"], "settings.modules.disabled": [] };

beforeAll(() => switchLanguage("en"));

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("ClosetModule on the runtime", () => {
  it("starts on the kit's starter pet, saves edits to Pet/pet.json and reads them back on the next launch", async () => {
    const { app, host } = await testApp({ moduleTypes: MODULE_LIST, settingsEntries: WITH_CLOSET }, NOW);
    const closet = app.modules.instance(ClosetModule);
    expect(closet).toBeDefined();
    if (!closet) return;
    await settle();
    expect(closet.store.profile.name).toBe("British Shorthair");
    expect(closet.store.state.hasSave).toBe(false);
    closet.store.rename("Mochi");
    await settle();
    await settle();
    const saved = host.documents.get("durable:Pet/pet");
    expect(saved).toContain('"name": "Mochi"');
    expect(closet.store.state.hasSave).toBe(true);

    const again = await testApp({ moduleTypes: MODULE_LIST, settingsEntries: WITH_CLOSET, host }, NOW);
    const reloaded = again.app.modules.instance(ClosetModule);
    await settle();
    await settle();
    expect(reloaded?.store.profile.name).toBe("Mochi");
    expect(reloaded?.store.state.hasSave).toBe(true);
    /* Every module shares the one pet. */
    expect(studyPet(new ModuleContext(MODULE_IDS.study, again.app.environment))).toBe(reloaded?.store);
  });

  it("pays a focus stretch cut short from the activity log, shares the pet, and buys with the points", async () => {
    const { app } = await testApp({ moduleTypes: MODULE_LIST, settingsEntries: WITH_CLOSET }, NOW);
    const closet = app.modules.instance(ClosetModule);
    if (!closet) throw new Error("no closet");
    await settle();
    expect(closet.store.closet.balance).toBe(0);
    expect(closet.store.tap("accessory.beanie").kind).toBe("needsPoints");
    const awards: number[] = [];
    closet.store.awards.on((award) => awards.push(award.points));
    await app.activityLog.record(
      makeActivityRecord({
        source: MODULE_IDS.focus,
        kind: ACTIVITY_KINDS.focusCompleted,
        start: NOW - 40 * 60,
        end: NOW,
        quantity: 40,
        unit: ACTIVITY_UNITS.minutes,
        metadata: { outcome: "abandoned" },
      }),
    );
    expect(awards).toEqual([40]);
    expect(closet.store.closet.balance).toBe(40);
    expect(closet.store.tap("accessory.beanie").kind).toBe("boughtAndWore");
    expect(closet.store.profile.accessories).toEqual(["beanie"]);
    expect(app.providers.snapshot.get().pet?.profile.accessories).toEqual(["beanie"]);
    expect(closet.store.streak.length).toBe(1);
  });

  it("shows the demo closet, writes nothing, and handles every snapshot state it lists", async () => {
    const { app, host } = await testApp({ moduleTypes: MODULE_LIST, settingsEntries: WITH_CLOSET, runMode: { isDemo: true, isSnapshot: true } }, NOW);
    const closet = app.modules.instance(ClosetModule);
    if (!closet) throw new Error("no closet");
    expect(closet.store.profile.name).toBe("Mochi");
    expect(closet.store.profile.outfit).toBe("cozyHoodie");
    expect(closet.store.closet.balance).toBe(240);
    for (const state of ClosetModule.snapshotStates ?? []) {
      await closet.showSnapshotState(state);
    }
    expect(closet.store.state.section).toBe("activity");
    expect(closet.store.state.tryingOn).toBe("accessory.angelWings");
    expect(takeoverSlot(app.shared).get()).toBeDefined();
    closet.moment.dismiss();
    expect(takeoverSlot(app.shared).get()).toBeUndefined();
    await closet.showSnapshotState("long-name");
    expect(closet.store.profile.name).toBe("Wolfgang Wombats");
    for (const state of ClosetModule.closedSnapshotStates ?? []) {
      await closet.showSnapshotState(state);
      const overlay = closedOverlaySlot(app.shared).get();
      expect(overlay, state).toBeDefined();
      const rect = overlay?.rect({ pill: { x: 150, y: 0, width: 260, height: 40 }, canvas: { width: 560, height: 236 } });
      expect(rect?.x).toBeGreaterThanOrEqual(0);
      expect((rect?.x ?? 0) + (rect?.width ?? 0)).toBeLessThanOrEqual(560);
    }
    expect([...host.documents.keys()]).toEqual([]);
  });

  it("keeps the demo closet in a demo run without the snapshot flag and never writes either", async () => {
    const { app, host } = await testApp({ moduleTypes: MODULE_LIST, settingsEntries: WITH_CLOSET, runMode: DEMO_RUN_MODE }, NOW);
    const closet = app.modules.instance(ClosetModule);
    if (!closet) throw new Error("no closet");
    closet.store.rename("Pumpkin");
    await settle();
    expect(closet.store.profile.name).toBe("Pumpkin");
    expect(closet.store.state.milestones.studyDays.length).toBeGreaterThan(5);
    expect(closet.recaps.archive.recaps.length).toBe(4);
    expect([...host.documents.keys()]).toEqual([]);
  });
});
