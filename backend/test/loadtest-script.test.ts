import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { PEAK_MODEL, fakeIp, formatReport, loadTest, parseArgs, peakRates, percentile, totalRate } from "../scripts/loadtest";
import { ADMIN_TOKEN, BASE } from "./helpers";

describe("peakRates", () => {
  it("turns the peak-hour model into requests per second per route", () => {
    const r = peakRates(10_000, { online: 0.3, studying: 0.5, panelOpen: 0.2, inParty: 0.5, leaderboardPerHour: 2 });
    // 3,000 online: 1,500 heartbeat every 120 s and 1,500 every 300 s.
    expect(r.heartbeat).toBeCloseTo(1500 / 120 + 1500 / 300);
    expect(r.friends).toBeCloseTo(600 / 60);
    expect(r.party).toBeCloseTo(300 / 30);
    expect(r.leaderboard).toBeCloseTo(6000 / 3600);
    expect(totalRate(r)).toBeCloseTo(17.5 + 10 + 10 + 6000 / 3600);
  });

  it("grows linearly with users", () => {
    expect(totalRate(peakRates(50_000))).toBeCloseTo(5 * totalRate(peakRates(10_000)));
    expect(totalRate(peakRates(10_000, PEAK_MODEL))).toBeGreaterThan(20);
  });
});

describe("helpers", () => {
  it("gives every user a distinct private IP", () => {
    const ips = new Set(Array.from({ length: 70_000 }, (_, i) => fakeIp(i)));
    expect(ips.size).toBe(70_000);
    expect(fakeIp(0)).toBe("10.0.0.0");
    expect(fakeIp(65_537, 172)).toBe("172.1.0.1");
  });

  it("reads percentiles from sorted values", () => {
    const values = Array.from({ length: 100 }, (_, i) => i + 1);
    expect(percentile(values, 0.5)).toBe(50);
    expect(percentile(values, 0.99)).toBe(99);
    expect(percentile(values, 1)).toBe(100);
    expect(percentile([], 0.5)).toBe(0);
  });

  it("parses options and refuses to run against production", () => {
    const o = parseArgs(["--users", "500", "--stages", "1,3", "--duration", "5", "--url", "http://localhost:9000/"], { TABBI_ADMIN_TOKEN: "x" });
    expect(o).toMatchObject({ users: 500, stages: [1, 3], duration: 5, url: "http://localhost:9000", adminToken: "x", friends: 3 });
    expect(parseArgs([], {}).adminToken).toBeUndefined();
    expect(() => parseArgs(["--users", "0"])).toThrow(/positive/);
    expect(() => parseArgs(["--stages", "1,x"])).toThrow(/positive/);
    expect(() => parseArgs(["--bogus", "1"])).toThrow(/unknown option/);
    expect(() => parseArgs(["--url", "https://tabbi-friends.example.workers.dev"])).toThrow(/production/);
  });
});

describe("loadTest against the real Worker", () => {
  const worker = ((url: string, init?: RequestInit) => SELF.fetch(url, init)) as typeof fetch;

  it("sets up users, friends and parties, runs a stage and measures rows per request", async () => {
    const o = { ...parseArgs(["--users", "12", "--friends", "2", "--duration", "0.5", "--stages", "200"], { TABBI_ADMIN_TOKEN: ADMIN_TOKEN }), url: BASE, ipOctet: 172 };
    const report = await loadTest(o, worker);
    expect(report).toMatchObject({ users: 12, friendsPerUser: 4, parties: 1, setup: { failures: 0 } });
    // 12 registrations, 24 friend adds, 1 party created and 3 joins.
    expect(report.setup.requests).toBe(40);
    const [stage] = report.stages;
    expect(stage.multiple).toBe(200);
    expect(stage.shed).toBe(0);
    const sent = Object.values(stage.perRoute).reduce((n, r) => n + r.sent, 0);
    expect(sent).toBeGreaterThan(0);
    expect(stage.statuses["200"]).toBe(sent);
    // Every request reads rows (at least the caller's token); steady heartbeats write none.
    expect(stage.rows!.readPerRequest).toBeGreaterThan(0);
    expect(stage.rows!.writtenPerRequest).toBeLessThan(1);
    const text = formatReport(report);
    expect(text).toContain("12 users, 4 friends each, 1 parties of 4");
    expect(text).toMatch(/^x200 /m);
  });

  it("leaves the row columns out without the admin token", async () => {
    const o = { ...parseArgs(["--users", "4", "--friends", "1", "--duration", "0.2", "--stages", "500"], {}), url: BASE, ipOctet: 173 };
    const report = await loadTest(o, worker);
    expect(report.stages[0].rows).toBeNull();
    expect(formatReport(report)).toMatch(/^x500 .* -\s+-$/m);
  });
});
