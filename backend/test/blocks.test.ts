import { describe, expect, it } from "vitest";
import { MAX_BLOCKS } from "../src/moderation";
import { env, runInDurableObject } from "cloudflare:test";
import { migrate } from "../src/hub";
import { call, expectError, hub, register } from "./helpers";

const codes = (list: { profile: { code: string } }[]) => list.map((x) => x.profile.code);
const friendsOf = async (u: { token: string }) => codes((await call("GET", "/v1/friends", undefined, u.token)).body.friends);
const blocksOf = async (u: { token: string }) => (await call("GET", "/v1/blocks", undefined, u.token)).body.blocks;
const block = (by: { token: string }, who: { code: string }) => call("POST", "/v1/blocks", { code: who.code }, by.token);

async function createParty(u: { token: string }) {
  const r = await call("POST", "/v1/party", undefined, u.token);
  expect(r.status).toBe(201);
  return r.body.party.code as string;
}
const join = (u: { token: string }, code: string) => call("POST", "/v1/party/join", { code }, u.token);
const partyOf = async (u: { token: string }) => (await call("GET", "/v1/party", undefined, u.token)).body.party;

describe("blocks", () => {
  it("ends the friendship, lists the block with current names, and is idempotent", async () => {
    const a = await register({ name: "Ana" });
    const b = await register({ name: "Ben", petName: "Mochi" });
    await call("POST", "/v1/friends", { code: b.code }, a.token);

    const r = await call("POST", "/v1/blocks", { code: ` ${b.code.toLowerCase()} ` }, a.token);
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ ok: true, blocked: true, block: { code: b.code, name: "Ben", petName: "Mochi" } });
    expect(await friendsOf(a)).toEqual([]);
    expect(await friendsOf(b)).toEqual([]);

    await call("PATCH", "/v1/me", { name: "Benji" }, b.token);
    expect(await blocksOf(a)).toEqual([{ code: b.code, name: "Benji", petName: "Mochi", since: expect.any(Number) }]);
    expect(await blocksOf(b)).toEqual([]);
    expect((await block(a, b)).body.blocked).toBe(false);
    expect(await blocksOf(a)).toHaveLength(1);
  });

  it("stops either side from adding the other, without telling the blocked user", async () => {
    const a = await register();
    const b = await register();
    await block(a, b);
    expectError(await call("POST", "/v1/friends", { code: a.code }, b.token), 404, "unknown_code");
    expectError(await call("POST", "/v1/friends", { code: b.code }, a.token), 409, "blocked");
  });

  it("drops the blocked user from the leaderboard", async () => {
    const a = await register();
    const b = await register();
    await call("POST", "/v1/friends", { code: b.code }, a.token);
    await block(b, a);
    const board = (await call("GET", "/v1/leaderboard", undefined, a.token)).body.entries;
    expect(board.map((e: { profile: { code: string } }) => e.profile.code)).toEqual([a.code]);
  });

  it("lifts with unblock, without restoring the friendship", async () => {
    const a = await register();
    const b = await register();
    await call("POST", "/v1/friends", { code: b.code }, a.token);
    await block(a, b);
    expect((await call("DELETE", `/v1/blocks/${b.code.toLowerCase()}`, undefined, a.token)).body).toEqual({ ok: true, unblocked: true });
    expect((await call("DELETE", `/v1/blocks/${b.code}`, undefined, a.token)).body).toEqual({ ok: true, unblocked: false });
    expect(await blocksOf(a)).toEqual([]);
    expect(await friendsOf(a)).toEqual([]);
    expect((await call("POST", "/v1/friends", { code: a.code }, b.token)).body.added).toBe(true);
  });

  it("only lets the blocker lift a block", async () => {
    const a = await register();
    const b = await register();
    await block(a, b);
    expect((await call("DELETE", `/v1/blocks/${a.code}`, undefined, b.token)).body.unblocked).toBe(false);
    expectError(await call("POST", "/v1/friends", { code: a.code }, b.token), 404, "unknown_code");
  });

  it("keeps a blocked user out of a party I host, by code or through a friend", async () => {
    const host = await register();
    const b = await register();
    const party = await createParty(host);
    await block(host, b);
    expectError(await join(b, party), 404, "party_not_found");
    // The blocker cannot join the blocked user's party either.
    const theirs = await createParty(b);
    expectError(await join(host, theirs), 404, "party_not_found");
  });

  it("removes the blocked member from my party, or takes me out of theirs", async () => {
    const host = await register();
    const b = await register();
    const party = await createParty(host);
    expect((await join(b, party)).status).toBe(200);
    await block(host, b);
    expect(await partyOf(b)).toBeNull();
    expect(codes((await partyOf(host)).members)).toEqual([host.code]);

    const c = await register();
    const theirs = await createParty(c);
    await join(b, theirs);
    await block(b, c);
    expect(await partyOf(b)).toBeNull();
    expect(codes((await partyOf(c)).members)).toEqual([c.code]);
  });

  it("hides two members from each other in someone else's party", async () => {
    const host = await register();
    const a = await register();
    const b = await register();
    const party = await createParty(host);
    await join(a, party);
    await join(b, party);
    await block(a, b);
    expect(codes((await partyOf(a)).members)).toEqual([host.code, a.code]);
    expect(codes((await partyOf(b)).members)).toEqual([host.code, b.code]);
    expect(codes((await partyOf(host)).members)).toEqual([host.code, a.code, b.code]);
  });

  it("forgets blocks either way when a user is deleted", async () => {
    const a = await register();
    const b = await register();
    const c = await register();
    await block(a, b);
    await block(c, a);
    await call("DELETE", "/v1/me", undefined, b.token);
    expect(await blocksOf(a)).toEqual([]);
    await call("DELETE", "/v1/me", undefined, a.token);
    expect(await blocksOf(c)).toEqual([]);
  });

  it("validates the code", async () => {
    const a = await register();
    expectError(await call("POST", "/v1/blocks", { code: a.code }, a.token), 400, "self_block");
    expectError(await call("POST", "/v1/blocks", { code: "AAAAAAAA" }, a.token), 404, "unknown_code");
    expectError(await call("POST", "/v1/blocks", { code: "short" }, a.token), 400, "invalid_field");
    expectError(await call("POST", "/v1/blocks", { code: a.code, reason: "spam" }, a.token), 400, "unknown_field");
    expectError(await call("DELETE", "/v1/blocks/bad", undefined, a.token), 400, "invalid_field");
  });

  it(`caps blocks at ${MAX_BLOCKS} per user`, async () => {
    const a = await register();
    const b = await register();
    await runInDurableObject(hub(), (_, state) => {
      for (let i = 0; i < MAX_BLOCKS; i++) {
        state.storage.sql.exec("INSERT INTO blocks (blocker, blocked, created_at) VALUES (?, ?, 0)", a.code, `X${i}`);
      }
    });
    expectError(await block(a, b), 409, "block_limit");
  });

  it("requires a token", async () => {
    expectError(await call("GET", "/v1/blocks"), 401, "unauthorized");
    expectError(await call("POST", "/v1/blocks", { code: "AAAAAAAA" }), 401, "unauthorized");
    expectError(await call("DELETE", "/v1/blocks/AAAAAAAA"), 401, "unauthorized");
  });
});

describe("schema step 3", () => {
  it("adds the blocks table to a database at version 2 and keeps its data", async () => {
    const stub = env.HUB.get(env.HUB.idFromName("before-blocks"));
    await runInDurableObject(stub, (_, state) => {
      const sql = state.storage.sql;
      sql.exec("DROP TABLE blocks");
      sql.exec("DROP TABLE reports");
      sql.exec("DROP TABLE bans");
      sql.exec("DROP TABLE name_holds");
      sql.exec("UPDATE schema_version SET version = 2");
      sql.exec("INSERT INTO friends (a, b, created_at) VALUES ('AAAAAAAA', 'BBBBBBBB', 0)");
      migrate(state.storage);
      expect(sql.exec("SELECT version FROM schema_version").toArray()).toEqual([{ version: 4 }]);
      expect(sql.exec("SELECT * FROM blocks").toArray()).toEqual([]);
      expect(sql.exec("SELECT a FROM friends").toArray()).toEqual([{ a: "AAAAAAAA" }]);
    });
  });
});
