import { describe, expect, it } from "vitest";
import { MAX_FRIENDS } from "../src/lib";
import { call, expectError, register } from "./helpers";

describe("friends", () => {
  it("adds symmetrically by code and lists profiles sorted by name", async () => {
    const a = await register({ name: "Zoe" });
    const b = await register({ name: "Ben", petName: "Mochi", species: "dog", breed: "corgi" });
    const c = await register({ name: "amy" });

    const add = await call("POST", "/v1/friends", { code: b.code }, a.token);
    expect(add.status).toBe(200);
    expect(add.body).toEqual({ ok: true, added: true, friend: b.profile });
    // Codes are case-insensitive and trimmed.
    expect((await call("POST", "/v1/friends", { code: ` ${c.code.toLowerCase()} ` }, a.token)).body.added).toBe(true);

    const mine = await call("GET", "/v1/friends", undefined, a.token);
    expect(mine.status).toBe(200);
    expect(mine.body.friends.map((f: { profile: { name: string } }) => f.profile.name)).toEqual(["amy", "Ben"]);
    expect(mine.body.friends[1].profile).toEqual(b.profile);
    expect(typeof mine.body.friends[1].since).toBe("number");

    const theirs = await call("GET", "/v1/friends", undefined, b.token);
    expect(theirs.body.friends.map((f: { profile: { code: string } }) => f.profile.code)).toEqual([a.code]);
  });

  it("shows profile changes to friends", async () => {
    const a = await register();
    const b = await register();
    await call("POST", "/v1/friends", { code: b.code }, a.token);
    await call("PATCH", "/v1/me", { petName: "Kiwi", costume: "scrubs" }, b.token);
    const list = await call("GET", "/v1/friends", undefined, a.token);
    expect(list.body.friends[0].profile).toMatchObject({ petName: "Kiwi", costume: "scrubs" });
  });

  it("is idempotent from either side", async () => {
    const a = await register();
    const b = await register();
    expect((await call("POST", "/v1/friends", { code: b.code }, a.token)).body.added).toBe(true);
    expect((await call("POST", "/v1/friends", { code: b.code }, a.token)).body.added).toBe(false);
    expect((await call("POST", "/v1/friends", { code: a.code }, b.token)).body.added).toBe(false);
    expect((await call("GET", "/v1/friends", undefined, a.token)).body.friends).toHaveLength(1);
  });

  it("validates the code", async () => {
    const a = await register();
    expectError(await call("POST", "/v1/friends", { code: a.code }, a.token), 400, "self_friend");
    expectError(await call("POST", "/v1/friends", { code: "AAAAAAAA" }, a.token), 404, "unknown_code");
    for (const code of [undefined, 12345678, "SHORT", "ABCDEFG1", "ABCDEFGO", "ABCDEFGHJ"]) {
      expectError(await call("POST", "/v1/friends", code === undefined ? {} : { code }, a.token), 400, "invalid_field");
    }
    expectError(await call("POST", "/v1/friends", { code: "AAAAAAAA", note: "hi" }, a.token), 400, "unknown_field");
    expectError(await call("POST", "/v1/friends", "[1]", a.token), 400, "invalid_json");
    expectError(await call("DELETE", "/v1/friends/bad%ZZ", undefined, a.token), 400, "invalid_field");
  });

  it("removes symmetrically, and removing a non-friend is a no-op", async () => {
    const a = await register();
    const b = await register();
    await call("POST", "/v1/friends", { code: b.code }, a.token);
    const del = await call("DELETE", `/v1/friends/${b.code.toLowerCase()}`, undefined, a.token);
    expect(del.body).toEqual({ ok: true, removed: true });
    expect((await call("GET", "/v1/friends", undefined, a.token)).body.friends).toEqual([]);
    expect((await call("GET", "/v1/friends", undefined, b.token)).body.friends).toEqual([]);
    expect((await call("DELETE", `/v1/friends/${b.code}`, undefined, a.token)).body).toEqual({ ok: true, removed: false });
  });

  it("drops a deleted user from every friend list", async () => {
    const a = await register();
    const b = await register();
    const c = await register();
    await call("POST", "/v1/friends", { code: a.code }, b.token);
    await call("POST", "/v1/friends", { code: a.code }, c.token);
    await call("POST", "/v1/friends", { code: b.code }, c.token);
    expect((await call("DELETE", "/v1/me", undefined, a.token)).status).toBe(200);
    expect((await call("GET", "/v1/friends", undefined, b.token)).body.friends.map((f: { profile: { code: string } }) => f.profile.code)).toEqual([c.code]);
    expect((await call("GET", "/v1/friends", undefined, c.token)).body.friends.map((f: { profile: { code: string } }) => f.profile.code)).toEqual([b.code]);
    // The code is gone, so it can no longer be added.
    expectError(await call("POST", "/v1/friends", { code: a.code }, b.token), 404, "unknown_code");
  });

  it(`caps both sides at ${MAX_FRIENDS} friends`, async () => {
    const hub = await register();
    for (let i = 0; i < MAX_FRIENDS; i++) {
      const f = await register();
      expect((await call("POST", "/v1/friends", { code: hub.code }, f.token)).body.added).toBe(true);
    }
    const late = await register();
    expectError(await call("POST", "/v1/friends", { code: late.code }, hub.token), 409, "friend_limit");
    expectError(await call("POST", "/v1/friends", { code: hub.code }, late.token), 409, "their_friend_limit");
    expect((await call("GET", "/v1/friends", undefined, hub.token)).body.friends).toHaveLength(MAX_FRIENDS);
    expect((await call("GET", "/v1/friends", undefined, late.token)).body.friends).toEqual([]);
  });

  it("requires a token", async () => {
    expectError(await call("GET", "/v1/friends"), 401, "unauthorized");
    expectError(await call("POST", "/v1/friends", { code: "AAAAAAAA" }), 401, "unauthorized");
    expectError(await call("DELETE", "/v1/friends/AAAAAAAA"), 401, "unauthorized");
  });
});
