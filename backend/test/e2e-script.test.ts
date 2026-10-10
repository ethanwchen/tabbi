import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { formatReport, parseArgs, runE2E } from "../scripts/e2e";
import { BASE, admin } from "./helpers";

const worker = ((url: string, init?: RequestInit) => SELF.fetch(url, init)) as typeof fetch;

/** The Worker, with the replies to `path` (and `method`) rewritten by `edit`. */
function tamper(method: string, path: string, edit: (status: number, body: any) => { status: number; body: unknown }): typeof fetch { // eslint-disable-line @typescript-eslint/no-explicit-any
  return (async (url: string, init?: RequestInit) => {
    const res = await SELF.fetch(url, init);
    if (new URL(url).pathname !== path || (init?.method ?? "GET") !== method) return res;
    const text = await res.text();
    const out = edit(res.status, text ? JSON.parse(text) : null);
    return new Response(JSON.stringify(out.body), { status: out.status, headers: { "Content-Type": "application/json" } });
  }) as typeof fetch;
}

const usersInHub = async () => (await admin("GET", "/stats")).body.users.total as number;

describe("parseArgs", () => {
  it("reads the URL and refuses production", () => {
    expect(parseArgs([])).toEqual({ url: "http://localhost:8787", json: false, ipOctet: 10 });
    expect(parseArgs(["--url", "http://127.0.0.1:9000//", "--json"])).toMatchObject({ url: "http://127.0.0.1:9000", json: true });
    expect(() => parseArgs(["--url"])).toThrow(/needs a value/);
    expect(() => parseArgs(["--users", "2"])).toThrow(/unknown option/);
    expect(() => parseArgs(["--url", "https://tabbi-friends.example.workers.dev"])).toThrow(/production/);
  });
});

describe("runE2E against the real Worker", () => {
  it("befriends, parties, studies, blocks and cleans up", async () => {
    const before = await usersInHub();
    expect(before).toEqual(expect.any(Number));
    const lines: string[] = [];
    const report = await runE2E({ ...parseArgs([]), url: BASE, ipOctet: 174 }, worker, (s) => lines.push(s));
    expect(report.steps.filter((s) => !s.ok)).toEqual([]);
    expect(report.ok).toBe(true);
    expect(report.steps.map((s) => s.name)).toEqual([
      "the Worker is up",
      "Ana and Ben register",
      "Ana adds Ben by his friend code, and both see the friendship",
      "Ana starts studying and Ben sees her online",
      "Ana hosts a party and Ben joins through her",
      "Ana starts a shared session and Ben follows it",
      "Ben studies along, and both show up studying",
      "Ana ends the session and takes a break",
      "Ben blocks Ana: the friendship and the party end",
      "Ana cannot reach Ben again, and is not told why",
      "Ben unblocks Ana: no friendship comes back until one adds the other",
      "both accounts are deleted",
    ]);
    expect(lines).toHaveLength(12);
    expect(lines.every((l) => l.startsWith("ok "))).toBe(true);
    expect(await usersInHub()).toBe(before);
    expect(formatReport(report)).toMatch(/All 12 steps passed\.$/);
  });

  it("can run again right away, as repeated runs against wrangler dev do", async () => {
    for (let i = 0; i < 2; i++) {
      expect((await runE2E({ ...parseArgs([]), url: BASE, ipOctet: 175 }, worker)).ok).toBe(true);
    }
  });

  it("stops at a block the server failed to apply, says why, and still deletes both accounts", async () => {
    const before = await usersInHub();
    // A Worker that forgets to drop the blocked user from the friend list.
    const broken = tamper("GET", "/v1/friends", (status, body) => {
      if (body?.friends?.length === 0) body.friends = [{ profile: { code: "AAAAAAAA" } }];
      return { status, body };
    });
    const report = await runE2E({ ...parseArgs([]), url: BASE, ipOctet: 176 }, broken);
    expect(report.ok).toBe(false);
    const last = report.steps.at(-1)!;
    expect(last).toMatchObject({ name: "Ben blocks Ana: the friendship and the party end", ok: false });
    expect(last.error).toMatch(/^Ana's friend list after the block: got /);
    expect(report.steps.slice(0, -1).every((s) => s.ok)).toBe(true);
    expect(formatReport(report)).toMatch(/Failed at step 9: Ben blocks Ana/);
    expect(await usersInHub()).toBe(before);
  });

  it("reports an unexpected status with the reply", async () => {
    const down = tamper("GET", "/v1/health", () => ({ status: 503, body: { ok: false, error: "unavailable" } }));
    const report = await runE2E({ ...parseArgs([]), url: BASE, ipOctet: 177 }, down);
    expect(report).toEqual({
      ok: false,
      steps: [{ name: "the Worker is up", ok: false, ms: expect.any(Number), error: 'GET /v1/health: expected 200, got 503 {"ok":false,"error":"unavailable"}' }],
    });
  });

  it("reports a network failure as a failed step instead of throwing", async () => {
    const offline = (async () => { throw new TypeError("fetch failed"); }) as typeof fetch;
    const report = await runE2E({ ...parseArgs([]), url: BASE, ipOctet: 178 }, offline);
    expect(report.ok).toBe(false);
    expect(report.steps).toEqual([{ name: "the Worker is up", ok: false, ms: expect.any(Number), error: "fetch failed" }]);
  });
});
