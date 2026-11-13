import { runDurableObjectAlarm } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { JOIN_REQUESTS_PER_DAY, JOIN_REQUEST_TTL_S, MAX_CREW_JOIN_REQUESTS } from "../src/crews";
import { admin, call, expectError, hub, oldCall, register } from "./helpers";
import { User, advance, atWeek, joinByCode, makeCrew, rows } from "./crewHelpers";
import { check, checkCrews } from "./schema";

/** Weeks of their own, far from crews.test.ts and crews-credit.test.ts. */
let slot = 2000;
const fresh = () => atWeek((slot += 10));

afterEach(() => {
  vi.useRealTimers();
});

const user = async (name = "Sam") => await register({ name, petName: "Mochi" }) as User;

/** Asks to join a public crew by id, checking the reply's shape. */
async function ask(u: User, crewId: string) {
  const r = await call("POST", "/v1/crews/join", { crew: crewId }, u.token);
  expect(r.status, JSON.stringify(r.body)).toBe(200);
  expect(checkCrews("joinReply", r.body)).toEqual([]);
  return r.body;
}

/** The owner's view of their crew, with its waiting requests. */
async function ownerView(owner: User) {
  const r = await call("GET", "/v1/crews/mine", undefined, owner.token);
  expect(checkCrews("mineReply", r.body)).toEqual([]);
  return r.body.crew as { requests: { ref: string; name: string; pet: unknown; requestedAt: number; expiresAt: number }[]; memberCount: number };
}

describe("asking to join a public crew", () => {
  it("waits for the owner, who sees the request and lets me in", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const me = await user("Asker");
    const asked = await ask(me, crew.id);
    expect(asked).toMatchObject({ joined: false, requested: true, request: { crew: { id: crew.id } }, crew: { mine: false, memberCount: 1 } });
    expect(asked.request.expiresAt - asked.request.requestedAt).toBe(JOIN_REQUEST_TTL_S);
    expect(asked.crew).not.toHaveProperty("requests");

    const mine = (await call("GET", "/v1/crews/mine", undefined, me.token)).body;
    expect(mine).toMatchObject({ crew: null, request: { crew: { id: crew.id } } });

    const view = await ownerView(owner);
    expect(view.requests).toEqual([expect.objectContaining({ name: "Asker", pet: expect.objectContaining({ petName: "Mochi" }), badges: [] })]);
    expect(view.requests[0]).not.toHaveProperty("code");

    const approved = await call("POST", `/v1/crews/mine/requests/${view.requests[0].ref}/approve`, undefined, owner.token);
    expect(checkCrews("crewReply", approved.body)).toEqual([]);
    expect(approved.body.crew).toMatchObject({ memberCount: 2, requests: [] });
    expect((await call("GET", "/v1/crews/mine", undefined, me.token)).body).toMatchObject({ crew: { id: crew.id, mine: true }, request: null });
    expectError(await call("POST", `/v1/crews/mine/requests/${view.requests[0].ref}/approve`, undefined, owner.token), 404, "request_not_found");
  });

  it("treats asking again as a no-op, and a request to another crew replaces mine", async () => {
    fresh();
    const a = await makeCrew();
    const b = await makeCrew();
    const me = await user();
    const first = await ask(me, a.crew.id);
    advance(60);
    const again = await ask(me, a.crew.id);
    expect(again.request.requestedAt).toBe(first.request.requestedAt);
    expect((await ownerView(a.owner)).requests).toHaveLength(1);
    await ask(me, b.crew.id);
    expect((await ownerView(a.owner)).requests).toEqual([]);
    expect((await ownerView(b.owner)).requests).toHaveLength(1);
  });

  it("lets an invite code join at once, public or private, and drops my request", async () => {
    fresh();
    const a = await makeCrew();
    const b = await makeCrew();
    const me = await user();
    await ask(me, a.crew.id);
    await joinByCode(me, b.crew.inviteCode);
    expect((await ownerView(a.owner)).requests).toEqual([]);
    expect((await call("GET", "/v1/crews/mine", undefined, me.token)).body.request).toBeNull();
  });

  it("is declined quietly, and can be cancelled", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const me = await user();
    await ask(me, crew.id);
    const ref = (await ownerView(owner)).requests[0].ref;
    const declined = await call("POST", `/v1/crews/mine/requests/${ref}/decline`, undefined, owner.token);
    expect(checkCrews("declineReply", declined.body)).toEqual([]);
    expect(declined.body).toEqual({ ok: true, declined: true });
    expect((await call("GET", "/v1/crews/mine", undefined, me.token)).body.request).toBeNull();

    await ask(me, crew.id);
    const cancelled = await call("POST", "/v1/crews/requests/cancel", {}, me.token);
    expect(checkCrews("cancelReply", cancelled.body)).toEqual([]);
    expect(cancelled.body.cancelled).toBe(true);
    expect((await call("POST", "/v1/crews/requests/cancel", {}, me.token)).body.cancelled).toBe(false);
    expect((await ownerView(owner)).requests).toEqual([]);
  });

  it("lets only the owner answer", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const member = await user();
    await joinByCode(member, crew.inviteCode);
    await ask(await user(), crew.id);
    const ref = (await ownerView(owner)).requests[0].ref;
    expect((await call("GET", "/v1/crews/mine", undefined, member.token)).body.crew).not.toHaveProperty("requests");
    expectError(await call("POST", `/v1/crews/mine/requests/${ref}/approve`, undefined, member.token), 403, "not_owner");
    expectError(await call("POST", `/v1/crews/mine/requests/${ref}/decline`, undefined, member.token), 403, "not_owner");
    expectError(await call("POST", "/v1/crews/mine/requests/AAAAAAAAAA/decline", undefined, owner.token), 404, "request_not_found");
  });

  it("expires after seven days, and the sweep deletes it", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const me = await user();
    await ask(me, crew.id);
    advance(JOIN_REQUEST_TTL_S + 60);
    expect((await ownerView(owner)).requests).toEqual([]);
    expect((await call("GET", "/v1/crews/mine", undefined, me.token)).body.request).toBeNull();
    expect(await runDurableObjectAlarm(hub())).toBe(true);
    expect(await rows("SELECT * FROM crew_join_requests WHERE code = ?", me.code)).toEqual([]);
  });

  it("refuses to approve into a full crew and keeps the request, and drops one whose sender joined elsewhere", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const late = await user("Late");
    await ask(late, crew.id);
    for (let i = 1; i < 20; i++) await joinByCode(await user(), crew.inviteCode);
    const lateRef = (await ownerView(owner)).requests[0].ref;
    expectError(await call("POST", `/v1/crews/mine/requests/${lateRef}/approve`, undefined, owner.token), 409, "crew_full");
    expect((await ownerView(owner)).requests.map((r) => r.name)).toEqual(["Late"]);

    const mover = await user("Mover");
    await ask(mover, crew.id);
    const moverRef = (await ownerView(owner)).requests.find((r) => r.name === "Mover")!.ref;
    await joinByCode(mover, (await makeCrew()).crew.inviteCode);
    expectError(await call("POST", `/v1/crews/mine/requests/${moverRef}/approve`, undefined, owner.token), 404, "request_not_found");
  });

  it("answers in_crew when the sender joined another crew in the meantime", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const other = await makeCrew();
    const me = await user();
    await ask(me, crew.id);
    const ref = (await ownerView(owner)).requests[0].ref;
    // A request left behind by a race (the join raced the request): the approve finds them in a crew.
    await rows("INSERT INTO crew_members (code, crew, ref, joined_at) VALUES (?, ?, 'ZZZZZZZZZZ', 0)", me.code, other.crew.id);
    expectError(await call("POST", `/v1/crews/mine/requests/${ref}/approve`, undefined, owner.token), 409, "in_crew");
    expect((await ownerView(owner)).requests).toEqual([]);
  });

  it(`holds at most ${MAX_CREW_JOIN_REQUESTS} requests per crew and ${JOIN_REQUESTS_PER_DAY} new requests per user a day`, async () => {
    fresh();
    const { crew } = await makeCrew();
    const at = Math.floor(Date.now() / 1000);
    for (let i = 0; i < MAX_CREW_JOIN_REQUESTS; i++) {
      await rows("INSERT INTO crew_join_requests (code, crew, ref, created_at) VALUES (?, ?, ?, ?)",
        `Q${String(i).padStart(7, "0")}`, crew.id, `R${String(i).padStart(9, "0")}`, at);
    }
    expectError(await call("POST", "/v1/crews/join", { crew: crew.id }, (await user()).token), 409, "requests_full");

    const busy = await user();
    const crews = [];
    for (let i = 0; i <= JOIN_REQUESTS_PER_DAY; i++) crews.push((await makeCrew()).crew.id);
    for (let i = 0; i < JOIN_REQUESTS_PER_DAY; i++) {
      if (i % 9 === 8) advance(60); // stay under the per-minute crews limit
      await ask(busy, crews[i]);
    }
    advance(60);
    expectError(await call("POST", "/v1/crews/join", { crew: crews[JOIN_REQUESTS_PER_DAY] }, busy.token), 429, "request_limit");
  });
});

describe("join requests and moderation", () => {
  it("keeps removed members from asking, and banned users from asking or staying asked", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const removed = await user();
    const joined = await joinByCode(removed, crew.inviteCode);
    const ref = joined.members.find((m: { me: boolean }) => m.me).ref;
    await call("POST", `/v1/crews/mine/members/${ref}/remove`, undefined, owner.token);
    expectError(await call("POST", "/v1/crews/join", { crew: crew.id }, removed.token), 403, "removed_from_crew");

    const banned = await user();
    await ask(banned, crew.id);
    await admin("POST", `/users/${banned.code}/ban`);
    expect((await ownerView(owner)).requests).toEqual([]);
    expect(await rows("SELECT * FROM crew_join_requests WHERE code = ?", banned.code)).toEqual([]);
    expectError(await call("POST", "/v1/crews/join", { crew: crew.id }, banned.token), 403, "banned");
  });

  it("drops a request when the owner blocks the requester by its ref, or either blocks the other", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const a = await user("Ada");
    const b = await user("Bea");
    await ask(a, crew.id);
    const ref = (await ownerView(owner)).requests[0].ref;
    expect((await call("POST", "/v1/crews/block", { crew: crew.id, member: ref }, owner.token)).body.blocked).toBe(true);
    expect(await rows("SELECT * FROM crew_join_requests WHERE code = ?", a.code)).toEqual([]);
    expectError(await call("POST", "/v1/crews/join", { crew: crew.id }, a.token), 404, "crew_not_found");

    await ask(b, crew.id);
    await call("POST", "/v1/blocks", { code: owner.code }, b.token);
    expect(await rows("SELECT * FROM crew_join_requests WHERE code = ?", b.code)).toEqual([]);
  });

  it("drops a crew's requests when it is hidden or deleted, and a user's when they delete their account", async () => {
    fresh();
    const hidden = await makeCrew();
    const deleted = await makeCrew();
    const a = await user();
    const b = await user();
    const gone = await user();
    await ask(a, hidden.crew.id);
    await ask(b, deleted.crew.id);
    await ask(gone, hidden.crew.id);
    await call("DELETE", "/v1/me", undefined, gone.token);
    expect(await rows("SELECT * FROM crew_join_requests WHERE code = ?", gone.code)).toEqual([]);
    await admin("POST", `/crews/${hidden.crew.id}/hide`);
    await admin("DELETE", `/crews/${deleted.crew.id}`);
    expect(await rows("SELECT * FROM crew_join_requests WHERE crew IN (?, ?)", hidden.crew.id, deleted.crew.id)).toEqual([]);
    expect((await call("GET", "/v1/crews/mine", undefined, a.token)).body.request).toBeNull();
  });
});

describe("the heartbeat's crews field", () => {
  it("counts the requests waiting for the crew I own, and names my crew", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const member = await user();
    await joinByCode(member, crew.inviteCode);
    await ask(await user(), crew.id);
    await ask(await user(), crew.id);
    const beat = await call("POST", "/v1/presence", { status: "studying" }, owner.token);
    expect(check("heartbeatReply", beat.body)).toEqual([]);
    expect(beat.body.crews).toEqual({ requests: 2, crew: crew.id });
    expect((await call("POST", "/v1/presence", { status: "idle" }, member.token)).body.crews).toEqual({ requests: 0, crew: crew.id });
    const loner = await user();
    expect((await call("POST", "/v1/presence", { status: "idle" }, loner.token)).body.crews).toEqual({ requests: 0, crew: null });
  });

  it("leaves protocol 1 and 2 apps' heartbeats, friends and parties as they were", async () => {
    fresh();
    const v1 = await register({ name: "Olive" }, true) as User;
    const { owner, crew } = await makeCrew();
    await ask(v1, crew.id);
    const beat = await oldCall("POST", "/v1/presence", { status: "studying", todayMinutes: 5 }, v1.token);
    expect(beat.status).toBe(200);
    expect(beat.body).toMatchObject({ ok: true, presence: { status: "studying", todayMinutes: 5 }, heartbeatSeconds: 120 });
    expect(check("heartbeatReply", beat.body)).toEqual([]);
    expect((await oldCall("POST", "/v1/friends", { code: owner.code }, v1.token)).status).toBe(200);
    const party = (await call("POST", "/v1/party", undefined, owner.token)).body.party;
    expect((await oldCall("POST", "/v1/party/join", { code: party.code }, v1.token)).status).toBe(200);
  });
});
