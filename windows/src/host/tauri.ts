import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import type { Host, HostEvent, HostSource, Startup } from "./host";

/* The host inside the app: Rust commands and events (src-tauri/src/lib.rs). */
export function tauriHost(): Host {
  return {
    setShape: (rect) => invoke("island_set_shape", { shape: rect }),
    setOpen: (open) => invoke("island_set_open", { open }),
    activate: () => invoke("island_activate"),
    restoreFocus: () => invoke("island_restore_focus"),
    armHotZone: (armed) => invoke("island_arm_hot_zone", { armed }),
    ready: () => invoke<Startup>("island_ready"),
    subscribe(listener) {
      const pending: Promise<UnlistenFn>[] = [
        listen("island:hot-zone", () => listener({ type: "hotZone" })),
        listen<HostSource>("island:toggle", (e) => listener({ type: "toggle", source: e.payload })),
        listen<HostSource>("island:open", (e) => listener({ type: "open", source: e.payload })),
        listen("island:outside-click", () => listener({ type: "outsideClick" })),
        listen<boolean>("island:fullscreen", (e) => listener({ type: "fullscreen", active: e.payload })),
        listen<string>("island:link", (e) => listener({ type: "link", url: e.payload })),
        listen<number>("island:placed", (e) => listener({ type: "placed", scale: e.payload })),
        getCurrentWindow().onFocusChanged((e) => listener({ type: "focus", focused: e.payload })),
      ];
      return () => {
        for (const p of pending) void p.then((unlisten) => unlisten());
      };
    },
  };
}

export function insideTauri(): boolean {
  return "__TAURI_INTERNALS__" in window;
}

export type { HostEvent };
