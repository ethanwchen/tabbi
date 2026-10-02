import { env, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import catalog from "../shared/catalog.json";
import type { Hub } from "../src/hub";
import { call, expectError, register } from "./helpers";

const now = () => Math.floor(Date.now() / 1000);
const EXPIRY = catalog.limits.partyIdleExpirySeconds;

/** Moves the clock (seen by both the test and the Hub, which share an isolate) forward. */
function advance(seconds: number) {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(Date.now() + seconds * 1000);
}

/** The party row as persisted in SQLite. */
async function storedParty(code: string) {
  const stub = env.HUB.get(env.HUB.idFromName("hub"));
  return runInDurableObject(stub, (_hub: Hub, state) =>
    state.storage.sql.exec("SELECT * FROM parties WHERE code = ?", code).toArray()[0] ?? null);
}

async function create(user: { token: string }) {
  const r = await call("POST", "/v1/party", undefined, user.token);
  expect(r.status).toBe(201);
  return r.body.party;
}

const memberCodes = (party: { members: { profile: { code: string } }[] }) => party.members.map((m) => m.profile.code);

afterEach(() => {
  vi.useRealTimers();
});

describe("parties", () => {
  it("creates a party with a 6-character code and the caller as host", async () => {
    const a = await register({ name: "Ana", petName: "Miso" });
    expect((await call("GET", "/v1/party", undefined, a.token)).body).toEqual({ ok: true, party: null });
    const party = await create(a);
    expect(party.code).toMatch(/^[A-HJ-NP-Z2-9]{6}$/);
    expect(party).toMatchObject({
      host: a.code, session: null, maxMembers: catalog.limits.maxPartyMembers, expiresAt: party.lastActive + EXPIRY,
    });
    expect(party.members).toEqual([
      { profile: a.profile, joinedAt: expect.any(Number), host: true, presence: null, online: false },
    ]);
    expect((await call("GET", "/v1/party", undefined, a.token)).body.party).toEqual(party);
    expectError(await call("POST", "/v1/party", { name: "x" }, a.token), 400, "unknown_field");
    expectError(await call("POST", "/v1/party"), 401, "unauthorized");
  });

  it("joins by party code and shows members with presence", async () => {
    const a = await register();
    const b = await register();
    const party = await create(a);
    await call("POST", "/v1/presence", { status: "studying", method: "anki" }, b.token);

    // Codes are case-insensitive and trimmed.
    const join = await call("POST", "/v1/party/join", { code: ` ${party.code.toLowerCase()} ` }, b.token);
    expect(join.status).toBe(200);
    expect(join.body.joined).toBe(true);
    expect(memberCodes(join.body.party)).toEqual([a.code, b.code]);
    expect(join.body.party.members[1]).toMatchObject({ host: false, online: true, presence: { status: "studying", method: "anki" } });
    expect(memberCodes((await call("GET", "/v1/party", undefined, a.token)).body.party)).toEqual([a.code, b.code]);

    // Joining again is a no-op.
    const again = await call("POST", "/v1/party/join", { code: party.code }, b.token);
    expect(again.body.joined).toBe(false);
    expect(again.body.party.members).toHaveLength(2);
  });

  it("joins an online friend's party", async () => {
    const a = await register();
    const b = await register();
    const stranger = await register();
    await call("POST", "/v1/friends", { code: a.code }, b.token);
    const party = await create(a);

    // Friends see which party a friend is in.
    expect((await call("GET", "/v1/friends", undefined, b.token)).body.friends[0].party).toEqual({ code: party.code, size: 1 });

    expectError(await call("POST", "/v1/party/join", { friend: a.code }, b.token), 409, "friend_offline");
    await call("POST", "/v1/presence", { status: "studying" }, a.token);
    expectError(await call("POST", "/v1/party/join", { friend: a.code }, stranger.token), 403, "not_friend");
    const join = await call("POST", "/v1/party/join", { friend: a.code }, b.token);
    expect(join.body.joined).toBe(true);
    expect(join.body.party.code).toBe(party.code);

    // A friend who is online but not in a party.
    await call("POST", "/v1/party/leave", undefined, b.token);
    await call("POST", "/v1/presence", { status: "idle" }, b.token);
    expectError(await call("POST", "/v1/party/join", { friend: b.code }, a.token), 404, "friend_not_in_party");
  });

  it("validates join bodies", async () => {
    const a = await register();
    const bad: unknown[] = [{}, { code: "ABCDEF", friend: "ABCDEFGH" }, { code: "ABCDE" }, { code: "ABCDE1" }, { code: 123456 },
      { friend: "SHORT" }, { friend: null }];
    for (const body of bad) expectError(await call("POST", "/v1/party/join", body, a.token), 400, "invalid_field");
    expectError(await call("POST", "/v1/party/join", { code: "ABCDEF", deck: "x" }, a.token), 400, "unknown_field");
    expectError(await call("POST", "/v1/party/join", { code: "ZZZZZZ" }, a.token), 404, "party_not_found");
  });

  it("caps a party at 8 members", async () => {
    const host = await register();
    const party = await create(host);
    for (let i = 1; i < catalog.limits.maxPartyMembers; i++) {
      const u = await register();
      expect((await call("POST", "/v1/party/join", { code: party.code }, u.token)).status).toBe(200);
    }
    const late = await register();
    expectError(await call("POST", "/v1/party/join", { code: party.code }, late.token), 409, "party_full");
    expect((await call("GET", "/v1/party", undefined, host.token)).body.party.members).toHaveLength(8);
    // A late user's own party is untouched by the failed join.
    const own = await create(late);
    expectError(await call("POST", "/v1/party/join", { code: party.code }, late.token), 409, "party_full");
    expect((await call("GET", "/v1/party", undefined, late.token)).body.party.code).toBe(own.code);
  });

  it("is one party at a time: creating or joining leaves the previous party", async () => {
    const a = await register();
    const b = await register();
    const first = await create(a);
    await call("POST", "/v1/party/join", { code: first.code }, b.token);
    const second = await create(b);
    expect(memberCodes((await call("GET", "/v1/party", undefined, a.token)).body.party)).toEqual([a.code]);
    await call("POST", "/v1/party/join", { code: second.code }, a.token);
    // The first party lost its last member and is gone.
    expect(await storedParty(first.code)).toBeNull();
    expectError(await call("POST", "/v1/party/join", { code: first.code }, b.token), 404, "party_not_found");
  });

  it("hands the host role over when the host leaves, and deletes an empty party", async () => {
    const a = await register();
    const b = await register();
    const c = await register();
    const party = await create(a);
    await call("POST", "/v1/party/join", { code: party.code }, b.token);
    await call("POST", "/v1/party/join", { code: party.code }, c.token);

    expect((await call("POST", "/v1/party/leave", undefined, a.token)).body).toEqual({ ok: true, left: true });
    expect((await call("POST", "/v1/party/leave", undefined, a.token)).body).toEqual({ ok: true, left: false });
    const view = (await call("GET", "/v1/party", undefined, c.token)).body.party;
    expect(view.host).toBe(b.code);
    expect(view.members.map((m: { host: boolean }) => m.host)).toEqual([true, false]);

    // A non-host leaving keeps the host.
    await call("POST", "/v1/party/leave", undefined, c.token);
    expect((await call("GET", "/v1/party", undefined, b.token)).body.party.host).toBe(b.code);
    await call("POST", "/v1/party/leave", undefined, b.token);
    expect(await storedParty(party.code)).toBeNull();
    expectError(await call("POST", "/v1/party/leave", { x: 1 }, b.token), 400, "unknown_field");
  });

  it("shares a session started by the host", async () => {
    const a = await register();
    const b = await register();
    const party = await create(a);
    await call("POST", "/v1/party/join", { code: party.code }, b.token);
    const phaseEndsAt = now() + 25 * 60;

    expectError(await call("POST", "/v1/party/session", { method: "pomodoro", phaseEndsAt }, b.token), 403, "not_host");
    const start = await call("POST", "/v1/party/session", { method: "pomodoro", phaseEndsAt }, a.token);
    expect(start.status).toBe(200);
    expect(start.body.party.session).toEqual({ method: "pomodoro", phaseEndsAt, startedAt: expect.any(Number) });
    expect((await call("GET", "/v1/party", undefined, b.token)).body.party.session).toEqual(start.body.party.session);

    expectError(await call("DELETE", "/v1/party/session", undefined, b.token), 403, "not_host");
    const end = await call("DELETE", "/v1/party/session", undefined, a.token);
    expect(end.body.party.session).toBeNull();
    expect((await call("GET", "/v1/party", undefined, b.token)).body.party.session).toBeNull();

    // The session survives a host handover.
    await call("POST", "/v1/party/session", { method: "52-17", phaseEndsAt }, a.token);
    await call("POST", "/v1/party/leave", undefined, a.token);
    expect((await call("GET", "/v1/party", undefined, b.token)).body.party.session).toMatchObject({ method: "52-17" });
    expect((await call("POST", "/v1/party/session", { method: "flowtime", phaseEndsAt }, b.token)).status).toBe(200);
  });

  it("validates sessions", async () => {
    const a = await register();
    const loner = await register();
    expectError(await call("POST", "/v1/party/session", { method: "pomodoro", phaseEndsAt: now() + 60 }, loner.token), 404, "not_in_party");
    expectError(await call("DELETE", "/v1/party/session", undefined, loner.token), 404, "not_in_party");
    await create(a);
    const bad: Record<string, unknown>[] = [
      {}, { method: "pomodoro" }, { phaseEndsAt: now() + 60 }, { method: "cram", phaseEndsAt: now() + 60 },
      { method: "pomodoro", phaseEndsAt: now() - 1 }, { method: "pomodoro", phaseEndsAt: now() + 2 * 86400 },
      { method: "pomodoro", phaseEndsAt: "soon" },
    ];
    for (const body of bad) expectError(await call("POST", "/v1/party/session", body, a.token), 400, "invalid_field");
    expectError(await call("POST", "/v1/party/session", { method: "pomodoro", phaseEndsAt: now() + 60, deck: "x" }, a.token), 400, "unknown_field");
  });

  it("expires after 12 hours without activity", async () => {
    const a = await register();
    const b = await register();
    await call("POST", "/v1/friends", { code: a.code }, b.token);
    const party = await create(a);

    // Polls keep the party alive, but write at most every 10 minutes.
    advance(300);
    await call("GET", "/v1/party", undefined, a.token);
    expect((await storedParty(party.code))!.last_active).toBe(party.lastActive);
    advance(300);
    const polled = (await call("GET", "/v1/party", undefined, a.token)).body.party;
    expect(polled.lastActive).toBe(party.lastActive + 600);
    expect(polled.expiresAt).toBe(polled.lastActive + EXPIRY);

    advance(EXPIRY - 1);
    expect((await call("GET", "/v1/friends", undefined, b.token)).body.friends[0].party).toEqual({ code: party.code, size: 1 });
    advance(1);
    expect((await call("GET", "/v1/friends", undefined, b.token)).body.friends[0].party).toBeNull();
    expectError(await call("POST", "/v1/party/join", { code: party.code }, b.token), 404, "party_not_found");
    expect(await storedParty(party.code)).toBeNull();
    expect((await call("GET", "/v1/party", undefined, a.token)).body.party).toBeNull();
  });

  it("sweeps expired parties nobody touches when a new party is created", async () => {
    const a = await register();
    const old = await create(a);
    advance(EXPIRY);
    const b = await register();
    await create(b);
    expect(await storedParty(old.code)).toBeNull();
  });

  it("leaves the party when the account is deleted", async () => {
    const a = await register();
    const b = await register();
    const party = await create(a);
    await call("POST", "/v1/party/join", { code: party.code }, b.token);
    await call("DELETE", "/v1/me", undefined, a.token);
    const view = (await call("GET", "/v1/party", undefined, b.token)).body.party;
    expect(view.host).toBe(b.code);
    expect(memberCodes(view)).toEqual([b.code]);
  });
});
