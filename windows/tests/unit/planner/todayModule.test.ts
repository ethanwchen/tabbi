import { describe, expect, it } from "vitest";
import { MODULE_IDS } from "../../../src/core/modules/moduleId";
import { DEMO_RUN_MODE } from "../../../src/core/modules/runMode";
import { MODULE_LIST } from "../../../src/modules/moduleList";
import { TodayModule } from "../../../src/modules/planner/todayModule";
import { ScheduleModule } from "../../../src/modules/schedule/scheduleModule";
import { testApp } from "../../support/runtime";

/* 2026-10-15 09:00 UTC, a Thursday. */
const MORNING = 1_792_054_800;

describe("Today module", () => {
  it("shares its checklist, today's events and the Pomodoro with the hub, and keeps the sample day in demo mode", async () => {
    const { app } = await testApp({ moduleTypes: MODULE_LIST, runMode: DEMO_RUN_MODE }, MORNING);
    const today = app.modules.instance(TodayModule);
    expect(today).toBeDefined();
    if (today === undefined) return;
    await today.store.ready;
    today.store.upNext.setVisible(true);
    await today.store.upNext.reload();
    const snapshot = app.providers.snapshot.get();
    expect(snapshot.tasks.filter((task) => task.source === MODULE_IDS.planner).length).toBe(3);
    expect(snapshot.events.length).toBeGreaterThan(0);
    /* The merged clock may be another module's (the Study timer in demo); Today's own provision carries the Pomodoro. */
    expect(today.provision?.get().focus?.source).toBe(MODULE_IDS.planner);
    today.store.upNext.setVisible(false);
    app.dispose();
  });

  it("edits today's list and saves each change as the Mac's day file", async () => {
    const { app, host } = await testApp({ moduleTypes: MODULE_LIST }, MORNING);
    const today = app.modules.instance(TodayModule);
    if (today === undefined) throw new Error("Today is missing");
    await today.store.ready;
    expect(today.store.add("  Read   chapter 4 ")).toBe(true);
    expect(today.store.add("   ")).toBe(false);
    const item = today.store.items[0];
    if (item === undefined) throw new Error("no item");
    expect(item.title).toBe("Read chapter 4");
    today.store.toggle(item.id);
    expect(today.store.items[0]?.isDone).toBe(true);
    await new Promise((resolve) => setTimeout(resolve, 0));
    const key = [...host.documents.keys()].find((name) => name.includes("2026-10-15"));
    const text = key === undefined ? undefined : host.documents.get(key);
    expect(key).toBe("durable:Planner/2026-10-15");
    expect(text).toContain("\"schemaVersion\" : 2");
    expect(text).toContain("Read chapter 4");
    today.store.show("yesterday");
    expect(today.store.canEdit).toBe(false);
    expect(today.store.add("Nope")).toBe(false);
    app.dispose();
  });

  it("builds the Schedule over the same calendar and kept blocks", async () => {
    const { app } = await testApp({ moduleTypes: MODULE_LIST, runMode: DEMO_RUN_MODE }, MORNING);
    const schedule = app.modules.instance(ScheduleModule);
    if (schedule === undefined) throw new Error("Schedule is missing");
    expect(schedule.store.dayLayout.placed.length).toBeGreaterThan(0);
    schedule.store.planDay();
    expect(schedule.store.state.draft?.isEmpty).toBe(false);
    const first = schedule.store.state.draft?.items[0];
    if (first === undefined) throw new Error("no block");
    await schedule.store.add(first.id);
    expect(schedule.store.state.items.some((item) => item.kind === "planned" && item.title === first.title)).toBe(true);
    app.dispose();
  });

  it("makes stores that snapshot runs can drive without a host", async () => {
    const { app } = await testApp({ moduleTypes: [TodayModule], runMode: { isDemo: true, isSnapshot: true } }, MORNING);
    const today = app.modules.instance(TodayModule);
    if (today === undefined) throw new Error("Today is missing");
    await today.showSnapshotState?.("plan");
    expect(today.store.plan.state.phase.kind).toBe("proposal");
    await today.showSnapshotState?.("review-loading");
    expect(today.store.review.isSummarizing).toBe(true);
    app.dispose();
  });
});
