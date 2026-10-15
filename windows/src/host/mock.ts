import type { Host, HostEvent, Startup } from "./host";

/*
 * A host for the browser: Vitest, the Vite dev server and the Playwright
 * snapshot runs. It records every call, and `emit` plays a host event, so a
 * test can drive the island the way Windows would.
 */
export interface MockHost extends Host {
  readonly calls: { name: string; args: unknown[] }[];
  emit(event: HostEvent): void;
}

export function mockHost(startup: Startup = { hotkey: { shortcut: "ctrl+alt+space", registered: true }, notchMode: null }): MockHost {
  const listeners = new Set<(event: HostEvent) => void>();
  const calls: { name: string; args: unknown[] }[] = [];
  const record = (name: string) => (...args: unknown[]) => {
    calls.push({ name, args });
    return Promise.resolve();
  };
  return {
    calls,
    setShape: record("setShape"),
    setOpen: record("setOpen"),
    activate: record("activate"),
    restoreFocus: record("restoreFocus"),
    armHotZone: record("armHotZone"),
    ready: () => {
      calls.push({ name: "ready", args: [] });
      return Promise.resolve(startup);
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    emit(event) {
      for (const listener of listeners) listener(event);
    },
  };
}
