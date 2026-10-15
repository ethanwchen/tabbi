import { runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { migrate } from "../src/hub";
import { FRIEND_REQUESTS_PER_DAY, FRIEND_REQUESTS_PER_MIN, MAX_FRIENDS, MAX_PENDING_REQUESTS } from "../src/lib";
import { admin, befriend, call, expectError, hub, register } from "./helpers";

type User = { code: string; token: string };
const codes = (list: { profile: { code: string } }[]) => list.map((x) => x.profile.code);
const listOf = async (u: User) => (await call("GET", "/v1/friends", undefined, u.token)).body;
const ask = (from: User, to: User) => call("POST", "/v1/friends", { code: to.code }, from.token);
const accept = (by: User, from: User) => call("POST", `/v1/friends/${from.code}/accept`, undefined, by.token);
const remove = (by: User, who: User) => call("DELETE", `/v1/friends/${who.code}`, undefined, by.token);
const waiting = async (u: User) => (await call("POST", "/v1/presence", { status: "idle" }, u.token)).body.incomingRequests;

afterEach(() => {
  vi.useRealTimers();
});

describe("friend requests", () => {
  it("asks by code, and makes friends only once the other accepts", async () => {
    const a = await register({ name: "Ana" });
    const b = await register({ name: "Ben", petName: "Mochi", species: "dog", breed: "corgi" });

    // Codes are case-insensitive and trimmed.
    const asked = await call("POST", "/v1/friends", { code: ` ${b.code.toLowerCase()} ` }, a.token);
    expect(asked.status).toBe(200);
    expect(asked.body).toEqual({ ok: true, added: false, status: "requested", friend: b.profile });

    const mine = await listOf(a);
    expect(mine.friends).toEqual([]);
    expect(mine.incoming).toEqual([]);
    expect(mine.outgoing).toEqual([{ profile: { ...b.profile, badges: [] }, since: expect.any(Number) }]);
    const theirs = await listOf(b);
    expect(theirs.friends).toEqual([]);
    expect(theirs.incoming).toEqual([{ profile: { ...a.profile, badges: [] }, since: expect.any(Number) }]);
    expect(theirs.outgoing).toEqual([]);
    expect(await waiting(b)).toBe(1);
    expect(await waiting(a)).toBe(0);
    // Nothing is shared before the request is accepted.
    expect((await call("GET", "/v1/leaderboard", undefined, a.token)).body.entries).toHaveLength(1);

    const accepted = await call("POST", `/v1/friends/${a.code.toLowerCase()}/accept`, undefined, b.token);
    expect(accepted.body).toEqual({ ok: true, added: true, status: "friends", friend: a.profile });
    for (const [u, other] of [[a, b], [b, a]]) {
      const list = await listOf(u);
      expect(codes(list.friends)).toEqual([other.code]);
      expect(list.incoming).toEqual([]);
      expect(list.outgoing).toEqual([]);
    }
    expect(await waiting(b)).toBe(0);
    // Accepting again is a no-op success.
    expect((await accept(b, a)).body).toMatchObject({ ok: true, added: false, status: "friends" });
  });

  it("lists friends sorted by name, with their profiles", async () => {
    const a = await register({ name: "Zoe" });
    const b = await register({ name: "Ben", petName: "Mochi", species: "dog", breed: "corgi" });
    const c = await register({ name: "amy" });
    await befriend(a, b);
    await befriend(c, a);

    const mine = await listOf(a);
    expect(mine.friends.map((f: { profile: { name: string } }) => f.profile.name)).toEqual(["amy", "Ben"]);
    expect(mine.friends[1].profile).toEqual({ ...b.profile, badges: [] });
    expect(typeof mine.friends[1].since).toBe("number");
    expect(codes((await listOf(b)).friends)).toEqual([a.code]);
  });

  it("shows profile changes to friends, every worn item included", async () => {
    const a = await register();
    const b = await register();
    await befriend(a, b);
    const look = { petName: "Kiwi", costume: "dinosaur-hoodie", accessories: ["wizard-hat", "heart-glasses", "snow-scarf", "angel-wings", "sparkle-trail"] };
    expect((await call("PATCH", "/v1/me", look, b.token)).status).toBe(200);
    expect((await listOf(a)).friends[0].profile).toMatchObject(look);
  });

  it("turns requests both ways into a friendship", async () => {
    const a = await register();
    const b = await register();
    expect((await ask(a, b)).body.status).toBe("requested");
    expect((await ask(b, a)).body).toMatchObject({ ok: true, added: true, status: "friends" });
    expect(codes((await listOf(a)).friends)).toEqual([b.code]);
    expect((await listOf(a)).outgoing).toEqual([]);
    expect((await listOf(b)).incoming).toEqual([]);
  });

  it("is idempotent: asking again keeps one request, asking a friend changes nothing", async () => {
    const a = await register();
    const b = await register();
    await ask(a, b);
    expect((await ask(a, b)).body).toMatchObject({ added: false, status: "requested" });
    expect((await listOf(b)).incoming).toHaveLength(1);
    await accept(b, a);
    expect((await ask(a, b)).body).toMatchObject({ added: false, status: "friends" });
    expect((await ask(b, a)).body).toMatchObject({ added: false, status: "friends" });
    expect((await listOf(a)).friends).toHaveLength(1);
  });

  it("declines quietly: the request leaves my list but still reads as sent for them", async () => {
    const a = await register();
    const b = await register();
    await ask(a, b);
    expect((await remove(b, a)).body).toEqual({ ok: true, removed: true });
    expect((await listOf(b)).incoming).toEqual([]);
    expect(await waiting(b)).toBe(0);
    expect(codes((await listOf(a)).outgoing)).toEqual([b.code]);
    // Asking again does not bring it back, and there is nothing left to accept.
    expect((await ask(a, b)).body.status).toBe("requested");
    expect((await listOf(b)).incoming).toEqual([]);
    expectError(await accept(b, a), 404, "no_request");
    expect((await remove(b, a)).body).toEqual({ ok: true, removed: false });
    // Changing my mind later: adding them back makes us friends.
    expect((await ask(b, a)).body).toMatchObject({ added: true, status: "friends" });
    expect((await listOf(a)).outgoing).toEqual([]);
  });

  it("cancels my own request", async () => {
    const a = await register();
    const b = await register();
    await ask(a, b);
    expect((await remove(a, b)).body).toEqual({ ok: true, removed: true });
    expect((await listOf(a)).outgoing).toEqual([]);
    expect((await listOf(b)).incoming).toEqual([]);
    expectError(await accept(b, a), 404, "no_request");
    await ask(a, b);
    expect(codes((await listOf(b)).incoming)).toEqual([a.code]);
  });

  it("accepts only a request that is waiting", async () => {
    const a = await register();
    const b = await register();
    expectError(await accept(b, a), 404, "no_request");
    // My own request is not mine to accept.
    await ask(a, b);
    expectError(await accept(a, b), 404, "no_request");
    expectError(await call("POST", "/v1/friends/AAAAAAAA/accept", undefined, b.token), 404, "unknown_code");
    expectError(await call("POST", "/v1/friends/bad/accept", undefined, b.token), 400, "invalid_field");
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
    await befriend(a, b);
    const del = await call("DELETE", `/v1/friends/${b.code.toLowerCase()}`, undefined, a.token);
    expect(del.body).toEqual({ ok: true, removed: true });
    expect((await listOf(a)).friends).toEqual([]);
    expect((await listOf(b)).friends).toEqual([]);
    expect((await remove(a, b)).body).toEqual({ ok: true, removed: false });
  });

  it("drops a deleted user from every friend list and request", async () => {
    const a = await register();
    const b = await register();
    const c = await register();
    const d = await register();
    const e = await register();
    await befriend(b, a);
    await befriend(c, a);
    await befriend(c, b);
    await ask(a, d);
    await ask(e, a);
    expect((await call("DELETE", "/v1/me", undefined, a.token)).status).toBe(200);
    expect(codes((await listOf(b)).friends)).toEqual([c.code]);
    expect(codes((await listOf(c)).friends)).toEqual([b.code]);
    expect((await listOf(d)).incoming).toEqual([]);
    expect((await listOf(e)).outgoing).toEqual([]);
    const left = await runInDurableObject(hub(), (_, state) =>
      state.storage.sql.exec("SELECT * FROM friend_requests WHERE sender = ? OR recipient = ?", a.code, a.code).toArray());
    expect(left).toEqual([]);
    // The code is gone, so it can no longer be asked.
    expectError(await ask(b, a), 404, "unknown_code");
  });

  it(`caps both sides at ${MAX_FRIENDS} friends`, async () => {
    const full = await register();
    for (let i = 0; i < MAX_FRIENDS; i++) await befriend(await register(), full);
    const late = await register();
    expectError(await ask(full, late), 409, "friend_limit");
    expectError(await ask(late, full), 409, "their_friend_limit");
    expect((await listOf(full)).friends).toHaveLength(MAX_FRIENDS);
    expect((await listOf(late)).friends).toEqual([]);

    // A request sent before the list filled up cannot be accepted past the cap either.
    const early = await register();
    await call("DELETE", `/v1/friends/${(await listOf(full)).friends[0].profile.code}`, undefined, full.token);
    await ask(early, full);
    await befriend(late, full);
    expectError(await accept(full, early), 409, "friend_limit");
    expect(codes((await listOf(full)).incoming)).toEqual([early.code]);
  });

  it("drops requests between users when one blocks the other, and refuses new ones", async () => {
    const a = await register();
    const b = await register();
    await ask(b, a);
    await call("POST", "/v1/blocks", { code: b.code }, a.token);
    expect((await listOf(a)).incoming).toEqual([]);
    expect((await listOf(b)).outgoing).toEqual([]);
    expectError(await ask(b, a), 404, "unknown_code");
    expectError(await ask(a, b), 409, "blocked");
    expectError(await accept(a, b), 404, "no_request");
  });

  it("hides a banned user's requests and lets no banned user ask or accept", async () => {
    const a = await register();
    const b = await register();
    const c = await register();
    await ask(b, a);
    await ask(c, b);
    await admin("POST", `/users/${b.code}/ban`);
    expect((await listOf(a)).incoming).toEqual([]);
    expect((await listOf(c)).outgoing).toEqual([]);
    expect(await waiting(a)).toBe(0);
    expectError(await accept(a, b), 404, "unknown_code");
    expectError(await ask(b, c), 403, "banned");
    expectError(await accept(b, c), 403, "banned");
    await admin("DELETE", `/users/${b.code}/ban`);
    expect(codes((await listOf(a)).incoming)).toEqual([b.code]);
  });

  it(`limits new requests to ${FRIEND_REQUESTS_PER_MIN} a minute and ${FRIEND_REQUESTS_PER_DAY} a day`, async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.parse("2026-10-15T09:00:00Z"));
    const a = await register();
    const others: User[] = [];
    for (let i = 0; i < FRIEND_REQUESTS_PER_DAY + 1; i++) others.push(await register());

    for (let i = 0; i < FRIEND_REQUESTS_PER_MIN; i++) expect((await ask(a, others[i])).status).toBe(200);
    const fast = await ask(a, others[FRIEND_REQUESTS_PER_MIN]);
    expectError(fast, 429, "rate_limited");
    expect(Number(fast.headers.get("Retry-After"))).toBeGreaterThan(0);
    // Asking someone already asked is not a new request, so it never counts.
    expect((await ask(a, others[0])).status).toBe(200);

    for (let i = FRIEND_REQUESTS_PER_MIN; i < FRIEND_REQUESTS_PER_DAY; i++) {
      if (i % FRIEND_REQUESTS_PER_MIN === 0) vi.setSystemTime(Date.now() + 60_000);
      expect((await ask(a, others[i])).status).toBe(200);
    }
    // Cancelling does not give a request back.
    await remove(a, others[0]);
    vi.setSystemTime(Date.now() + 60_000);
    const daily = await ask(a, others[FRIEND_REQUESTS_PER_DAY]);
    expectError(daily, 429, "request_limit");
    expect(Number(daily.headers.get("Retry-After"))).toBeGreaterThan(60);
    expect((await listOf(a)).outgoing).toHaveLength(FRIEND_REQUESTS_PER_DAY - 1);
  });

  it(`keeps at most ${MAX_PENDING_REQUESTS} requests waiting per sender`, async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.parse("2026-11-02T09:00:00Z"));
    const a = await register();
    await runInDurableObject(hub(), (_, state) => {
      for (let i = 0; i < MAX_PENDING_REQUESTS; i++) {
        state.storage.sql.exec("INSERT INTO friend_requests (sender, recipient, created_at) VALUES (?, ?, ?)",
          a.code, `PENDING${String(i).padStart(2, "0")}`, Math.floor(Date.now() / 1000));
      }
    });
    expectError(await ask(a, await register()), 409, "pending_limit");
  });

  it("requires a token", async () => {
    expectError(await call("GET", "/v1/friends"), 401, "unauthorized");
    expectError(await call("POST", "/v1/friends", { code: "AAAAAAAA" }), 401, "unauthorized");
    expectError(await call("POST", "/v1/friends/AAAAAAAA/accept"), 401, "unauthorized");
    expectError(await call("DELETE", "/v1/friends/AAAAAAAA"), 401, "unauthorized");
  });
});

describe("schema step 14", () => {
  it("adds the friend requests table to a database at version 13 and keeps every friendship", async () => {
    await runInDurableObject(hub(), (_, state) => {
      const sql = state.storage.sql;
      sql.exec("DROP TABLE friend_requests");
      sql.exec("ALTER TABLE users DROP COLUMN protocol");
      sql.exec("UPDATE schema_version SET version = 13");
      sql.exec("INSERT OR IGNORE INTO friends (a, b, created_at) VALUES ('MIGR8AAA', 'MIGR8BBB', 5), ('MIGR8BBB', 'MIGR8AAA', 5)");
      migrate(state.storage);
      expect(sql.exec("SELECT version FROM schema_version").toArray()).toEqual([{ version: 14 }]);
      expect(sql.exec("SELECT * FROM friend_requests").toArray()).toEqual([]);
      expect(sql.exec("SELECT a, b, created_at FROM friends WHERE a IN ('MIGR8AAA', 'MIGR8BBB') ORDER BY a").toArray()).toEqual([
        { a: "MIGR8AAA", b: "MIGR8BBB", created_at: 5 },
        { a: "MIGR8BBB", b: "MIGR8AAA", created_at: 5 },
      ]);
    });
  });
});
