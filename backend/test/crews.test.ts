import { afterEach, describe, expect, it, vi } from "vitest";
import crewsCatalog from "../shared/crews.json";
import { admin, call, expectError, oldCall, register } from "./helpers";
import { COLOR, EMBLEM, FRAME, User, advance, atWeek, callWithHeader, crewBody, joinByCode, makeCrew, report, rows, session, uniqueName } from "./crewHelpers";
import { checkCrews } from "./schema";

const MAX = crewsCatalog.limits.maxMembers;
/** Ten weeks apart, like crews-credit.test.ts, so one test's rollover never freezes another's week. */
let slot = 0;
const fresh = () => atWeek((slot += 10));

afterEach(() => {
  vi.useRealTimers();
});

const user = async (name = "Sam") => await register({ name, petName: "Mochi" }) as User;

describe("creating and editing a crew", () => {
  it("creates a crew with me as its owner and only member", async () => {
    fresh();
    const { owner, crew } = await makeCrew({ name: "Night Owls", visibility: "private" });
    expect(crew).toMatchObject({
      name: "Night Owls", frame: FRAME, emblem: EMBLEM, color: COLOR, visibility: "private", laurel: null, trophies: 0,
      memberCount: 1, maxMembers: MAX, weekMinutes: 0, rank: null, mine: true, owner: true, hidden: false,
      medals: { gold: 0, silver: 0, bronze: 0 },
    });
    expect(crew.id).toMatch(/^[A-HJ-NP-Z2-9]{10}$/);
    expect(crew.inviteCode).toMatch(/^[A-HJ-NP-Z2-9]{7}$/);
    expect(crew.members).toEqual([{
      ref: crew.members[0].ref, name: "Owner", pet: expect.objectContaining({ species: "cat" }), badges: [],
      weekMinutes: 0, owner: true, me: true,
    }]);
    expect(crew.members[0].ref).toMatch(/^[A-HJ-NP-Z2-9]{10}$/);
    expect(crew.members[0]).not.toHaveProperty("code");
    const mine = await call("GET", "/v1/crews/mine", undefined, owner.token);
    expect(checkCrews("mineReply", mine.body)).toEqual([]);
    expect(mine.body.crew.id).toBe(crew.id);
    expect(mine.body.week.endsAt - mine.body.week.startsAt).toBe(7 * 86_400);
  });

  it("answers null and the week when I have no crew", async () => {
    const monday = fresh();
    const me = await user();
    const r = await call("GET", "/v1/crews/mine", undefined, me.token);
    expect(r.body).toMatchObject({ ok: true, crew: null, week: { startsAt: monday, endsAt: monday + 7 * 86_400 } });
    expect(r.body.week.id).toMatch(/^\d{4}-W\d{2}$/);
    expect(checkCrews("mineReply", r.body)).toEqual([]);
  });

  it("filters names and descriptions, and keeps names unique ignoring case", async () => {
    fresh();
    const me = await user();
    expectError(await call("POST", "/v1/crews", crewBody({ name: "f u c k" }), me.token), 400, "crew_name_not_allowed");
    expectError(await call("POST", "/v1/crews", crewBody({ description: "sh1t heads" }), me.token), 400, "description_not_allowed");
    expectError(await call("POST", "/v1/crews", crewBody({ frame: "not-a-frame" }), me.token), 400, "invalid_field");
    expectError(await call("POST", "/v1/crews", crewBody({ emblem: "not-an-emblem" }), me.token), 400, "invalid_field");
    expectError(await call("POST", "/v1/crews", { ...crewBody(), icon: "owl" }, me.token), 400, "unknown_field");
    expectError(await call("POST", "/v1/crews", crewBody({ color: "#FF0000" }), me.token), 400, "invalid_field");
    expectError(await call("POST", "/v1/crews", crewBody({ visibility: "secret" }), me.token), 400, "invalid_field");
    expectError(await call("POST", "/v1/crews", crewBody({ name: "x".repeat(25) }), me.token), 400, "invalid_field");
    expectError(await call("POST", "/v1/crews", crewBody({ name: "  " }), me.token), 400, "invalid_field");
    expectError(await call("POST", "/v1/crews", { ...crewBody(), deck: "x" }, me.token), 400, "unknown_field");
    const name = uniqueName("Taken");
    await makeCrew({ name });
    expectError(await call("POST", "/v1/crews", crewBody({ name: name.toUpperCase() }), me.token), 409, "name_taken");
  });

  it("refuses a second crew while I am in one, and more than three new crews a day", async () => {
    fresh();
    const { owner } = await makeCrew();
    expectError(await call("POST", "/v1/crews", crewBody(), owner.token), 409, "in_crew");
    for (let i = 0; i < 2; i++) {
      await call("POST", "/v1/crews/leave", {}, owner.token);
      expect((await call("POST", "/v1/crews", crewBody(), owner.token)).status).toBe(201);
    }
    await call("POST", "/v1/crews/leave", {}, owner.token);
    expectError(await call("POST", "/v1/crews", crewBody(), owner.token), 429, "crew_limit");
  });

  it("lets only the owner edit, and an empty description clears it", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const member = await user();
    await joinByCode(member, crew.inviteCode);
    expectError(await call("PATCH", "/v1/crews/mine", { name: uniqueName() }, member.token), 403, "not_owner");
    const name = uniqueName("Renamed");
    const frame = crewsCatalog.frames.at(-1)!;
    const emblem = crewsCatalog.emblems.at(-1)!;
    const r = await call("PATCH", "/v1/crews/mine", { name, description: "", visibility: "private", color: "sky", frame, emblem }, owner.token);
    expect(r.status).toBe(200);
    expect(checkCrews("crewReply", r.body)).toEqual([]);
    expect(r.body.crew).toMatchObject({ name, description: "", visibility: "private", color: "sky", frame, emblem });
    expectError(await call("PATCH", "/v1/crews/mine", { emblem: "dragon" }, owner.token), 400, "invalid_field");
    // Keeping its own name in another case is fine; another crew's name is not.
    expect((await call("PATCH", "/v1/crews/mine", { name: name.toLowerCase() }, owner.token)).status).toBe(200);
    const other = await makeCrew();
    expectError(await call("PATCH", "/v1/crews/mine", { name: other.crew.name }, owner.token), 409, "name_taken");
    expectError(await call("PATCH", "/v1/crews/mine", { name: "x" }, (await user()).token), 404, "not_in_crew");
  });
});

describe("joining, leaving and removing", () => {
  it("joins a private crew by invite code and a public one by id, but never a private one by id", async () => {
    fresh();
    const priv = await makeCrew({ visibility: "private" });
    const pub = await makeCrew({ visibility: "public" });
    const me = await user();
    expectError(await call("POST", "/v1/crews/join", { crew: priv.crew.id }, me.token), 404, "crew_not_found");
    const joined = await call("POST", "/v1/crews/join", { code: priv.crew.inviteCode.toLowerCase() }, me.token);
    expect(checkCrews("joinReply", joined.body)).toEqual([]);
    expect(joined.body).toMatchObject({ joined: true, crew: { id: priv.crew.id, memberCount: 2, mine: true, owner: false } });
    expect((await call("POST", "/v1/crews/join", { code: priv.crew.inviteCode }, me.token)).body.joined).toBe(false);
    expectError(await call("POST", "/v1/crews/join", { crew: pub.crew.id }, me.token), 409, "in_crew");
    await call("POST", "/v1/crews/leave", {}, me.token);
    // A public crew by id asks its owner (crews-requests.test.ts); by invite it joins at once.
    expect((await call("POST", "/v1/crews/join", { crew: pub.crew.id }, me.token)).body).toMatchObject({ joined: false, requested: true });
    expect((await call("POST", "/v1/crews/join", { code: pub.crew.inviteCode }, me.token)).body.joined).toBe(true);
    expectError(await call("POST", "/v1/crews/join", { code: "AAAAAAA" }, me.token), 404, "crew_not_found");
    expectError(await call("POST", "/v1/crews/join", { code: "AAAAAAA", crew: pub.crew.id }, me.token), 400, "invalid_field");
    expectError(await call("POST", "/v1/crews/join", { code: "OOOOOOO" }, me.token), 400, "invalid_field");
  });

  it(`holds at most ${MAX} members`, async () => {
    fresh();
    const { crew } = await makeCrew();
    for (let i = 1; i < MAX; i++) await joinByCode(await user(), crew.inviteCode);
    expectError(await call("POST", "/v1/crews/join", { code: crew.inviteCode }, (await user()).token), 409, "crew_full");
  });

  it("hands the crew to the longest-standing member when the owner leaves, and deletes it with the last one", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const first = await user("First");
    const second = await user("Second");
    await joinByCode(first, crew.inviteCode);
    await joinByCode(second, crew.inviteCode);
    const left = await call("POST", "/v1/crews/leave", {}, owner.token);
    expect(checkCrews("leaveReply", left.body)).toEqual([]);
    expect(left.body.left).toBe(true);
    expect((await call("POST", "/v1/crews/leave", {}, owner.token)).body.left).toBe(false);
    const seen = (await call("GET", "/v1/crews/mine", undefined, first.token)).body.crew;
    expect(seen.owner).toBe(true);
    expect(seen.members.map((m: { name: string }) => m.name)).toEqual(["First", "Second"]);
    await call("POST", "/v1/crews/leave", {}, first.token);
    await call("POST", "/v1/crews/leave", {}, second.token);
    expectError(await call("GET", `/v1/crews/${crew.id}`, undefined, first.token), 404, "crew_not_found");
    // The name is free again.
    expect((await call("POST", "/v1/crews", crewBody({ name: crew.name }), first.token)).status).toBe(201);
  });

  it("lets the owner remove a member for good", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const member = await user();
    const joined = await joinByCode(member, crew.inviteCode);
    const ref = joined.members.find((m: { me: boolean }) => m.me).ref;
    expectError(await call("POST", `/v1/crews/mine/members/${ref}/remove`, undefined, member.token), 403, "not_owner");
    expectError(await call("POST", "/v1/crews/mine/members/AAAAAAAAAA/remove", undefined, owner.token), 404, "member_not_found");
    const removed = await call("POST", `/v1/crews/mine/members/${ref}/remove`, undefined, owner.token);
    expect(checkCrews("removeReply", removed.body)).toEqual([]);
    expect(removed.body).toMatchObject({ removed: true, crew: { memberCount: 1 } });
    expect((await call("GET", "/v1/crews/mine", undefined, member.token)).body.crew).toBeNull();
    expectError(await call("POST", "/v1/crews/join", { code: crew.inviteCode }, member.token), 403, "removed_from_crew");
  });

  it("lets a member hide their pet from every crew page", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const member = await user("Hidden");
    await joinByCode(member, crew.inviteCode);
    const r = await call("PATCH", "/v1/crews/mine/me", { showPet: false }, member.token);
    expect(checkCrews("crewReply", r.body)).toEqual([]);
    const byOwner = (await call("GET", "/v1/crews/mine", undefined, owner.token)).body.crew;
    const hidden = byOwner.members.find((m: { name: string }) => m.name === "Hidden");
    expect(hidden.pet).toBeNull();
    expect(hidden.name).toBe("Hidden");
    expectError(await call("PATCH", "/v1/crews/mine/me", { showPet: "no" }, member.token), 400, "invalid_field");
    await call("PATCH", "/v1/crews/mine/me", { showPet: true }, member.token);
    const again = (await call("GET", `/v1/crews/${crew.id}`, undefined, (await user()).token)).body.crew;
    expect(again.members.find((m: { name: string }) => m.name === "Hidden").pet).toMatchObject({ petName: "Mochi" });
    expect(again).toMatchObject({ mine: false, owner: false, inviteCode: null, hidden: false });
  });
});

describe("finding and viewing crews", () => {
  it("finds public crews by name, most minutes first, never private ones", async () => {
    fresh();
    const tag = `Zq${Date.now() % 100000}`;
    const quiet = await makeCrew({ name: `${tag} Quiet` });
    const busy = await makeCrew({ name: `${tag} Busy` });
    await makeCrew({ name: `${tag} Secret`, visibility: "private" });
    advance(3600);
    await report(busy.owner, [session(50)]);
    const me = await user();
    const r = await call("GET", `/v1/crews?q=${encodeURIComponent(tag.toUpperCase())}`, undefined, me.token);
    expect(checkCrews("searchReply", r.body)).toEqual([]);
    expect(r.body.crews.map((c: { id: string }) => c.id)).toEqual([busy.crew.id, quiet.crew.id]);
    expect(r.body.crews[0].weekMinutes).toBe(50);
    // LIKE wildcards in the query are literal.
    expect((await call("GET", "/v1/crews?q=%25", undefined, me.token)).body.crews).toEqual([]);
    expect((await call("GET", "/v1/crews", undefined, me.token)).body.crews.length).toBeGreaterThan(0);
  });

  it("opens public crews and my own, but a private crew only from the board", async () => {
    fresh();
    const pub = await makeCrew();
    const priv = await makeCrew({ visibility: "private" });
    const me = await user();
    expect((await call("GET", `/v1/crews/${pub.crew.id}`, undefined, me.token)).status).toBe(200);
    expectError(await call("GET", `/v1/crews/${priv.crew.id}`, undefined, me.token), 404, "crew_not_found");
    expect((await call("GET", `/v1/crews/${priv.crew.id}`, undefined, priv.owner.token)).status).toBe(200);
    advance(3600);
    await report(priv.owner, [session(30)]);
    const board = await call("GET", "/v1/crews/board", undefined, me.token);
    expect(checkCrews("boardReply", board.body)).toEqual([]);
    expect(board.body.top.map((e: { crew: { id: string } }) => e.crew.id)).toContain(priv.crew.id);
    const opened = await call("GET", `/v1/crews/${priv.crew.id}`, undefined, me.token);
    expect(opened.status).toBe(200);
    expect(opened.body.crew).toMatchObject({ visibility: "private", inviteCode: null, rank: 1 });
    expectError(await call("GET", "/v1/crews/not-an-id", undefined, me.token), 400, "invalid_field");
  });
});

describe("moderation", () => {
  it("removes a member the owner blocks, takes out a member who blocks the owner, and hides other blocks", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const a = await user("Ada");
    const b = await user("Bea");
    const c = await user("Cy");
    for (const u of [a, b, c]) await joinByCode(u, crew.inviteCode);
    const detail = (await call("GET", "/v1/crews/mine", undefined, owner.token)).body.crew;
    const refOf = (name: string) => detail.members.find((m: { name: string }) => m.name === name).ref;

    const blocked = await call("POST", "/v1/crews/block", { crew: crew.id, member: refOf("Ada") }, owner.token);
    expect(checkCrews("blockReply", blocked.body)).toEqual([]);
    expect(blocked.body.blocked).toBe(true);
    expect((await call("GET", "/v1/crews/mine", undefined, a.token)).body.crew).toBeNull();
    expectError(await call("POST", "/v1/crews/join", { code: crew.inviteCode }, a.token), 404, "crew_not_found");

    // Bea blocks the owner through the usual route: she leaves.
    await call("POST", "/v1/blocks", { code: owner.code }, b.token);
    expect((await call("GET", "/v1/crews/mine", undefined, b.token)).body.crew).toBeNull();

    // A block between two members only hides them from each other.
    const d = await user("Dee");
    await joinByCode(d, crew.inviteCode);
    const byCy = (await call("GET", "/v1/crews/mine", undefined, c.token)).body.crew;
    const dee = byCy.members.find((m: { name: string }) => m.name === "Dee").ref;
    await call("POST", "/v1/crews/block", { crew: crew.id, member: dee }, c.token);
    const names = (await call("GET", "/v1/crews/mine", undefined, c.token)).body.crew.members.map((m: { name: string }) => m.name);
    // No one has minutes, so members are in name order.
    expect(names).toEqual(["Cy", "Owner"]);
    expect((await call("GET", "/v1/crews/mine", undefined, d.token)).body.crew.members.map((m: { name: string }) => m.name))
      .toEqual(["Dee", "Owner"]);
    expect((await call("POST", "/v1/crews/block", { crew: crew.id, member: dee }, c.token)).body.blocked).toBe(false);
    const self = byCy.members.find((m: { me: boolean }) => m.me).ref;
    expectError(await call("POST", "/v1/crews/block", { crew: crew.id, member: self }, c.token), 400, "self_block");
  });

  it("files a report about a crew or a member once, then updates it", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const me = await user();
    const first = await call("POST", "/v1/crews/reports", { crew: crew.id, reason: "inappropriate_name", note: "rude" }, me.token);
    expect(first.status).toBe(201);
    expect(checkCrews("reportReply", first.body)).toEqual([]);
    const again = await call("POST", "/v1/crews/reports", { crew: crew.id, reason: "spam" }, me.token);
    expect(again.body).toEqual({ ok: true, created: false });
    const ref = crew.members[0].ref;
    expect((await call("POST", "/v1/crews/reports", { crew: crew.id, member: ref, reason: "cheating" }, me.token)).status).toBe(201);
    expectError(await call("POST", "/v1/crews/reports", { crew: crew.id, member: ref, reason: "cheating" }, owner.token), 400, "self_report");
    expectError(await call("POST", "/v1/crews/reports", { crew: crew.id, member: "AAAAAAAAAA", reason: "spam" }, me.token), 404, "member_not_found");
    expectError(await call("POST", "/v1/crews/reports", { crew: crew.id, reason: "boring" }, me.token), 400, "invalid_field");

    const list = await admin("GET", "/crews/reports");
    const mine = list.body.reports.filter((r: { crew: { id: string } }) => r.crew.id === crew.id);
    expect(mine).toHaveLength(2);
    expect(mine.find((r: { member: unknown }) => r.member !== null)).toMatchObject({ reason: "cheating", member: { code: owner.code, name: "Owner" } });
    const id = mine[0].id;
    expect((await admin("POST", `/crews/reports/${id}/dismiss`)).body).toEqual({ ok: true, dismissed: true });
    expect((await admin("POST", `/crews/reports/${id}/dismiss`)).body).toEqual({ ok: true, dismissed: false });
    expect((await admin("GET", "/crews/reports")).body.reports.some((r: { id: number }) => r.id === id)).toBe(false);
    expect((await admin("GET", "/crews/reports?status=all")).body.reports.some((r: { id: number }) => r.id === id)).toBe(true);
    expectError(await admin("POST", "/crews/reports/999999/dismiss"), 404, "report_not_found");
  });

  it("keeps banned users out of crews and off other people's crew pages", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const cheat = await user("Cheat");
    await joinByCode(cheat, crew.inviteCode);
    advance(3600);
    await report(cheat, [session(60)]);
    expect((await call("GET", "/v1/crews/mine", undefined, owner.token)).body.crew.weekMinutes).toBe(60);
    await admin("POST", `/users/${cheat.code}/ban`);
    const seen = (await call("GET", "/v1/crews/mine", undefined, owner.token)).body.crew;
    expect(seen.memberCount).toBe(1);
    expect(seen.weekMinutes).toBe(0);
    expectError(await call("POST", "/v1/crews/join", { code: crew.inviteCode }, cheat.token), 403, "banned");
    expectError(await call("POST", "/v1/crews", crewBody(), cheat.token), 403, "banned");
  });

  it("lets the maintainer view, rename, hide and delete a crew", async () => {
    fresh();
    const { owner, crew } = await makeCrew({ name: uniqueName("Bad") });
    const me = await user();
    const viewed = await admin("GET", `/crews/${crew.id}`);
    expect(viewed.body.crew).toMatchObject({ id: crew.id, owner: owner.code, inviteCode: crew.inviteCode });
    expect(viewed.body.crew.members[0]).toMatchObject({ code: owner.code, name: "Owner", showPet: true });

    const renamed = await admin("POST", `/crews/${crew.id}/rename`);
    expect(renamed.body.crew).toMatchObject({ name: `Crew ${crew.id.slice(0, 4)}`, description: "" });
    expectError(await call("POST", "/v1/crews", crewBody({ name: crew.name }), me.token), 400, "crew_name_not_allowed");
    expectError(await call("PATCH", "/v1/crews/mine", { name: crew.name }, owner.token), 400, "crew_name_not_allowed");

    expect((await admin("POST", `/crews/${crew.id}/hide`)).body).toMatchObject({ hidden: true, changed: true });
    expectError(await call("GET", `/v1/crews/${crew.id}`, undefined, me.token), 404, "crew_not_found");
    expect((await call("GET", "/v1/crews/mine", undefined, owner.token)).body.crew.hidden).toBe(true);
    expect((await call("GET", `/v1/crews?q=${encodeURIComponent(renamed.body.crew.name)}`, undefined, me.token)).body.crews).toEqual([]);
    expect((await admin("DELETE", `/crews/${crew.id}/hide`)).body).toMatchObject({ hidden: false, changed: true });
    expect((await call("GET", `/v1/crews/${crew.id}`, undefined, me.token)).status).toBe(200);

    expect((await admin("DELETE", `/crews/${crew.id}`)).body).toEqual({ ok: true, deleted: true });
    expect((await call("GET", "/v1/crews/mine", undefined, owner.token)).body.crew).toBeNull();
    expectError(await admin("GET", `/crews/${crew.id}`), 404, "crew_not_found");
    expect((await admin("GET", "/crews/AAAAAAAAAA", "wrong-token")).status).toBe(404);
  });

  it("counts crews in the maintainer's stats", async () => {
    fresh();
    await makeCrew();
    const stats = (await admin("GET", "/stats")).body.crews;
    expect(stats.total).toBeGreaterThan(0);
    expect(Object.keys(stats).sort()).toEqual(["activeThisWeek", "hidden", "members", "openFlags", "openReports", "public", "total"]);
  });

  it("deletes a user's crews data with the account, and the crew keeps the week's minutes", async () => {
    fresh();
    const { owner, crew } = await makeCrew();
    const gone = await user("Gone");
    await joinByCode(gone, crew.inviteCode);
    advance(3600);
    await report(gone, [session(40)]);
    expect((await call("DELETE", "/v1/me", undefined, gone.token)).status).toBe(200);
    const seen = (await call("GET", "/v1/crews/mine", undefined, owner.token)).body.crew;
    expect(seen).toMatchObject({ memberCount: 1, weekMinutes: 40 });
    for (const table of ["crew_members", "crew_stints", "crew_sessions", "crew_day_credits", "crew_flags", "crew_removals"]) {
      expect(await rows(`SELECT * FROM ${table} WHERE code = ?`, gone.code), table).toEqual([]);
    }
  });
});

describe("Crews beside older apps", () => {
  it("leaves friends, parties and the leaderboard of protocol 1 and 2 apps unchanged for crew members", async () => {
    fresh();
    const crewMember = await register({ name: "Cleo" }) as User;
    const v1 = await register({ name: "Olive" }, true) as User;
    const v2 = await register({ name: "Ben" }) as User;
    await makeCrew({}, crewMember);
    advance(3600);
    await report(crewMember, [session(25)]);
    // Friends: a protocol 1 add is instant with crew members too; protocol 2 still asks.
    expect((await oldCall("POST", "/v1/friends", { code: crewMember.code }, v1.token)).body).toMatchObject({ ok: true });
    const asked = await callWithHeader("2", "POST", "/v1/friends", { code: crewMember.code }, v2.token);
    expect(asked.body.status).toBe("requested");
    await call("POST", `/v1/friends/${v2.code}/accept`, undefined, crewMember.token);
    await call("POST", `/v1/friends/${v1.code}/accept`, undefined, crewMember.token);
    // Party: all three sit together.
    const party = (await call("POST", "/v1/party", undefined, crewMember.token)).body.party;
    expect((await oldCall("POST", "/v1/party/join", { code: party.code }, v1.token)).status).toBe(200);
    expect((await callWithHeader("2", "POST", "/v1/party/join", { code: party.code }, v2.token)).status).toBe(200);
    const seen = (await oldCall("GET", "/v1/party", undefined, v1.token)).body.party;
    expect(seen.members).toHaveLength(3);
    for (const m of seen.members) expect(Object.keys(m.profile)).not.toContain("crew");
    // The leaderboard still sums heartbeats, never crew sessions.
    await oldCall("POST", "/v1/presence", { status: "studying", todayMinutes: 7 }, v1.token);
    const board = (await oldCall("GET", "/v1/leaderboard", undefined, v1.token)).body.entries;
    const cleo = board.find((e: { profile: { code: string } }) => e.profile.code === crewMember.code);
    expect(cleo.minutes).toBe(0);
    // Crews routes need no protocol header, so nothing breaks if an older app ever reaches one.
    expect((await oldCall("GET", "/v1/crews/board", undefined, v1.token)).status).toBe(200);
    expect((await call("GET", "/")).body).toMatchObject({ protocol: 3, minProtocol: 1 });
  });
});
