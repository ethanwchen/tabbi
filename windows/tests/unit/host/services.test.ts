import { beforeEach, describe, expect, it, vi } from "vitest";
import { isHostError, type HttpStreamEvent, type MediaSnapshot } from "../../../src/host/host";
import { mockHost } from "../../../src/host/mock";

const invoke = vi.fn<(command: string, args?: Record<string, unknown>) => Promise<unknown>>();
const listen = vi.fn((event: string) => Promise.resolve(() => void event));

vi.mock("@tauri-apps/api/core", () => ({
  invoke: (command: string, args?: Record<string, unknown>) => invoke(command, args),
  Channel: class {
    onmessage: (message: unknown) => void = () => undefined;
  },
}));
vi.mock("@tauri-apps/api/event", () => ({ listen: (event: string) => listen(event) }));
vi.mock("@tauri-apps/api/window", () => ({ getCurrentWindow: () => ({ onFocusChanged: () => Promise.resolve(() => undefined) }) }));

const { tauriHost } = await import("../../../src/host/tauri");

const song: MediaSnapshot = {
  appId: "Spotify.exe",
  title: "Song",
  artist: "Band",
  album: "Record",
  thumbnail: null,
  status: "playing",
  positionSeconds: 12,
  durationSeconds: 200,
  updatedAt: 1_792_022_400_000,
  shuffle: false,
  repeat: "none",
  controls: { play: true, pause: true, toggle: true, next: true, previous: true, shuffle: true, repeat: true },
};

describe("the Tauri host's service commands", () => {
  beforeEach(() => {
    invoke.mockReset();
    invoke.mockResolvedValue(null);
  });

  /* The command names and argument keys must match the Rust commands registered in lib.rs. */
  it("call the Rust commands by name with their argument names", async () => {
    const host = tauriHost();
    await host.storageRead("durable", "Activity/2026-10-15");
    await host.storageWrite("cache", "calendar", { schemaVersion: 1 });
    await host.storageList("durable", null);
    await host.storageDelete("durable", "pet");
    await host.credentialGet("party");
    await host.credentialSet("ai/anthropic", "sk-ant");
    await host.credentialDelete("ai/openai");
    await host.notify("Break time", "Stretch your legs");
    await host.mediaSnapshot();
    await host.mediaControl({ type: "repeat", mode: "list" });
    await host.mediaWatch(true);
    await host.systemWatch(false);
    await host.httpRequest({ method: "POST", url: "http://127.0.0.1:8765", body: "{}" });
    await host.fetchCalendar("webcal://example.org/a.ics");
    await host.autostartEnable();
    await host.autostartDisable();
    await host.autostartIsEnabled();
    await host.aiPaths();
    expect(invoke.mock.calls).toEqual([
      ["storage_read", { area: "durable", name: "Activity/2026-10-15" }],
      ["storage_write", { area: "cache", name: "calendar", value: { schemaVersion: 1 } }],
      ["storage_list", { area: "durable", folder: null }],
      ["storage_delete", { area: "durable", name: "pet" }],
      ["credential_get", { name: "party" }],
      ["credential_set", { name: "ai/anthropic", secret: "sk-ant" }],
      ["credential_delete", { name: "ai/openai" }],
      ["notify", { title: "Break time", body: "Stretch your legs" }],
      ["media_snapshot", undefined],
      ["media_control", { action: { type: "repeat", mode: "list" } }],
      ["media_watch", { on: true }],
      ["system_watch", { on: false }],
      ["http_request", { request: { method: "POST", url: "http://127.0.0.1:8765", body: "{}" } }],
      ["http_fetch_calendar", { url: "webcal://example.org/a.ics" }],
      ["autostart_enable", undefined],
      ["autostart_disable", undefined],
      ["autostart_is_enabled", undefined],
      ["ai_paths", undefined],
    ]);
  });

  it("streams through a channel and cancels by id", async () => {
    invoke.mockResolvedValueOnce(7).mockResolvedValueOnce(true);
    const events: HttpStreamEvent[] = [];
    const stream = await tauriHost().httpStream({ method: "POST", url: "https://api.anthropic.com/v1/messages" }, (e) => events.push(e));
    expect(stream.id).toBe(7);
    const [command, args] = invoke.mock.calls[0] ?? [];
    expect(command).toBe("http_stream");
    const channel = args?.onEvent as { onmessage: (event: HttpStreamEvent) => void };
    channel.onmessage({ type: "chunk", text: "Hi" });
    expect(events).toEqual([{ type: "chunk", text: "Hi" }]);
    await expect(stream.cancel()).resolves.toBe(true);
    expect(invoke.mock.calls[1]).toEqual(["http_cancel", { id: 7 }]);
  });

  it("listens to the media and system events by name", () => {
    const host = tauriHost();
    host.onMedia(() => undefined)();
    host.onSystemStats(() => undefined)();
    expect(listen.mock.calls.map(([event]) => event)).toEqual(["media:changed", "system:stats"]);
  });
});

describe("the mock host's services", () => {
  it("keeps documents in memory with the host's naming rules", async () => {
    const host = mockHost();
    await host.storageWrite("durable", "settings", { schemaVersion: 1 });
    await host.storageWrite("durable", "Activity/2026-10-15", []);
    await host.storageWrite("cache", "calendar", "BEGIN:VCALENDAR");
    expect(await host.storageRead("durable", "settings")).toEqual({ schemaVersion: 1 });
    expect(await host.storageRead("durable", "missing")).toBeNull();
    expect(await host.storageList("durable", null)).toEqual(["settings"]);
    expect(await host.storageList("durable", "Activity")).toEqual(["Activity/2026-10-15"]);
    expect(await host.storageDelete("durable", "settings")).toBe(true);
    expect(await host.storageDelete("durable", "settings")).toBe(false);
    for (const bad of ["../x", "a/b/c", ".hidden", "CON", "a..b", "trailing."]) {
      await expect(host.storageWrite("durable", bad, 1)).rejects.toMatchObject({ code: "invalidName" });
    }
  });

  it("returns copies, so a caller cannot change a stored document in place", async () => {
    const host = mockHost();
    const doc = { tasks: ["read"] };
    await host.storageWrite("durable", "planner", doc);
    doc.tasks.push("changed");
    expect(await host.storageRead("durable", "planner")).toEqual({ tasks: ["read"] });
  });

  it("holds credentials without logging their values", async () => {
    const host = mockHost();
    await host.credentialSet("party", "secret-token");
    expect(await host.credentialGet("party")).toBe("secret-token");
    expect(JSON.stringify(host.calls)).not.toContain("secret-token");
    expect(await host.credentialDelete("party")).toBe(true);
    expect(await host.credentialGet("party")).toBeNull();
  });

  it("plays media and system events to their listeners", async () => {
    const host = mockHost();
    const heard: (MediaSnapshot | null)[] = [];
    const stop = host.onMedia((media) => heard.push(media));
    expect(await host.mediaControl({ type: "toggle" })).toBe(false);
    host.emitMedia(song);
    expect(await host.mediaSnapshot()).toEqual(song);
    expect(await host.mediaControl({ type: "next" })).toBe(true);
    stop();
    host.emitMedia(null);
    expect(heard).toEqual([song]);

    const stats: number[] = [];
    host.onSystemStats((s) => stats.push(s.cpu?.total ?? -1));
    host.emitSystemStats({ cpu: { total: 0.5, perCore: [0.5] }, memory: null, gpu: null });
    expect(stats).toEqual([0.5]);
  });

  it("makes no network calls and starts with autostart off", async () => {
    const host = mockHost();
    const error: unknown = await host.httpRequest({ method: "GET", url: "https://api.openai.com/v1/models" }).catch((e: unknown) => e);
    expect(isHostError(error) && error.code).toBe("network");
    await expect(host.fetchCalendar("https://example.org/a.ics")).rejects.toMatchObject({ code: "network" });
    expect(await host.autostartIsEnabled()).toBe(false);
    await host.autostartEnable();
    expect(await host.autostartIsEnabled()).toBe(true);
  });
});
