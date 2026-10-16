import { afterEach, describe, expect, it } from "vitest";
import type { AppServices } from "../../../src/app/appServices";
import { memoryFromUsed } from "../../../src/core/system/memoryStats";
import { demoCPU, demoGPU, DEMO_CORE_COUNT, DEMO_TOTAL_MEMORY_BYTES } from "../../../src/core/system/systemDemoData";
import { HISTORY_CAPACITY, SystemMonitorState } from "../../../src/core/system/systemStats";
import type { SystemStats } from "../../../src/host/host";
import { SystemModule } from "../../../src/modules/system/systemModule";
import { readingFrom, type SystemStore } from "../../../src/modules/system/systemStore";
import { testApp, type TestApp } from "../../support/runtime";

/* Port of the SystemMonitor tests over the Windows host's readings: sampling only while seen, the first reading, the gap rule, the demo. */

const START = 1_790_000_000;
const GIB = 1_073_741_824;

function stats(fields: Partial<SystemStats> = {}): SystemStats {
  return {
    cpu: { total: 0.25, perCore: [0.5, 0.0] },
    memory: { usedBytes: 12 * GIB, totalBytes: 16 * GIB },
    gpu: 0.1,
    ...fields,
  };
}

function enable(app: AppServices, id: string): void {
  if (app.settings.current.modules.isEnabled(id)) return;
  app.settings.update((settings) => {
    const modules = settings.modules.clone();
    modules.add(id);
    return { ...settings, modules };
  });
}

let apps: TestApp[] = [];

async function systemApp(demo = false): Promise<TestApp & { store: SystemStore }> {
  const test = await testApp({ moduleTypes: [SystemModule], ...(demo ? { runMode: { isDemo: true, isSnapshot: false } } : {}) }, START);
  apps.push(test);
  enable(test.app, SystemModule.descriptor.id);
  const module = test.app.modules.instance(SystemModule);
  if (!module) throw new Error("System not registered");
  return { ...test, store: module.store };
}

afterEach(() => {
  for (const test of apps) test.app.dispose();
  apps = [];
});

const watchCalls = (host: TestApp["host"]) => host.calls.filter((call) => call.name === "systemWatch").map((call) => call.args[0]);

describe("SystemMonitorState.applyReading", () => {
  it("takes the host's usage under the gap rule, restarting the histories after a pause", () => {
    const state = new SystemMonitorState();
    state.applyReading({ capturedAt: START, gpu: 0.2, memory: { usedBytes: 8 * GIB, totalBytes: 16 * GIB } });
    expect(state.cpu).toBeUndefined();
    expect(state.gpu).toBe(0.2);
    expect(state.memory?.pressure).toBe("normal");
    expect(state.gpuHistory.elements).toEqual([0.2]);
    state.applyReading({ capturedAt: START + 1, cpu: { total: 0.4, perCore: [0.4] }, gpu: 1.4, memory: { usedBytes: 15 * GIB, totalBytes: 16 * GIB } });
    expect(state.cpu?.total).toBe(0.4);
    expect(state.cpuHistory.elements).toEqual([0.4]);
    expect(state.gpuHistory.elements).toEqual([0.2, 1]);
    expect(state.memory?.pressure).toBe("critical");
    expect(state.memoryHistory.elements).toEqual([0.5, 15 / 16]);
    /* Three seconds without a reading: the baseline is stale, so everything starts over. */
    state.applyReading({ capturedAt: START + 4, cpu: { total: 0.1, perCore: [0.1] }, gpu: 0.3 });
    expect(state.cpu).toBeUndefined();
    expect(state.cpuHistory.isEmpty).toBe(true);
    expect(state.gpuHistory.elements).toEqual([0.3]);
    expect(state.memory).toBeUndefined();
    expect(state.memoryHistory.isEmpty).toBe(true);
  });

  it("judges pressure from what is in use", () => {
    expect(memoryFromUsed(10 * GIB, 16 * GIB).pressure).toBe("normal");
    expect(memoryFromUsed(13.5 * GIB, 16 * GIB).pressure).toBe("warning");
    expect(memoryFromUsed(20 * GIB, 16 * GIB)).toEqual({ usedBytes: 16 * GIB, totalBytes: 16 * GIB, pressure: "critical" });
  });

  it("reads the host's nulls as absent", () => {
    expect(readingFrom({ cpu: null, memory: null, gpu: null }, START)).toEqual({ capturedAt: START });
    expect(readingFrom(stats(), START)).toEqual({ capturedAt: START, cpu: { total: 0.25, perCore: [0.5, 0] }, memory: { usedBytes: 12 * GIB, totalBytes: 16 * GIB }, gpu: 0.1 });
  });
});

describe("SystemStore", () => {
  it("samples only while a panel is visible, once for any number of viewers", async () => {
    const { host, store } = await systemApp();
    expect(watchCalls(host)).toEqual([]);
    store.setPanelVisible(true);
    store.setPanelVisible(true);
    expect(store.isSampling).toBe(true);
    expect(watchCalls(host)).toEqual([true]);
    store.setPanelVisible(false);
    expect(store.isSampling).toBe(true);
    store.setPanelVisible(false);
    expect(store.isSampling).toBe(false);
    expect(watchCalls(host)).toEqual([true, false]);
  });

  it("shows the first reading as measuring, then the load, and restarts after a gap", async () => {
    const { host, store, clock } = await systemApp();
    store.setPanelVisible(true);
    host.emitSystemStats(stats({ cpu: null }));
    expect(store.state.cpu).toBeUndefined();
    expect(store.state.cpuSeries.isEmpty).toBe(true);
    expect(store.state.gpu).toBe(0.1);
    expect(store.state.memory?.usedBytes).toBe(12 * GIB);
    clock.now = START + 1;
    host.emitSystemStats(stats());
    expect(store.state.cpu?.perCore).toEqual([0.5, 0]);
    expect(store.state.cpuSeries.points).toEqual([{ x: HISTORY_CAPACITY - 1, y: 0.25 }]);
    expect(store.state.gpuSeries.points.length).toBe(2);
    /* Hidden for a while, then shown again: the old window is not stretched over the gap. */
    store.setPanelVisible(false);
    clock.now = START + 60;
    store.setPanelVisible(true);
    host.emitSystemStats(stats({ cpu: null }));
    expect(store.state.cpu).toBeUndefined();
    expect(store.state.gpuSeries.points.length).toBe(1);
    /* A reading nobody asked for (after the watch ended) changes nothing. */
    store.setPanelVisible(false);
    const before = store.state;
    host.emitSystemStats(stats());
    expect(store.state).toBe(before);
  });

  it("in demo mode opens with a full minute of the demo curves, steps them, and never asks the host", async () => {
    const { host, store } = await systemApp(true);
    expect(store.state.cpuSeries.points.length).toBe(HISTORY_CAPACITY);
    expect(store.state.cpu?.perCore.length).toBe(DEMO_CORE_COUNT);
    expect(store.state.cpu?.total).toBeCloseTo(demoCPU(HISTORY_CAPACITY), 12);
    expect(store.state.gpu).toBeCloseTo(demoGPU(HISTORY_CAPACITY), 12);
    expect(store.state.memory?.totalBytes).toBe(DEMO_TOTAL_MEMORY_BYTES);
    store.sampleDemo();
    expect(store.state.cpu?.total).toBeCloseTo(demoCPU(HISTORY_CAPACITY + 1), 12);
    expect(store.state.cpuSeries.points.length).toBe(HISTORY_CAPACITY);
    store.setPanelVisible(true);
    store.setPanelVisible(false);
    expect(host.calls.filter((call) => call.name === "systemWatch")).toEqual([]);
  });

  it("renders the measuring snapshot state: no CPU yet, GPU and memory from the first reading", async () => {
    const { store } = await systemApp(true);
    store.showSnapshotState("measuring");
    expect(store.state.cpu).toBeUndefined();
    expect(store.state.cpuSeries.isEmpty).toBe(true);
    expect(store.state.gpu).toBeCloseTo(demoGPU(1), 12);
    expect(store.state.gpuSeries.points.length).toBe(1);
    expect(store.state.memory?.pressure).toBe("normal");
  });
});
