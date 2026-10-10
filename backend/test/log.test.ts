import { runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { HEALTH_MAX_FAILURES, HEALTH_WINDOW_S, type Hub } from "../src/hub";
import { REQUEST_SAMPLE_RATE, SLOW_REQUEST_MS, errorFields, requestLog, routeOf } from "../src/log";
import worker, { type Env } from "../src/index";
import { BASE, call, expectError, hub, register } from "./helpers";

afterEach(() => {
  vi.restoreAllMocks();
  vi.useRealTimers();
});

/** Every structured line written to the console while `run` runs, parsed. */
async function captureLogs(run: () => Promise<unknown>): Promise<{ lines: Record<string, unknown>[]; raw: string }> {
  const raw: string[] = [];
  const capture = (...args: unknown[]) => { raw.push(args.map(String).join(" ")); };
  vi.spyOn(console, "log").mockImplementation(capture);
  vi.spyOn(console, "warn").mockImplementation(capture);
  vi.spyOn(console, "error").mockImplementation(capture);
  await run();
  vi.restoreAllMocks();
  return { lines: raw.filter((l) => l.startsWith("{")).map((l) => JSON.parse(l)), raw: raw.join("\n") };
}

describe("routeOf", () => {
  it("keeps fixed segments and replaces ids", () => {
    expect(routeOf("/v1/presence")).toBe("/v1/presence");
    expect(routeOf("/v1/friends/AB3D5F7H")).toBe("/v1/friends/:id");
    expect(routeOf("/v1/admin/users/AB3D5F7H/ban/")).toBe("/v1/admin/users/:id/ban");
    expect(routeOf("/v1/admin/users/AB3D5F7H/grants/launch-cap")).toBe("/v1/admin/users/:id/grants/:id");
    expect(routeOf("/v1/admin/suggestions/42")).toBe("/v1/admin/suggestions/:id");
  });

  it("folds everything outside /v1 into one value", () => {
    expect(routeOf("/")).toBe("/");
    expect(routeOf("/wp-login.php")).toBe("other");
    expect(routeOf("/v2/friends")).toBe("other");
  });
});

describe("requestLog", () => {
  const ok = { method: "post", path: "/v1/friends/AB3D5F7H", status: 200, ms: 12 };

  it("always logs server errors and slow requests", () => {
    expect(requestLog({ ...ok, status: 503 }, 0.99)).toEqual({
      level: "error", fields: { method: "POST", route: "/v1/friends/:id", status: 503, ms: 12, sampled: false },
    });
    expect(requestLog({ ...ok, ms: SLOW_REQUEST_MS }, 0.99)?.level).toBe("warn");
  });

  it("samples the rest, client errors included", () => {
    expect(requestLog(ok, REQUEST_SAMPLE_RATE)).toBeNull();
    expect(requestLog({ ...ok, status: 429 }, 0)).toEqual({
      level: "info", fields: { method: "POST", route: "/v1/friends/:id", status: 429, ms: 12, sampled: true },
    });
  });
});

describe("errorFields", () => {
  it("keeps the name and the first line of the message", () => {
    const e = new TypeError("first line\nsecond line " + "x".repeat(300));
    expect(errorFields(e)).toEqual({ errorName: "TypeError", errorMessage: "first line" });
    expect(errorFields(new Error("y".repeat(300))).errorMessage).toHaveLength(200);
    expect(errorFields("boom")).toEqual({ errorName: "string", errorMessage: null });
  });
});

describe("request logs", () => {
  it("never contain tokens, friend codes or IP addresses", async () => {
    const me = await register();
    const friend = await register();
    vi.spyOn(Math, "random").mockReturnValue(0);
    const { lines, raw } = await captureLogs(async () => {
      await call("POST", "/v1/friends", { code: friend.code }, me.token, "203.0.113.77");
      await call("DELETE", `/v1/friends/${friend.code}`, undefined, me.token, "203.0.113.77");
    });
    expect(lines).toEqual([
      { level: "info", event: "request", method: "POST", route: "/v1/friends", status: 200, ms: expect.any(Number), sampled: true },
      { level: "info", event: "request", method: "DELETE", route: "/v1/friends/:id", status: 200, ms: expect.any(Number), sampled: true },
    ]);
    for (const secret of [me.token, friend.code, me.code, "203.0.113.77"]) expect(raw).not.toContain(secret);
  });

  it("skip unsampled successful requests", async () => {
    vi.spyOn(Math, "random").mockReturnValue(0.5);
    const { lines } = await captureLogs(() => call("GET", "/v1/catalog"));
    expect(lines).toEqual([]);
  });
});

describe("GET /v1/health", () => {
  it("answers from the Hub without a token", async () => {
    const r = await call("GET", "/v1/health");
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ ok: true });
    expect(r.headers.get("Cache-Control")).toBe("no-store");
  });

  it("reports degraded after a burst of server errors, and recovers once they age out", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    const start = Date.now();
    await runInDurableObject(hub(), (instance: Hub) => {
      const recordFailure = (instance as unknown as { recordFailure(now: number): void }).recordFailure.bind(instance);
      for (let i = 0; i < HEALTH_MAX_FAILURES - 1; i++) recordFailure(Math.floor(start / 1000));
    });
    expect((await call("GET", "/v1/health")).status).toBe(200);
    await runInDurableObject(hub(), (instance: Hub) => {
      (instance as unknown as { recordFailure(now: number): void }).recordFailure(Math.floor(start / 1000));
    });
    expectError(await call("GET", "/v1/health"), 503, "degraded");
    vi.setSystemTime(start + (HEALTH_WINDOW_S + 1) * 1000);
    expect((await call("GET", "/v1/health")).status).toBe(200);
  });

  it("counts a real 500 and logs it without request details", async () => {
    const me = await register();
    await runInDurableObject(hub(), (instance: Hub) => {
      const target = instance as unknown as { listFriends: () => never };
      vi.spyOn(target, "listFriends").mockImplementation(() => { throw new Error("no such table: friends"); });
    });
    const { lines, raw } = await captureLogs(async () => {
      expectError(await call("GET", "/v1/friends", undefined, me.token), 500, "internal");
    });
    expect(lines).toContainEqual({
      level: "error", event: "hub_exception", route: "/v1/friends", errorName: "Error", errorMessage: "no such table: friends",
    });
    expect(lines).toContainEqual(expect.objectContaining({ level: "error", event: "request", route: "/v1/friends", status: 500 }));
    expect(raw).not.toContain(me.token);
    await runInDurableObject(hub(), (instance: Hub) => {
      expect((instance as unknown as { failures: number[] }).failures.length).toBeGreaterThan(0);
    });
  });
});

describe("the Worker when the Hub cannot be reached", () => {
  /** An env whose Hub stub throws the way a Durable Object that is overloaded or resetting does. */
  const unreachableHub = (hubFetches: string[]) => ({
    HUB: {
      idFromName: (name: string) => name,
      get: () => ({
        fetch: async (req: Request) => {
          hubFetches.push(new URL(req.url).pathname);
          throw new Error("Durable Object reset because its code was updated.\nat Hub.fetch (hub.ts:1)");
        },
      }),
    },
  }) as unknown as Env;

  it("answers 503 unavailable as JSON with CORS and logs why, without request details", async () => {
    const hubFetches: string[] = [];
    let res!: Response;
    const { lines, raw } = await captureLogs(async () => {
      res = await worker.fetch(new Request(BASE + "/v1/friends/AB3D5F7H", {
        method: "POST", headers: { Authorization: "Bearer " + "a".repeat(64), "CF-Connecting-IP": "10.9.9.9" }, body: "{}",
      }), unreachableHub(hubFetches));
    });
    expect(res.status).toBe(503);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(await res.json()).toEqual({ ok: false, error: "unavailable", message: "service temporarily unavailable" });
    expect(hubFetches).toEqual(["/v1/friends/AB3D5F7H"]);
    expect(lines).toContainEqual({ level: "error", event: "hub_unreachable", errorName: "Error", errorMessage: "Durable Object reset because its code was updated." });
    // A 5xx is always logged, under its route only.
    expect(lines).toContainEqual(expect.objectContaining({ level: "error", event: "request", route: "/v1/friends/:id", status: 503 }));
    expect(raw).not.toContain("AB3D5F7H");
    expect(raw).not.toContain("a".repeat(64));
    expect(raw).not.toContain("10.9.9.9");
  });

  it("still answers the health check, the catalog and preflights itself", async () => {
    const hubFetches: string[] = [];
    await captureLogs(async () => {
      expect((await worker.fetch(new Request(BASE + "/"), unreachableHub(hubFetches))).status).toBe(200);
      expect((await worker.fetch(new Request(BASE + "/v1/catalog"), unreachableHub(hubFetches))).status).toBe(200);
      expect((await worker.fetch(new Request(BASE + "/v1/sync", { method: "OPTIONS" }), unreachableHub(hubFetches))).status).toBe(204);
      expect((await worker.fetch(new Request(BASE + "/wp-login.php"), unreachableHub(hubFetches))).status).toBe(404);
    });
    expect(hubFetches).toEqual([]);
  });
});
