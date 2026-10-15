/*
 * The UI's only door to the Rust host. Components talk to a Host, never to
 * Tauri, so the same UI runs inside the app, in Vitest and in the Playwright
 * snapshot runs (against the mock in mock.ts).
 */

import type { HitRect } from "../ui/shell/geometry";

export type HostSource = "hotkey" | "tray" | "launch";

export interface HotkeyStatus {
  readonly shortcut: string;
  readonly registered: boolean;
}

export interface Startup {
  readonly hotkey: HotkeyStatus | null;
  /* A development override of the closed-island mode; null in release builds. */
  readonly notchMode: string | null;
}

export type HostEvent =
  | { type: "hotZone" }
  | { type: "toggle"; source: HostSource }
  | { type: "open"; source: HostSource }
  | { type: "outsideClick" }
  | { type: "fullscreen"; active: boolean }
  | { type: "focus"; focused: boolean }
  | { type: "link"; url: string }
  | { type: "placed"; scale: number };

export interface Host {
  /* Limits drawing and clicks to this rectangle of the window, or to nothing. */
  setShape(rect: HitRect | null): Promise<void>;
  /* Open lets the panel take focus and watches for clicks outside it. */
  setOpen(open: boolean): Promise<void>;
  activate(): Promise<void>;
  restoreFocus(): Promise<void>;
  armHotZone(armed: boolean): Promise<void>;
  /* Shows the window once the first frame is drawn. */
  ready(): Promise<Startup>;
  subscribe(listener: (event: HostEvent) => void): () => void;

  /* Windows services, each in src-tauri/src/<service>.rs; their types follow the interface. */

  /* A named JSON document ("name" or "folder/name"), or null when it was never written. */
  storageRead(area: StorageArea, name: string): Promise<JsonValue | null>;
  /* Replaces the document atomically. */
  storageWrite(area: StorageArea, name: string, value: JsonValue): Promise<void>;
  /* The documents in the area's root (folder null) or in one folder, as full names, sorted. */
  storageList(area: StorageArea, folder: string | null): Promise<string[]>;
  storageDelete(area: StorageArea, name: string): Promise<boolean>;

  credentialGet(name: CredentialName): Promise<string | null>;
  credentialSet(name: CredentialName, secret: string): Promise<void>;
  credentialDelete(name: CredentialName): Promise<boolean>;

  /* A Windows toast; Windows holds it back during Do Not Disturb. */
  notify(title: string, body: string): Promise<void>;

  mediaSnapshot(): Promise<MediaSnapshot | null>;
  /* False when nothing is playing or the app turned the request down. */
  mediaControl(action: MediaAction): Promise<boolean>;
  /* On while Now Playing or the ticker shows the song; onMedia then hears every change. */
  mediaWatch(on: boolean): Promise<void>;
  onMedia(listener: (media: MediaSnapshot | null) => void): () => void;

  /* On while the System tab is visible; onSystemStats then hears a reading a second. */
  systemWatch(on: boolean): Promise<void>;
  onSystemStats(listener: (stats: SystemStats) => void): () => void;

  httpRequest(request: HttpRequest): Promise<HttpResponse>;
  httpStream(request: HttpRequest, onEvent: (event: HttpStreamEvent) => void): Promise<HttpStream>;
  /* A user-entered ICS address (https or webcal, any public host): the calendar's text. */
  fetchCalendar(url: string): Promise<string>;
  /* The user's own Party server from Settings (public https only), or null for none; requests may then reach it. */
  setPartyServer(server: string | null): Promise<void>;

  /* Start with Windows: off until the user turns it on. */
  autostartEnable(): Promise<void>;
  autostartDisable(): Promise<void>;
  autostartIsEnabled(): Promise<boolean>;

  aiPaths(): Promise<AiPaths>;
}

/*
 * Types of the Windows services. Every service command
 * rejects with a HostError, whose code is stable, so the UI shows its own
 * designed message instead of the host's text.
 */

export type HostErrorCode =
  | "invalid"
  | "invalidName"
  | "io"
  | "corrupt"
  | "tooLarge"
  | "credential"
  | "notification"
  | "media"
  | "autostart"
  | "blocked"
  | "network"
  | "timeout"
  | "status"
  | "notCalendar"
  | "cancelled";

export interface HostError {
  readonly code: HostErrorCode;
  /* For logs; never a secret, a token or typed text. */
  readonly message: string;
}

export function isHostError(value: unknown): value is HostError {
  return typeof value === "object" && value !== null && "code" in value && "message" in value;
}

export type JsonValue = null | boolean | number | string | readonly JsonValue[] | { readonly [key: string]: JsonValue };

/* Durable is %APPDATA%\Tabbi (settings, tasks, the pet); cache is %LOCALAPPDATA%\Tabbi (anything refetchable). */
export type StorageArea = "durable" | "cache";

/*
 * Party's token, or an AI provider's key by its Mac AIProviderID raw value
 * (ai/anthropic, ai/openai, ai/gemini): 1 to 32 of a-z, 0-9 and -.
 */
export type CredentialName = "party" | `ai/${string}`;

export type MediaStatus = "closed" | "opened" | "changing" | "stopped" | "playing" | "paused";
export type MediaRepeat = "none" | "track" | "list";

/* Which controls the playing app accepts right now. */
export interface MediaControls {
  readonly play: boolean;
  readonly pause: boolean;
  readonly toggle: boolean;
  readonly next: boolean;
  readonly previous: boolean;
  readonly shuffle: boolean;
  readonly repeat: boolean;
}

export interface MediaSnapshot {
  /* The app that owns the session, such as "Spotify.exe" or a browser's app id. */
  readonly appId: string;
  readonly title: string;
  readonly artist: string;
  readonly album: string;
  /* A JPEG data URL, at most 256 px on its longer side, or null without artwork. */
  readonly thumbnail: string | null;
  readonly status: MediaStatus;
  /* The position at updatedAt; while playing, advance it with the clock. */
  readonly positionSeconds: number;
  /* Zero when the app reports no timeline (a live stream). */
  readonly durationSeconds: number;
  /* Unix milliseconds. */
  readonly updatedAt: number;
  readonly shuffle: boolean | null;
  readonly repeat: MediaRepeat | null;
  readonly controls: MediaControls;
}

export type MediaAction =
  | { readonly type: "play" }
  | { readonly type: "pause" }
  | { readonly type: "toggle" }
  | { readonly type: "next" }
  | { readonly type: "previous" }
  | { readonly type: "shuffle"; readonly on: boolean }
  | { readonly type: "repeat"; readonly mode: MediaRepeat };

/* Mirrors the Mac's CPUUsage: fractions in 0...1. */
export interface CpuUsage {
  readonly total: number;
  readonly perCore: readonly number[];
}

export interface MemoryStats {
  readonly usedBytes: number;
  readonly totalBytes: number;
}

/* One reading a second while watched; null where the machine cannot say (CPU on the first reading, GPU without counters). */
export interface SystemStats {
  readonly cpu: CpuUsage | null;
  readonly memory: MemoryStats | null;
  /* The busiest 3D engine, 0...1. */
  readonly gpu: number | null;
}

export type HttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

/*
 * A request to an allow-listed service: AnkiConnect and Ollama on localhost,
 * the Claude, OpenAI and Gemini APIs, and the Party Worker (src-tauri/src/http.rs).
 * Redirects are not followed.
 */
export interface HttpRequest {
  readonly method: HttpMethod;
  readonly url: string;
  readonly headers?: readonly (readonly [name: string, value: string])[];
  readonly body?: string;
}

export interface HttpResponse {
  readonly status: number;
  /* Lowercase names; repeated headers joined with ", ". */
  readonly headers: Readonly<Record<string, string>>;
  readonly body: string;
}

/* A streamed reply: a head, text chunks as they arrive, then an end or an error. */
export type HttpStreamEvent =
  | { readonly type: "head"; readonly status: number; readonly headers: Readonly<Record<string, string>> }
  | { readonly type: "chunk"; readonly text: string }
  | { readonly type: "end" }
  | { readonly type: "error"; readonly error: HostError };

export interface HttpStream {
  readonly id: number;
  /* Stops the stream, which then ends with a "cancelled" error; false if it had already ended. */
  cancel(): Promise<boolean>;
}

/* Where the AI command line tools and their logs are; null when not found. */
export interface AiPaths {
  readonly claudeHome: string | null;
  readonly codexHome: string | null;
  readonly claude: string | null;
  readonly codex: string | null;
  readonly gemini: string | null;
}
