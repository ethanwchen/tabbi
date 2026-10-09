import { SELF } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import catalog from "../shared/catalog.json";
import { REGISTER_PER_MIN, RATE_LIMIT_PER_MIN } from "../src/lib";
import { BASE, call, expectError, freshIp, pinClockToMinuteStart, register } from "./helpers";

const FULL = {
  name: "Maya",
  petName: "Mochi",
  species: "dog",
  breed: "corgi",
  colors: ["#f5a623", "#FFFFFF"],
  costume: "white-coat",
  accessories: ["glasses", "book"],
  points: 1200,
  level: 7,
};

describe("worker basics", () => {
  it("answers the health check, the catalog and CORS preflight", async () => {
    const root = await call("GET", "/");
    expect(root.body).toEqual({ ok: true, service: "tabbi-friends", version: 1 });
    const cat = await call("GET", "/v1/catalog");
    expect(cat.body).toEqual({ ok: true, catalog });
    const pre = await SELF.fetch(BASE + "/v1/me", { method: "OPTIONS" });
    expect(pre.status).toBe(204);
    expect(pre.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(root.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(root.headers.get("Cache-Control")).toBe("no-store");
  });

  it("404s unknown routes with an error code", async () => {
    expectError(await call("GET", "/nope"), 404, "not_found");
    const a = await register();
    expectError(await call("GET", "/v1/nope", undefined, a.token), 404, "not_found");
    expectError(await call("POST", "/v1/me", {}, a.token), 404, "not_found");
  });
});

describe("register", () => {
  it("creates a user with defaults", async () => {
    const a = await register();
    expect(a.profile).toEqual({
      code: a.code, name: "student", petName: "buddy", species: "cat", breed: catalog.breeds.cat[0],
      colors: [], costume: "none", accessories: [], points: 0, level: 1,
    });
  });

  it("stores every profile field, normalizing colors", async () => {
    const a = await register(FULL);
    expect(a.profile).toEqual({ ...FULL, code: a.code, colors: ["#F5A623", "#FFFFFF"] });
    const me = await call("GET", "/v1/me", undefined, a.token);
    expect(me.body).toEqual({ ok: true, profile: a.profile });
  });

  it("is idempotent with a valid token and updates the profile", async () => {
    const a = await register({ name: "Maya" });
    const again = await call("POST", "/v1/register", { petName: "Kiwi" }, a.token);
    expect(again.status).toBe(200);
    expect(again.body.code).toBe(a.code);
    expect(again.body.token).toBeUndefined();
    expect(again.body.profile.petName).toBe("Kiwi");
    expect(again.body.profile.name).toBe("Maya");
  });

  it("gives every user a distinct code and token", async () => {
    const users = await Promise.all([register(), register(), register()]);
    expect(new Set(users.map((u) => u.code)).size).toBe(3);
    expect(new Set(users.map((u) => u.token)).size).toBe(3);
  });

  it("strips control characters and treats blank text as unset", async () => {
    const a = await register({ name: " Bo\u0000b\u200b ", petName: "   " });
    expect(a.profile.name).toBe("Bob");
    expect(a.profile.petName).toBe("buddy");
  });
});

describe("profile validation", () => {
  const bad: [string, Record<string, unknown>, string][] = [
    ["unknown field", { deck: "Cardio" }, "unknown_field"],
    ["note text", { noteText: "x" }, "unknown_field"],
    ["name too long", { name: "a".repeat(25) }, "invalid_field"],
    ["name not a string", { name: 5 }, "invalid_field"],
    ["petName too long", { petName: "b".repeat(25) }, "invalid_field"],
    ["unknown species", { species: "hamster" }, "invalid_field"],
    ["unknown breed", { breed: "unicorn" }, "invalid_field"],
    ["dog breed on a cat", { species: "cat", breed: "corgi" }, "invalid_field"],
    ["breed not a string", { breed: 3 }, "invalid_field"],
    ["too many colors", { colors: Array(7).fill("#000000") }, "invalid_field"],
    ["short hex", { colors: ["#FFF"] }, "invalid_field"],
    ["named color", { colors: ["red"] }, "invalid_field"],
    ["colors not an array", { colors: "#000000" }, "invalid_field"],
    ["unknown costume", { costume: "cape" }, "invalid_field"],
    ["too many accessories", { accessories: ["glasses", "bow", "scarf", "crown", "halo"] }, "invalid_field"],
    ["duplicate accessory", { accessories: ["bow", "bow"] }, "invalid_field"],
    ["unknown accessory", { accessories: ["jetpack"] }, "invalid_field"],
    ["negative points", { points: -1 }, "invalid_field"],
    ["fractional points", { points: 1.5 }, "invalid_field"],
    ["huge points", { points: 1e12 }, "invalid_field"],
    ["level zero", { level: 0 }, "invalid_field"],
    ["level as string", { level: "3" }, "invalid_field"],
  ];
  it.each(bad)("rejects %s on register and PATCH /v1/me", async (_label, body, error) => {
    expectError(await call("POST", "/v1/register", body, undefined, freshIp()), 400, error);
    const a = await register();
    expectError(await call("PATCH", "/v1/me", body, a.token), 400, error);
  });

  it("rejects malformed and oversized bodies", async () => {
    const a = await register();
    expectError(await call("PATCH", "/v1/me", "{nope", a.token), 400, "invalid_json");
    expectError(await call("PATCH", "/v1/me", "[1]", a.token), 400, "invalid_json");
    expectError(await call("PATCH", "/v1/me", { name: "x".repeat(5000) }, a.token), 413, "body_too_large");
  });
});

describe("PATCH /v1/me", () => {
  it("updates only the given fields", async () => {
    const a = await register(FULL);
    const r = await call("PATCH", "/v1/me", { level: 8, accessories: [] }, a.token);
    expect(r.status).toBe(200);
    expect(r.body.profile).toEqual({ ...a.profile, level: 8, accessories: [] });
  });

  it("switching species without a breed picks that species' default breed", async () => {
    const a = await register({ species: "dog", breed: "pug" });
    const r = await call("PATCH", "/v1/me", { species: "cat" }, a.token);
    expect(r.body.profile.breed).toBe(catalog.breeds.cat[0]);
    const r2 = await call("PATCH", "/v1/me", { species: "dog", breed: "husky" }, a.token);
    expect(r2.body.profile).toMatchObject({ species: "dog", breed: "husky" });
  });
});

describe("auth", () => {
  it("rejects missing, malformed and unknown tokens with 401", async () => {
    expectError(await call("GET", "/v1/me"), 401, "unauthorized");
    expectError(await call("GET", "/v1/me", undefined, "not-hex"), 401, "unauthorized");
    expectError(await call("GET", "/v1/me", undefined, "0".repeat(64)), 401, "unauthorized");
    expectError(await call("POST", "/v1/register", {}, "0".repeat(64)), 401, "unauthorized");
  });
});

describe("DELETE /v1/me", () => {
  it("deletes the user; the token stops working", async () => {
    const a = await register(FULL);
    expect((await call("DELETE", "/v1/me", undefined, a.token)).body).toEqual({ ok: true });
    expectError(await call("GET", "/v1/me", undefined, a.token), 401, "unauthorized");
  });
});

describe("rate limits", () => {
  beforeEach(pinClockToMinuteStart);
  afterEach(() => vi.useRealTimers());

  it(`allows ${REGISTER_PER_MIN} registrations per minute per IP, then 429 with Retry-After`, async () => {
    const ip = freshIp();
    for (let i = 0; i < REGISTER_PER_MIN; i++) expect((await call("POST", "/v1/register", {}, undefined, ip)).status).toBe(201);
    const r = await call("POST", "/v1/register", {}, undefined, ip);
    expectError(r, 429, "rate_limited");
    expect(r.headers.get("Retry-After")).toBe("60");
    expect((await call("POST", "/v1/register", {}, undefined, freshIp())).status).toBe(201);
  });

  it(`allows ${RATE_LIMIT_PER_MIN} requests per minute per token`, async () => {
    const a = await register();
    const b = await register();
    for (let i = 0; i < RATE_LIMIT_PER_MIN; i++) expect((await call("GET", "/v1/me", undefined, a.token)).status).toBe(200);
    expectError(await call("GET", "/v1/me", undefined, a.token), 429, "rate_limited");
    expect((await call("GET", "/v1/me", undefined, b.token)).status).toBe(200);
  });

  it("limits unauthenticated guessing per IP", async () => {
    const ip = freshIp();
    for (let i = 0; i < RATE_LIMIT_PER_MIN; i++) expect((await call("GET", "/v1/me", undefined, "bad", ip)).status).toBe(401);
    expectError(await call("GET", "/v1/me", undefined, "bad", ip), 429, "rate_limited");
  });
});
