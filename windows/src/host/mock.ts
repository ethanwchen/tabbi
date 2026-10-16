import type { CredentialName, Host, HostError, HostEvent, HotkeyStatus, KitFilePick, MediaSnapshot, NotificationSetting, StorageArea, Startup, SystemStats } from "./host";

/*
 * The windows mock hosts share, so a test can play the island and the
 * Settings window side by side: what one broadcasts, the others hear.
 */
export class MockWindowBus {
  private readonly windows = new Set<{ deliver(topic: string, payload: unknown): void }>();

  join(window: { deliver(topic: string, payload: unknown): void }): () => void {
    this.windows.add(window);
    return () => {
      this.windows.delete(window);
    };
  }

  post(from: object, topic: string, payload: unknown): void {
    /* A copy, as the real host serializes every message. */
    const copy: unknown = JSON.parse(JSON.stringify(payload));
    for (const window of this.windows) if (window !== from) window.deliver(topic, copy);
  }
}

export interface MockHostOptions {
  /* Other mock windows that hear this one's broadcasts. */
  readonly bus?: MockWindowBus;
  /* The section settingsReady reports. */
  readonly settingsSection?: string | null;
  /* Shortcuts another app owns, which setHotkey then reports as not registered. */
  readonly takenShortcuts?: readonly string[];
  /* What the file dialog returns; null (the default) is a cancelled dialog. */
  readonly kitFile?: KitFilePick | null;
  /* Windows' toast setting for Tabbi; enabled by default. */
  readonly notifications?: NotificationSetting;
  /* The modified time every seeded AI log reports, in seconds since 1970. */
  readonly aiLogModified?: number;
}

/* What a mock host starts with: the default hotkey registered, live data, no development servers. */
export const MOCK_STARTUP: Startup = {
  hotkey: { shortcut: "ctrl+alt+space", registered: true },
  notchMode: null,
  demo: false,
  partyServer: null,
  appVersion: "0.1.0",
  systemVersion: "10.0.26200",
};

/*
 * A host for the browser: Vitest, the Vite dev server and the Playwright
 * snapshot runs. It records every call, and `emit` plays a host event, so a
 * test can drive the island the way Windows would. Demo and snapshot runs
 * keep documents and credentials in memory here and make no network calls.
 */
export interface MockHost extends Host {
  readonly calls: { name: string; args: unknown[] }[];
  emit(event: HostEvent): void;
  emitMedia(media: MediaSnapshot | null): void;
  emitSystemStats(stats: SystemStats): void;
  /* Documents by "area:name", for tests to seed and inspect. */
  readonly documents: Map<string, string>;
  readonly credentials: Map<CredentialName, string>;
  /* AI logs by "tool:path", for tests to seed; aiLogs lists them and aiLogRead reads their UTF-8 bytes. */
  readonly aiLogFiles: Map<string, string>;
}

const RESERVED = /^(con|prn|aux|nul|com\d|lpt\d)$/i;

/* The host's rule for one path segment (storage.rs `valid_segment`). */
function validSegment(segment: string): boolean {
  const stem = (segment.split(".")[0] ?? segment).trimEnd();
  return (
    /^[A-Za-z0-9][A-Za-z0-9._ -]{0,63}$/.test(segment) &&
    !segment.endsWith(".") &&
    !segment.endsWith(" ") &&
    !segment.includes("..") &&
    !RESERVED.test(stem)
  );
}

/* Folders a name may nest (storage.rs `MAX_FOLDERS`). */
const MAX_FOLDERS = 2;

function isJson(text: string): boolean {
  try {
    JSON.parse(text);
    return true;
  } catch {
    return false;
  }
}

function rejection(code: HostError["code"], message: string): Promise<never> {
  const error: HostError = { code, message };
  return Promise.reject(error);
}

export function mockHost(startup: Startup = MOCK_STARTUP, options: MockHostOptions = {}): MockHost {
  const listeners = new Set<(event: HostEvent) => void>();
  const broadcastListeners = new Map<string, Set<(payload: unknown) => void>>();
  const endpoint = {
    deliver(topic: string, payload: unknown) {
      for (const listener of [...(broadcastListeners.get(topic) ?? [])]) listener(payload);
    },
  };
  options.bus?.join(endpoint);
  const mediaListeners = new Set<(media: MediaSnapshot | null) => void>();
  const statsListeners = new Set<(stats: SystemStats) => void>();
  const calls: { name: string; args: unknown[] }[] = [];
  const documents = new Map<string, string>();
  const credentials = new Map<CredentialName, string>();
  let media: MediaSnapshot | null = null;
  let autostart = false;
  let updateAutoCheck = false;
  const aiLogFiles = new Map<string, string>();
  const aiLogModified = options.aiLogModified ?? 0;
  const encoder = new TextEncoder();

  const log = (name: string, args: unknown[]) => calls.push({ name, args });
  const record = (name: string) => (...args: unknown[]) => {
    log(name, args);
    return Promise.resolve();
  };
  const answer = <T>(name: string, args: unknown[], value: T): Promise<T> => {
    log(name, args);
    return Promise.resolve(value);
  };
  const key = (area: StorageArea, name: string): string | null => {
    const parts = name.split("/");
    return parts.length <= MAX_FOLDERS + 1 && parts.every(validSegment) ? `${area}:${name}` : null;
  };
  const badName = (name: string) => rejection("invalidName", `"${name}" is not a document name`);
  const offline = () => rejection("network", "the mock host makes no network calls");
  const subscribe = <T>(set: Set<(value: T) => void>, listener: (value: T) => void) => {
    set.add(listener);
    return () => {
      set.delete(listener);
    };
  };

  return {
    calls,
    documents,
    credentials,
    setShape: record("setShape"),
    setOpen: record("setOpen"),
    activate: record("activate"),
    restoreFocus: record("restoreFocus"),
    armHotZone: record("armHotZone"),
    startup: () => answer("startup", [], startup),
    ready: () => answer("ready", [], startup),
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    emit(event) {
      for (const listener of listeners) listener(event);
    },
    setCanvas: record("setCanvas"),
    openSettings: record("openSettings"),
    settingsReady: () => answer("settingsReady", [], { startup, section: options.settingsSection ?? null }),
    broadcast(topic, payload) {
      log("broadcast", [topic]);
      options.bus?.post(endpoint, topic, payload);
      return Promise.resolve();
    },
    onBroadcast(topic, listener) {
      const set = broadcastListeners.get(topic) ?? new Set();
      broadcastListeners.set(topic, set);
      set.add(listener);
      return () => {
        set.delete(listener);
      };
    },

    storageRead(area, name) {
      const k = key(area, name);
      if (k === null) return badName(name);
      return answer("storageRead", [area, name], documents.get(k) ?? null);
    },
    storageWrite(area, name, text) {
      const k = key(area, name);
      if (k === null) return badName(name);
      if (!isJson(text)) return rejection("invalid", `${name} is not valid JSON`);
      documents.set(k, text);
      return answer("storageWrite", [area, name, text], undefined);
    },
    storageList(area, folder) {
      if (folder !== null) {
        const parts = folder.split("/");
        if (parts.length > MAX_FOLDERS || !parts.every(validSegment)) return badName(folder);
      }
      const prefix = `${area}:${folder === null ? "" : `${folder}/`}`;
      const names = [...documents.keys()]
        .filter((k) => k.startsWith(prefix) && !k.slice(prefix.length).includes("/"))
        .map((k) => k.slice(area.length + 1))
        .sort();
      return answer("storageList", [area, folder], names);
    },
    storageDelete(area, name) {
      const k = key(area, name);
      if (k === null) return badName(name);
      return answer("storageDelete", [area, name], documents.delete(k));
    },

    /* Calls are logged by name only, so no secret lands in a test's call list. */
    credentialGet: (name) => answer("credentialGet", [name], credentials.get(name) ?? null),
    credentialSet(name, secret) {
      credentials.set(name, secret);
      return answer("credentialSet", [name], undefined);
    },
    credentialDelete: (name) => answer("credentialDelete", [name], credentials.delete(name)),

    notify: record("notify"),

    mediaSnapshot: () => answer("mediaSnapshot", [], media),
    mediaControl: (action) => answer("mediaControl", [action], media !== null),
    mediaWatch: record("mediaWatch"),
    onMedia: (listener) => subscribe(mediaListeners, listener),
    emitMedia(next) {
      media = next;
      for (const listener of mediaListeners) listener(next);
    },

    systemWatch: record("systemWatch"),
    onSystemStats: (listener) => subscribe(statsListeners, listener),
    emitSystemStats(stats) {
      for (const listener of statsListeners) listener(stats);
    },

    httpRequest(request) {
      log("httpRequest", [request]);
      return offline();
    },
    httpStream(request) {
      log("httpStream", [request]);
      return offline();
    },
    fetchCalendar(url) {
      log("fetchCalendar", [url]);
      return offline();
    },
    openUrl(url) {
      log("openUrl", [url]);
      return Promise.resolve();
    },
    setPartyServer(server) {
      log("setPartyServer", [server]);
      return Promise.resolve();
    },

    /* The mock never sees the user's input or apps: the pet coach stays quiet on it. */
    coachSample: () => answer("coachSample", [], null),
    savePicture: (name, pngBase64) => answer("savePicture", [name, pngBase64.length], `C:\\Users\\mock\\Pictures\\${name}`),

    autostartEnable() {
      autostart = true;
      return answer("autostartEnable", [], undefined);
    },
    autostartDisable() {
      autostart = false;
      return answer("autostartDisable", [], undefined);
    },
    autostartIsEnabled: () => answer("autostartIsEnabled", [], autostart),

    aiPaths: () => answer("aiPaths", [], { claudeHome: null, codexHome: null, claude: null, codex: null, gemini: null }),

    setHotkey(shortcut) {
      const status: HotkeyStatus = {
        shortcut: shortcut ?? "",
        registered: shortcut !== null && !(options.takenShortcuts ?? []).includes(shortcut),
      };
      return answer("setHotkey", [shortcut], status);
    },
    notificationsSetting: () => answer("notificationsSetting", [], options.notifications ?? "enabled"),
    pickKitFile: () => answer("pickKitFile", [], options.kitFile ?? null),
    openApp: (app) => answer("openApp", [app], undefined),
    setTrayLabels: (labels) => answer("setTrayLabels", [labels], undefined),
    aiLogFiles,
    aiLogs: (tool) =>
      answer(
        "aiLogs",
        [tool],
        [...aiLogFiles.entries()]
          .filter(([k]) => k.startsWith(`${tool}:`))
          .map(([k, text]) => ({ path: k.slice(tool.length + 1), size: encoder.encode(text).length, identity: "1", modified: aiLogModified }))
          .sort((a, b) => (a.path < b.path ? -1 : 1)),
      ),
    aiLogRead(tool, path, offset) {
      const text = aiLogFiles.get(`${tool}:${path}`);
      if (text === undefined) return rejection("blocked", `${path} is not a log of ${tool}`);
      return answer("aiLogRead", [tool, path, offset], encoder.encode(text).subarray(offset));
    },

    /* No feed in tests: the running build is the latest, and the automatic check stays off until set. */
    updateCheck: () => answer("updateCheck", [], null),
    updateInstall: record("updateInstall"),
    updateAutoCheck: () => answer("updateAutoCheck", [], updateAutoCheck),
    setUpdateAutoCheck(on) {
      updateAutoCheck = on;
      return answer("setUpdateAutoCheck", [on], undefined);
    },
    updateTakeRequest: () => answer("updateTakeRequest", [], false),
    onUpdateRequest: () => () => {},
  };
}
