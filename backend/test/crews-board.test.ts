import { afterEach, describe, expect, it, vi } from "vitest";
import crewsCatalog from "../shared/crews.json";
import { BOARD_PAGE, decodeBoardCursor, weekOf } from "../src/crews";
import { admin, call, expectError, register } from "./helpers";
import { User, advance, atWeek, crewBody, joinByCode, makeCrew, report, session } from "./crewHelpers";
import { checkCrews } from "./schema";

/** Weeks of their own, far from the other crews test files. */
let slot = 3000;
const fresh = (offsetS?: number) => atWeek((slot += 10), offsetS);

afterEach(() => {
  vi.useRealTimers();
});

const user = async (name: string, petName = "Mochi") => await register({ name, petName }) as User;

async function board(token: string, cursor?: string) {
  const r = await call("GET", `/v1/crews/board${cursor ? `?cursor=${cursor}` : ""}`, undefined, token);
  expect(r.status, JSON.stringify(r.body)).toBe(200);
  expect(checkCrews("boardReply", r.body)).toEqual([]);
  return r.body;
}

describe("crew names", () => {
  it(`are at most ${crewsCatalog.limits.nameMaxLength} characters`, async () => {
    fresh();
    expect(crewsCatalog.limits.nameMaxLength).toBe(20);
    const me = await user("Sam");
    expectError(await call("POST", "/v1/crews", crewBody({ name: `N${Date.now() % 1000}`.padEnd(21, "x") }), me.token), 400, "invalid_field");
    const name = `M${Date.now() % 1000}`.padEnd(20, "y");
    const made = await call("POST", "/v1/crews", crewBody({ name }), me.token);
    expect(made.status).toBe(201);
    expectError(await call("PATCH", "/v1/crews/mine", { name: name + "z" }, me.token), 400, "invalid_field");
    // The maintainer's placeholder fits too.
    const renamed = await admin("POST", `/crews/${made.body.crew.id}/rename`);
    expect([...renamed.body.crew.name].length).toBeLessThanOrEqual(20);
  });
});

describe("the weekly board", () => {
  it("ranks the rest below the top 3 in pages with a stable cursor, and counts the crews", async () => {
    fresh();
    const crews: Awaited<ReturnType<typeof makeCrew>>[] = [];
    for (let i = 0; i < 3 + BOARD_PAGE + 4; i++) crews.push(await makeCrew());
    advance(3 * 3600);
    // Minutes 100, 99, 98, ... except two pairs that tie, to cross the page edge with ties.
    const minutes = crews.map((_, i) => 100 - i);
    minutes[10] = minutes[9];
    minutes[BOARD_PAGE + 2] = minutes[BOARD_PAGE + 1];
    for (const [i, made] of crews.entries()) {
      await report(made.owner, [session(minutes[i])]);
    }
    const me = crews[5].owner;
    const first = await board(me.token);
    expect(first.top.map((e: { rank: number }) => e.rank)).toEqual([1, 2, 3]);
    expect(first.rows).toHaveLength(BOARD_PAGE);
    expect(first.rows[0].rank).toBe(4);
    expect(first.crewCount).toBeGreaterThanOrEqual(crews.length);
    expect(first.mine).toEqual({ rank: 6, minutes: 95 });
    expect(first.next).not.toBeNull();
    expect(decodeBoardCursor(first.next).id).toBe(first.rows.at(-1).crew.id);

    const second = await board(me.token, first.next);
    expect(second).not.toHaveProperty("top");
    expect(second).not.toHaveProperty("mine");
    expect(second.next).toBeNull();
    const all = [...first.rows, ...second.rows];
    const mineIds = crews.map((c) => c.crew.id);
    const ours = all.filter((e: { crew: { id: string } }) => mineIds.includes(e.crew.id));
    const expected = mineIds.map((id, i) => ({ id, m: minutes[i] })).slice(3)
      .sort((x, y) => y.m - x.m || (x.id < y.id ? -1 : 1)).map((x) => x.id);
    expect(ours.map((e: { crew: { id: string } }) => e.crew.id)).toEqual(expected);
    // Ties share a place, the next is skipped, and each names the other.
    const at = (i: number) => ours.find((e: { crew: { id: string } }) => e.crew.id === crews[i].crew.id);
    expect([at(9).rank, at(10).rank, at(11).rank]).toEqual([10, 10, 12]);
    expect(at(9).tiedWith).toEqual([crews[10].crew.name]);
    expect(at(10).tiedWith).toEqual([crews[9].crew.name]);
    expect(at(11).tiedWith).toEqual([]);
    // The same walk again gives the same pages.
    const again = await board(me.token);
    expect(again.rows.map((e: { crew: { id: string } }) => e.crew.id)).toEqual(first.rows.map((e: { crew: { id: string } }) => e.crew.id));
    expect((await board(me.token, again.next)).rows.map((e: { crew: { id: string } }) => e.crew.id))
      .toEqual(second.rows.map((e: { crew: { id: string } }) => e.crew.id));
    expectError(await call("GET", "/v1/crews/board?cursor=bad*", undefined, me.token), 400, "invalid_field");
  });

  it("says where my crew stands, with no rank before its first minute", async () => {
    fresh();
    const { owner } = await makeCrew();
    expect((await board(owner.token)).mine).toEqual({ rank: null, minutes: 0 });
    expect((await board((await user("Loner")).token)).mine).toBeNull();
  });

  it("names the crews a top place is shared with, and shows the most active members' pets", async () => {
    const monday = fresh();
    const a = await makeCrew({}, await user("Ann", "Biscuit"));
    const b = await makeCrew({}, await user("Bo", "Pepper"));
    const quiet = await user("Quiet", "Tofu");
    const busy = await user("Busy", "Waffles");
    const hidden = await user("Hidden", "Secret");
    for (const u of [quiet, busy, hidden]) await joinByCode(u, a.crew.inviteCode);
    await call("PATCH", "/v1/crews/mine/me", { showPet: false }, hidden.token);
    advance(3 * 3600);
    await report(busy, [session(40)]);
    await report(hidden, [session(30)]);
    await report(a.owner, [session(20)]);
    await report(quiet, [session(5)]);
    await report(b.owner, [session(95)]);
    type Entry = { rank: number; crew: { id: string; laurel: string }; tiedWith: string[]; pets: { petName: string }[] };
    const byId = (list: Entry[], id: string) => list.find((e) => e.crew.id === id)!;
    const top = (await board(a.owner.token)).top as Entry[];
    expect(top.map((e) => e.rank)).toEqual([1, 1]);
    expect(byId(top, a.crew.id).tiedWith).toEqual([b.crew.name]);
    expect(byId(top, b.crew.id).tiedWith).toEqual([a.crew.name]);
    expect(byId(top, a.crew.id).pets.map((p) => p.petName)).toEqual(["Waffles", "Biscuit", "Tofu"]);
    expect(byId(top, b.crew.id).pets.map((p) => p.petName)).toEqual(["Pepper"]);

    vi.setSystemTime((monday + 7 * 86_400 + 60) * 1000);
    const featured = (await board(a.owner.token)).featured.entries as Entry[];
    expect(featured.map((e) => [e.rank, e.crew.laurel])).toEqual([[1, "gold"], [1, "gold"]]);
    expect(byId(featured, a.crew.id).tiedWith).toEqual([b.crew.name]);
    expect(byId(featured, a.crew.id).pets.map((p) => p.petName)).toEqual(["Waffles", "Biscuit", "Tofu"]);
    const summary = (await call("GET", `/v1/crews/${a.crew.id}`, undefined, a.owner.token)).body.crew;
    expect(summary).toMatchObject({ golds: 1, trophies: 1 });

    const hall = (await call("GET", "/v1/crews/hall", undefined, a.owner.token)).body;
    expect(checkCrews("hallReply", hall)).toEqual([]);
    expect(hall.entries.slice(0, 3).every((e: { pets?: unknown[] }) => Array.isArray(e.pets))).toBe(true);
    expect(hall.entries.slice(3).some((e: { pets?: unknown[] }) => e.pets !== undefined)).toBe(false);
    expect(hall.mine).toMatchObject({ medals: { gold: 1, silver: 0, bronze: 0 } });
    expect(hall.mine.rank).toBeGreaterThanOrEqual(1);
    const fresher = await makeCrew();
    expect((await call("GET", "/v1/crews/hall", undefined, fresher.owner.token)).body.mine)
      .toEqual({ rank: null, medals: { gold: 0, silver: 0, bronze: 0 }, reachedAt: null });
  });
});

describe("a crew page", () => {
  it("lists members by minutes this week, then by name, and counts the board's crews", async () => {
    fresh();
    const { owner, crew } = await makeCrew({}, await user("Zed"));
    const amy = await user("Amy");
    const bea = await user("Bea");
    await joinByCode(amy, crew.inviteCode);
    await joinByCode(bea, crew.inviteCode);
    advance(3 * 3600);
    await report(bea, [session(30)]);
    const page = (await call("GET", "/v1/crews/mine", undefined, owner.token)).body.crew;
    expect(page.members.map((m: { name: string }) => m.name)).toEqual(["Bea", "Amy", "Zed"]);
    expect(page.crewCount).toBeGreaterThanOrEqual(1);
    expect(page.members[0]).not.toHaveProperty("studyLevel");
  });

  it("shows the last three finished weeks, a week outside the top 3 included, and nothing before the crew existed", async () => {
    const monday = fresh();
    const crews = [];
    for (let i = 0; i < 5; i++) crews.push(await makeCrew());
    advance(3 * 3600);
    // Week 1: crew 4 is fifth. Week 2: crew 4 wins. Week 3: crew 4 studies nothing.
    for (const [i, c] of crews.entries()) await report(c.owner, [session(50 - i * 5)]);
    vi.setSystemTime((monday + 7 * 86_400 + 3 * 3600) * 1000);
    await report(crews[4].owner, [session(90)]);
    vi.setSystemTime((monday + 14 * 86_400 + 3 * 3600) * 1000);
    const late = await makeCrew();
    vi.setSystemTime((monday + 21 * 86_400 + 3 * 3600) * 1000);
    const page = (await call("GET", `/v1/crews/${crews[4].crew.id}`, undefined, crews[4].owner.token)).body.crew;
    expect(checkCrews("crewDetail", page)).toEqual([]);
    expect(page.history).toEqual([
      { week: weekOf(monday + 14 * 86_400), place: null, minutes: 0, medal: null },
      { week: weekOf(monday + 7 * 86_400), place: 1, minutes: 90, medal: "gold" },
      { week: weekOf(monday), place: 5, minutes: 30, medal: null },
    ]);
    // Made during week 3: only that week shows.
    const lateHistory = (await call("GET", `/v1/crews/${late.crew.id}`, undefined, late.owner.token)).body.crew.history;
    expect(lateHistory).toEqual([{ week: weekOf(monday + 14 * 86_400), place: null, minutes: 0, medal: null }]);
    const brandNew = await makeCrew();
    expect((await call("GET", `/v1/crews/${brandNew.crew.id}`, undefined, brandNew.owner.token)).body.crew.history).toEqual([]);
  });
});
