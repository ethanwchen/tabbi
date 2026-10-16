import { Channel, invoke } from "@tauri-apps/api/core";
import { emit, listen, type UnlistenFn } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import type {
  AiLogFile,
  AiPaths,
  Host,
  HostEvent,
  HostSource,
  HttpResponse,
  HttpStreamEvent,
  MediaSnapshot,
  SettingsLaunch,
  Startup,
  SystemStats,
} from "./host";

/* Tells this window's own broadcasts apart from the other windows'. */
const WINDOW_ID = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;

/* Tauri event names allow letters, digits and - / : _ only. */
const eventName = (topic: string) => `tabbi:${topic.replace(/[^A-Za-z0-9/:_-]/g, "_")}`;

interface Broadcast {
  readonly sender: string;
  readonly payload: unknown;
}

/* Listens to one host event until the returned function is called. */
function on<T>(event: string, listener: (payload: T) => void): () => void {
  const pending = listen<T>(event, (e) => listener(e.payload));
  return () => void pending.then((unlisten) => unlisten());
}

/* The host inside the app: Rust commands and events (src-tauri/src/lib.rs and the service modules beside it). */
export function tauriHost(): Host {
  /*
   * Listeners register asynchronously. The host holds island events until
   * `island_ready`, so `ready` waits for every registration first: a launch
   * link or an early tray click then reaches a listener instead of nothing.
   */
  const registrations: Promise<unknown>[] = [];

  return {
    setShape: (rect) => invoke("island_set_shape", { shape: rect }),
    setOpen: (open) => invoke("island_set_open", { open }),
    activate: () => invoke("island_activate"),
    restoreFocus: () => invoke("island_restore_focus"),
    armHotZone: (armed) => invoke("island_arm_hot_zone", { armed }),
    startup: () => invoke<Startup>("island_startup"),
    ready: async () => {
      await Promise.all(registrations);
      return invoke<Startup>("island_ready");
    },
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
        listen<string>("settings:section", (e) => listener({ type: "settingsSection", section: e.payload })),
      ];
      registrations.push(...pending);
      return () => {
        for (const p of pending) void p.then((unlisten) => unlisten());
      };
    },

    setCanvas: (width, height) => invoke("island_set_canvas", { width, height }),
    openSettings: (section) => invoke("settings_open", { section }),
    settingsReady: () => invoke<SettingsLaunch>("settings_ready"),
    openUrl: (url) => {
      if (!url.toLowerCase().startsWith("http://") && !url.toLowerCase().startsWith("https://")) {
        return Promise.reject(new Error("Only web addresses open in the browser"));
      }
      /* Until the host has an open_url command, the webview's own new-window request reaches the default browser. */
      return invoke("open_url", { url })
        .then(() => undefined)
        .catch(() => {
          window.open(url, "_blank", "noopener");
        });
    },
    broadcast: (topic, payload) => emit(eventName(topic), { sender: WINDOW_ID, payload } satisfies Broadcast),
    onBroadcast: (topic, listener) =>
      on<Broadcast>(eventName(topic), (message) => {
        if (message.sender !== WINDOW_ID) listener(message.payload);
      }),

    storageRead: (area, name) => invoke<string | null>("storage_read", { area, name }),
    storageWrite: (area, name, text) => invoke("storage_write", { area, name, text }),
    storageList: (area, folder) => invoke<string[]>("storage_list", { area, folder }),
    storageDelete: (area, name) => invoke<boolean>("storage_delete", { area, name }),

    credentialGet: (name) => invoke<string | null>("credential_get", { name }),
    credentialSet: (name, secret) => invoke("credential_set", { name, secret }),
    credentialDelete: (name) => invoke<boolean>("credential_delete", { name }),

    notify: (title, body) => invoke("notify", { title, body }),

    mediaSnapshot: () => invoke<MediaSnapshot | null>("media_snapshot"),
    mediaControl: (action) => invoke<boolean>("media_control", { action }),
    mediaWatch: (on) => invoke("media_watch", { on }),
    onMedia: (listener) => on<MediaSnapshot | null>("media:changed", listener),

    systemWatch: (on) => invoke("system_watch", { on }),
    onSystemStats: (listener) => on<SystemStats>("system:stats", listener),

    httpRequest: (request) => invoke<HttpResponse>("http_request", { request }),
    async httpStream(request, onEvent) {
      const channel = new Channel<HttpStreamEvent>();
      channel.onmessage = onEvent;
      const id = await invoke<number>("http_stream", { request, onEvent: channel });
      return { id, cancel: () => invoke<boolean>("http_cancel", { id }) };
    },
    fetchCalendar: (url) => invoke<string>("http_fetch_calendar", { url }),
    setPartyServer: (server) => invoke("http_set_party_server", { server }),
    openUrl: (url) => invoke("open_url", { url }),

    autostartEnable: () => invoke("autostart_enable"),
    autostartDisable: () => invoke("autostart_disable"),
    autostartIsEnabled: () => invoke<boolean>("autostart_is_enabled"),

    aiPaths: () => invoke<AiPaths>("ai_paths"),
    aiLogs: (tool) => invoke<AiLogFile[]>("ai_logs_list", { tool }),
    /* The host answers with a raw body, which arrives as an ArrayBuffer. */
    aiLogRead: async (tool, path, offset) => new Uint8Array(await invoke<ArrayBuffer>("ai_log_read", { tool, path, offset })),
  };
}

export function insideTauri(): boolean {
  return "__TAURI_INTERNALS__" in window;
}

/* The Tauri window this page runs in: "island" or "settings". */
export function tauriWindowLabel(): string {
  return getCurrentWindow().label;
}

export type { HostEvent };
