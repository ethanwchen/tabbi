import { runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import crewsCatalog from "../shared/crews.json";
import { HALL_PAGE, allocateMinutes, decodeHallCursor, sessionSegments, weekFromId, weekOf, weekPlaces } from "../src/crews";
import type { Hub } from "../src/hub";
import { admin, call, expectError, hub, register } from "./helpers";
import { User, advance, atWeek, joinByCode, makeCrew, nowS, report, rows, session } from "./crewHelpers";
import { checkCrews } from "./schema";

const DAY_CAP = crewsCatalog.limits.dailyCapMinutes;
const WEEK_CAP = crewsCatalog.limits.weeklyCapMinutes;
const MAX_SESSION = crewsCatalog.limits.maxSessionMinutes;
/** Ten weeks apart: a test may move up to seven weeks ahead, and must not freeze the next test's week early. */
let slot = 500;
const fresh = (offsetS?: number) => atWeek((slot += 10), offsetS);

afterEach(() => {
  vi.useRealTimers();
});

const user = async (name = "Sam") => await register({ name }) as User;

/** A crew whose owner joined an hour ago, so sessions ending now count in full. */
async function crewAnHourOld(over: Record<string, unknown> = {}) {
  const made = await makeCrew(over);
  advance(3600);
  return made;
}

describe("crediting sessions", () => {
  it("credits a session to my crew and tells me the crew's and my minutes", async () => {
    fresh();
    const { owner, crew } = await crewAnHourOld();
    const r = await report(owner, [session(25)]);
    expect(r).toMatchObject({ results: [{ status: "credited", credited: 25 }], crewMinutes: 25, myMinutes: 25 });
    const seen = (await call("GET", `/v1/crews/${crew.id}`, undefined, owner.token)).body.crew;
    expect(seen).toMatchObject({ weekMinutes: 25, rank: 1 });
    expect(seen.members[0].weekMinutes).toBe(25);
  });

  it("answers a retry as a duplicate and refuses overlapping, future and impossible sessions", async () => {
    fresh();
    const { owner } = await crewAnHourOld();
    const s = session(30, 60);
    expect((await report(owner, [s])).results).toEqual([{ status: "credited", credited: 30 }]);
    const r = await report(owner, [
      s,
      { start: s.start + 60, end: s.end + 30, minutes: 5 },
      { start: nowS() + 100, end: nowS() + 400, minutes: 5 },
      { start: s.end, end: s.end + 60, minutes: 2 },
      { start: s.end, end: s.end - 1, minutes: 1 },
      { start: 1000, end: 1000 + (MAX_SESSION + 1) * 60, minutes: 10 },
      { start: s.end, end: s.end + 59, minutes: 0 },
      { start: s.end + 0.5, end: s.end + 59, minutes: 1 },
      { start: s.end, end: s.end + 59, minutes: 1, cards: 3 },
      "nope",
    ] as unknown as { start: number; end: number; minutes: number }[]);
    expect(r.results.map((x) => x.status)).toEqual([
      "duplicate", "overlap", "future", "invalid", "invalid", "invalid", "invalid", "invalid", "invalid", "invalid",
    ]);
    expect(r.myMinutes).toBe(30);
    expectError(await call("POST", "/v1/crews/sessions", { sessions: [] }, owner.token), 400, "invalid_field");
    expectError(await call("POST", "/v1/crews/sessions", { sessions: Array(21).fill(s) }, owner.token), 400, "invalid_field");
    expectError(await call("POST", "/v1/crews/sessions", { sessions: [s], total: 999 }, owner.token), 400, "unknown_field");
  });

  it("stores nothing for someone in no crew", async () => {
    fresh();
    const loner = await user();
    const r = await report(loner, [session(20)]);
    expect(r).toMatchObject({ results: [{ status: "no_crew", credited: 0 }], crewMinutes: null, myMinutes: 0 });
    expect(await rows("SELECT * FROM crew_sessions WHERE code = ?", loner.code)).toEqual([]);
  });

  it("counts a session only from the moment I joined", async () => {
    fresh();
    const { crew } = await crewAnHourOld();
    const late = await user();
    const s = { start: nowS() - 40 * 60, end: nowS() - 600, minutes: 30 };
    advance(-30 * 60);
    await joinByCode(late, crew.inviteCode); // joined 10 minutes into the 30-minute session
    advance(30 * 60);
    expect((await report(late, [s])).results).toEqual([{ status: "credited", credited: 20 }]);
  });

  it("leaves past minutes with the crew they were studied for when I switch crews", async () => {
    fresh();
    const a = await crewAnHourOld();
    const b = await makeCrew();
    const mover = await user();
    await joinByCode(mover, a.crew.inviteCode);
    advance(3600);
    const before = session(30);
    await report(mover, [before]);
    await call("POST", "/v1/crews/leave", {}, mover.token);
    await joinByCode(mover, b.crew.inviteCode);
    advance(3600);
    // A late report of a session studied in crew A still goes to A.
    const lateForA = { start: before.start - 1800, end: before.start - 60, minutes: 29 };
    const r = await report(mover, [session(15), lateForA]);
    expect(r.results).toEqual([{ status: "credited", credited: 15 }, { status: "credited", credited: 29 }]);
    expect((await call("GET", `/v1/crews/${a.crew.id}`, undefined, mover.token)).body.crew.weekMinutes).toBe(59);
    expect((await call("GET", `/v1/crews/${b.crew.id}`, undefined, mover.token)).body.crew.weekMinutes).toBe(15);
    expect(r).toMatchObject({ crewMinutes: 15, myMinutes: 74 });
  });

  it(`credits at most ${DAY_CAP} minutes a UTC day and ${WEEK_CAP} a week, and flags both`, async () => {
    const monday = fresh(23 * 3600);
    const { owner } = await makeCrew();
    // The crew was made at 23:00 on Monday; study through Monday night and Tuesday in 12-hour blocks.
    vi.setSystemTime((monday + 6 * 86_400 + 23 * 3600) * 1000);
    let credited = 0;
    const starts = [];
    for (let t = monday + 23 * 3600; t + MAX_SESSION * 60 <= nowS(); t += MAX_SESSION * 60) starts.push(t);
    for (let i = 0; i < starts.length; i += 6) {
      const batch = starts.slice(i, i + 6).map((start) => ({ start, end: start + MAX_SESSION * 60, minutes: MAX_SESSION }));
      const r = await report(owner, batch);
      credited = r.myMinutes;
      advance(60);
    }
    expect(credited).toBe(WEEK_CAP);
    const days = await rows("SELECT day, SUM(minutes) AS m FROM crew_day_credits WHERE code = ? GROUP BY day", owner.code);
    for (const d of days) expect(d.m as number).toBeLessThanOrEqual(DAY_CAP);
    const flags = (await admin("GET", "/crews/flags")).body.flags.filter((f: { user: { code: string } }) => f.user.code === owner.code);
    expect(flags.map((f: { kind: string }) => f.kind).sort()).toEqual(["daily_cap", "weekly_cap"]);
    expect(flags[0].weekMinutes).toBe(WEEK_CAP);
  });

  it("flags a run of overlapping or future reports for the maintainer, once", async () => {
    fresh();
    const { owner } = await crewAnHourOld();
    const s = session(30);
    await report(owner, [s]);
    const overlaps = Array.from({ length: 6 }, (_, i) => ({ start: s.start + i * 60 + 30, end: s.end - 60, minutes: 5 }));
    const futures = Array.from({ length: 4 }, (_, i) => ({ start: nowS() + 300 + i, end: nowS() + 900, minutes: 5 }));
    await report(owner, [...overlaps, ...futures]);
    const kinds = (await admin("GET", "/crews/flags")).body.flags
      .filter((f: { user: { code: string } }) => f.user.code === owner.code).map((f: { kind: string }) => f.kind).sort();
    expect(kinds).toEqual(["future", "overlaps"]);
  });

  it("splits a session across the rollover and refuses one wholly in a frozen week", async () => {
    const monday = fresh(-3600); // Sunday 23:00
    const { owner } = await makeCrew();
    advance(1800);
    const lastWeek = session(20);
    advance(3600); // Monday 00:30
    const across = { start: monday - 600, end: monday + 1200, minutes: 30 };
    const r = await report(owner, [lastWeek, across]);
    expect(r.results).toEqual([{ status: "week_closed", credited: 0 }, { status: "credited", credited: 20 }]);
    expect(r.myMinutes).toBe(20);
    expect((await call("POST", "/v1/crews/sessions", { sessions: [session(1)] }, owner.token)).status).toBe(200);
  });

  it("rate-limits session reports", async () => {
    fresh();
    const { owner } = await crewAnHourOld();
    for (let i = 0; i < 6; i++) await report(owner, [session(1, i * 120)]);
    expectError(await call("POST", "/v1/crews/sessions", { sessions: [session(1, 2000)] }, owner.token), 429, "rate_limited");
  });

  it("lets the maintainer void a flagged user's open week, which the crew loses", async () => {
    fresh();
    const { owner, crew } = await crewAnHourOld();
    const cheat = await user();
    await joinByCode(cheat, crew.inviteCode);
    advance(3600);
    await report(owner, [session(30)]);
    const s = session(30, 600);
    const overlaps = Array.from({ length: 5 }, (_, i) => ({ start: s.start + i * 10 + 1, end: s.end - 1, minutes: 1 }));
    await report(cheat, [{ start: s.start, end: s.end, minutes: 30 }, ...overlaps]);
    expect((await call("GET", "/v1/crews/mine", undefined, owner.token)).body.crew.weekMinutes).toBe(60);
    const flag = (await admin("GET", "/crews/flags")).body.flags.find((f: { user: { code: string } }) => f.user.code === cheat.code);
    expect(flag).toMatchObject({ kind: "overlaps", crew: { id: crew.id }, weekMinutes: 30 });
    expect((await admin("POST", `/crews/flags/${flag.id}/void`)).body).toEqual({ ok: true, voided: 30, frozen: false });
    expect((await call("GET", "/v1/crews/mine", undefined, owner.token)).body.crew.weekMinutes).toBe(30);
    expect((await admin("GET", "/crews/flags")).body.flags.some((f: { id: number }) => f.id === flag.id)).toBe(false);
    expect((await admin("GET", "/crews/flags?status=all")).body.flags.find((f: { id: number }) => f.id === flag.id).resolution).toBe("voided");
    expect((await admin("POST", `/crews/flags/${flag.id}/dismiss`)).body.dismissed).toBe(false);
    expectError(await admin("POST", "/crews/flags/999999/void"), 404, "flag_not_found");
  });
});

describe("the weekly board", () => {
  /** Three crews with 90, 60 and 30 minutes this week, plus a hidden one with the most. */
  async function race() {
    const crews = [];
    for (const minutes of [60, 90, 30, 120]) {
      const made = await makeCrew({ visibility: minutes === 30 ? "private" : "public" });
      crews.push({ ...made, minutes });
    }
    advance(3 * 3600);
    for (const c of crews) await report(c.owner, [session(c.minutes)]);
    await admin("POST", `/crews/${crews[3].crew.id}/hide`);
    return { second: crews[0], first: crews[1], third: crews[2] };
  }

  it("shows the live top 3, with a private crew opened from it", async () => {
    fresh();
    const { first, second, third } = await race();
    const viewer = await user();
    const board = await call("GET", "/v1/crews/board", undefined, viewer.token);
    expect(checkCrews("boardReply", board.body)).toEqual([]);
    expect(board.body.top.map((e: { rank: number; minutes: number; crew: { id: string } }) => [e.rank, e.minutes, e.crew.id]))
      .toEqual([[1, 90, first.crew.id], [2, 60, second.crew.id], [3, 30, third.crew.id]]);
    expect(board.body.featured).toBeNull();
    expect((await call("GET", `/v1/crews/${third.crew.id}`, undefined, viewer.token)).status).toBe(200);
  });

  it("freezes the week at rollover: laurels for a week, trophies forever, the winners featured", async () => {
    const monday = fresh();
    const { first, second, third } = await race();
    vi.setSystemTime((monday + 7 * 86_400 + 60) * 1000);
    const late = await report(first.owner, [{ start: monday + 7 * 86_400 - 3600, end: monday + 7 * 86_400 - 60, minutes: 50 }]);
    expect(late.results[0].status).toBe("week_closed");
    const viewer = await user();
    const board = (await call("GET", "/v1/crews/board", undefined, viewer.token)).body;
    expect(checkCrews("boardReply", board)).toEqual([]);
    expect(board.top).toEqual([]);
    expect(board.featured.week).toEqual(weekOf(monday));
    expect(board.featured.entries.map((e: { rank: number; minutes: number; crew: { id: string; laurel: string } }) =>
      [e.rank, e.minutes, e.crew.id, e.crew.laurel]))
      .toEqual([[1, 90, first.crew.id, "gold"], [2, 60, second.crew.id, "silver"], [3, 30, third.crew.id, "bronze"]]);
    const page = (await call("GET", `/v1/crews/${third.crew.id}`, undefined, viewer.token)).body.crew;
    expect(page).toMatchObject({ laurel: "bronze", trophies: 1, medals: { gold: 0, silver: 0, bronze: 1 }, weekMinutes: 0 });
    // The rollup is idempotent: the alarm and later requests change nothing.
    expect(await runDurableObjectAlarm(hub())).toBe(true);
    expect((await rows("SELECT COUNT(*) AS n FROM crew_awards WHERE week = ?", weekOf(monday).id))[0].n).toBe(3);
    // A week later the laurel is gone, the trophy stays.
    vi.setSystemTime((monday + 14 * 86_400 + 60) * 1000);
    const after = (await call("GET", `/v1/crews/${first.crew.id}`, undefined, viewer.token)).body.crew;
    expect(after).toMatchObject({ laurel: null, trophies: 1, medals: { gold: 1, silver: 0, bronze: 0 } });
    expect((await call("GET", "/v1/crews/board", undefined, viewer.token)).body.featured).toBeNull();
  });

  it("shares places on equal minutes: two crews tied first both win gold and the next crew is third", async () => {
    const monday = fresh();
    const a = await makeCrew();
    const b = await makeCrew();
    const c = await makeCrew();
    const d = await makeCrew();
    advance(3 * 3600);
    for (const [made, minutes] of [[a, 45], [b, 45], [c, 30], [d, 20]] as const) await report(made.owner, [session(minutes)]);
    const ids = [a, b].map((x) => x.crew.id).sort();
    const live = (await call("GET", "/v1/crews/board", undefined, a.owner.token)).body.top;
    expect(live.map((e: { rank: number; crew: { id: string } }) => [e.rank, e.crew.id])).toEqual([[1, ids[0]], [1, ids[1]], [3, c.crew.id]]);
    vi.setSystemTime((monday + 7 * 86_400 + 60) * 1000);
    const board = (await call("GET", "/v1/crews/board", undefined, a.owner.token)).body;
    expect(checkCrews("boardReply", board)).toEqual([]);
    expect(board.featured.entries.map((e: { rank: number; crew: { id: string; laurel: string } }) => [e.rank, e.crew.id, e.crew.laurel]))
      .toEqual([[1, ids[0], "gold"], [1, ids[1], "gold"], [3, c.crew.id, "bronze"]]);
    const medals = async (x: typeof a) => (await call("GET", `/v1/crews/${x.crew.id}`, undefined, x.owner.token)).body.crew.medals;
    expect(await medals(a)).toEqual({ gold: 1, silver: 0, bronze: 0 });
    expect(await medals(b)).toEqual({ gold: 1, silver: 0, bronze: 0 });
    expect(await medals(c)).toEqual({ gold: 0, silver: 0, bronze: 1 });
    expect(await medals(d)).toEqual({ gold: 0, silver: 0, bronze: 0 });
  });

  it("can place more than three crews when they tie for third", async () => {
    const monday = fresh();
    const crews = [];
    for (let i = 0; i < 5; i++) crews.push(await makeCrew());
    advance(3 * 3600);
    for (const [i, made] of crews.entries()) await report(made.owner, [session([60, 50, 40, 40, 10][i])]);
    vi.setSystemTime((monday + 7 * 86_400 + 60) * 1000);
    const entries = (await call("GET", "/v1/crews/board", undefined, crews[0].owner.token)).body.featured.entries;
    expect(entries.map((e: { rank: number; crew: { laurel: string } }) => [e.rank, e.crew.laurel]))
      .toEqual([[1, "gold"], [2, "silver"], [3, "bronze"], [3, "bronze"]]);
  });

  it("freezes a week the alarm reaches first, even with no request", async () => {
    const monday = fresh();
    const { owner, crew } = await crewAnHourOld();
    await report(owner, [session(10)]);
    vi.setSystemTime((monday + 7 * 86_400 + 3600) * 1000);
    expect(await runDurableObjectAlarm(hub())).toBe(true);
    expect(await rows("SELECT rank, crew FROM crew_awards WHERE week = ?", weekOf(monday).id)).toEqual([{ rank: 1, crew: crew.id }]);
  });
});

describe("retention", () => {
  it("drops old sessions, closed stints and old weeks, and keeps awards", async () => {
    const monday = fresh();
    const { owner, crew } = await crewAnHourOld();
    await report(owner, [session(10)]);
    // Someone stays, so the crew lives on and wins its week.
    await joinByCode(await user(), crew.inviteCode);
    await call("POST", "/v1/crews/leave", {}, owner.token);
    vi.setSystemTime((monday + 50 * 86_400) * 1000);
    expect(await runDurableObjectAlarm(hub())).toBe(true);
    for (const table of ["crew_sessions", "crew_stints", "crew_day_credits"]) {
      expect(await rows(`SELECT * FROM ${table} WHERE code = ?`, owner.code), table).toEqual([]);
    }
    expect(await rows("SELECT * FROM crew_weeks WHERE crew = ?", crew.id)).toEqual([]);
    expect(await rows("SELECT crew FROM crew_awards WHERE week = ?", weekOf(monday).id)).toEqual([{ crew: crew.id }]);
  });
});

describe("signing in folds an anonymous user's crew into the account", () => {
  it("moves the membership and minutes when the account has no crew", async () => {
    fresh();
    const { owner, crew } = await crewAnHourOld();
    const account = await user("Account");
    await report(owner, [session(20)]);
    await runInDurableObject(hub(), (h: Hub, state) => {
      state.storage.transactionSync(() => (h as unknown as { foldInto(a: string, b: string, n: number): void }).foldInto(owner.code, account.code, nowS()));
    });
    const seen = (await call("GET", "/v1/crews/mine", undefined, account.token)).body.crew;
    expect(seen).toMatchObject({ id: crew.id, owner: true, weekMinutes: 20 });
    expect(seen.members[0].weekMinutes).toBe(20);
    // The moved session still guards against a double report.
    expect((await report(account, [session(20)])).results[0].status).toBe("duplicate");
  });
});

describe("splitting a session", () => {
  it("clips to stints and the open week, splits at UTC midnight and keeps whole minutes", () => {
    const day = 86_400 * 20000;
    const stints = [{ crew: "A", joinedAt: day - 3600, leftAt: day + 1800 }, { crew: "B", joinedAt: day + 1800, leftAt: null }];
    const segs = sessionSegments(day - 1800, day + 3600, stints, day - 600);
    expect(segs).toEqual([
      { crew: "A", day: "2024-10-03", seconds: 600 },
      { crew: "A", day: "2024-10-04", seconds: 1800 },
      { crew: "B", day: "2024-10-04", seconds: 1800 },
    ]);
    expect(allocateMinutes(90, 5400, segs)).toEqual([10, 30, 30]);
    expect(allocateMinutes(7, 5400, segs).reduce((a, b) => a + b, 0)).toBe(5);
  });
});

describe("places and weeks", () => {
  it("ranks a week by competition ranking and never places a crew with no minutes", () => {
    const places = weekPlaces([
      { id: "B", minutes: 10 }, { id: "A", minutes: 10 }, { id: "C", minutes: 5 }, { id: "D", minutes: 0 }, { id: "E", minutes: 3 },
    ]);
    expect(places.map((p) => [p.id, p.rank])).toEqual([["A", 1], ["B", 1], ["C", 3]]);
    expect(weekPlaces([{ id: "A", minutes: 0 }])).toEqual([]);
  });

  it("reads a week back from its key", () => {
    for (const t of [Date.UTC(2026, 10, 12) / 1000, Date.UTC(2027, 0, 1) / 1000, Date.UTC(2026, 0, 1) / 1000]) {
      expect(weekFromId(weekOf(t).id)).toEqual(weekOf(t));
    }
  });
});

describe("the Hall of Fame", () => {
  /** Gives each crew minutes in the current week, then closes it; `minutes[i]` for crews[i]. */
  async function playWeek(crews: { owner: User }[], minutes: number[]) {
    for (const [i, made] of crews.entries()) if (minutes[i] > 0) await report(made.owner, [session(minutes[i], 0)]);
    const next = weekOf(nowS()).endsAt;
    vi.setSystemTime((next + 6 * 3600) * 1000);
  }

  const hall = async (token: string, cursor?: string) => {
    const r = await call("GET", `/v1/crews/hall${cursor ? `?cursor=${cursor}` : ""}`, undefined, token);
    expect(r.status, JSON.stringify(r.body)).toBe(200);
    expect(checkCrews("hallReply", r.body)).toEqual([]);
    return r.body as { entries: { rank: number; medals: Record<string, number>; reachedAt: number; crew: { id: string } }[]; next: string | null };
  };

  /** The hall's entries for just these crews (other tests' crews may be in it too). */
  const only = <T extends { crew: { id: string } }>(entries: T[], ids: string[]) => entries.filter((e) => ids.includes(e.crew.id));

  it("orders by golds, silvers, bronzes, then who reached the tally first, then id, with distinct ranks", async () => {
    fresh(9 * 3600);
    const crews = [];
    for (let i = 0; i < 4; i++) crews.push(await makeCrew({ visibility: i === 3 ? "private" : "public" }));
    advance(3 * 3600);
    // Week 1: A gold, B silver, C bronze. Week 2: B gold, A silver, D bronze.
    // Week 3: C gold, D gold (tie), A bronze. Now A 1g1s1b, B 1g1s, C 1g1b, D 1g1b (D reached it with C).
    await playWeek(crews, [90, 60, 30, 0]);
    advance(3600);
    await playWeek(crews, [60, 90, 0, 30]);
    advance(3600);
    const week3End = weekOf(nowS()).endsAt;
    await playWeek(crews, [30, 0, 90, 90]);
    const ids = crews.map((c) => c.crew.id);
    const page = only(await hallAll(crews[0].owner.token), ids);
    const [a, b, c, d] = ids;
    const cd = [c, d].sort();
    expect(page.map((e) => e.crew.id)).toEqual([a, b, ...cd]);
    expect(page[0].medals).toEqual({ gold: 1, silver: 1, bronze: 1 });
    expect(page[1].medals).toEqual({ gold: 1, silver: 1, bronze: 0 });
    // C and D have the same tally from the same week: the id decides, and every rank is its own.
    expect(page[2].rank).toBe(page[1].rank + 1);
    expect(page[3].rank).toBe(page[2].rank + 1);
    expect(page[2].reachedAt).toBe(week3End);
    // The private crew is listed, like on the board.
    expect(page.some((e) => e.crew.id === d)).toBe(true);
  });

  it("breaks an equal tally by who reached it first", async () => {
    fresh(9 * 3600);
    const early = await makeCrew();
    const late = await makeCrew();
    advance(3600);
    await playWeek([early, late], [60, 0]);
    advance(3600);
    await playWeek([early, late], [0, 60]);
    const page = only(await hallAll(early.owner.token), [early.crew.id, late.crew.id]);
    expect(page.map((e) => e.crew.id)).toEqual([early.crew.id, late.crew.id]);
    expect(page[0].reachedAt).toBeLessThan(page[1].reachedAt);
    expect(page[1].rank).toBe(page[0].rank + 1);
  });

  it("keeps medals through a rename, and drops hidden and deleted crews", async () => {
    fresh(9 * 3600);
    const kept = await makeCrew();
    const hidden = await makeCrew();
    const deleted = await makeCrew();
    advance(3 * 3600);
    await playWeek([kept, hidden, deleted], [90, 60, 30]);
    await call("PATCH", "/v1/crews/mine", { name: `Renamed ${kept.crew.id}` }, kept.owner.token);
    await admin("POST", `/crews/${kept.crew.id}/rename`);
    await admin("POST", `/crews/${hidden.crew.id}/hide`);
    await admin("DELETE", `/crews/${deleted.crew.id}`);
    const ids = [kept, hidden, deleted].map((x) => x.crew.id);
    const mine = only(await hallAll(kept.owner.token), ids);
    expect(mine.map((e) => e.crew.id)).toEqual([kept.crew.id]);
    expect(mine[0].medals).toEqual({ gold: 1, silver: 0, bronze: 0 });
    await admin("DELETE", `/crews/${hidden.crew.id}/hide`);
    // Shown again, the hidden crew is back with its silver.
    const back = only(await hallAll(kept.owner.token), [hidden.crew.id]);
    expect(back.map((e) => e.medals)).toEqual([{ gold: 0, silver: 1, bronze: 0 }]);
  });

  /** Every hall entry, following `next` to the end. */
  async function hallAll(token: string) {
    let all: { rank: number; crew: { id: string }; medals: Record<string, number>; reachedAt: number }[] = [];
    let cursor: string | undefined;
    do {
      const page = await hall(token, cursor);
      all = all.concat(page.entries);
      cursor = page.next ?? undefined;
    } while (cursor);
    return all;
  }

  it(`pages ${HALL_PAGE} at a time in a stable order, with ranks over the whole order`, async () => {
    fresh(9 * 3600);
    const crews = [];
    for (let i = 0; i < HALL_PAGE + 5; i++) crews.push(await makeCrew());
    advance(3600);
    // Every crew tied first: each wins a gold, reached the same week, so only the id orders them.
    await playWeek(crews, crews.map(() => 30));
    const all = await hallAll(crews[0].owner.token);
    const ids = all.map((e) => e.crew.id);
    expect(new Set(ids).size).toBe(ids.length);
    const mine = only(all, crews.map((c) => c.crew.id));
    expect(mine).toHaveLength(crews.length);
    // Equal tallies reached the same week are in id order, each with its own rank.
    expect(new Set(mine.map((e) => e.rank)).size).toBe(mine.length);
    expect(mine.map((e) => e.crew.id)).toEqual([...mine.map((e) => e.crew.id)].sort());
    // Ranks are 1 plus the position in the whole order, across pages.
    expect(all.map((e) => e.rank)).toEqual(all.map((_, i) => i + 1));
    // The same walk again gives the same order, page by page.
    expect((await hallAll(crews[0].owner.token)).map((e) => e.crew.id)).toEqual(ids);
    const first = await hall(crews[0].owner.token);
    expect(first.entries).toHaveLength(HALL_PAGE);
    expect(first.next).not.toBeNull();
    expect(decodeHallCursor(first.next!).id).toBe(first.entries.at(-1)!.crew.id);
    expectError(await call("GET", "/v1/crews/hall?cursor=not*valid", undefined, crews[0].owner.token), 400, "invalid_field");
    expectError(await call("GET", `/v1/crews/hall?cursor=${btoa("[1,2]")}`, undefined, crews[0].owner.token), 400, "invalid_field");
  });

  it("writes medals once per closed week, and catches up several missed weeks in order", async () => {
    const monday = fresh(9 * 3600);
    const a = await makeCrew();
    const b = await makeCrew();
    advance(3600);
    await report(a.owner, [session(50)]);
    await report(b.owner, [session(40)]);
    // Two weeks later with no request or alarm in between: week 1 freezes now.
    // Week 2 has no minutes; it is frozen empty.
    await runInDurableObject(hub(), (_h: Hub, state) => {
      state.storage.sql.exec("INSERT INTO crew_weeks (week, crew, minutes) VALUES (?, ?, 20)", weekOf(monday + 7 * 86_400).id, b.crew.id);
    });
    vi.setSystemTime((monday + 14 * 86_400 + 3600) * 1000);
    expect(await runDurableObjectAlarm(hub())).toBe(true);
    expect(await runDurableObjectAlarm(hub())).toBe(true);
    await call("GET", "/v1/crews/board", undefined, a.owner.token);
    const tally = async (x: typeof a) => (await call("GET", `/v1/crews/${x.crew.id}`, undefined, x.owner.token)).body.crew.medals;
    expect(await tally(a)).toEqual({ gold: 1, silver: 0, bronze: 0 });
    expect(await tally(b)).toEqual({ gold: 1, silver: 1, bronze: 0 });
    const reached = (await hallAll(a.owner.token)).find((e) => e.crew.id === b.crew.id)!.reachedAt;
    expect(reached).toBe(monday + 14 * 86_400);
    expect(await rows("SELECT week, rank FROM crew_awards WHERE crew = ? ORDER BY week", b.crew.id))
      .toEqual([{ week: weekOf(monday).id, rank: 2 }, { week: weekOf(monday + 7 * 86_400).id, rank: 1 }]);
  });
});
