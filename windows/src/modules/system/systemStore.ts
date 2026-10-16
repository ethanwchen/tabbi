/*
 * Port of SystemMonitor: the System panel's live CPU, GPU and memory
 * readings and their one-minute histories. The host samples once a second
 * only while the panel asks (`systemWatch(true)` on the first viewer,
 * `false` when the last leaves), so nothing runs while the tab is hidden.
 * The rules (the gap that restarts a history, the pressure level) are the
 * core's SystemMonitorState; this store only feeds it and republishes. In
 * demo mode it plays back the core's demo curves, and a snapshot run holds
 * one still frame of them.
 */

import type { ModuleContext } from "../../app/context";
import { Store } from "../../app/store";
import type { CPUUsage } from "../../core/system/cpuUsage";
import type { HistorySeries } from "../../core/system/history";
import type { MemoryStats } from "../../core/system/memoryStats";
import { demoGPU, demoMemory } from "../../core/system/systemDemoData";
import { HISTORY_CAPACITY, SystemMonitorState, type SystemReading } from "../../core/system/systemStats";
import type { SystemStats } from "../../host/host";

export interface SystemState {
  /** Undefined until two readings a second apart exist. */
  readonly cpu: CPUUsage | undefined;
  /** Undefined when no adapter reports utilization. */
  readonly gpu: number | undefined;
  readonly memory: MemoryStats | undefined;
  readonly cpuSeries: HistorySeries;
  readonly gpuSeries: HistorySeries;
  readonly memorySeries: HistorySeries;
}

/** The panel states a snapshot run renders beyond the demo's full minute. */
export const SYSTEM_SNAPSHOT_STATES = ["measuring"] as const;

/** The host's reading as the core takes it, at `capturedAt`. */
export function readingFrom(stats: SystemStats, capturedAt: number): SystemReading {
  return {
    capturedAt,
    ...(stats.cpu ? { cpu: { total: stats.cpu.total, perCore: [...stats.cpu.perCore] } } : {}),
    ...(stats.memory ? { memory: { usedBytes: stats.memory.usedBytes, totalBytes: stats.memory.totalBytes } } : {}),
    ...(stats.gpu === null ? {} : { gpu: stats.gpu }),
  };
}

function stateOf(monitor: SystemMonitorState): SystemState {
  return {
    cpu: monitor.cpu,
    gpu: monitor.gpu,
    memory: monitor.memory,
    cpuSeries: monitor.cpuSeries,
    gpuSeries: monitor.gpuSeries,
    memorySeries: monitor.memorySeries,
  };
}

export class SystemStore extends Store<SystemState> {
  private monitor: SystemMonitorState;
  private demoStep = 0;
  /** Visible panels; sampling stops when it drops to zero. */
  private viewers = 0;
  private stopSampling: (() => void) | undefined;

  constructor(private readonly context: ModuleContext) {
    const monitor = context.isDemo ? SystemMonitorState.demo() : new SystemMonitorState();
    super(stateOf(monitor));
    this.monitor = monitor;
    if (context.isDemo) this.demoStep = HISTORY_CAPACITY;
  }

  /** True while a panel is visible and the once-a-second sampling runs. */
  get isSampling(): boolean {
    return this.stopSampling !== undefined;
  }

  /** Call from the panel's mount and unmount. Sampling only runs while a panel can be seen. */
  setPanelVisible(visible: boolean): void {
    this.viewers = Math.max(this.viewers + (visible ? 1 : -1), 0);
    if (this.viewers > 0) this.start();
    else this.stop();
  }

  /** One host reading; also how tests step the store. */
  sample(stats: SystemStats): void {
    this.monitor.applyReading(readingFrom(stats, this.context.now()));
    this.publish();
  }

  /** One demo step, the curves the Mac's demo mode plays. */
  sampleDemo(): void {
    this.demoStep += 1;
    this.monitor.applyDemo(this.demoStep);
    this.publish();
  }

  /** The panel as a snapshot run shows it: `measuring` is the first reading, before CPU can be told. */
  showSnapshotState(state: string): void {
    if (state !== "measuring") return;
    this.monitor = new SystemMonitorState();
    const memory = demoMemory(1);
    this.monitor.applyReading({ capturedAt: this.context.now(), gpu: demoGPU(1), memory: { usedBytes: memory.usedBytes, totalBytes: memory.totalBytes } });
    this.publish();
  }

  private start(): void {
    if (this.stopSampling !== undefined) return;
    /* A snapshot is one still frame: the demo's full minute as it was built. */
    if (this.context.isSnapshot) {
      this.stopSampling = () => {};
      return;
    }
    if (this.context.isDemo) {
      const timer = setInterval(() => this.sampleDemo(), 1000);
      this.stopSampling = () => clearInterval(timer);
      return;
    }
    const host = this.context.host;
    const unsubscribe = host.onSystemStats((stats) => this.sample(stats));
    void host.systemWatch(true).catch((error: unknown) => this.context.logger.error("system watch failed", error));
    this.stopSampling = () => {
      unsubscribe();
      void host.systemWatch(false).catch((error: unknown) => this.context.logger.error("system watch failed", error));
    };
  }

  private stop(): void {
    this.stopSampling?.();
    this.stopSampling = undefined;
  }

  private publish(): void {
    this.changed(stateOf(this.monitor));
  }
}
