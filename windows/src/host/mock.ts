import type { CredentialName, Host, HostError, HostEvent, MediaSnapshot, StorageArea, Startup, SystemStats } from "./host";

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

export function mockHost(startup: Startup = { hotkey: { shortcut: "ctrl+alt+space", registered: true }, notchMode: null }): MockHost {
  const listeners = new Set<(event: HostEvent) => void>();
  const mediaListeners = new Set<(media: MediaSnapshot | null) => void>();
  const statsListeners = new Set<(stats: SystemStats) => void>();
  const calls: { name: string; args: unknown[] }[] = [];
  const documents = new Map<string, string>();
  const credentials = new Map<CredentialName, string>();
  let media: MediaSnapshot | null = null;
  let autostart = false;

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
    ready: () => answer("ready", [], startup),
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    emit(event) {
      for (const listener of listeners) listener(event);
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
    setPartyServer(server) {
      log("setPartyServer", [server]);
      return Promise.resolve();
    },

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
  };
}
